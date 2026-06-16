// supabase/functions/compute-prediction-comparison/index.ts
//
// Phase 9E — Prediction vs Actual Comparison (per model_stage)
//
// Runs every 10 minutes via pg_cron. Finds auctions closed in the last 48 hours
// that have ai_predictions rows but no complete ai_prediction_comparisons row for
// that (auction_id, model_stage) pair.
//
// Phase 9E extension: processes both 'shadow' (active model) and 'candidate'
// (Phase 9E candidate model) predictions independently. Each stage gets its own
// comparison row, enabling per-stage accuracy tracking for the promotion gate.
//
// Upsert key: (auction_id, model_stage) — allows one comparison per stage.
//
// Error metrics:
//   APE  = |predicted - actual_value| / actual_value
//   For no-bid closes: actual_value = starting_price → APE = |pred - start| / start
//
// actual_signal thresholds:
//   actual_value / starting_price > 1.30 → undervalued
//   actual_value / starting_price < 1.10 → overpriced
//   otherwise                            → fairly_priced
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const STAGES_TO_PROCESS = ['shadow', 'candidate'] as const;

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

  const result = {
    compared: 0,
    skipped_no_prediction: 0,
    already_done: 0,
    errors: 0,
    stages_processed: { shadow: 0, candidate: 0 },
  };

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

    // ── Pre-filter: skip (auction_id, model_stage) pairs with complete metrics
    // A pair is complete when absolute_percentage_error is non-null.
    const auctionIds = closedAuctions.map((a: any) => a.id);
    const { data: completeRows } = await supabase
      .from('ai_prediction_comparisons')
      .select('auction_id, model_stage')
      .in('auction_id', auctionIds)
      .not('absolute_percentage_error', 'is', null);

    const alreadyComplete = new Set(
      (completeRows ?? []).map((r: any) => `${r.auction_id}|${r.model_stage}`)
    );

    // ── Process each auction × stage pair ────────────────────────────────────
    for (const auction of closedAuctions) {
      const auctionId: string = auction.id;

      for (const modelStage of STAGES_TO_PROCESS) {
        const pairKey = `${auctionId}|${modelStage}`;

        if (alreadyComplete.has(pairKey)) {
          result.already_done++;
          continue;
        }

        try {
          // Find the most recent auction_price_estimate prediction for this stage
          const { data: predictions, error: pErr } = await supabase
            .from('ai_predictions')
            .select(
              'id, model_version, expected_auction_price, value_signal, starting_price_at_prediction, created_at'
            )
            .eq('auction_id', auctionId)
            .eq('prediction_type', 'auction_price_estimate')
            .eq('model_stage', modelStage)
            .order('created_at', { ascending: false })
            .limit(1);

          if (pErr) throw pErr;

          if (!predictions?.length) {
            // No prediction for this stage — skip silently (candidate may not exist yet)
            if (modelStage === 'shadow') result.skipped_no_prediction++;
            continue;
          }

          const prediction = predictions[0];
          const predictedValue = Number(prediction.expected_auction_price ?? 0);

          const startingPrice = Number(
            prediction.starting_price_at_prediction ?? auction.starting_price ?? 0
          );

          const rawWinningAmount = auction.winning_amount != null
            ? Number(auction.winning_amount)
            : null;
          const actualValue = rawWinningAmount ?? startingPrice;

          const hadBids = auction.winner_uid != null
            && rawWinningAmount != null
            && rawWinningAmount > 0;

          // ── Error metrics ──────────────────────────────────────────────────
          let absoluteErrorRwf: number | null = null;
          let absolutePercentageError: number | null = null;
          let residual: number | null = null;

          if (predictedValue > 0 && actualValue > 0) {
            residual = predictedValue - actualValue;
            absoluteErrorRwf = Math.round(Math.abs(residual) * 100) / 100;
            absolutePercentageError = Math.abs(residual) / actualValue;
          }

          // ── Actual signal ──────────────────────────────────────────────────
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

          // ── Upsert comparison record (keyed by auction_id + model_stage) ───
          const { error: upsertErr } = await supabase
            .from('ai_prediction_comparisons')
            .upsert({
              auction_id: auctionId,
              model_stage: modelStage,
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
            }, { onConflict: 'auction_id,model_stage' });

          if (upsertErr) throw upsertErr;

          await supabase.from('ai_prediction_logs').insert({
            auction_id: auctionId,
            event_type: 'comparison_computed',
            model_versions: { model_a: prediction.model_version },
            metadata: {
              model_stage: modelStage,
              had_bids: hadBids,
              predicted_value: predictedValue,
              actual_value: actualValue,
              absolute_percentage_error: absolutePercentageError,
              signal_correct: signalCorrect,
            },
          }).catch(() => {}); // log failure is non-fatal

          result.compared++;
          (result.stages_processed as Record<string, number>)[modelStage]++;
        } catch (pairErr) {
          console.error(`[compute-comparison] ${auctionId}/${modelStage}:`, pairErr);
          await supabase.from('ai_prediction_logs').insert({
            auction_id: auctionId,
            event_type: 'prediction_error',
            error_code: 'COMPARISON_ERROR',
            error_message: String(pairErr),
            metadata: { model_stage: modelStage },
          }).catch(() => {});
          result.errors++;
        }
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
