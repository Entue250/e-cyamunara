// supabase/functions/check-model-drift/index.ts
//
// Phase 9G — Daily Drift Detection
//
// Runs daily at 04:00 UTC via pg_cron (30 min after promote-candidate at 03:30 UTC).
// Computes drift signals for each model from ai_prediction_comparisons data,
// upserts results into ai_drift_metrics, and triggers early retraining when
// drift_severity = 'high'.
//
// Three drift signals (all derived from model_stage='shadow' comparison rows):
//
//   mape_spike        — 7d rolling MAPE > 30d baseline MAPE × 1.20
//   residual_bias     — |mean_residual| / mean_actual > 0.15
//   high_error_rate   — >10% of recent predictions have APE > 0.50
//
// Severity:
//   none (0 signals) — log only
//   low  (1 signal)  — log only
//   high (2+ signals) — log + call trigger-early-retraining self-invoke
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY (called by pg_cron)
//
// Secrets needed: none beyond SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
// (those are always present in Edge Functions).

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const MAPE_SPIKE_THRESHOLD = 1.20;   // 7d/30d ratio must exceed this
const BIAS_THRESHOLD = 0.15;          // |mean_residual|/mean_actual
const HIGH_ERROR_APE_THRESHOLD = 0.50; // APE value considered "high"
const HIGH_ERROR_RATE_THRESHOLD = 0.10; // fraction of high-APE predictions
const MIN_ROWS_FOR_SIGNAL = 5;         // minimum comparison rows to evaluate

const MODEL_NAMES = ["model_a", "model_b", "model_c"] as const;

// Lookback windows for the two MAPE windows
const DAYS_7 = 7;
const DAYS_30 = 30;

serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ── Auth guard ─────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ") || authHeader !== `Bearer ${serviceKey}`) {
    return jsonError("Unauthorized", 401);
  }

  const supabase = createClient(supabaseUrl, serviceKey);
  const now = new Date();
  const todayStr = now.toISOString().slice(0, 10); // YYYY-MM-DD

  const result: Record<string, unknown> = {
    checked_at: now.toISOString(),
    models: [] as unknown[],
    early_retrain_triggered: false,
    errors: 0,
  };

  let anyHighSeverity = false;
  const highSeverityModels: string[] = [];

  for (const modelName of MODEL_NAMES) {
    try {
      const modelResult = await _checkModelDrift(
        supabase, modelName, now, todayStr,
      );
      (result.models as unknown[]).push(modelResult);

      if (modelResult.drift_severity === "high") {
        anyHighSeverity = true;
        highSeverityModels.push(modelName);
      }
    } catch (err) {
      console.error(`[check-model-drift] ${modelName} error:`, err);
      (result.errors as number)++;
      (result.models as unknown[]).push({
        model_name: modelName,
        outcome: "error",
        error: String(err),
      });
    }
  }

  // ── Trigger early retraining if any model has high severity ───────────────
  if (anyHighSeverity) {
    const triggerOk = await _triggerEarlyRetraining(
      supabaseUrl, serviceKey, highSeverityModels,
    );
    result.early_retrain_triggered = triggerOk;
  }

  return jsonOk(result);
});

// ---------------------------------------------------------------------------
// Per-model drift check
// ---------------------------------------------------------------------------

async function _checkModelDrift(
  supabase: ReturnType<typeof createClient>,
  modelName: string,
  now: Date,
  todayStr: string,
): Promise<Record<string, unknown>> {
  const cutoff30d = new Date(now.getTime() - DAYS_30 * 86_400_000).toISOString();
  const cutoff7d = new Date(now.getTime() - DAYS_7 * 86_400_000).toISOString();

  // ── Fetch 30-day comparison rows (shadow stage only) ──────────────────────
  const { data: rows30, error: e30 } = await supabase
    .from("ai_prediction_comparisons")
    .select("absolute_percentage_error, residual, actual_value, created_at")
    .eq("model_stage", "shadow")
    .not("absolute_percentage_error", "is", null)
    .not("actual_value", "is", null)
    .gte("created_at", cutoff30d)
    .order("created_at", { ascending: false });

  if (e30) throw e30;

  const rows30d = rows30 ?? [];
  const rows7d = rows30d.filter((r: any) => r.created_at >= cutoff7d);

  const apes30d = rows30d.map((r: any) => r.absolute_percentage_error as number);
  const apes7d = rows7d.map((r: any) => r.absolute_percentage_error as number);
  const residuals = rows30d
    .filter((r: any) => r.residual != null)
    .map((r: any) => r.residual as number);
  const actuals = rows30d
    .filter((r: any) => r.actual_value != null)
    .map((r: any) => r.actual_value as number);

  // ── Compute MAPE values ───────────────────────────────────────────────────
  const mape30d = apes30d.length > 0 ? _mean(apes30d) : null;
  const mape7d = apes7d.length > 0 ? _mean(apes7d) : null;

  // ── Signal: mape_spike ────────────────────────────────────────────────────
  const mapeSpikeRatio = mape7d != null && mape30d != null && mape30d > 0
    ? mape7d / mape30d
    : null;
  const mapeSpikeDetected = mapeSpikeRatio != null
    && mapeSpikeRatio > MAPE_SPIKE_THRESHOLD;

  // ── Signal: residual_bias ─────────────────────────────────────────────────
  let residualBiasRatio: number | null = null;
  let residualBiasDetected = false;
  let meanResidual: number | null = null;
  let meanActual: number | null = null;

  if (residuals.length >= MIN_ROWS_FOR_SIGNAL && actuals.length >= MIN_ROWS_FOR_SIGNAL) {
    meanResidual = _mean(residuals);
    meanActual = _mean(actuals);
    if (meanActual > 0) {
      residualBiasRatio = Math.abs(meanResidual) / meanActual;
      residualBiasDetected = residualBiasRatio > BIAS_THRESHOLD;
    }
  }

  // ── Signal: high_error_rate ───────────────────────────────────────────────
  let highErrorRate: number | null = null;
  let highErrorRateDetected = false;
  let highErrorCount = 0;

  if (apes30d.length >= MIN_ROWS_FOR_SIGNAL) {
    highErrorCount = apes30d.filter(a => a > HIGH_ERROR_APE_THRESHOLD).length;
    highErrorRate = highErrorCount / apes30d.length;
    highErrorRateDetected = highErrorRate > HIGH_ERROR_RATE_THRESHOLD;
  }

  // ── Severity ──────────────────────────────────────────────────────────────
  const signals: string[] = [];
  if (mapeSpikeDetected) signals.push("mape_spike");
  if (residualBiasDetected) signals.push("residual_bias");
  if (highErrorRateDetected) signals.push("high_error_rate");

  const driftDetected = signals.length > 0;
  const driftSeverity = signals.length === 0 ? "none"
    : signals.length === 1 ? "low"
    : "high";

  // ── Upsert into ai_drift_metrics ──────────────────────────────────────────
  const { error: upsertErr } = await supabase
    .from("ai_drift_metrics")
    .upsert({
      model_name: modelName,
      metric_date: todayStr,
      comparisons_7d: rows7d.length,
      comparisons_30d: rows30d.length,
      mape_7d: mape7d != null ? Math.round(mape7d * 10000) / 10000 : null,
      mape_30d: mape30d != null ? Math.round(mape30d * 10000) / 10000 : null,
      mape_spike_ratio: mapeSpikeRatio != null ? Math.round(mapeSpikeRatio * 10000) / 10000 : null,
      mape_spike_detected: mapeSpikeDetected,
      mean_residual: meanResidual != null ? Math.round(meanResidual * 100) / 100 : null,
      mean_actual: meanActual != null ? Math.round(meanActual * 100) / 100 : null,
      residual_bias_ratio: residualBiasRatio != null ? Math.round(residualBiasRatio * 10000) / 10000 : null,
      residual_bias_detected: residualBiasDetected,
      high_error_count: highErrorCount,
      high_error_total: apes30d.length,
      high_error_rate: highErrorRate != null ? Math.round(highErrorRate * 10000) / 10000 : null,
      high_error_rate_detected: highErrorRateDetected,
      drift_detected: driftDetected,
      drift_severity: driftSeverity,
      signals_triggered: signals,
      early_retrain_triggered: false, // updated after trigger call
      notes: signals.length > 0
        ? `Signals: ${signals.join(", ")}`
        : "No drift detected",
    }, { onConflict: "model_name,metric_date" });

  if (upsertErr) {
    console.warn(`[check-model-drift] ${modelName} upsert warning:`, upsertErr);
  }

  console.log(
    `[check-model-drift] ${modelName}: severity=${driftSeverity} signals=${signals.join(",")||"none"} ` +
    `mape_7d=${mape7d?.toFixed(4) ?? "null"} mape_30d=${mape30d?.toFixed(4) ?? "null"} ` +
    `rows_7d=${rows7d.length} rows_30d=${rows30d.length}`,
  );

  return {
    model_name: modelName,
    drift_severity: driftSeverity,
    drift_detected: driftDetected,
    signals_triggered: signals,
    mape_7d: mape7d,
    mape_30d: mape30d,
    comparisons_7d: rows7d.length,
    comparisons_30d: rows30d.length,
  };
}

// ---------------------------------------------------------------------------
// Trigger early retraining via self-invoke
// ---------------------------------------------------------------------------

async function _triggerEarlyRetraining(
  supabaseUrl: string,
  serviceKey: string,
  highSeverityModels: string[],
): Promise<boolean> {
  try {
    const url = `${supabaseUrl}/functions/v1/trigger-early-retraining`;
    const res = await fetch(url, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        trigger: "drift",
        models: highSeverityModels,
      }),
    });
    if (!res.ok) {
      const body = await res.text();
      console.warn(`[check-model-drift] trigger-early-retraining returned ${res.status}: ${body}`);
      return false;
    }
    console.log(`[check-model-drift] early retraining triggered for: ${highSeverityModels.join(", ")}`);
    return true;
  } catch (err) {
    console.warn("[check-model-drift] could not reach trigger-early-retraining:", err);
    return false;
  }
}

// ---------------------------------------------------------------------------
// Utilities
// ---------------------------------------------------------------------------

function _mean(values: number[]): number {
  return values.reduce((s, v) => s + v, 0) / values.length;
}

function jsonOk(data: unknown): Response {
  return new Response(JSON.stringify(data), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
