// supabase/functions/generate-auction-price-estimate/index.ts
//
// Phase 4B Shadow Mode — Synthetic Auction Price Estimate Generation
//
// Runs hourly via pg_cron. Generates synthetic predictions for all eligible
// active auctions. No external ML API is called — predictions are produced
// via a deterministic formula keyed on auction_id (same input always
// produces the same prediction). Model versions come from ai_feature_flags.
//
// Synthetic formula rationale:
//   • starting_price × multiplier where multiplier ∈ [1.05, 1.50]
//   • multiplier is derived from auction_id bits (deterministic, uniform)
//   • metadata_completeness_score adjusts multiplier slightly upward
//   • value_signal thresholds: < 1.10 → overpriced, > 1.30 → undervalued
//   • confidence_score ∈ [0.55, 0.85] based on metadata completeness
//
// Idempotency:
//   • Skips auctions with an auction_price_estimate prediction created today (UTC)
//   • Logs every skip with skip_reason = 'already_predicted'
//
// Shadow mode invariant:
//   • ai.shadow_mode_enabled must be 'true' (else all auctions skipped)
//   • ai.predictions_visible_to_clients remains 'false' — not touched here
//
// Auth: Bearer SUPABASE_SERVICE_ROLE_KEY (same pattern as auto-close-auctions)

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

serve(async (req) => {
  // ── Auth guard: service role key only ──────────────────────────────────────
  const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const incomingAuth = req.headers.get('Authorization') ?? '';
  if (!expectedKey || incomingAuth !== `Bearer ${expectedKey}`) {
    return json({ error: 'Unauthorized' }, 401);
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
        'ai.model_a_active_version',
        'ai.model_b_active_version',
        'ai.model_c_active_version',
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

    const modelAVersion = flags['ai.model_a_active_version'] ?? 'v1.0.4-synthetic';
    const modelBVersion = flags['ai.model_b_active_version'] ?? 'v1.0.0-synthetic';
    const modelCVersion = flags['ai.model_c_active_version'] ?? 'v1.0.0-synthetic';
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

        // Filter: already predicted today
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

        // ── Synthetic prediction formulas ──────────────────────────────────
        const factor = auctionIdFactor(auctionId); // deterministic [0, 1)
        const startingPrice = Math.max(Number(auction.starting_price ?? 0), 0);

        // Model A: auction price estimate
        const aMultiplier = 1.05 + factor * 0.40 + completeness * 0.05;
        const expectedAuctionPrice = startingPrice > 0
          ? Math.round(startingPrice * aMultiplier)
          : 0;
        const valueRatio = startingPrice > 0
          ? Math.round((expectedAuctionPrice / startingPrice) * 1000) / 1000
          : 1.0;
        const valueSignal: string = valueRatio > 1.30
          ? 'undervalued'
          : valueRatio < 1.10
          ? 'overpriced'
          : 'fairly_priced';
        const confidenceA = Math.min(0.55 + completeness * 0.30, 0.85);

        // Model B: winning bid estimate (slightly above Model A)
        const bMultiplier = aMultiplier + 0.05 + factor * 0.10;
        const predictedWinningBid = startingPrice > 0
          ? Math.round(startingPrice * bMultiplier)
          : 0;
        const confidenceB = Math.min(0.50 + completeness * 0.25, 0.80);

        // Model C: bid probability (0.50–0.95)
        const predictedProbability = Math.min(
          0.50 + factor * 0.40 + completeness * 0.10,
          0.95,
        );
        const confidenceC = Math.min(0.60 + completeness * 0.20, 0.80);

        const featureSnapshot = {
          region: auction.region,
          main_category: auction.main_category,
          sub_category: auction.sub_category,
          brand: auction.brand,
          model: auction.model,
          manufacturing_year: auction.manufacturing_year,
          mileage: auction.mileage,
          condition: auction.condition,
          fuel_type: auction.fuel_type,
          transmission: auction.transmission,
          starting_price: startingPrice,
          asset_age: auction.asset_age,
          auction_duration_hours: auction.auction_duration_hours,
          total_bids: auction.total_bids,
          unique_bidder_count: auction.unique_bidder_count,
          views_count: auction.views_count,
          metadata_completeness_score: completeness,
          has_images: auction.has_images,
          has_description: auction.has_description,
          synthetic: true,
        };

        // ── Insert all 3 prediction types atomically ───────────────────────
        const { error: insertErr } = await supabase.from('ai_predictions').insert([
          {
            auction_id: auctionId,
            model_version: modelAVersion,
            prediction_type: 'auction_price_estimate',
            expected_auction_price: expectedAuctionPrice,
            value_signal: valueSignal,
            value_ratio: valueRatio,
            starting_price_at_prediction: startingPrice,
            confidence_score: confidenceA,
            feature_snapshot: featureSnapshot,
          },
          {
            auction_id: auctionId,
            model_version: modelBVersion,
            prediction_type: 'winning_bid',
            predicted_winning_bid: predictedWinningBid,
            confidence_score: confidenceB,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'B' },
          },
          {
            auction_id: auctionId,
            model_version: modelCVersion,
            prediction_type: 'bid_probability',
            predicted_probability: predictedProbability,
            confidence_score: confidenceC,
            feature_snapshot: { ...featureSnapshot, prediction_model: 'C' },
          },
        ]);

        if (insertErr) throw insertErr;

        const durationMs = Date.now() - startMs;

        await logEvent(supabase, auctionId, 'prediction_generated', {
          models_run: ['model_a', 'model_b', 'model_c'],
          model_versions: {
            model_a: modelAVersion,
            model_b: modelBVersion,
            model_c: modelCVersion,
          },
          duration_ms: durationMs,
          feature_completeness_score: completeness,
          metadata: {
            expected_auction_price: expectedAuctionPrice,
            value_signal: valueSignal,
            value_ratio: valueRatio,
            synthetic: true,
          },
        });

        result.generated++;
      } catch (auctionErr) {
        const durationMs = Date.now() - startMs;
        console.error(`[generate-estimate] auction ${auctionId}:`, auctionErr);
        await logEvent(supabase, auctionId, 'prediction_error', {
          duration_ms: durationMs,
          error_code: 'SYNTHETIC_GENERATION_ERROR',
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

// Derives a stable [0, 1) float from the first 8 hex digits of a UUID.
// Same auction_id always produces the same factor — no randomness.
function auctionIdFactor(auctionId: string): number {
  const hex = auctionId.replace(/-/g, '').substring(0, 8);
  const val = parseInt(hex, 16);
  return (val % 1000) / 1000;
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
