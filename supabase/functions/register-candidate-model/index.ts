// supabase/functions/register-candidate-model/index.ts
// Phase 9E — Register a newly trained real-data model as a shadow candidate.
//
// Called by training_worker/candidate_registry.py after a successful real-data
// training run. Performs three actions atomically:
//   1. Upsert ai_feature_flags: ai.model_{name}_shadow_version = candidate_version
//   2. Insert ai_candidate_models row (status='evaluating')
//   3. Optionally call POST /models/reload-shadow on the inference service
//      so it immediately starts serving dual predictions (active + candidate)
//
// Required secrets:
//   AI_INFERENCE_URL   — Base URL of the FastAPI inference service (optional).
//                        If omitted, the reload-shadow step is skipped. The
//                        inference service will pick up the new flag on next restart.
//   AI_INFERENCE_TOKEN — Bearer token for the inference service (optional).
//
// Auth: only the training_worker service (service_role key) may call this.
// Super admins may call manually for testing.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AI_INFERENCE_URL = Deno.env.get("AI_INFERENCE_URL") ?? "";
const AI_INFERENCE_TOKEN = Deno.env.get("AI_INFERENCE_TOKEN") ?? "";

const VALID_MODELS = new Set(["model_a", "model_b", "model_c"]);

serve(async (req: Request) => {
  // ── Auth guard — service_role key or super_admin JWT ──────────────────────
  const authHeader = req.headers.get("Authorization") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

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

  // ── Parse + validate body ─────────────────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonError("invalid JSON body", 400);
  }

  const { model_name, candidate_version, active_version } = body as {
    model_name?: string;
    candidate_version?: string;
    active_version?: string;
  };

  if (!model_name || !VALID_MODELS.has(model_name)) {
    return jsonError(`model_name must be one of: ${[...VALID_MODELS].join(", ")}`, 400);
  }
  if (!candidate_version || typeof candidate_version !== "string") {
    return jsonError("candidate_version is required", 400);
  }
  if (!active_version || typeof active_version !== "string") {
    return jsonError("active_version is required", 400);
  }

  // ── Step 1: Update ai_feature_flags shadow version flag ──────────────────
  const flagKey = `ai.${model_name}_shadow_version`;
  const { error: flagErr } = await supabase
    .from("ai_feature_flags")
    .upsert(
      { flag_key: flagKey, flag_value: candidate_version, updated_at: new Date().toISOString() },
      { onConflict: "flag_key" },
    );

  if (flagErr) {
    console.error("Failed to upsert ai_feature_flags:", flagErr);
    return jsonError(`Failed to set shadow flag: ${flagErr.message}`, 500);
  }

  // ── Step 2: Insert ai_candidate_models row ───────────────────────────────
  const { data: candidate, error: candidateErr } = await supabase
    .from("ai_candidate_models")
    .upsert(
      {
        model_name,
        candidate_version,
        active_version_at_registration: active_version,
        status: "evaluating",
        registered_at: new Date().toISOString(),
        evaluation_started_at: new Date().toISOString(),
        min_comparisons_needed: 100,
        comparisons_count: 0,
      },
      { onConflict: "model_name,candidate_version" },
    )
    .select()
    .single();

  if (candidateErr) {
    console.error("Failed to insert ai_candidate_models:", candidateErr);
    return jsonError(`Failed to register candidate: ${candidateErr.message}`, 500);
  }

  // ── Step 3: Hot-reload inference service (optional) ───────────────────────
  let reloadStatus: string = "skipped";
  if (AI_INFERENCE_URL) {
    try {
      const reloadHeaders: Record<string, string> = {
        "Content-Type": "application/json",
      };
      if (AI_INFERENCE_TOKEN) {
        reloadHeaders["Authorization"] = `Bearer ${AI_INFERENCE_TOKEN}`;
      }
      const reloadRes = await fetch(`${AI_INFERENCE_URL}/models/reload-shadow`, {
        method: "POST",
        headers: reloadHeaders,
      });
      reloadStatus = reloadRes.ok ? "ok" : `error:${reloadRes.status}`;
      if (!reloadRes.ok) {
        const body = await reloadRes.text();
        console.warn("reload-shadow returned non-ok:", reloadRes.status, body);
      }
    } catch (err) {
      reloadStatus = `unreachable:${String(err)}`;
      console.warn("Could not reach inference reload-shadow endpoint:", err);
    }
  }

  console.log(
    `Registered candidate ${model_name}@${candidate_version} (active was ${active_version}). reload=${reloadStatus}`,
  );

  return new Response(
    JSON.stringify({
      registered: true,
      model_name,
      candidate_version,
      active_version_at_registration: active_version,
      flag_key: flagKey,
      candidate_id: candidate?.id ?? null,
      inference_reload: reloadStatus,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
