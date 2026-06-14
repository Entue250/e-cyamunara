// supabase/functions/ai-bid-forecast/index.ts
//
// Phase 7 — Real ML Bid Forecast (Models B + C)
//
// POST /functions/v1/ai-bid-forecast
// Body: { auction_id: string, features: EngagementFeatures }
//       (features must include total_bids, unique_bidder_count, views_count)
//
// Flow:
//   1. Verify JWT (any authenticated user)
//   2. Check ai.shadow_mode_enabled flag (503 if disabled)
//   3. Cache check — return existing real predictions if < 30 min old
//   4. Call FastAPI /predict-winning-bid AND /predict-winning-probability in parallel
//      with 3-attempt retry + 30 s timeout each
//   5. Visibility gate — if ai.predictions_visible_to_clients=false,
//      return { stored: true } instead of values
//
// Env vars required:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//   AI_INFERENCE_URL   — base URL of the FastAPI service (no trailing slash)

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const INFERENCE_TIMEOUT_MS = 30_000;
const CACHE_WINDOW_MS      = 30 * 60 * 1_000;
const MAX_RETRIES          = 3;

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // ── 1. Auth ──────────────────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Not authenticated' }, 401);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const { data: { user }, error: authErr } = await createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    ).auth.getUser();

    if (authErr || !user) return json({ error: 'Not authenticated' }, 401);

    // ── 2. Parse body ────────────────────────────────────────────────────────
    let body: { auction_id?: string; features?: unknown };
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Invalid JSON body' }, 400);
    }
    const { auction_id, features } = body;
    if (!auction_id || !features) {
      return json({ error: 'auction_id and features are required' }, 400);
    }

    // ── 3. Feature flags ─────────────────────────────────────────────────────
    const { data: flagRows } = await supabase
      .from('ai_feature_flags')
      .select('key, value')
      .in('key', ['ai.shadow_mode_enabled', 'ai.predictions_visible_to_clients']);

    const flags = Object.fromEntries((flagRows ?? []).map((r: any) => [r.key, r.value]));
    const shadowEnabled    = flags['ai.shadow_mode_enabled']            === 'true';
    const visibleToClients = flags['ai.predictions_visible_to_clients'] === 'true';

    if (!shadowEnabled) {
      return json({ error: 'AI predictions not available (shadow mode disabled)' }, 503);
    }

    // ── 4. Cache check — both prediction types must be fresh ─────────────────
    const cacheAfter = new Date(Date.now() - CACHE_WINDOW_MS).toISOString();
    const { data: cachedRows } = await supabase
      .from('ai_predictions')
      .select('id, prediction_type, predicted_winning_bid, predicted_probability, confidence_score, model_version')
      .eq('auction_id', auction_id)
      .in('prediction_type', ['winning_bid', 'bid_probability'])
      .eq('prediction_source', 'real')
      .gte('created_at', cacheAfter)
      .order('created_at', { ascending: false });

    const cachedB = cachedRows?.find((r: any) => r.prediction_type === 'winning_bid');
    const cachedC = cachedRows?.find((r: any) => r.prediction_type === 'bid_probability');

    if (cachedB && cachedC) {
      console.log(JSON.stringify({ event: 'cache_hit', auction_id, type: 'both' }));
      if (!visibleToClients) return json({ stored: true, auction_id, shadow_mode: true });
      return json({
        winning_bid: {
          prediction_id:       cachedB.id,
          model_version:       cachedB.model_version,
          predicted_winning_bid: cachedB.predicted_winning_bid,
          confidence_score:    cachedB.confidence_score,
          cached:              true,
        },
        bid_probability: {
          prediction_id:        cachedC.id,
          model_version:        cachedC.model_version,
          predicted_probability: cachedC.predicted_probability,
          confidence_score:     cachedC.confidence_score,
          cached:               true,
        },
      });
    }

    // ── 5. Call FastAPI — both models in parallel ────────────────────────────
    const inferenceUrl = Deno.env.get('AI_INFERENCE_URL');
    if (!inferenceUrl) {
      console.error(JSON.stringify({ event: 'config_error', missing: 'AI_INFERENCE_URL' }));
      return json({ error: 'AI inference service not configured' }, 503);
    }

    const payload = { auction_id, store_prediction: true, features };
    const startMs = Date.now();

    let respB: Response, respC: Response;
    try {
      [respB, respC] = await Promise.all([
        withRetry(
          () => fetchWithTimeout(
            `${inferenceUrl}/predict-winning-bid`,
            { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) },
            INFERENCE_TIMEOUT_MS,
          ),
          MAX_RETRIES,
        ),
        withRetry(
          () => fetchWithTimeout(
            `${inferenceUrl}/predict-winning-probability`,
            { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload) },
            INFERENCE_TIMEOUT_MS,
          ),
          MAX_RETRIES,
        ),
      ]);
    } catch (err) {
      const durationMs = Date.now() - startMs;
      console.error(JSON.stringify({
        event: 'inference_unavailable', auction_id, duration_ms: durationMs, error: String(err),
      }));
      return json({ error: 'AI inference service unavailable' }, 503);
    }

    const durationMs = Date.now() - startMs;

    if (!respB.ok || !respC.ok) {
      const errB = !respB.ok ? await respB.text().catch(() => '') : '';
      const errC = !respC.ok ? await respC.text().catch(() => '') : '';
      console.error(JSON.stringify({
        event: 'inference_error', auction_id,
        status_b: respB.status, body_b: errB,
        status_c: respC.status, body_c: errC,
        duration_ms: durationMs,
      }));
      return json({ error: 'Bid forecast generation failed' }, 502);
    }

    const predB = await respB.json() as {
      prediction_id?:       string;
      model_version:        string;
      predicted_winning_bid: number;
      confidence_score:     number;
      inference_ms:         number;
    };
    const predC = await respC.json() as {
      prediction_id?:        string;
      model_version:         string;
      predicted_probability: number;
      confidence_score:      number;
      inference_ms:          number;
    };

    console.log(JSON.stringify({
      event: 'forecast_generated', auction_id, duration_ms: durationMs,
      model_b: predB.model_version, model_c: predC.model_version,
    }));

    // ── 6. Visibility gate ───────────────────────────────────────────────────
    if (!visibleToClients) return json({ stored: true, auction_id, shadow_mode: true });

    return json({
      winning_bid: {
        prediction_id:        predB.prediction_id ?? null,
        model_version:        predB.model_version,
        predicted_winning_bid: predB.predicted_winning_bid,
        confidence_score:     predB.confidence_score,
        inference_ms:         predB.inference_ms,
        cached:               false,
      },
      bid_probability: {
        prediction_id:         predC.prediction_id ?? null,
        model_version:         predC.model_version,
        predicted_probability: predC.predicted_probability,
        confidence_score:      predC.confidence_score,
        inference_ms:          predC.inference_ms,
        cached:                false,
      },
    });

  } catch (err) {
    console.error(JSON.stringify({ event: 'ai_bid_forecast_unhandled', error: String(err) }));
    return json({ error: 'An unexpected error occurred' }, 500);
  }
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

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, 'Content-Type': 'application/json' },
  });
}
