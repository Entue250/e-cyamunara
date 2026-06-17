// supabase/functions/promote-candidate/index.ts
//
// Phase 9F — Promotion Engine
//
// Runs daily at 03:30 UTC via pg_cron (30 min after collect-candidate-metrics).
// Also callable manually by super_admins for on-demand evaluation.
//
// For each ai_candidate_models row with status='evaluating':
//
//   EXPIRY check (before gate):
//     If registered_at < now - 30 days AND comparisons_count < min_comparisons_needed
//     → status = 'expired', clear shadow flag, call reload-shadow
//
//   GATE check (when metrics available):
//     Gate 1: comparisons_count >= min_comparisons_needed (default 100)
//     Gate 2: candidate_mape IS NOT NULL
//     Gate 3: active_mape IS NOT NULL AND > 0
//     Gate 4: candidate_mape < active_mape * 0.97 (3% improvement)
//
//   ON PASS:
//     - Call POST /models/{model_name}/promote on inference service
//     - status = 'promoted', evaluation_ended_at = now()
//     - Clear ai_feature_flags shadow version flag (set to '')
//     - Call reload-shadow (inference service re-loads without shadow)
//     - Log to ai_prediction_logs
//
//   ON FAIL (gate evaluated but did not pass):
//     - status = 'rejected', evaluation_ended_at = now()
//     - Clear shadow flag, call reload-shadow
//     - Log reason to ai_prediction_logs
//
//   PENDING (not enough comparisons yet, not expired):
//     - No status change; log current metrics for observability
//
// Required secrets:
//   AI_INFERENCE_URL   — FastAPI inference service base URL
//   AI_INFERENCE_TOKEN — Bearer token for inference service (optional)
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or super_admin JWT

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const AI_INFERENCE_URL = Deno.env.get("AI_INFERENCE_URL") ?? "";
const AI_INFERENCE_TOKEN = Deno.env.get("AI_INFERENCE_TOKEN") ?? "";

const IMPROVEMENT_THRESHOLD = 0.97;  // candidate_mape < active_mape * 0.97
const EXPIRY_DAYS = 30;

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

  const result: Record<string, unknown> = {
    evaluated: 0,
    promoted: 0,
    rejected: 0,
    expired: 0,
    pending: 0,
    errors: 0,
    candidates: [] as unknown[],
  };

  try {
    const now = new Date();

    // ── Fetch all evaluating candidates ──────────────────────────────────────
    const { data: candidates, error: cErr } = await supabase
      .from("ai_candidate_models")
      .select(
        "id, model_name, candidate_version, active_version_at_registration, " +
        "status, registered_at, min_comparisons_needed, comparisons_count, " +
        "candidate_mape, active_mape",
      )
      .eq("status", "evaluating");

    if (cErr) throw cErr;
    if (!candidates?.length) {
      return jsonOk({ ...result, message: "No evaluating candidates" });
    }

    // ── Process each candidate ───────────────────────────────────────────────
    for (const cand of candidates) {
      (result.evaluated as number)++;
      const candRecord: Record<string, unknown> = {
        id: cand.id,
        model_name: cand.model_name,
        candidate_version: cand.candidate_version,
      };

      try {
        const registeredAt = new Date(cand.registered_at);
        const ageDays = Math.floor((now.getTime() - registeredAt.getTime()) / 86_400_000);

        // ── Expiry check ────────────────────────────────────────────────────
        if (ageDays >= EXPIRY_DAYS && cand.comparisons_count < cand.min_comparisons_needed) {
          await _closeCandidate(supabase, cand, "expired", now,
            `expired_after_${ageDays}d_with_${cand.comparisons_count}/${cand.min_comparisons_needed}_comparisons`);
          await _clearShadowFlag(supabase, cand.model_name);
          await _reloadShadow();
          (result.expired as number)++;
          candRecord.outcome = "expired";
          candRecord.age_days = ageDays;
          (result.candidates as unknown[]).push(candRecord);
          continue;
        }

        // ── Gate check ──────────────────────────────────────────────────────
        const { passed, reason } = _evaluateGates(cand);

        if (passed === null) {
          // Metrics not yet sufficient — waiting for more comparisons
          (result.pending as number)++;
          candRecord.outcome = "pending";
          candRecord.comparisons_count = cand.comparisons_count;
          candRecord.min_needed = cand.min_comparisons_needed;
          (result.candidates as unknown[]).push(candRecord);
          continue;
        }

        if (passed) {
          // ── PROMOTE ──────────────────────────────────────────────────────
          const promoteOk = await _callInferencePromote(cand.model_name, cand.candidate_version);
          await _closeCandidate(supabase, cand, "promoted", now, reason);
          await _clearShadowFlag(supabase, cand.model_name);
          await _reloadShadow();
          await _logEvent(supabase, cand, "candidate_promoted", {
            reason,
            candidate_mape: cand.candidate_mape,
            active_mape: cand.active_mape,
            inference_promote_ok: promoteOk,
          });
          (result.promoted as number)++;
          candRecord.outcome = "promoted";
          candRecord.reason = reason;
          candRecord.inference_promote_ok = promoteOk;
        } else {
          // ── REJECT ───────────────────────────────────────────────────────
          await _closeCandidate(supabase, cand, "rejected", now, reason);
          await _clearShadowFlag(supabase, cand.model_name);
          await _reloadShadow();
          await _logEvent(supabase, cand, "candidate_rejected", {
            reason,
            candidate_mape: cand.candidate_mape,
            active_mape: cand.active_mape,
          });
          (result.rejected as number)++;
          candRecord.outcome = "rejected";
          candRecord.reason = reason;
        }

        (result.candidates as unknown[]).push(candRecord);
        console.log(`[promote-candidate] ${cand.model_name}@${cand.candidate_version}: ${candRecord.outcome} — ${reason}`);
      } catch (candErr) {
        console.error(`Error processing candidate ${cand.id}:`, candErr);
        (result.errors as number)++;
        (result.candidates as unknown[]).push({ ...candRecord, outcome: "error", error: String(candErr) });
      }
    }
  } catch (e) {
    console.error("[promote-candidate] fatal:", e);
    return jsonError(String(e), 500);
  }

  return jsonOk(result);
});

// ---------------------------------------------------------------------------
// Gate evaluation (pure logic — mirrors promotion_gate.py)
// ---------------------------------------------------------------------------

function _evaluateGates(cand: any): { passed: boolean | null; reason: string } {
  // null = not enough data yet (pending)
  if (cand.comparisons_count < cand.min_comparisons_needed) {
    return { passed: null, reason: `insufficient_comparisons:${cand.comparisons_count}<${cand.min_comparisons_needed}` };
  }
  if (cand.candidate_mape == null) {
    return { passed: null, reason: "candidate_mape_unavailable" };
  }
  if (cand.active_mape == null) {
    return { passed: null, reason: "active_mape_unavailable" };
  }
  if (cand.active_mape <= 0) {
    return { passed: false, reason: `active_mape_not_positive:${cand.active_mape}` };
  }

  const threshold = cand.active_mape * IMPROVEMENT_THRESHOLD;
  if (cand.candidate_mape < threshold) {
    return {
      passed: true,
      reason: `candidate_mape(${cand.candidate_mape.toFixed(4)})<threshold(${threshold.toFixed(4)})=active_mape(${cand.active_mape.toFixed(4)})*${IMPROVEMENT_THRESHOLD}`,
    };
  }
  return {
    passed: false,
    reason: `candidate_mape(${cand.candidate_mape.toFixed(4)})>=threshold(${threshold.toFixed(4)})=active_mape(${cand.active_mape.toFixed(4)})*${IMPROVEMENT_THRESHOLD}`,
  };
}

// ---------------------------------------------------------------------------
// Side-effects
// ---------------------------------------------------------------------------

async function _closeCandidate(
  supabase: ReturnType<typeof createClient>,
  cand: any,
  status: "promoted" | "rejected" | "expired",
  now: Date,
  notes: string,
): Promise<void> {
  await supabase
    .from("ai_candidate_models")
    .update({ status, evaluation_ended_at: now.toISOString(), notes })
    .eq("id", cand.id);
}

async function _clearShadowFlag(
  supabase: ReturnType<typeof createClient>,
  modelName: string,
): Promise<void> {
  const flagKey = `ai.${modelName}_shadow_version`;
  await supabase
    .from("ai_feature_flags")
    .update({ value: "", updated_at: new Date().toISOString() })
    .eq("key", flagKey);
}

async function _callInferencePromote(modelName: string, version: string): Promise<boolean> {
  if (!AI_INFERENCE_URL) {
    console.warn("AI_INFERENCE_URL not set — skipping inference promote call");
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
      const body = await res.text();
      console.warn(`Inference promote returned ${res.status}: ${body}`);
      return false;
    }
    return true;
  } catch (err) {
    console.warn("Could not reach inference promote endpoint:", err);
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
    // Non-fatal — inference service will pick up cleared flag on next restart
  }
}

async function _logEvent(
  supabase: ReturnType<typeof createClient>,
  cand: any,
  eventType: string,
  metadata: Record<string, unknown>,
): Promise<void> {
  await supabase.from("ai_prediction_logs").insert({
    event_type: eventType,
    metadata: {
      model_name: cand.model_name,
      candidate_version: cand.candidate_version,
      active_version_at_registration: cand.active_version_at_registration,
      comparisons_count: cand.comparisons_count,
      ...metadata,
    },
  }).catch(() => {});
}

function jsonOk(data: unknown): Response {
  return new Response(JSON.stringify(data), { status: 200, headers: { "Content-Type": "application/json" } });
}

function jsonError(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), { status, headers: { "Content-Type": "application/json" } });
}
