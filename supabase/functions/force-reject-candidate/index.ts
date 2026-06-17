// supabase/functions/force-reject-candidate/index.ts
//
// Phase 9I — Super Admin AI Manual Controls
//
// Manually rejects a candidate model that is currently under evaluation.
// Clears the shadow slot for the model so a new candidate can be registered.
//
// Use this when:
//   - The candidate is known to be bad (data issue, wrong training run)
//   - You want to clear the evaluation slot immediately
//   - The automated gate would eventually reject it, but you can't wait
//
// What it does:
//   1. Validate auth (super_admin JWT or service role)
//   2. Fetch ai_candidate_models row by id — reject if not 'evaluating'
//   3. Update ai_candidate_models: status='rejected', evaluation_ended_at=now()
//   4. Clear ai_feature_flags shadow version flag for the model
//   5. POST /models/reload-shadow to inference service (remove shadow model)
//   6. Log to ai_prediction_logs (event_type='candidate_rejected', forced=true)
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
  let reason = "manual_rejection";
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
    console.error("[force-reject-candidate] fetch error:", fetchErr);
    return jsonError(fetchErr.message, 500);
  }
  if (!cand) {
    return jsonError(`candidate '${candidateId}' not found`, 404);
  }
  if (cand.status !== "evaluating") {
    return jsonError(
      `cannot reject: candidate status is '${cand.status}', expected 'evaluating'`,
      409,
    );
  }

  const now = new Date().toISOString();

  // ── Step 3: Mark candidate as rejected ────────────────────────────────────
  const { error: rejectErr } = await supabase
    .from("ai_candidate_models")
    .update({
      status: "rejected",
      evaluation_ended_at: now,
      notes: `forced_rejection reason:${reason}`,
    })
    .eq("id", candidateId);

  if (rejectErr) {
    console.error("[force-reject-candidate] update error:", rejectErr);
    return jsonError(rejectErr.message, 500);
  }

  // ── Step 4: Clear shadow flag ──────────────────────────────────────────────
  await supabase
    .from("ai_feature_flags")
    .update({ value: "", updated_at: now })
    .eq("key", `ai.${cand.model_name}_shadow_version`)
    .catch((e: unknown) =>
      console.warn("[force-reject-candidate] clear shadow flag failed:", e),
    );

  // ── Step 5: Tell inference service to reload without shadow ───────────────
  await _reloadShadow();

  // ── Step 6: Log event ──────────────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "candidate_rejected",
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
    },
  }).catch(() => {});

  console.log(
    `[force-reject-candidate] ${cand.model_name}@${cand.candidate_version} rejected ` +
    `(forced, reason=${reason})`,
  );

  return jsonOk({
    ok: true,
    model_name: cand.model_name,
    rejected_version: cand.candidate_version,
    reason,
  });
});

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
