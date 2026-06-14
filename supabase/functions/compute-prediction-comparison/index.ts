// supabase/functions/compute-prediction-comparison/index.ts
//
// Phase 4B Shadow Mode — Prediction vs Actual Comparison
//
// Runs every 10 minutes via pg_cron. Finds auctions closed in the last 48 hours
// that have an ai_predictions row but no ai_prediction_comparisons row yet.
// Computes accuracy metrics and upserts comparison records.
//
// Lookup window: 48 hours (catches manual closes, cron closes, and any lag).
// Error metrics are NULL when had_bids = false (no actual to compare against).
// actual_signal uses the same ratio thresholds as the prediction generator:
//   winning_amount / starting_price > 1.30 → undervalued
//   winning_amount / starting_price < 1.10 → overpriced
//   otherwise                               → fairly_priced
//
// Idempotency:
//   • Pre-filters auctions already in ai_prediction_comparisons
//   • Catches PostgreSQL unique-violation (23505) as a safety net
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const incomingAuth = req.headers.get('Authorization') ?? '';
  if (!expectedKey || incomingAuth !== `Bearer ${expectedKey}`) {
    return json({ error: 'Unauthorized' }, 401);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const result = { compared: 0, skipped_no_prediction: 0, already_done: 0, errors: 0 };

  try {
    const windowStart = new Date(Date.now() - 48 * 60 * 60 * 1000).toISOString();

    // ── Find recently closed auctions ────────────────────────────────────────
    const { data: closedAuctions, error: aErr } = await supabase
      .from('auctions')
      .select('id, starting_price, winning_amount, winner_uid, closed_at')
      .eq('auction_status', 'closed')
      .eq('is_deleted', false)
      .gte('closed_at', windowStart)
      .not('closed_at', 'is', null);

    if (aErr) throw aErr;
    if (!closedAuctions?.length) {
      return json({ ...result, message: 'No recently closed auctions in window' });
    }

    // ── Pre-filter: exclude auctions already compared ────────────────────────
    const auctionIds = closedAuctions.map((a: any) => a.id);
    const { data: existingRows } = await supabase
      .from('ai_prediction_comparisons')
      .select('auction_id')
      .in('auction_id', auctionIds);

    const alreadyCompared = new Set(
      (existingRows ?? []).map((r: any) => r.auction_id)
    );

    const toCompare = closedAuctions.filter((a: any) => !alreadyCompared.has(a.id));

    if (!toCompare.length) {
      result.already_done = closedAuctions.length;
      return json({ ...result, message: 'All recent closes already compared' });
    }

    // ── Process each uncomared auction ───────────────────────────────────────
    for (const auction of toCompare) {
      const auctionId: string = auction.id;

      try {
        // Find the most recent auction_price_estimate prediction
        const { data: predictions, error: pErr } = await supabase
          .from('ai_predictions')
          .select(
            'id, model_version, expected_auction_price, value_signal, starting_price_at_prediction, created_at'
          )
          .eq('auction_id', auctionId)
          .eq('prediction_type', 'auction_price_estimate')
          .order('created_at', { ascending: false })
          .limit(1);

        if (pErr) throw pErr;

        if (!predictions?.length) {
          result.skipped_no_prediction++;
          continue;
        }

        const prediction = predictions[0];
        const predictedValue = Number(prediction.expected_auction_price ?? 0);
        const actualValue = auction.winning_amount != null ? Number(auction.winning_amount) : null;
        const hadBids = auction.winner_uid != null && actualValue != null && actualValue > 0;

        // Error metrics (only when there are bids and both values are positive)
        let absoluteErrorRwf: number | null = null;
        let absolutePercentageError: number | null = null;
        let residual: number | null = null;

        if (hadBids && actualValue && actualValue > 0 && predictedValue > 0) {
          residual = predictedValue - actualValue;
          absoluteErrorRwf = Math.round(Math.abs(residual) * 100) / 100;
          absolutePercentageError = Math.abs(residual) / actualValue;
        }

        // Actual signal: derive from winning_amount / starting_price
        let actualSignal: string | null = null;
        const startingPrice = Number(
          prediction.starting_price_at_prediction ?? auction.starting_price ?? 0
        );
        if (hadBids && actualValue && startingPrice > 0) {
          const actualRatio = actualValue / startingPrice;
          actualSignal = actualRatio > 1.30 ? 'undervalued'
            : actualRatio < 1.10 ? 'overpriced'
            : 'fairly_priced';
        }

        const signalCorrect: boolean | null =
          prediction.value_signal != null && actualSignal != null
            ? prediction.value_signal === actualSignal
            : null;

        // ── Insert comparison record ─────────────────────────────────────────
        const { error: insertErr } = await supabase
          .from('ai_prediction_comparisons')
          .insert({
            auction_id: auctionId,
            prediction_id: prediction.id,
            model_version: prediction.model_version,
            predicted_value: predictedValue,
            predicted_value_signal: prediction.value_signal ?? null,
            actual_value: actualValue,
            had_bids: hadBids,
            absolute_error_rwf: absoluteErrorRwf,
            absolute_percentage_error: absolutePercentageError,
            residual: residual,
            actual_signal: actualSignal,
            signal_correct: signalCorrect,
            prediction_created_at: prediction.created_at,
            auction_closed_at: auction.closed_at,
          });

        if (insertErr) {
          // 23505 = unique_violation — concurrent run already inserted this row
          if (insertErr.code === '23505') {
            result.already_done++;
            continue;
          }
          throw insertErr;
        }

        await supabase.from('ai_prediction_logs').insert({
          auction_id: auctionId,
          event_type: 'comparison_computed',
          model_versions: { model_a: prediction.model_version },
          metadata: {
            had_bids: hadBids,
            predicted_value: predictedValue,
            actual_value: actualValue,
            absolute_percentage_error: absolutePercentageError,
            signal_correct: signalCorrect,
          },
        });

        result.compared++;
      } catch (auctionErr) {
        console.error(`[compute-comparison] auction ${auctionId}:`, auctionErr);
        await supabase.from('ai_prediction_logs').insert({
          auction_id: auctionId,
          event_type: 'prediction_error',
          error_code: 'COMPARISON_ERROR',
          error_message: String(auctionErr),
        }).catch(() => {});
        result.errors++;
      }
    }
  } catch (e) {
    console.error('[compute-comparison] fatal:', e);
    return json({ error: String(e), ...result }, 500);
  }

  return json(result);
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
