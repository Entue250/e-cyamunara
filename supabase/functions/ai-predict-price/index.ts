// supabase/functions/ai-predict-price/index.ts
//
// Phase 7 — Real ML Market-Value Prediction (Model A)
//
// POST /functions/v1/ai-predict-price
// Body: { auction_id: string, features: AuctionFeatures }
//
// Flow:
//   1. Verify JWT (any authenticated user)
//   2. Check ai.shadow_mode_enabled flag (503 if disabled)
//   3. Cache check — return existing real prediction if < 30 min old
//   4. Call FastAPI /predict-price with 3-attempt retry + 30 s timeout
//   5. Visibility gate — if ai.predictions_visible_to_clients=false,
//      return { stored: true } instead of the actual values
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
const CACHE_WINDOW_MS      = 30 * 60 * 1_000;  // 30 minutes
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
    const shadowEnabled    = flags['ai.shadow_mode_enabled']         === 'true';
    const visibleToClients = flags['ai.predictions_visible_to_clients'] === 'true';

    if (!shadowEnabled) {
      return json({ error: 'AI predictions not available (shadow mode disabled)' }, 503);
    }

    // ── 4. Cache check — return stored prediction if < 30 min old ────────────
    const cacheAfter = new Date(Date.now() - CACHE_WINDOW_MS).toISOString();
    const { data: cached } = await supabase
      .from('ai_predictions')
      .select('id, expected_auction_price, value_signal, value_ratio, confidence_score, model_version')
      .eq('auction_id', auction_id)
      .eq('prediction_type', 'auction_price_estimate')
      .eq('prediction_source', 'real')
      .gte('created_at', cacheAfter)
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle();

    if (cached) {
      console.log(JSON.stringify({ event: 'cache_hit', auction_id, prediction_id: cached.id }));
      if (!visibleToClients) return json({ stored: true, auction_id, shadow_mode: true });
      return json({
        prediction_id:          cached.id,
        model_version:          cached.model_version,
        expected_auction_price: cached.expected_auction_price,
        value_signal:           cached.value_signal,
        value_ratio:            cached.value_ratio,
        confidence_score:       cached.confidence_score,
        cached:                 true,
      });
    }

    // ── 5. Call FastAPI with retry + timeout ─────────────────────────────────
    const inferenceUrl = Deno.env.get('AI_INFERENCE_URL');
    if (!inferenceUrl) {
      console.error(JSON.stringify({ event: 'config_error', missing: 'AI_INFERENCE_URL' }));
      return json({ error: 'AI inference service not configured' }, 503);
    }

    const startMs = Date.now();
    let inferenceResp: Response;
    try {
      inferenceResp = await withRetry(
        () => fetchWithTimeout(
          `${inferenceUrl}/predict-price`,
          {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ auction_id, store_prediction: true, features }),
          },
          INFERENCE_TIMEOUT_MS,
        ),
        MAX_RETRIES,
      );
    } catch (err) {
      const durationMs = Date.now() - startMs;
      console.error(JSON.stringify({
        event: 'inference_unavailable', auction_id, duration_ms: durationMs, error: String(err),
      }));
      return json({ error: 'AI inference service unavailable' }, 503);
    }

    const durationMs = Date.now() - startMs;

    if (!inferenceResp.ok) {
      const errText = await inferenceResp.text().catch(() => '');
      console.error(JSON.stringify({
        event: 'inference_error', auction_id, status: inferenceResp.status,
        body: errText, duration_ms: durationMs,
      }));
      return json({ error: 'Prediction generation failed' }, 502);
    }

    const prediction = await inferenceResp.json() as {
      prediction_id?:         string;
      model_version:          string;
      expected_auction_price: number;
      value_signal:           string;
      value_ratio:            number;
      confidence_score:       number;
      inference_ms:           number;
    };

    console.log(JSON.stringify({
      event: 'prediction_generated', auction_id,
      model_version: prediction.model_version, duration_ms: durationMs,
    }));

    // ── 6. Visibility gate ───────────────────────────────────────────────────
    if (!visibleToClients) return json({ stored: true, auction_id, shadow_mode: true });

    return json({
      prediction_id:          prediction.prediction_id ?? null,
      model_version:          prediction.model_version,
      expected_auction_price: prediction.expected_auction_price,
      value_signal:           prediction.value_signal,
      value_ratio:            prediction.value_ratio,
      confidence_score:       prediction.confidence_score,
      inference_ms:           prediction.inference_ms,
      cached:                 false,
    });

  } catch (err) {
    console.error(JSON.stringify({ event: 'ai_predict_price_unhandled', error: String(err) }));
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
