-- =============================================================================
-- E-CYAMUNARA — pg_cron setup
-- Run this ONCE in Supabase Dashboard → SQL Editor (production project only)
-- =============================================================================
--
-- BEFORE RUNNING:
--   1. Replace YOUR_SERVICE_ROLE_KEY below with your actual service role key.
--      → Dashboard → Settings → API → "service_role" key (keep this secret)
--   2. Confirm pg_cron extension is enabled:
--      Dashboard → Database → Extensions → search "pg_cron" → enable it
--   3. Confirm pg_net extension is enabled (needed for net.http_post):
--      Dashboard → Database → Extensions → search "pg_net" → enable it
--   4. Deploy auto-close-auctions with the auth guard before running this:
--      supabase functions deploy auto-close-auctions
--
-- NEVER commit the service role key to Git. This file uses a placeholder.
-- =============================================================================

-- ── Step 1: Verify both extensions are active ─────────────────────────────────
SELECT extname, extversion
FROM pg_extension
WHERE extname IN ('pg_cron', 'pg_net');
-- Expected: two rows. If either is missing, enable it in the Dashboard first.

-- ── Step 2: Remove any existing jobs (idempotent re-run safety) ───────────────
SELECT cron.unschedule('close-auctions')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'close-auctions'
);

SELECT cron.unschedule('cleanup-notifications')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'cleanup-notifications'
);

-- ── Step 3: Schedule auto-close-auctions (every 5 minutes) ───────────────────
-- This calls the Edge Function with the service role key in the Authorization
-- header, which is the ONLY accepted caller after the auth guard was added.
SELECT cron.schedule(
  'close-auctions',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/auto-close-auctions',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step 4: Schedule cleanup-notifications (every Sunday 22:00 UTC) ──────────
-- 22:00 UTC = midnight Kigali (UTC+2). Deletes notifications older than 30 days.
SELECT cron.schedule(
  'cleanup-notifications',
  '0 22 * * 0',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/cleanup-notifications',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step 5: Verify jobs were created ─────────────────────────────────────────
SELECT jobid, jobname, schedule, active
FROM cron.job
ORDER BY jobname;
-- Expected: two rows — 'close-auctions' and 'cleanup-notifications'

-- ── Step 6: Monitor first execution ──────────────────────────────────────────
-- Wait up to 5 minutes, then run:
SELECT
  d.jobid,
  j.jobname,
  d.start_time      AS run_started_at,
  d.end_time,
  d.return_message,
  d.status
FROM cron.job_run_details d
JOIN cron.job j ON j.jobid = d.jobid
ORDER BY d.start_time DESC
LIMIT 10;
-- 'succeeded' status confirms the cron is working.
-- 'failed' with 401 means the service role key placeholder was not replaced.

-- =============================================================================
-- ROLLBACK (if you need to disable the cron jobs):
--   SELECT cron.unschedule('close-auctions');
--   SELECT cron.unschedule('cleanup-notifications');
-- =============================================================================


-- =============================================================================
-- PHASE 4B — Shadow Mode Prediction Pipeline (added 2026-06-12)
-- Deploy these three Edge Functions first, then run the SQL below:
--   supabase functions deploy generate-auction-price-estimate
--   supabase functions deploy compute-prediction-comparison
--   supabase functions deploy collect-ai-shadow-metrics
-- Replace YOUR_SERVICE_ROLE_KEY with your actual key before running.
-- =============================================================================

-- ── Step A: Remove any existing Phase 4B jobs (idempotent re-run safety) ─────
SELECT cron.unschedule('generate-auction-price-estimate')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'generate-auction-price-estimate'
);

SELECT cron.unschedule('compute-prediction-comparison')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'compute-prediction-comparison'
);

SELECT cron.unschedule('collect-ai-shadow-metrics')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'collect-ai-shadow-metrics'
);

-- ── Step B: Generate synthetic predictions for active auctions (hourly) ───────
-- Runs at the top of every hour. Skips auctions already predicted today.
-- Shadow mode flag ai.shadow_mode_enabled is checked inside the function.
SELECT cron.schedule(
  'generate-auction-price-estimate',
  '0 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/generate-auction-price-estimate',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step C: Compare predictions vs actual outcomes (every 10 minutes) ─────────
-- Finds closed auctions in the last 48 hours with no comparison row yet.
-- ON CONFLICT (auction_id) safety net prevents double-writes.
SELECT cron.schedule(
  'compute-prediction-comparison',
  '*/10 * * * *',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/compute-prediction-comparison',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step D: Collect daily shadow metrics (02:00 UTC = 04:00 Kigali) ───────────
-- Aggregates yesterday's prediction events, rolling MAPE, and coverage.
-- Upserts on metric_date — safe to re-trigger if the 02:00 job ever fails.
SELECT cron.schedule(
  'collect-ai-shadow-metrics',
  '0 2 * * *',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/collect-ai-shadow-metrics',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step E: Schedule weekly retraining (Phase 9D) ────────────────────────────
-- 03:00 UTC = 05:00 Kigali (UTC+2). Every Sunday.
-- Prerequisite: TRAINING_WORKER_URL secret must be set in Supabase before enabling.
-- If the training worker is not yet deployed, comment out this block.
SELECT cron.schedule(
  'weekly-retraining',
  '0 3 * * 0',
  $$
    SELECT net.http_post(
      url     := 'https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/trigger-weekly-retraining',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body    := '{}'::jsonb
    )
  $$
);

-- ── Step F: Verify all 6 jobs are active ─────────────────────────────────────
SELECT jobid, jobname, schedule, active
FROM cron.job
ORDER BY jobname;
-- Expected 6 rows:
--   cleanup-notifications          0 22 * * 0
--   close-auctions                 */5 * * * *
--   collect-ai-shadow-metrics      0 2 * * *
--   compute-prediction-comparison  */10 * * * *
--   generate-auction-price-estimate 0 * * * *
--   weekly-retraining              0 3 * * 0

-- =============================================================================
-- PHASE 4B ROLLBACK (remove Phase 4B jobs only):
--   SELECT cron.unschedule('generate-auction-price-estimate');
--   SELECT cron.unschedule('compute-prediction-comparison');
--   SELECT cron.unschedule('collect-ai-shadow-metrics');
-- PHASE 9D ROLLBACK:
--   SELECT cron.unschedule('weekly-retraining');
-- =============================================================================
