// supabase/functions/ai-model-promote/index.ts
//
// Phase 7 — Promote a Model Version to Active
//
// POST /functions/v1/ai-model-promote
// Body: { model_name: "model_a"|"model_b"|"model_c", version: string }
//
// Auth: super_admin only (region_admin and clients are rejected with 403)
//
// Flow:
//   1. Verify JWT and assert super_admin role
//   2. Validate body fields
//   3. POST to FastAPI /models/{model_name}/promote with retry + timeout
//   4. Return promote result (model_name, promoted_version, previous_version, message)
//
// The FastAPI service atomically:
//   - Sets the requested version as "active" in the registry
//   - Deprecates the previous active version
//   - Reloads the ModelLoader so predictions switch immediately (no restart)
//
// Env vars required:
//   SUPABASE_URL, SUPABASE_ANON_KEY, SUPABASE_SERVICE_ROLE_KEY
//   AI_INFERENCE_URL

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const INFERENCE_TIMEOUT_MS = 15_000;
const MAX_RETRIES          = 2;

const VALID_MODELS = new Set(['model_a', 'model_b', 'model_c']);

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // ── 1. Auth + super_admin gate ───────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Not authenticated' }, 401);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const role = await getCallerRole(authHeader, supabase);
    if (role !== 'super_admin') {
      const status = role === 'unknown' ? 401 : 403;
      const error  = role === 'suspended'
        ? 'Your account is suspended'
        : 'Super admin access required';
      return json({ error }, status);
    }

    // ── 2. Parse + validate body ─────────────────────────────────────────────
    let body: { model_name?: string; version?: string };
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Invalid JSON body' }, 400);
    }

    const { model_name, version } = body;
    if (!model_name || !VALID_MODELS.has(model_name)) {
      return json({
        error: `model_name must be one of: ${[...VALID_MODELS].join(', ')}`,
      }, 400);
    }
    if (!version || typeof version !== 'string' || !version.trim()) {
      return json({ error: 'version is required' }, 400);
    }

    // ── 3. Call FastAPI /models/{model_name}/promote ─────────────────────────
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
          `${inferenceUrl}/models/${encodeURIComponent(model_name)}/promote`,
          {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ version }),
          },
          INFERENCE_TIMEOUT_MS,
        ),
        MAX_RETRIES,
      );
    } catch (err) {
      const durationMs = Date.now() - startMs;
      console.error(JSON.stringify({
        event: 'promote_unavailable', model_name, version, duration_ms: durationMs, error: String(err),
      }));
      return json({ error: 'AI inference service unavailable' }, 503);
    }

    const durationMs = Date.now() - startMs;

    if (!inferenceResp.ok) {
      const errBody = await inferenceResp.json().catch(() => ({ detail: 'unknown' })) as any;
      console.error(JSON.stringify({
        event: 'promote_error', model_name, version,
        status: inferenceResp.status, detail: errBody?.detail, duration_ms: durationMs,
      }));
      // Forward FastAPI's status code (404 = version not found, 409 = already active, 422 = failed acceptance)
      return json({ error: errBody?.detail ?? 'Promotion failed' }, inferenceResp.status);
    }

    const result = await inferenceResp.json() as {
      model_name:       string;
      promoted_version: string;
      previous_version: string | null;
      message:          string;
    };

    console.log(JSON.stringify({
      event: 'model_promoted', model_name, version,
      previous_version: result.previous_version, duration_ms: durationMs,
    }));

    return json(result);

  } catch (err) {
    console.error(JSON.stringify({ event: 'ai_model_promote_unhandled', error: String(err) }));
    return json({ error: 'An unexpected error occurred' }, 500);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getCallerRole(
  authHeader: string,
  supabase: ReturnType<typeof createClient>,
): Promise<string> {
  const { data: { user } } = await createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } },
  ).auth.getUser();

  if (!user) return 'unknown';

  const { data: sa } = await supabase
    .from('super_admins')
    .select('account_status')
    .eq('id', user.id)
    .maybeSingle();
  if (sa) return sa.account_status === 'active' ? 'super_admin' : 'suspended';

  const { data: ra } = await supabase
    .from('region_admins')
    .select('account_status')
    .eq('id', user.id)
    .maybeSingle();
  if (ra) return ra.account_status === 'active' ? 'region_admin' : 'suspended';

  return 'client';
}

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
