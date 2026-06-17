// supabase/functions/force-promote-candidate/index.ts
//
// Phase 9I — Super Admin AI Manual Controls
//
// Manually promotes a candidate model to active, bypassing the automated
// 100-comparison MAPE gate from promote-candidate (Phase 9F).
//
// Use this when:
//   - A candidate is clearly superior but hasn't collected enough comparisons yet
//   - You need to roll forward during an incident
//   - A test candidate should be promoted immediately
//
// What it does (mirrors promote-candidate's ON PASS path):
//   1. Validate auth (super_admin JWT or service role)
//   2. Fetch ai_candidate_models row by id — reject if not 'evaluating'
//   3. POST /models/{model_name}/promote to inference service
//   4. Update ai_candidate_models: status='promoted', evaluation_ended_at=now()
//   5. Supersede other evaluating candidates for the same model
//   6. Clear ai_feature_flags shadow version flag for the model
//   7. POST /models/reload-shadow to inference service
//   8. Log to ai_prediction_logs (event_type='candidate_promoted', forced=true)
//
// Required secrets (shared with promote-candidate):
//   AI_INFERENCE_URL   — FastAPI inference service base URL
//   AI_INFERENCE_TOKEN — Bearer token for inference service (optional)
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or active super_admin JWT

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AI_INFERENCE_URL   = Deno.env.get("AI_INFERENCE_URL") ?? "";
const AI_INFERENCE_TOKEN = Deno.env.get("AI_INFERENCE_TOKEN") ?? "";

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
  let candidateId: string | undefined;
  let reason = "manual_promotion";
  try {
    const body = await req.json() as { candidate_id?: string; reason?: string };
    candidateId = body.candidate_id;
    if (body.reason) reason = body.reason;
  } catch {
    return jsonError("invalid JSON body", 400);
  }

  if (!candidateId) {
    return jsonError("candidate_id is required", 400);
  }

  // ── Fetch candidate ────────────────────────────────────────────────────────
  const { data: cand, error: fetchErr } = await supabase
    .from("ai_candidate_models")
    .select(
      "id, model_name, candidate_version, active_version_at_registration, " +
      "status, comparisons_count, candidate_mape, active_mape",
    )
    .eq("id", candidateId)
    .maybeSingle();

  if (fetchErr) {
    console.error("[force-promote-candidate] fetch error:", fetchErr);
    return jsonError(fetchErr.message, 500);
  }
  if (!cand) {
    return jsonError(`candidate '${candidateId}' not found`, 404);
  }
  if (cand.status !== "evaluating") {
    return jsonError(
      `cannot promote: candidate status is '${cand.status}', expected 'evaluating'`,
      409,
    );
  }

  const now = new Date().toISOString();

  // ── Step 3: Tell inference service to activate this version ───────────────
  const inferenceOk = await _callInferencePromote(cand.model_name, cand.candidate_version);

  // ── Step 4: Mark candidate as promoted ────────────────────────────────────
  const { error: promoteErr } = await supabase
    .from("ai_candidate_models")
    .update({
      status: "promoted",
      evaluation_ended_at: now,
      notes: `forced_promotion reason:${reason} inference_ok:${inferenceOk}`,
    })
    .eq("id", candidateId);

  if (promoteErr) {
    console.error("[force-promote-candidate] update error:", promoteErr);
    return jsonError(promoteErr.message, 500);
  }

  // ── Step 5: Supersede other evaluating candidates for same model ──────────
  await supabase
    .from("ai_candidate_models")
    .update({ status: "superseded", evaluation_ended_at: now })
    .eq("model_name", cand.model_name)
    .eq("status", "evaluating")
    .neq("id", candidateId)
    .catch((e: unknown) =>
      console.warn("[force-promote-candidate] supersede step failed:", e),
    );

  // ── Step 6: Clear shadow flag for this model ───────────────────────────────
  await supabase
    .from("ai_feature_flags")
    .update({ value: "", updated_at: now })
    .eq("key", `ai.${cand.model_name}_shadow_version`)
    .catch((e: unknown) =>
      console.warn("[force-promote-candidate] clear shadow flag failed:", e),
    );

  // ── Step 7: Tell inference service to reload without shadow ───────────────
  await _reloadShadow();

  // ── Step 8: Log event ──────────────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "candidate_promoted",
    metadata: {
      candidate_id: candidateId,
      model_name: cand.model_name,
      candidate_version: cand.candidate_version,
      active_version_at_registration: cand.active_version_at_registration,
      comparisons_count: cand.comparisons_count,
      candidate_mape: cand.candidate_mape,
      active_mape: cand.active_mape,
      reason,
      forced: true,
      inference_promote_ok: inferenceOk,
    },
  }).catch(() => {});

  console.log(
    `[force-promote-candidate] ${cand.model_name}@${cand.candidate_version} promoted ` +
    `(forced, inference_ok=${inferenceOk})`,
  );

  return jsonOk({
    ok: true,
    model_name: cand.model_name,
    promoted_version: cand.candidate_version,
    inference_promote_ok: inferenceOk,
    reason,
  });
});

// ── Inference service helpers (shared pattern with promote-candidate) ────────

async function _callInferencePromote(modelName: string, version: string): Promise<boolean> {
  if (!AI_INFERENCE_URL) {
    console.warn("[force-promote-candidate] AI_INFERENCE_URL not set — skipping inference call");
    return false;
  }
  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (AI_INFERENCE_TOKEN) headers["Authorization"] = `Bearer ${AI_INFERENCE_TOKEN}`;
    const res = await fetch(`${AI_INFERENCE_URL}/models/${modelName}/promote`, {
      method: "POST",
      headers,
      body: JSON.stringify({ version }),
    });
    if (!res.ok) {
      console.warn(`[force-promote-candidate] inference returned ${res.status}: ${await res.text()}`);
      return false;
    }
    return true;
  } catch (err) {
    console.warn("[force-promote-candidate] could not reach inference promote endpoint:", err);
    return false;
  }
}

async function _reloadShadow(): Promise<void> {
  if (!AI_INFERENCE_URL) return;
  try {
    const headers: Record<string, string> = { "Content-Type": "application/json" };
    if (AI_INFERENCE_TOKEN) headers["Authorization"] = `Bearer ${AI_INFERENCE_TOKEN}`;
    await fetch(`${AI_INFERENCE_URL}/models/reload-shadow`, { method: "POST", headers });
  } catch {
    // Non-fatal
  }
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
