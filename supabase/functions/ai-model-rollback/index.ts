// supabase/functions/ai-model-rollback/index.ts
//
// Phase 7 — Roll Back a Model to the Previous Deprecated Version
//
// POST /functions/v1/ai-model-rollback
// Body: { model_name: "model_a"|"model_b"|"model_c" }
//
// Auth: super_admin only (region_admin and clients are rejected with 403)
//
// Flow:
//   1. Verify JWT and assert super_admin role
//   2. Validate model_name
//   3. POST to FastAPI /models/{model_name}/rollback with retry + timeout
//   4. Return rollback result (model_name, rolled_back_from, rolled_back_to, message)
//
// The FastAPI service atomically:
//   - Finds the most recently deprecated version that passed acceptance
//   - Sets it as "active", deprecates the current active version
//   - Reloads the ModelLoader (live switch, no restart)
//
// Returns 409 if there is no deprecated version to roll back to.
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
    let body: { model_name?: string };
    try {
      body = await req.json();
    } catch {
      return json({ error: 'Invalid JSON body' }, 400);
    }

    const { model_name } = body;
    if (!model_name || !VALID_MODELS.has(model_name)) {
      return json({
        error: `model_name must be one of: ${[...VALID_MODELS].join(', ')}`,
      }, 400);
    }

    // ── 3. Call FastAPI /models/{model_name}/rollback ────────────────────────
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
          `${inferenceUrl}/models/${encodeURIComponent(model_name)}/rollback`,
          { method: 'POST', headers: { 'Content-Type': 'application/json' } },
          INFERENCE_TIMEOUT_MS,
        ),
        MAX_RETRIES,
      );
    } catch (err) {
      const durationMs = Date.now() - startMs;
      console.error(JSON.stringify({
        event: 'rollback_unavailable', model_name, duration_ms: durationMs, error: String(err),
      }));
      return json({ error: 'AI inference service unavailable' }, 503);
    }

    const durationMs = Date.now() - startMs;

    if (!inferenceResp.ok) {
      const errBody = await inferenceResp.json().catch(() => ({ detail: 'unknown' })) as any;
      console.error(JSON.stringify({
        event: 'rollback_error', model_name,
        status: inferenceResp.status, detail: errBody?.detail, duration_ms: durationMs,
      }));
      // Forward FastAPI status codes:
      //   404 = unknown model (shouldn't happen — we validate above)
      //   409 = no active version / no deprecated version to roll back to
      return json({ error: errBody?.detail ?? 'Rollback failed' }, inferenceResp.status);
    }

    const result = await inferenceResp.json() as {
      model_name:       string;
      rolled_back_from: string;
      rolled_back_to:   string;
      message:          string;
    };

    console.log(JSON.stringify({
      event: 'model_rolled_back', model_name,
      from: result.rolled_back_from, to: result.rolled_back_to, duration_ms: durationMs,
    }));

    // Phase 9J: audit log — best-effort, silent on failure
    // Requires 'model_rolled_back' event_type added in migration 20260617000003.
    await supabase.from('ai_prediction_logs').insert({
      event_type: 'model_rolled_back',
      duration_ms: durationMs,
      metadata: {
        model_name,
        rolled_back_from: result.rolled_back_from,
        rolled_back_to:   result.rolled_back_to,
        message:          result.message,
      },
    }).catch(() => {});

    // Phase 9Q — notify all active super admins of the rollback
    await _notifySuperAdmins(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      '🔄 AI Model Rolled Back',
      `${model_name} rolled back from v${result.rolled_back_from} to v${result.rolled_back_to}.`,
      'ai_rollback',
    );

    return json(result);

  } catch (err) {
    console.error(JSON.stringify({ event: 'ai_model_rollback_unhandled', error: String(err) }));
    return json({ error: 'An unexpected error occurred' }, 500);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

// Phase 9Q — super-admin notification (in-app + optional OneSignal push)
async function _notifySuperAdmins(
  supabaseUrl: string,
  serviceKey: string,
  title: string,
  body: string,
  notifType: string,
): Promise<void> {
  try {
    const sb = createClient(supabaseUrl, serviceKey);
    const { data: supers } = await sb
      .from('super_admins')
      .select('id')
      .eq('account_status', 'active');
    if (!supers?.length) return;

    await sb.from('notifications').insert(
      (supers as any[]).map((s) => ({
        user_uid: s.id, title, body, type: notifType, auction_id: null,
      })),
    ).catch(() => {});

    try {
      const { data: withIds } = await sb
        .from('super_admins').select('onesignal_player_id')
        .eq('account_status', 'active').not('onesignal_player_id', 'is', null);
      const playerIds = (withIds ?? []).map((s: any) => s.onesignal_player_id).filter(Boolean);
      if (playerIds.length > 0) {
        const apiKey = Deno.env.get('ONESIGNAL_REST_API_KEY');
        const appId  = Deno.env.get('ONESIGNAL_APP_ID');
        if (apiKey && appId) {
          await fetch('https://onesignal.com/api/v1/notifications', {
            method: 'POST',
            headers: { Authorization: `Basic ${apiKey}`, 'Content-Type': 'application/json' },
            body: JSON.stringify({
              app_id: appId, include_player_ids: playerIds,
              headings: { en: title }, contents: { en: body }, data: { type: notifType },
            }),
          }).catch(() => {});
        }
      }
    } catch { /* onesignal_player_id absent — skip push */ }
  } catch { /* never propagate */ }
}

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
