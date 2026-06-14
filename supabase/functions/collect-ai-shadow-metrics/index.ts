// supabase/functions/collect-ai-shadow-metrics/index.ts
//
// Phase 4B Shadow Mode — Daily Metrics Aggregation
//
// Runs daily at 02:00 UTC via pg_cron. Aggregates the previous UTC day's
// prediction events into a single ai_shadow_metrics row. Also computes
// rolling accuracy from the last 100 closed auctions with bids.
//
// Idempotency:
//   • Upserts on metric_date UNIQUE constraint (re-running overwrites stale data)
//   • Multiple calls on the same UTC day overwrite with fresh aggregations
//
// Retrain trigger:
//   • If rolling MAPE > ai.retrain_mape_trigger_threshold AND
//     ai.retrain_pending = 'false', sets retrain_pending = 'true' and
//     records the reason in ai.retrain_trigger_reason
//   • Does NOT update ai.last_retrain_date (that is set on retrain completion)
//
// Coverage definition:
//   • eligible = active auctions now + auctions closed yesterday
//   • covered  = distinct auction_ids with prediction_generated events yesterday
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

  try {
    // ── Date window: yesterday UTC ────────────────────────────────────────────
    const now = new Date();
    const yesterday = new Date(now);
    yesterday.setUTCDate(yesterday.getUTCDate() - 1);
    const metricDate = yesterday.toISOString().split('T')[0];
    const dayStart = `${metricDate}T00:00:00.000Z`;
    const dayEnd = `${metricDate}T23:59:59.999Z`;

    // ── Read thresholds from feature flags ────────────────────────────────────
    const { data: flagRows, error: flagErr } = await supabase
      .from('ai_feature_flags')
      .select('key, value')
      .in('key', [
        'ai.retrain_mape_trigger_threshold',
        'ai.retrain_pending',
      ]);

    if (flagErr) throw flagErr;

    const flags = Object.fromEntries(
      (flagRows ?? []).map((r: any) => [r.key, r.value])
    );
    const mapeThreshold = parseFloat(flags['ai.retrain_mape_trigger_threshold'] ?? '0.25');
    const currentRetrainPending = flags['ai.retrain_pending'] ?? 'false';

    // ── Aggregate yesterday's prediction logs ────────────────────────────────
    const { data: logs, error: logsErr } = await supabase
      .from('ai_prediction_logs')
      .select('event_type, duration_ms')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd);

    if (logsErr) throw logsErr;

    const logsData = logs ?? [];
    const predictionsGenerated = logsData.filter(
      (l: any) => l.event_type === 'prediction_generated'
    ).length;
    const predictionsSkipped = logsData.filter(
      (l: any) => l.event_type === 'prediction_skipped'
    ).length;
    const predictionsError = logsData.filter(
      (l: any) => l.event_type === 'prediction_error'
    ).length;

    // Latency distribution for generated predictions (sorted ascending for p95)
    const generatedMs: number[] = logsData
      .filter((l: any) => l.event_type === 'prediction_generated' && l.duration_ms != null)
      .map((l: any) => l.duration_ms as number)
      .sort((a: number, b: number) => a - b);

    const avgInferenceMs = generatedMs.length > 0
      ? generatedMs.reduce((s: number, v: number) => s + v, 0) / generatedMs.length
      : null;
    const p95InferenceMs = generatedMs.length > 0
      ? generatedMs[Math.floor(generatedMs.length * 0.95)]
      : null;

    // ── Value signal distribution yesterday ────────────────────────────────────
    const { data: signalRows } = await supabase
      .from('ai_predictions')
      .select('value_signal')
      .eq('prediction_type', 'auction_price_estimate')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd)
      .not('value_signal', 'is', null);

    const signalUndervalued = (signalRows ?? []).filter(
      (r: any) => r.value_signal === 'undervalued'
    ).length;
    const signalFairlyPriced = (signalRows ?? []).filter(
      (r: any) => r.value_signal === 'fairly_priced'
    ).length;
    const signalOverpriced = (signalRows ?? []).filter(
      (r: any) => r.value_signal === 'overpriced'
    ).length;

    // ── Average Model A confidence yesterday ──────────────────────────────────
    const { data: confRows } = await supabase
      .from('ai_predictions')
      .select('confidence_score')
      .eq('prediction_type', 'auction_price_estimate')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd)
      .not('confidence_score', 'is', null);

    const confScores = (confRows ?? []).map((r: any) => r.confidence_score as number);
    const avgConfidenceModelA = confScores.length > 0
      ? confScores.reduce((s: number, v: number) => s + v, 0) / confScores.length
      : null;

    // ── Coverage calculation ──────────────────────────────────────────────────
    // eligible = active auctions right now + auctions closed yesterday
    const [{ count: activeCount }, { count: closedYesterdayCount }] = await Promise.all([
      supabase
        .from('auctions')
        .select('*', { count: 'exact', head: true })
        .eq('auction_status', 'active')
        .eq('is_deleted', false),
      supabase
        .from('auctions')
        .select('*', { count: 'exact', head: true })
        .eq('auction_status', 'closed')
        .eq('is_deleted', false)
        .gte('closed_at', dayStart)
        .lte('closed_at', dayEnd),
    ]);

    const totalEligible = (activeCount ?? 0) + (closedYesterdayCount ?? 0);

    // covered = distinct auctions that got a prediction_generated log entry yesterday
    const { data: coveredRows } = await supabase
      .from('ai_prediction_logs')
      .select('auction_id')
      .eq('event_type', 'prediction_generated')
      .gte('created_at', dayStart)
      .lte('created_at', dayEnd)
      .not('auction_id', 'is', null);

    const coveredCount = new Set((coveredRows ?? []).map((r: any) => r.auction_id)).size;
    const coverageRate = totalEligible > 0 ? coveredCount / totalEligible : null;

    // ── Rolling accuracy (last 100 closed auctions with bids) ─────────────────
    const { data: comparisons, error: compErr } = await supabase
      .from('ai_prediction_comparisons')
      .select(
        'absolute_percentage_error, absolute_error_rwf, signal_correct, had_bids'
      )
      .eq('had_bids', true)
      .order('created_at', { ascending: false })
      .limit(100);

    if (compErr) throw compErr;

    const compWithMetrics = (comparisons ?? []).filter(
      (c: any) => c.absolute_percentage_error != null
    );
    const rollingMapeModelA = compWithMetrics.length > 0
      ? compWithMetrics.reduce(
          (s: number, c: any) => s + c.absolute_percentage_error,
          0
        ) / compWithMetrics.length
      : null;
    const rollingMaeRwfModelA = compWithMetrics.length > 0
      ? compWithMetrics.reduce(
          (s: number, c: any) => s + (c.absolute_error_rwf ?? 0),
          0
        ) / compWithMetrics.length
      : null;

    const withSignal = (comparisons ?? []).filter(
      (c: any) => c.signal_correct != null
    );
    const signalAccuracyRate = withSignal.length > 0
      ? withSignal.filter((c: any) => c.signal_correct).length / withSignal.length
      : null;

    const comparisonsComputed = comparisons?.length ?? 0;

    // ── Retrain trigger check ─────────────────────────────────────────────────
    let retrainTriggered = false;
    let retrainTriggerReason: string | null = null;

    if (
      rollingMapeModelA != null
      && rollingMapeModelA > mapeThreshold
      && currentRetrainPending !== 'true'
    ) {
      retrainTriggered = true;
      retrainTriggerReason =
        `mape=${rollingMapeModelA.toFixed(4)}_threshold=${mapeThreshold}_n=${compWithMetrics.length}`;

      const nowIso = new Date().toISOString();
      await Promise.all([
        supabase
          .from('ai_feature_flags')
          .update({ value: 'true', updated_at: nowIso })
          .eq('key', 'ai.retrain_pending')
          .eq('value', 'false'),
        supabase
          .from('ai_feature_flags')
          .update({ value: retrainTriggerReason, updated_at: nowIso })
          .eq('key', 'ai.retrain_trigger_reason'),
      ]);
    }

    // ── Upsert metrics row ────────────────────────────────────────────────────
    const metricsRow = {
      metric_date: metricDate,
      predictions_generated: predictionsGenerated,
      predictions_skipped: predictionsSkipped,
      predictions_error: predictionsError,
      eligible_auctions: totalEligible,
      covered_auctions: coveredCount,
      coverage_rate: coverageRate,
      avg_inference_ms: avgInferenceMs,
      p95_inference_ms: p95InferenceMs,
      avg_confidence_model_a: avgConfidenceModelA,
      signal_undervalued_count: signalUndervalued,
      signal_fairly_priced_count: signalFairlyPriced,
      signal_overpriced_count: signalOverpriced,
      comparisons_computed: comparisonsComputed,
      rolling_mape_model_a: rollingMapeModelA,
      rolling_mae_rwf_model_a: rollingMaeRwfModelA,
      signal_accuracy_rate: signalAccuracyRate,
      retrain_triggered: retrainTriggered,
      retrain_trigger_reason: retrainTriggerReason,
    };

    const { error: upsertErr } = await supabase
      .from('ai_shadow_metrics')
      .upsert(metricsRow, { onConflict: 'metric_date' });

    if (upsertErr) throw upsertErr;

    // ── Audit log ─────────────────────────────────────────────────────────────
    await supabase.from('ai_prediction_logs').insert({
      event_type: 'metrics_collected',
      metadata: {
        metric_date: metricDate,
        predictions_generated: predictionsGenerated,
        predictions_skipped: predictionsSkipped,
        predictions_error: predictionsError,
        coverage_rate: coverageRate,
        rolling_mape: rollingMapeModelA,
        retrain_triggered: retrainTriggered,
      },
    });

    return json({ metric_date: metricDate, ...metricsRow });
  } catch (e) {
    console.error('[collect-shadow-metrics] fatal:', e);
    return json({ error: String(e) }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
