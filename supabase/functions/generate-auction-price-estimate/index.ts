// supabase/functions/generate-auction-price-estimate/index.ts
//
// Phase 9A.2 — Real ML Auction Price Estimate Generation (batch shadow mode)
//
// Runs hourly via pg_cron. Calls the FastAPI inference service for all eligible
// active auctions and stores real model predictions in ai_predictions with
// prediction_source = 'real', model_stage = 'shadow'.
//
// All three models are called in parallel per auction (Promise.all). If any
// model call fails or FastAPI is unavailable, all three predictions for that
// auction are skipped atomically and the error is logged. The function never
// returns an error response to pg_cron — per-auction failures are isolated.
//
// Feature payload is built from v_auction_ml_features view columns.
// store_prediction = false is passed to FastAPI — this function handles its
// own INSERT to maintain full control over prediction_source and model_stage.
//
// Idempotency:
//   • Skips auctions with any auction_price_estimate prediction created today (UTC).
//     Covers both real and synthetic predictions — prevents double-generation
//     during the transition window after Phase 9A.2 is first deployed.
//
// Shadow mode invariant:
//   • ai.shadow_mode_enabled must be 'true' (else all auctions skipped)
//   • ai.predictions_visible_to_clients remains 'false' — not touched here
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SELECTED_COLUMNS = [
  'auction_id', 'region', 'main_category', 'sub_category',
  'brand', 'model', 'manufacturing_year', 'mileage', 'condition',
  'fuel_type', 'transmission', 'ownership_history', 'accident_history',
  'insurance_status', 'color', 'starting_price', 'asset_age',
  'auction_duration_hours', 'total_bids', 'unique_bidder_count',
  'views_count', 'bids_per_view_ratio', 'metadata_completeness_score',
  'has_images', 'has_description', 'auction_status',
].join(', ');

const INFERENCE_TIMEOUT_MS = 30_000;
const MAX_RETRIES = 3;

serve(async (req) => {
  // ── Auth guard: service role key only ──────────────────────────────────────
  const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const incomingAuth = req.headers.get('Authorization') ?? '';
  if (!expectedKey || incomingAuth !== `Bearer ${expectedKey}`) {
    return json({ error: 'Unauthorized' }, 401);
  }

  // ── Inference URL is required ──────────────────────────────────────────────
  const inferenceUrl = Deno.env.get('AI_INFERENCE_URL');
  if (!inferenceUrl) {
    console.error(JSON.stringify({ event: 'config_error', missing: 'AI_INFERENCE_URL' }));
    return json({ error: 'AI inference service not configured', generated: 0, skipped: 0, errors: 0 }, 503);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  const result = { generated: 0, skipped: 0, errors: 0 };

  try {
    // ── Read AI feature flags ────────────────────────────────────────────────
    const { data: flagRows, error: flagErr } = await supabase
      .from('ai_feature_flags')
      .select('key, value')
      .in('key', [
        'ai.shadow_mode_enabled',
        'ai.min_feature_completeness_score',
      ]);

    if (flagErr) throw flagErr;

    const flags = Object.fromEntries(
      (flagRows ?? []).map((r: any) => [r.key, r.value])
    );

    if (flags['ai.shadow_mode_enabled'] !== 'true') {
      await logEvent(supabase, null, 'prediction_skipped', {
        skip_reason: 'shadow_mode_disabled',
      });
      return json({ ...result, skipped_reason: 'shadow_mode_disabled' });
    }

    const minCompleteness = parseFloat(flags['ai.min_feature_completeness_score'] ?? '0.5');

    // ── Fetch active auctions via ML features view ───────────────────────────
    const { data: auctions, error: aErr } = await supabase
      .from('v_auction_ml_features')
      .select(SELECTED_COLUMNS)
      .eq('auction_status', 'active');

    if (aErr) throw aErr;
    if (!auctions?.length) {
      return json({ ...result, message: 'No active auctions' });
    }

    const todayStart = new Date().toISOString().split('T')[0] + 'T00:00:00.000Z';

    // ── Process each auction ─────────────────────────────────────────────────
    for (const auction of auctions) {
      const auctionId: string = auction.auction_id;
      const startMs = Date.now();

      try {
        const completeness: number = auction.metadata_completeness_score ?? 0;

        // Filter: metadata completeness threshold
        if (completeness < minCompleteness) {
          await logEvent(supabase, auctionId, 'prediction_skipped', {
            skip_reason: 'feature_completeness_low',
            feature_completeness_score: completeness,
          });
          result.skipped++;
          continue;
        }

        // Filter: already predicted today (any source — prevents double-generation)
        const { data: existing } = await supabase
          .from('ai_predictions')
          .select('id')
          .eq('auction_id', auctionId)
          .eq('prediction_type', 'auction_price_estimate')
          .gte('created_at', todayStart)
          .limit(1);

        if (existing?.length) {
          result.skipped++;
          continue;
        }

        const startingPrice = Math.max(Number(auction.starting_price ?? 0), 0);

        // ── Build feature payloads ─────────────────────────────────────────
        // baseFeatures → Model A (price estimate)
        // engagementFeatures → Models B + C (winning bid + bid probability)
        const baseFeatures: Record<string, unknown> = {
          main_category: auction.main_category,
          sub_category: auction.sub_category ?? null,
          brand: auction.brand ?? null,
          condition: auction.condition ?? null,
          region: auction.region,
          starting_price: startingPrice,
          fuel_type: auction.fuel_type ?? null,
          transmission: auction.transmission ?? null,
          mileage: auction.mileage ?? null,
          ownership_history: auction.ownership_history ?? null,
          accident_history: auction.accident_history ?? null,
          insurance_status: auction.insurance_status ?? null,
          manufacturing_year: auction.manufacturing_year ?? null,
          asset_age: auction.asset_age ?? null,
          auction_duration_hours: auction.auction_duration_hours ?? null,
          has_description: auction.has_description ?? false,
          has_images: auction.has_images ?? false,
        };

        const totalBids = auction.total_bids ?? 0;
        const viewsCount = auction.views_count ?? 0;

        const engagementFeatures: Record<string, unknown> = {
          ...baseFeatures,
          total_bids: totalBids,
          unique_bidder_count: auction.unique_bidder_count ?? 0,
          views_count: viewsCount,
          bids_per_view_ratio: auction.bids_per_view_ratio ?? 0,
          view_to_bid_ratio: totalBids > 0 ? viewsCount / totalBids : 0,
          bid_momentum: 0,
          time_to_first_bid_hours: null,
          is_first_bid_quick: false,
          days_until_close: 0,
          bid_acceleration: 0.5,
          price_tier: startingPrice >= 8_000_000 ? 'high'
            : startingPrice >= 2_000_000 ? 'medium'
            : 'low',
        };

        // ── Call FastAPI — all 3 models in parallel ────────────────────────
        // store_prediction: false — this function handles INSERT itself so that
        // prediction_source and model_stage are set explicitly as 'real'/'shadow'.
        let predA: any, predB: any, predC: any;
        try {
          const [respA, respB, respC] = await Promise.all([
            withRetry(
              () => fetchWithTimeout(
                `${inferenceUrl}/predict-price`,
                {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    auction_id: auctionId,
                    store_prediction: false,
                    features: baseFeatures,
                  }),
                },
                INFERENCE_TIMEOUT_MS,
              ),
              MAX_RETRIES,
            ),
            withRetry(
              () => fetchWithTimeout(
                `${inferenceUrl}/predict-winning-bid`,
                {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    auction_id: auctionId,
                    store_prediction: false,
                    features: engagementFeatures,
                  }),
                },
                INFERENCE_TIMEOUT_MS,
              ),
              MAX_RETRIES,
            ),
            withRetry(
              () => fetchWithTimeout(
                `${inferenceUrl}/predict-winning-probability`,
                {
                  method: 'POST',
                  headers: { 'Content-Type': 'application/json' },
                  body: JSON.stringify({
                    auction_id: auctionId,
                    store_prediction: false,
                    features: engagementFeatures,
                  }),
                },
                INFERENCE_TIMEOUT_MS,
              ),
              MAX_RETRIES,
            ),
          ]);

          if (!respA.ok || !respB.ok || !respC.ok) {
            throw new Error(
              `FastAPI error — A:${respA.status} B:${respB.status} C:${respC.status}`
            );
          }

          [predA, predB, predC] = await Promise.all([
            respA.json(),
            respB.json(),
            respC.json(),
          ]);
        } catch (inferErr) {
          const durationMs = Date.now() - startMs;
          console.error(`[generate-estimate] FastAPI unavailable for ${auctionId}:`, inferErr);
          await logEvent(supabase, auctionId, 'prediction_error', {
            duration_ms: durationMs,
            error_code: 'FASTAPI_INFERENCE_ERROR',
            error_message: String(inferErr),
          }).catch(() => {});
          result.errors++;
          continue;
        }

        // ── Feature snapshot for audit trail ──────────────────────────────
        const featureSnapshot = {
          region: auction.region,
          main_category: auction.main_category,
          sub_category: auction.sub_category,
          brand: auction.brand,
          manufacturing_year: auction.manufacturing_year,
          mileage: auction.mileage,
          condition: auction.condition,
          fuel_type: auction.fuel_type,
          transmission: auction.transmission,
          starting_price: startingPrice,
          asset_age: auction.asset_age,
          auction_duration_hours: auction.auction_duration_hours,
          total_bids: totalBids,
          unique_bidder_count: auction.unique_bidder_count,
          views_count: viewsCount,
          metadata_completeness_score: completeness,
          has_images: auction.has_images,
          has_description: auction.has_description,
          synthetic: false,
          generated_by: 'batch_cron',
        };

        // ── Insert active (shadow) prediction rows ─────────────────────────
        const shadowRows = [
          {
            auction_id: auctionId,
            model_version: predA.model_version,
            prediction_type: 'auction_price_estimate',
            prediction_source: 'real',
            model_stage: 'shadow',
            expected_auction_price: predA.expected_auction_price,
            value_signal: predA.value_signal,
            value_ratio: predA.value_ratio,
            starting_price_at_prediction: startingPrice,
            confidence_score: predA.confidence_score,
            feature_snapshot: featureSnapshot,
          },
          {
            auction_id: auctionId,
            model_version: predB.model_version,
            prediction_type: 'winning_bid',
            prediction_source: 'real',
            model_stage: 'shadow',
            predicted_winning_bid: predB.predicted_winning_bid,
            confidence_score: predB.confidence_score,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'B' },
          },
          {
            auction_id: auctionId,
            model_version: predC.model_version,
            prediction_type: 'bid_probability',
            prediction_source: 'real',
            model_stage: 'shadow',
            predicted_probability: predC.predicted_probability,
            confidence_score: predC.confidence_score,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'C' },
          },
        ];

        // Phase 9E: append candidate rows when inference returned candidate fields
        const candidateRows: Record<string, unknown>[] = [];

        if (predA.candidate_version) {
          candidateRows.push({
            auction_id: auctionId,
            model_version: predA.candidate_version,
            prediction_type: 'auction_price_estimate',
            prediction_source: 'real',
            model_stage: 'candidate',
            expected_auction_price: predA.candidate_expected_auction_price,
            value_signal: predA.candidate_value_signal,
            value_ratio: predA.candidate_value_ratio,
            starting_price_at_prediction: startingPrice,
            confidence_score: predA.candidate_confidence_score,
            feature_snapshot: featureSnapshot,
          });
        }
        if (predB.candidate_version) {
          candidateRows.push({
            auction_id: auctionId,
            model_version: predB.candidate_version,
            prediction_type: 'winning_bid',
            prediction_source: 'real',
            model_stage: 'candidate',
            predicted_winning_bid: predB.candidate_predicted_winning_bid,
            confidence_score: predB.candidate_confidence_score,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'B' },
          });
        }
        if (predC.candidate_version) {
          candidateRows.push({
            auction_id: auctionId,
            model_version: predC.candidate_version,
            prediction_type: 'bid_probability',
            prediction_source: 'real',
            model_stage: 'candidate',
            predicted_probability: predC.candidate_predicted_probability,
            confidence_score: predC.candidate_confidence_score,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'C' },
          });
        }

        const { error: insertErr } = await supabase
          .from('ai_predictions')
          .insert([...shadowRows, ...candidateRows]);

        if (insertErr) throw insertErr;

        const durationMs = Date.now() - startMs;

        await logEvent(supabase, auctionId, 'prediction_generated', {
          models_run: ['model_a', 'model_b', 'model_c'],
          model_versions: {
            model_a: predA.model_version,
            model_b: predB.model_version,
            model_c: predC.model_version,
          },
          duration_ms: durationMs,
          feature_completeness_score: completeness,
          metadata: {
            expected_auction_price: predA.expected_auction_price,
            value_signal: predA.value_signal,
            value_ratio: predA.value_ratio,
            predicted_winning_bid: predB.predicted_winning_bid,
            predicted_probability: predC.predicted_probability,
            synthetic: false,
          },
        });

        result.generated++;
      } catch (auctionErr) {
        const durationMs = Date.now() - startMs;
        console.error(`[generate-estimate] auction ${auctionId}:`, auctionErr);
        await logEvent(supabase, auctionId, 'prediction_error', {
          duration_ms: durationMs,
          error_code: 'GENERATION_ERROR',
          error_message: String(auctionErr),
        }).catch(() => {});
        result.errors++;
      }
    }
  } catch (e) {
    console.error('[generate-estimate] fatal:', e);
    return json({ error: String(e), ...result }, 500);
  }

  return json(result);
});

// ── Helpers ───────────────────────────────────────────────────────────────────

async function fetchWithTimeout(
  url: string,
  init: RequestInit,
  timeoutMs: number,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

async function withRetry<T>(
  fn: () => Promise<T>,
  maxAttempts: number,
  baseDelayMs = 1_000,
): Promise<T> {
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (err) {
      if (attempt === maxAttempts) throw err;
      await new Promise<void>(r => setTimeout(r, baseDelayMs * Math.pow(2, attempt - 1)));
    }
  }
  throw new Error('unreachable');
}

async function logEvent(
  supabase: ReturnType<typeof createClient>,
  auctionId: string | null,
  eventType: string,
  fields: Record<string, unknown>,
): Promise<void> {
  await supabase.from('ai_prediction_logs').insert({
    auction_id: auctionId,
    event_type: eventType,
    ...fields,
  });
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}
