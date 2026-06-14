// supabase/functions/ai-retrain-trigger/index.ts
//
// Phase 7 — Queue a Model Retraining Job
//
// POST /functions/v1/ai-retrain-trigger
// Body: { model_name: "model_a"|"model_b"|"model_c"|"all", datasource?: "synthetic"|"real" }
//
// Auth: region_admin or super_admin (clients are rejected with 403)
//
// Flow:
//   1. Verify JWT and resolve role (403 if not admin)
//   2. Validate body fields
//   3. Check FastAPI availability (GET /health)
//   4. POST to FastAPI /retrain-models (returns HTTP 202 + job_id immediately)
//   5. Return { job_id, status, poll_url } — caller can poll /ai-retrain-trigger/{job_id}
//      (not implemented here — poll via FastAPI directly or via a thin GET wrapper)
//
// Idempotency: FastAPI's JobStore allows multiple queued jobs; the caller
//   receives a fresh job_id each time. Callers should store the job_id and
//   poll before re-triggering.
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

const VALID_MODELS     = new Set(['model_a', 'model_b', 'model_c', 'all']);
const VALID_DATASOURCES = new Set(['synthetic', 'real']);

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });

  try {
    // ── 1. Auth + role check ─────────────────────────────────────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return json({ error: 'Not authenticated' }, 401);

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    const role = await getCallerRole(authHeader, supabase);
    if (role === 'unknown' || role === 'client') {
      return json({ error: 'Admin access required' }, 403);
    }
    if (role === 'suspended') {
      return json({ error: 'Your account is suspended' }, 403);
    }

    // ── 2. Parse + validate body ─────────────────────────────────────────────
    let body: { model_name?: string; datasource?: string };
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Invalid JSON body' }, 400);
    }

    const model_name  = body.model_name;
    const datasource  = body.datasource ?? 'synthetic';

    if (!model_name || !VALID_MODELS.has(model_name)) {
      return json({
        error: `model_name must be one of: ${[...VALID_MODELS].join(', ')}`,
      }, 400);
    }
    if (!VALID_DATASOURCES.has(datasource)) {
      return json({
        error: `datasource must be one of: ${[...VALID_DATASOURCES].join(', ')}`,
      }, 400);
    }

    // ── 3. Call FastAPI /retrain-models ──────────────────────────────────────
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
          `${inferenceUrl}/retrain-models`,
          {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ model_name, datasource }),
          },
          INFERENCE_TIMEOUT_MS,
        ),
        MAX_RETRIES,
      );
    } catch (err) {
      const durationMs = Date.now() - startMs;
      console.error(JSON.stringify({
        event: 'retrain_trigger_unavailable', model_name, duration_ms: durationMs, error: String(err),
      }));
      return json({ error: 'AI inference service unavailable' }, 503);
    }

    const durationMs = Date.now() - startMs;

    // FastAPI returns 202 on success
    if (inferenceResp.status !== 202) {
      const errText = await inferenceResp.text().catch(() => '');
      console.error(JSON.stringify({
        event: 'retrain_trigger_error', model_name, status: inferenceResp.status,
        body: errText, duration_ms: durationMs,
      }));
      return json({ error: 'Failed to queue retraining job' }, 502);
    }

    const result = await inferenceResp.json() as {
      job_id:     string;
      status:     string;
      model_name: string;
      datasource: string;
      message:    string;
    };

    console.log(JSON.stringify({
      event: 'retrain_queued', job_id: result.job_id, model_name,
      datasource, triggered_by_role: role, duration_ms: durationMs,
    }));

    return json({
      job_id:     result.job_id,
      status:     result.status,
      model_name: result.model_name,
      datasource: result.datasource,
      message:    result.message,
    }, 202);

  } catch (err) {
    console.error(JSON.stringify({ event: 'ai_retrain_trigger_unhandled', error: String(err) }));
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
