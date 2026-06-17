// supabase/functions/backfill-ai-predictions/index.ts
//
// Phase 9K — On-Demand Prediction Backfill
//
// Triggered manually by a super_admin from the AI dashboard.
// Finds all active (and optionally closed) auctions that have NEVER had an
// auction_price_estimate prediction, then calls the FastAPI inference service
// to generate predictions for them in batches of BATCH_SIZE.
//
// Unlike generate-auction-price-estimate (hourly cron), this backfill:
//   - Targets auctions with NO predictions ever (not just "not today")
//   - Also covers closed auctions if include_closed=true (useful for MAPE baseline)
//   - Caps the total run at MAX_AUCTIONS to avoid timeouts
//   - Returns a job summary: { eligible, triggered, skipped, errors }
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY or active super_admin JWT
//
// Body (optional): { include_closed?: boolean, limit?: number }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BATCH_SIZE     = 20;
const MAX_AUCTIONS   = 200;
const TIMEOUT_MS     = 25_000;

const SELECTED_COLUMNS = [
  "auction_id", "region", "main_category", "sub_category",
  "brand", "model", "manufacturing_year", "mileage", "condition",
  "fuel_type", "transmission", "ownership_history", "accident_history",
  "insurance_status", "color", "starting_price", "asset_age",
  "auction_duration_hours", "total_bids", "unique_bidder_count",
  "views_count", "bids_per_view_ratio", "metadata_completeness_score",
  "has_images", "has_description", "auction_status",
].join(", ");

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
  let includeClosed = false;
  let limitOverride: number | undefined;
  try {
    const body = await req.json().catch(() => ({})) as {
      include_closed?: boolean;
      limit?: number;
    };
    includeClosed = body.include_closed === true;
    if (typeof body.limit === "number" && body.limit > 0) {
      limitOverride = Math.min(body.limit, MAX_AUCTIONS);
    }
  } catch {
    // defaults already set
  }

  const limit = limitOverride ?? MAX_AUCTIONS;

  // ── Check shadow mode ──────────────────────────────────────────────────────
  const { data: flagRow } = await supabase
    .from("ai_feature_flags")
    .select("value")
    .eq("key", "ai.shadow_mode_enabled")
    .maybeSingle();

  if (flagRow?.value !== "true") {
    return jsonOk({
      ok: false,
      reason: "shadow_mode_disabled",
      eligible: 0, triggered: 0, skipped: 0, errors: 0,
    });
  }

  // ── Check FastAPI URL ──────────────────────────────────────────────────────
  const inferenceUrl = Deno.env.get("AI_INFERENCE_URL");
  if (!inferenceUrl) {
    return jsonError("AI_INFERENCE_URL not configured", 503);
  }

  // ── Fetch auctions without ANY auction_price_estimate prediction ───────────
  const statuses = includeClosed ? ["active", "closed"] : ["active"];

  const { data: features, error: featErr } = await supabase
    .from("v_auction_ml_features")
    .select(SELECTED_COLUMNS)
    .in("auction_status", statuses)
    .limit(limit * 3); // over-fetch so we can filter out already-predicted ones

  if (featErr) {
    return jsonError(`feature fetch failed: ${featErr.message}`, 500);
  }
  if (!features?.length) {
    return jsonOk({ ok: true, eligible: 0, triggered: 0, skipped: 0, errors: 0 });
  }

  // ── Find already-predicted auction IDs ────────────────────────────────────
  const { data: existingRows } = await supabase
    .from("ai_predictions")
    .select("auction_id")
    .in("auction_id", (features as any[]).map((f: any) => f.auction_id))
    .eq("prediction_type", "auction_price_estimate");

  const alreadyPredicted = new Set(
    (existingRows ?? []).map((r: any) => r.auction_id as string),
  );

  const eligible = (features as any[])
    .filter((f: any) => !alreadyPredicted.has(f.auction_id))
    .slice(0, limit);

  if (!eligible.length) {
    return jsonOk({
      ok: true,
      message: "All active auctions already have predictions",
      eligible: 0, triggered: 0, skipped: 0, errors: 0,
    });
  }

  // ── Process in batches ─────────────────────────────────────────────────────
  const result = { eligible: eligible.length, triggered: 0, skipped: 0, errors: 0 };
  const minCompleteness = 0.5;

  for (let i = 0; i < eligible.length; i += BATCH_SIZE) {
    const batch = eligible.slice(i, i + BATCH_SIZE);
    const auctionIds = batch
      .filter((f: any) => (f.metadata_completeness_score ?? 0) >= minCompleteness)
      .map((f: any) => f.auction_id as string);

    result.skipped += batch.length - auctionIds.length;

    if (!auctionIds.length) continue;

    try {
      const resp = await fetch(`${inferenceUrl}/predict/batch`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ auction_ids: auctionIds }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (resp.ok) {
        result.triggered += auctionIds.length;
      } else {
        result.errors += auctionIds.length;
        console.warn(
          `[backfill] batch error status=${resp.status} ids=${auctionIds.join(",")}`,
        );
      }
    } catch (e) {
      result.errors += auctionIds.length;
      console.error(`[backfill] batch fetch failed:`, e);
    }
  }

  // ── Audit log ──────────────────────────────────────────────────────────────
  await supabase.from("ai_prediction_logs").insert({
    event_type: "metrics_collected",
    metadata: {
      action:        "backfill_triggered",
      include_closed: includeClosed,
      ...result,
    },
  }).catch(() => {});

  console.log(
    `[backfill-ai-predictions] eligible=${result.eligible} ` +
    `triggered=${result.triggered} skipped=${result.skipped} errors=${result.errors}`,
  );

  return jsonOk({ ok: true, ...result });
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
