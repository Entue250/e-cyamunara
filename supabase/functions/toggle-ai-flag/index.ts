// supabase/functions/toggle-ai-flag/index.ts
//
// Phase 9I — Super Admin AI Manual Controls
//
// Allows super_admins to toggle any flag in the ai_feature_flags table
// that governs the prediction pipeline's runtime behaviour.
//
// Permitted keys (others are rejected with 400):
//   ai.shadow_mode_enabled           — run predictions silently in background
//   ai.predictions_visible_to_clients — expose AI insights to client screens
//
// NOT permitted via this function (managed by their own flows):
//   ai.retrain_pending             — set by trigger-early-retraining
//   ai.model_X_shadow_version      — set by register-candidate-model
//   ai.retrain_trigger_reason      — set by trigger-early-retraining
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or active super_admin JWT

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_KEYS = new Set([
  "ai.shadow_mode_enabled",
  "ai.predictions_visible_to_clients",   // Phase 9J fix: correct flag key
]);

serve(async (req: Request) => {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // ── CORS preflight ─────────────────────────────────────────────────────────
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
  let key: string | undefined;
  let value: string | undefined;
  try {
    const body = await req.json() as { key?: string; value?: string };
    key   = body.key;
    value = body.value;
  } catch {
    return jsonError("invalid JSON body", 400);
  }

  if (!key || !ALLOWED_KEYS.has(key)) {
    return jsonError(
      `key not permitted. Allowed: ${[...ALLOWED_KEYS].join(", ")}`,
      400,
    );
  }
  if (value !== "true" && value !== "false") {
    return jsonError('value must be "true" or "false"', 400);
  }

  // ── Write flag ─────────────────────────────────────────────────────────────
  const { error: upsertErr } = await supabase
    .from("ai_feature_flags")
    .upsert(
      { key, value, updated_at: new Date().toISOString() },
      { onConflict: "key" },
    );

  if (upsertErr) {
    console.error("[toggle-ai-flag] upsert failed:", upsertErr);
    return jsonError(upsertErr.message, 500);
  }

  // ── Best-effort audit log ──────────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "metrics_collected",
    metadata: { action: "flag_toggled", key, new_value: value },
  }).catch(() => {});

  console.log(`[toggle-ai-flag] ${key} = ${value}`);

  return jsonOk({ ok: true, key, value });
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
