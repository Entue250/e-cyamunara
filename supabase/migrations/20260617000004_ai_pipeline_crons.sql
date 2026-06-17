-- ============================================================
-- Phase 9L — AI Pipeline Cron Jobs
-- File: 20260617000004_ai_pipeline_crons.sql
-- ============================================================
--
-- Registers two pg_cron jobs that drive the AI continuous-learning pipeline:
--
--   1. collect-ai-shadow-metrics   — daily 02:00 UTC
--      Aggregates yesterday's prediction events into ai_shadow_metrics.
--      Triggers retrain flag when MAPE exceeds threshold.
--
--   2. generate-auction-price-estimate — every hour at :05
--      Calls FastAPI inference for all active auctions not yet predicted today.
--      Shadow mode must be enabled for predictions to run.
--
-- Prerequisites (must be applied first):
--   • 20260611000011_shadow_mode_infrastructure.sql  (ai_shadow_metrics, ai_feature_flags)
--   • 20260617000003_ai_pipeline_health.sql           (v_ai_pipeline_health)
--
-- Idempotency:
--   All SELECT cron.unschedule() calls are wrapped in DO blocks that swallow
--   "job not found" errors, so this migration is safe to re-run.
--
-- Manual invocation (for testing):
--   SELECT net.http_post(
--     url   := '<SUPABASE_URL>/functions/v1/collect-ai-shadow-metrics',
--     headers := '{"Authorization":"Bearer <SERVICE_KEY>"}',
--     body  := '{}'
--   );
--
-- ============================================================

-- ── 1. Remove old jobs if they exist (idempotent) ─────────────────────────
DO $$
BEGIN
  PERFORM cron.unschedule('collect-ai-shadow-metrics-daily');
EXCEPTION WHEN others THEN NULL;
END;
$$;

DO $$
BEGIN
  PERFORM cron.unschedule('generate-auction-price-estimate-hourly');
EXCEPTION WHEN others THEN NULL;
END;
$$;

-- ── 2. Daily shadow metrics collection — 02:00 UTC ────────────────────────
SELECT cron.schedule(
  'collect-ai-shadow-metrics-daily',
  '0 2 * * *',
  $$
  SELECT net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/collect-ai-shadow-metrics',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key')
               ),
    body    := '{}'::jsonb
  );
  $$
);

-- ── 3. Hourly price-estimate generation — every hour at :05 ─────────────
SELECT cron.schedule(
  'generate-auction-price-estimate-hourly',
  '5 * * * *',
  $$
  SELECT net.http_post(
    url     := current_setting('app.supabase_url') || '/functions/v1/generate-auction-price-estimate',
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || current_setting('app.supabase_service_role_key')
               ),
    body    := '{}'::jsonb
  );
  $$
);

-- ============================================================
-- VALIDATION Queries (run after applying)
-- ============================================================

-- V1: Both cron jobs registered:
-- SELECT jobname, schedule, active FROM cron.job
-- WHERE jobname IN (
--   'collect-ai-shadow-metrics-daily',
--   'generate-auction-price-estimate-hourly'
-- );
-- Expected: 2 rows, both active = true

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DO $$ BEGIN PERFORM cron.unschedule('collect-ai-shadow-metrics-daily'); EXCEPTION WHEN others THEN NULL; END; $$;
-- DO $$ BEGIN PERFORM cron.unschedule('generate-auction-price-estimate-hourly'); EXCEPTION WHEN others THEN NULL; END; $$;
