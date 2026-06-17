// supabase/functions/resolve-model-drift/index.ts
//
// Phase 9J — Drift Acknowledgment
//
// Allows a super_admin to manually acknowledge a drift alert for a specific
// model. This is a soft acknowledgment — it marks today's ai_drift_metrics
// row as drift_detected=false and drift_severity='none', then logs a
// 'drift_resolved' event. The check-model-drift cron will recompute drift
// at 04:00 UTC using fresh comparison data, so this only suppresses today's
// alert.
//
// Use this when:
//   - Drift was triggered by a data anomaly that is now resolved
//   - You have investigated the alert and determined it is a false positive
//   - You want the dashboard to show 'none' until the next scheduled check
//
// Body: { model_name: "model_a" | "model_b" | "model_c", reason?: string }
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or active super_admin JWT

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const VALID_MODELS = new Set(["model_a", "model_b", "model_c"]);

serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Authorization, Content-Type",
      },
    });
  }

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
    if (!sa) return jsonError("forbidden: super_admin only", 403);
  }

  // ── Parse body ─────────────────────────────────────────────────────────────
  let modelName: string | undefined;
  let reason = "manual_acknowledgment";
  try {
    const body = await req.json() as { model_name?: string; reason?: string };
    modelName = body.model_name;
    if (body.reason) reason = body.reason;
  } catch {
    return jsonError("invalid JSON body", 400);
  }

  if (!modelName || !VALID_MODELS.has(modelName)) {
    return jsonError(
      `model_name must be one of: ${[...VALID_MODELS].join(", ")}`,
      400,
    );
  }

  const today = new Date().toISOString().slice(0, 10);

  // ── Soft-clear today's drift row for this model ───────────────────────────
  // The check-model-drift cron will recompute tomorrow at 04:00 UTC.
  // Using UPSERT so the operation is safe even if no row exists for today.
  const { error: upsertErr } = await supabase
    .from("ai_drift_metrics")
    .upsert(
      {
        model_name:               modelName,
        metric_date:              today,
        drift_detected:           false,
        drift_severity:           "none",
        signals_triggered:        [],
        early_retrain_triggered:  false,
      },
      { onConflict: "model_name,metric_date" },
    );

  if (upsertErr) {
    console.error("[resolve-model-drift] upsert error:", upsertErr);
    return jsonError(upsertErr.message, 500);
  }

  // ── Log the acknowledgment ─────────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "drift_resolved",
    metadata: {
      model_name: modelName,
      metric_date: today,
      reason,
      action: "manual_acknowledgment",
    },
  }).catch((e: unknown) =>
    console.warn("[resolve-model-drift] log insert failed:", e),
  );

  console.log(
    `[resolve-model-drift] ${modelName} drift acknowledged for ${today} (reason=${reason})`,
  );

  return jsonOk({
    ok: true,
    model_name: modelName,
    metric_date: today,
    reason,
    note: "Drift cleared for today. check-model-drift will recompute at 04:00 UTC.",
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
