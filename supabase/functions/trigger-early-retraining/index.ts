// supabase/functions/trigger-early-retraining/index.ts
//
// Phase 9G — Early Retraining Trigger
//
// Called by check-model-drift when drift_severity = 'high' on any model.
// Also callable manually by super_admins to force an immediate retrain.
//
// What it does:
//   1. Validates auth (service_role or super_admin JWT)
//   2. Checks ai_feature_flags — skips if retrain_pending is already 'true'
//      (prevents double-trigger on the same day)
//   3. POSTs to TRAINING_WORKER_URL/train with {datasource: "real", trigger}
//   4. Sets ai_feature_flags:
//        ai.retrain_pending        = 'true'
//        ai.retrain_trigger_reason = trigger:drift or trigger:manual
//   5. Logs to ai_prediction_logs (event_type = 'early_retrain_triggered')
//   6. Updates ai_drift_metrics.early_retrain_triggered = true for today
//
// Required secrets:
//   TRAINING_WORKER_URL   — base URL of training worker HTTP API
//   TRAINING_WORKER_TOKEN — bearer token for training worker (optional)
//
// If TRAINING_WORKER_URL is not set (training worker not yet hosted),
// steps 2–4 still run so the flag is set and the intent is logged.
// The training worker can then pick up retrain_pending on next scheduled run.
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or super_admin JWT

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TRAINING_WORKER_URL = Deno.env.get("TRAINING_WORKER_URL") ?? "";
const TRAINING_WORKER_TOKEN = Deno.env.get("TRAINING_WORKER_TOKEN") ?? "";

serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ── Auth guard ─────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return jsonError("missing Authorization header", 401);
  }
  const token = authHeader.replace("Bearer ", "");
  const isServiceRole = token === serviceKey;

  const supabase = createClient(supabaseUrl, serviceKey);

  if (!isServiceRole) {
    const { data: { user }, error } = await supabase.auth.getUser(token);
    if (error || !user) return jsonError("unauthorized", 401);
    const { data: sa } = await supabase
      .from("super_admins")
      .select("id")
      .eq("id", user.id)
      .eq("account_status", "active")
      .maybeSingle();
    if (!sa) return jsonError("forbidden", 403);
  }

  // ── Parse body ─────────────────────────────────────────────────────────────
  let body: Record<string, unknown> = {};
  try {
    body = await req.json();
  } catch {
    // body is optional
  }
  const trigger = (body.trigger as string | undefined) ?? "manual";
  const models = (body.models as string[] | undefined) ?? ["model_a", "model_b", "model_c"];
  const todayStr = new Date().toISOString().slice(0, 10);
  const triggerReason = `trigger:${trigger} models:${models.join(",")} date:${todayStr}`;

  // ── Guard: skip if retrain already pending ─────────────────────────────────
  const { data: pendingFlag } = await supabase
    .from("ai_feature_flags")
    .select("value")
    .eq("key", "ai.retrain_pending")
    .maybeSingle();

  if (pendingFlag?.value === "true") {
    return jsonOk({
      status: "skipped",
      reason: "retrain_already_pending",
      trigger,
    });
  }

  // ── Call training worker (non-fatal if URL not set) ────────────────────────
  let workerCalled = false;
  let workerStatus: string | null = null;

  if (TRAINING_WORKER_URL) {
    try {
      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (TRAINING_WORKER_TOKEN) headers["Authorization"] = `Bearer ${TRAINING_WORKER_TOKEN}`;
      const res = await fetch(`${TRAINING_WORKER_URL.replace(/\/$/, "")}/train`, {
        method: "POST",
        headers,
        body: JSON.stringify({ datasource: "real", trigger, models }),
      });
      workerCalled = res.ok;
      workerStatus = `${res.status}`;
      if (!res.ok) {
        const body = await res.text();
        console.warn(`[trigger-early-retraining] worker returned ${res.status}: ${body}`);
      } else {
        console.log(`[trigger-early-retraining] worker accepted request (${res.status})`);
      }
    } catch (err) {
      console.warn("[trigger-early-retraining] could not reach training worker:", err);
      workerStatus = `connection_error:${err}`;
    }
  } else {
    console.warn(
      "[trigger-early-retraining] TRAINING_WORKER_URL not set — " +
      "setting retrain_pending flag only. Training worker will pick it up on next scheduled run.",
    );
    workerStatus = "url_not_configured";
  }

  // ── Update ai_feature_flags ────────────────────────────────────────────────
  await supabase
    .from("ai_feature_flags")
    .upsert([
      { key: "ai.retrain_pending", value: "true", updated_at: new Date().toISOString() },
      { key: "ai.retrain_trigger_reason", value: triggerReason, updated_at: new Date().toISOString() },
    ], { onConflict: "key" });

  // ── Log to ai_prediction_logs ──────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "early_retrain_triggered",
    metadata: {
      trigger,
      models,
      trigger_reason: triggerReason,
      worker_called: workerCalled,
      worker_status: workerStatus,
      training_worker_configured: !!TRAINING_WORKER_URL,
    },
  }).catch((e: unknown) => console.warn("Log insert failed:", e));

  // ── Mark ai_drift_metrics row for today ────────────────────────────────────
  // Best-effort: update all model rows for today with early_retrain_triggered=true
  for (const modelName of models) {
    await supabase
      .from("ai_drift_metrics")
      .update({ early_retrain_triggered: true })
      .eq("model_name", modelName)
      .eq("metric_date", todayStr)
      .catch(() => {});
  }

  console.log(
    `[trigger-early-retraining] done — trigger=${trigger} worker_called=${workerCalled} ` +
    `worker_status=${workerStatus}`,
  );

  return jsonOk({
    status: "triggered",
    trigger,
    models,
    trigger_reason: triggerReason,
    worker_called: workerCalled,
    worker_status: workerStatus,
    training_worker_configured: !!TRAINING_WORKER_URL,
    retrain_pending_flag_set: true,
  });
});

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
