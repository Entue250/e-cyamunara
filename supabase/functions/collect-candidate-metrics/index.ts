// supabase/functions/collect-candidate-metrics/index.ts
//
// Phase 9F — Candidate Metrics Collection
//
// Runs daily at 03:00 UTC via pg_cron (after generate-auction-price-estimate
// and compute-prediction-comparison have had time to build up data).
//
// For each ai_candidate_models row with status='evaluating':
//   1. Count comparison rows with model_stage='candidate' and
//      model_version = candidate.candidate_version (for comparisons_count)
//   2. Compute MAPE from those candidate comparison rows
//   3. Compute active MAPE from the 100 most recent model_stage='shadow' rows
//      (same auctions window — shadow rows track the incumbent active model)
//   4. Update ai_candidate_models with metrics and comparisons_count
//
// After this function runs, promote-candidate can evaluate the gates.
//
// Linking: ai_prediction_comparisons.model_version matches
//   - candidate rows: model_version = candidate_version
//   - shadow rows:    model_version = active synthetic model version
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

serve(async (req: Request) => {
  const expectedKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const incomingAuth = req.headers.get("Authorization") ?? "";
  if (!expectedKey || incomingAuth !== `Bearer ${expectedKey}`) {
    return jsonError("Unauthorized", 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const result: Record<string, unknown> = {
    evaluated: 0,
    updated: 0,
    skipped_no_data: 0,
    errors: 0,
    candidates: [] as unknown[],
  };

  try {
    // ── Fetch all evaluating candidates ──────────────────────────────────────
    const { data: candidates, error: cErr } = await supabase
      .from("ai_candidate_models")
      .select("id, model_name, candidate_version, active_version_at_registration, comparisons_count, min_comparisons_needed")
      .eq("status", "evaluating");

    if (cErr) throw cErr;
    if (!candidates?.length) {
      return jsonOk({ ...result, message: "No evaluating candidates" });
    }

    // ── Compute active (shadow) MAPE once — shared baseline for all candidates
    // Uses the 100 most recent shadow comparison rows with non-null APE.
    const { data: shadowRows, error: sErr } = await supabase
      .from("ai_prediction_comparisons")
      .select("absolute_percentage_error")
      .eq("model_stage", "shadow")
      .not("absolute_percentage_error", "is", null)
      .order("created_at", { ascending: false })
      .limit(100);

    if (sErr) throw sErr;

    const shadowApes = (shadowRows ?? []).map((r: any) => r.absolute_percentage_error as number);
    const activeMape: number | null = shadowApes.length > 0
      ? shadowApes.reduce((s: number, v: number) => s + v, 0) / shadowApes.length
      : null;

    // ── Process each candidate ───────────────────────────────────────────────
    for (const candidate of candidates) {
      (result.evaluated as number)++;

      try {
        // Candidate comparison rows: model_version matches candidate_version
        // and model_stage='candidate'
        const { data: candRows, error: cRowErr } = await supabase
          .from("ai_prediction_comparisons")
          .select("absolute_percentage_error")
          .eq("model_stage", "candidate")
          .eq("model_version", candidate.candidate_version)
          .not("absolute_percentage_error", "is", null);

        if (cRowErr) throw cRowErr;

        const candApes = (candRows ?? []).map((r: any) => r.absolute_percentage_error as number);
        const comparisonsCount = candApes.length;

        if (comparisonsCount === 0) {
          (result.skipped_no_data as number)++;
          (result.candidates as unknown[]).push({
            id: candidate.id,
            model_name: candidate.model_name,
            candidate_version: candidate.candidate_version,
            status: "skipped_no_data",
          });
          continue;
        }

        const candidateMape = candApes.reduce((s: number, v: number) => s + v, 0) / candApes.length;

        // ── Update ai_candidate_models with fresh metrics ──────────────────
        const { error: updErr } = await supabase
          .from("ai_candidate_models")
          .update({
            comparisons_count: comparisonsCount,
            candidate_mape: candidateMape,
            active_mape: activeMape,
          })
          .eq("id", candidate.id);

        if (updErr) throw updErr;

        (result.updated as number)++;
        (result.candidates as unknown[]).push({
          id: candidate.id,
          model_name: candidate.model_name,
          candidate_version: candidate.candidate_version,
          comparisons_count: comparisonsCount,
          candidate_mape: Math.round(candidateMape * 10000) / 10000,
          active_mape: activeMape != null ? Math.round(activeMape * 10000) / 10000 : null,
        });

        console.log(
          `Updated candidate ${candidate.model_name}@${candidate.candidate_version}: ` +
          `n=${comparisonsCount} candidate_mape=${candidateMape.toFixed(4)} active_mape=${activeMape?.toFixed(4) ?? "null"}`,
        );
      } catch (candErr) {
        console.error(`Error processing candidate ${candidate.id}:`, candErr);
        (result.errors as number)++;
      }
    }
  } catch (e) {
    console.error("[collect-candidate-metrics] fatal:", e);
    return jsonError(String(e), 500);
  }

  return jsonOk(result);
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
