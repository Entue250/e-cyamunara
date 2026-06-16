// supabase/functions/compute-prediction-comparison/index.ts
//
// Phase 9A.2 — Prediction vs Actual Comparison (real metrics for all closes)
//
// Runs every 10 minutes via pg_cron. Finds auctions closed in the last 48 hours
// that have an ai_predictions row but no complete ai_prediction_comparisons row.
// Computes accuracy metrics and upserts comparison records.
//
// Lookup window: 48 hours (catches manual closes, cron closes, and any lag).
//
// Error metrics are computed for ALL closed auctions, including no-bid closes.
// When had_bids = false, auto-close-auctions sets winning_amount = starting_price.
// That value is used as the ground-truth floor, giving a meaningful signal:
//   APE = |predicted - starting_price| / starting_price
//   actual_signal → 'overpriced' (ratio 1.0 < 1.10 threshold)
// This is semantically correct: if no one bid, the market rejected the starting price.
//
// actual_signal thresholds (same as the prediction generator):
//   actual_value / starting_price > 1.30 → undervalued
//   actual_value / starting_price < 1.10 → overpriced
//   otherwise                            → fairly_priced
//
// Idempotency:
//   • Pre-filters to skip only auctions whose comparison row has non-null
//     absolute_percentage_error. Rows with null metrics are re-processed.
//     This retroactively fixes legacy rows created before Phase 9A.2.
//   • Uses UPSERT (onConflict: auction_id) to safely update existing rows.
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

    // ── Pre-filter: skip only auctions with complete metrics already ─────────
    // Rows with null absolute_percentage_error are re-processed so that legacy
    // rows created before Phase 9A.2 are retroactively fixed via UPSERT.
    const auctionIds = closedAuctions.map((a: any) => a.id);
    const { data: completeRows } = await supabase
      .from('ai_prediction_comparisons')
      .select('auction_id')
      .in('auction_id', auctionIds)
      .not('absolute_percentage_error', 'is', null);

    const alreadyComplete = new Set(
      (completeRows ?? []).map((r: any) => r.auction_id)
    );

    const toCompare = closedAuctions.filter((a: any) => !alreadyComplete.has(a.id));
    result.already_done = closedAuctions.length - toCompare.length;

    if (!toCompare.length) {
      return json({ ...result, message: 'All recent closes already have complete metrics' });
    }

    // ── Process each auction ─────────────────────────────────────────────────
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

        // starting_price from the prediction snapshot (preferred) or live auction
        const startingPrice = Number(
          prediction.starting_price_at_prediction ?? auction.starting_price ?? 0
        );

        // actual_value: winning_amount when set by auto-close, fall back to
        // starting_price as the no-bid floor (defensive — auto-close should always set it).
        const rawWinningAmount = auction.winning_amount != null
          ? Number(auction.winning_amount)
          : null;
        const actualValue = rawWinningAmount ?? startingPrice;

        // had_bids: true only when a winner was recorded with a positive bid amount
        const hadBids = auction.winner_uid != null
          && rawWinningAmount != null
          && rawWinningAmount > 0;

        // ── Error metrics — computed for all auctions ────────────────────────
        // For no-bid closes actualValue = starting_price; divide-by-zero guard
        // ensures both values are positive before computing ratios.
        let absoluteErrorRwf: number | null = null;
        let absolutePercentageError: number | null = null;
        let residual: number | null = null;

        if (predictedValue > 0 && actualValue > 0) {
          residual = predictedValue - actualValue;
          absoluteErrorRwf = Math.round(Math.abs(residual) * 100) / 100;
          absolutePercentageError = Math.abs(residual) / actualValue;
        }

        // ── Actual signal — computed for all auctions ────────────────────────
        // No-bid: actualValue = starting_price → ratio = 1.0 → 'overpriced'.
        let actualSignal: string | null = null;
        if (actualValue > 0 && startingPrice > 0) {
          const actualRatio = actualValue / startingPrice;
          actualSignal = actualRatio > 1.30 ? 'undervalued'
            : actualRatio < 1.10 ? 'overpriced'
            : 'fairly_priced';
        }

        const signalCorrect: boolean | null =
          prediction.value_signal != null && actualSignal != null
            ? prediction.value_signal === actualSignal
            : null;

        // ── Upsert comparison record ─────────────────────────────────────────
        // onConflict: 'auction_id' updates the existing row if present (fixes
        // legacy null-metric rows) and inserts a new row otherwise.
        const { error: upsertErr } = await supabase
          .from('ai_prediction_comparisons')
          .upsert({
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
          }, { onConflict: 'auction_id' });

        if (upsertErr) throw upsertErr;

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
