-- supabase/migrations/20260611000011_shadow_mode_infrastructure.sql
--
-- Phase 4 Pre-work: Shadow-Mode AI Prediction Infrastructure
--
-- Creates the tables and policies required to run predictions silently:
--   Part 1 — app_settings table + shadow mode feature flag seeds
--   Part 2 — Modify client_read_auction_price_estimates RLS to enforce visibility gate
--   Part 3 — ai_prediction_logs (per-prediction event audit)
--   Part 4 — ai_prediction_comparisons (ground-truth vs predicted, filled as auctions close)
--   Part 5 — ai_shadow_metrics (daily aggregate health)
--   Part 6 — v_ai_shadow_dashboard (monitoring view, SECURITY INVOKER)
--
-- Shadow mode invariant: predictions ARE generated and stored, NOT visible to clients.
-- The gate: app_settings WHERE key = 'ai.predictions_visible_to_clients' AND value = 'false'
-- To graduate: UPDATE public.app_settings SET value = 'true'
--              WHERE key = 'ai.predictions_visible_to_clients';
--
-- Idempotency: CREATE TABLE IF NOT EXISTS, INSERT ON CONFLICT DO NOTHING/UPDATE,
--              DROP POLICY IF EXISTS before CREATE POLICY.
-- Prerequisites: migrations 000000-000010 applied.
-- Rollback: see bottom of file.

-- ============================================================
-- BEFORE Validation Queries
-- ============================================================

-- V1: app_settings should not yet exist (or OK if it does — CREATE IF NOT EXISTS):
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'app_settings'
-- ) AS table_exists;

-- V2: ai_prediction_logs should not yet exist:
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'ai_prediction_logs'
-- ) AS table_exists;
-- Expected: false

-- ============================================================
-- Part 1: app_settings — feature flag storage
-- ============================================================

CREATE TABLE IF NOT EXISTS public.app_settings (
  key        TEXT        PRIMARY KEY,
  value      TEXT        NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.app_settings IS
  'Key-value feature flags and operational settings. Written by service_role only. '
  'Read by all authenticated users (flags are non-sensitive).';

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

-- All authenticated users can READ settings (flags must be readable for RLS subqueries
-- in other tables — e.g. the ai.predictions_visible_to_clients flag in ai_predictions policy)
DROP POLICY IF EXISTS app_settings_authenticated_read ON public.app_settings;
CREATE POLICY app_settings_authenticated_read
  ON public.app_settings FOR SELECT TO authenticated
  USING (TRUE);

-- No authenticated write policy → only service_role (bypasses RLS) can write
-- Edge Functions use SUPABASE_SERVICE_ROLE_KEY and bypass RLS for flag updates

-- ── Seed shadow mode feature flags ────────────────────────────────────────────
-- INSERT ON CONFLICT (key) DO NOTHING → safe to re-run without overwriting operational flags.
-- Exception: config flags (non-operational) use DO UPDATE to keep defaults current.

INSERT INTO public.app_settings (key, value, updated_at) VALUES
  ('ai.shadow_mode_enabled',             'true',             NOW()),
  ('ai.predictions_visible_to_clients',  'false',            NOW()),
  ('ai.model_a_active_version',          'v1.0.4-synthetic', NOW()),
  ('ai.model_b_active_version',          'v1.0.0-synthetic', NOW()),
  ('ai.model_c_active_version',          'v1.0.0-synthetic', NOW()),
  ('ai.min_feature_completeness_score',  '0.5',              NOW()),
  ('ai.inference_timeout_ms',            '5000',             NOW()),
  ('ai.retrain_min_new_closed_auctions', '100',              NOW()),
  ('ai.retrain_mape_trigger_threshold',  '0.25',             NOW()),
  ('ai.coverage_alert_threshold',        '0.80',             NOW())
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      updated_at = NOW();

-- Operational flags: insert only — never overwrite existing values on re-run
INSERT INTO public.app_settings (key, value, updated_at) VALUES
  ('ai.retrain_pending',        'false', NOW()),
  ('ai.last_retrain_date',      '',      NOW()),
  ('ai.retrain_trigger_reason', '',      NOW())
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- Part 2: Modify client RLS policy to enforce shadow mode gate
-- ============================================================

-- The existing policy (from migrations 000009/000010) allows active clients to read
-- auction_price_estimate rows for active/closed auctions.  In shadow mode we add a
-- feature flag check so all client reads return 0 rows until the flag is flipped.
-- The subquery can read app_settings because of the SELECT policy set above.

DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;
CREATE POLICY client_read_auction_price_estimates
  ON public.ai_predictions FOR SELECT TO authenticated
  USING (
    prediction_type = 'auction_price_estimate'
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.account_status = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.auctions a
      WHERE a.id = auction_id AND a.auction_status IN ('active', 'closed')
    )
    AND (
      SELECT (value)::boolean
      FROM public.app_settings
      WHERE key = 'ai.predictions_visible_to_clients'
      LIMIT 1
    ) IS NOT DISTINCT FROM true
  );

-- ============================================================
-- Part 3: ai_prediction_logs — per-prediction event audit
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_prediction_logs (
  id                         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id                 UUID,                    -- no FK: log persists if auction deleted
  event_type                 TEXT         NOT NULL
                               CHECK (event_type IN (
                                 'prediction_generated',
                                 'prediction_skipped',
                                 'prediction_error',
                                 'comparison_computed',
                                 'retrain_trigger',
                                 'metrics_collected'
                               )),
  models_run                 TEXT[],                  -- ARRAY['model_a', 'model_b', 'model_c']
  model_versions             JSONB,                   -- {"model_a": "v1.0.4-synthetic", ...}
  duration_ms                INTEGER,                 -- wall-clock inference time
  error_code                 TEXT,
  error_message              TEXT,
  skip_reason                TEXT
                               CHECK (skip_reason IS NULL OR skip_reason IN (
                                 'shadow_mode_disabled',
                                 'feature_completeness_low',
                                 'already_predicted',
                                 'auction_not_active',
                                 'inference_timeout',
                                 'no_winning_amount'
                               )),
  feature_completeness_score FLOAT,
  metadata                   JSONB,                   -- feature snapshot, response details
  created_at                 TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_prediction_logs IS
  'Audit log for every prediction attempt (generated, skipped, or errored). '
  'Contains no PII. Written by service_role only.';

CREATE INDEX IF NOT EXISTS idx_ai_logs_auction_id
  ON public.ai_prediction_logs (auction_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_event_type_created
  ON public.ai_prediction_logs (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created_at
  ON public.ai_prediction_logs (created_at DESC);

ALTER TABLE public.ai_prediction_logs ENABLE ROW LEVEL SECURITY;

-- Super admins read all logs
DROP POLICY IF EXISTS super_admin_read_ai_logs ON public.ai_prediction_logs;
CREATE POLICY super_admin_read_ai_logs
  ON public.ai_prediction_logs FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

-- Region admins have no access to AI logs in shadow mode

-- ============================================================
-- Part 4: ai_prediction_comparisons — ground-truth records
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_prediction_comparisons (
  id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id                UUID          NOT NULL,
  prediction_id             UUID          REFERENCES public.ai_predictions(id) ON DELETE SET NULL,
  model_version             TEXT          NOT NULL,
  -- Predicted values (snapshotted from ai_predictions at comparison time)
  predicted_value           NUMERIC(15,2),
  predicted_value_signal    TEXT,                     -- undervalued / fairly_priced / overpriced
  -- Actual outcome
  actual_value              NUMERIC(15,2),            -- winning_amount (NULL if no bids)
  had_bids                  BOOLEAN       NOT NULL DEFAULT FALSE,
  -- Error metrics (NULL when had_bids = FALSE — no actual to measure against)
  absolute_error_rwf        NUMERIC(15,2),
  absolute_percentage_error FLOAT,
  residual                  NUMERIC(15,2),            -- predicted - actual
  -- Signal accuracy
  actual_signal             TEXT,                     -- signal computed from actual price
  signal_correct            BOOLEAN,
  -- Timestamps (for prediction lag analysis)
  prediction_created_at     TIMESTAMPTZ,
  auction_closed_at         TIMESTAMPTZ,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_prediction_comparisons IS
  'Ground-truth comparison: Model A predicted price vs actual winning_amount. '
  'One row per closed auction. Populated by compute-prediction-comparison Edge Function.';

-- UNIQUE on auction_id: one comparison record per auction, idempotent on webhook re-fire
CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_comparisons_auction_unique
  ON public.ai_prediction_comparisons (auction_id);
CREATE INDEX IF NOT EXISTS idx_ai_comparisons_model_version_created
  ON public.ai_prediction_comparisons (model_version, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_comparisons_created_at
  ON public.ai_prediction_comparisons (created_at DESC);

ALTER TABLE public.ai_prediction_comparisons ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS super_admin_read_ai_comparisons ON public.ai_prediction_comparisons;
CREATE POLICY super_admin_read_ai_comparisons
  ON public.ai_prediction_comparisons FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

-- ============================================================
-- Part 5: ai_shadow_metrics — daily aggregate health
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_shadow_metrics (
  id                          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  metric_date                 DATE         NOT NULL UNIQUE,
  -- Volume (from ai_prediction_logs for the day)
  predictions_generated       INTEGER      NOT NULL DEFAULT 0,
  predictions_skipped         INTEGER      NOT NULL DEFAULT 0,
  predictions_error           INTEGER      NOT NULL DEFAULT 0,
  -- Coverage
  eligible_auctions           INTEGER      NOT NULL DEFAULT 0,   -- active + closed
  covered_auctions            INTEGER      NOT NULL DEFAULT 0,   -- auctions with ≥1 prediction
  coverage_rate               FLOAT,                             -- covered / eligible
  -- Latency
  avg_inference_ms            FLOAT,
  p95_inference_ms            FLOAT,
  -- Confidence
  avg_confidence_model_a      FLOAT,
  -- Value signal distribution
  signal_undervalued_count    INTEGER      NOT NULL DEFAULT 0,
  signal_fairly_priced_count  INTEGER      NOT NULL DEFAULT 0,
  signal_overpriced_count     INTEGER      NOT NULL DEFAULT 0,
  -- Ground-truth accuracy (rolling over last 100 closed auctions with bids)
  comparisons_computed        INTEGER      NOT NULL DEFAULT 0,
  rolling_mape_model_a        FLOAT,
  rolling_mae_rwf_model_a     FLOAT,
  signal_accuracy_rate        FLOAT,
  -- Retrain state snapshot
  retrain_triggered           BOOLEAN      NOT NULL DEFAULT FALSE,
  retrain_trigger_reason      TEXT,
  created_at                  TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_shadow_metrics IS
  'Daily aggregate health metrics for shadow-mode prediction quality monitoring. '
  'Populated at 02:00 UTC by collect-ai-shadow-metrics Edge Function.';

CREATE INDEX IF NOT EXISTS idx_ai_shadow_metrics_date
  ON public.ai_shadow_metrics (metric_date DESC);

ALTER TABLE public.ai_shadow_metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS super_admin_read_shadow_metrics ON public.ai_shadow_metrics;
CREATE POLICY super_admin_read_shadow_metrics
  ON public.ai_shadow_metrics FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

-- ============================================================
-- Part 6: v_ai_shadow_dashboard — monitoring view
-- ============================================================

-- SECURITY INVOKER: PostgreSQL 15+. The view evaluates RLS using the *caller's*
-- permissions, not the definer's. This means the underlying table RLS policies
-- on ai_shadow_metrics, ai_prediction_logs, and app_settings still apply.
-- Super admins (who have read policies on all three) will see results.
-- Other authenticated users will see only the app_settings flags row (they
-- have global read on app_settings, but no read on the other tables).

CREATE OR REPLACE VIEW public.v_ai_shadow_dashboard
  WITH (security_invoker = true)
AS
WITH flags AS (
  SELECT
    MAX(CASE WHEN key = 'ai.shadow_mode_enabled'            THEN value END) AS shadow_mode_enabled,
    MAX(CASE WHEN key = 'ai.predictions_visible_to_clients' THEN value END) AS predictions_visible,
    MAX(CASE WHEN key = 'ai.model_a_active_version'         THEN value END) AS model_a_version,
    MAX(CASE WHEN key = 'ai.model_b_active_version'         THEN value END) AS model_b_version,
    MAX(CASE WHEN key = 'ai.model_c_active_version'         THEN value END) AS model_c_version,
    MAX(CASE WHEN key = 'ai.retrain_pending'                THEN value END) AS retrain_pending,
    MAX(CASE WHEN key = 'ai.last_retrain_date'              THEN value END) AS last_retrain_date,
    MAX(CASE WHEN key = 'ai.retrain_trigger_reason'         THEN value END) AS retrain_trigger_reason
  FROM public.app_settings
  WHERE key LIKE 'ai.%'
),
lifetime_log AS (
  SELECT
    COUNT(*) FILTER (WHERE event_type = 'prediction_generated') AS all_time_generated,
    COUNT(*) FILTER (WHERE event_type = 'prediction_error')     AS all_time_errors,
    COUNT(*) FILTER (WHERE event_type = 'prediction_skipped')   AS all_time_skipped,
    ROUND(AVG(duration_ms) FILTER (WHERE event_type = 'prediction_generated'))::INT
                                                                AS all_time_avg_ms
  FROM public.ai_prediction_logs
),
latest_metrics AS (
  SELECT
    metric_date,
    coverage_rate,
    rolling_mape_model_a,
    signal_accuracy_rate,
    avg_inference_ms,
    p95_inference_ms,
    predictions_generated,
    predictions_error,
    retrain_triggered
  FROM public.ai_shadow_metrics
  ORDER BY metric_date DESC
  LIMIT 1
)
SELECT
  -- Feature flags
  f.shadow_mode_enabled,
  f.predictions_visible,
  f.model_a_version,
  f.model_b_version,
  f.model_c_version,
  f.retrain_pending,
  f.last_retrain_date,
  f.retrain_trigger_reason,
  -- Latest daily snapshot
  m.metric_date                AS latest_metric_date,
  m.coverage_rate,
  m.rolling_mape_model_a,
  m.signal_accuracy_rate,
  m.avg_inference_ms           AS yesterday_avg_ms,
  m.p95_inference_ms           AS yesterday_p95_ms,
  m.predictions_generated      AS yesterday_generated,
  m.predictions_error          AS yesterday_errors,
  m.retrain_triggered          AS yesterday_retrain_triggered,
  -- All-time totals
  l.all_time_generated,
  l.all_time_errors,
  l.all_time_skipped,
  l.all_time_avg_ms
FROM flags f
CROSS JOIN lifetime_log l
LEFT JOIN latest_metrics m ON TRUE;

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- A1: Verify all 13 flags seeded:
-- SELECT COUNT(*) FROM public.app_settings WHERE key LIKE 'ai.%';
-- Expected: 13

-- A2: Verify shadow mode flags are correctly set:
-- SELECT key, value FROM public.app_settings WHERE key LIKE 'ai.%' ORDER BY key;
-- Expected: ai.shadow_mode_enabled='true', ai.predictions_visible_to_clients='false'

-- A3: Verify client policy contains feature flag subquery:
-- SELECT qual FROM pg_policies
-- WHERE tablename = 'ai_predictions'
--   AND policyname = 'client_read_auction_price_estimates';
-- Expected: qual contains 'predictions_visible_to_clients'

-- A4: Verify shadow mode blocks authenticated client reads (run as anon or client JWT):
-- SELECT COUNT(*) FROM public.ai_predictions WHERE prediction_type = 'auction_price_estimate';
-- Expected: 0 rows (even if rows exist — blocked by policy)

-- A5: Verify new tables exist:
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('app_settings','ai_prediction_logs','ai_prediction_comparisons','ai_shadow_metrics')
-- ORDER BY table_name;
-- Expected: 4 rows

-- A6: Verify dashboard view is queryable (as super_admin):
-- SELECT shadow_mode_enabled, predictions_visible, retrain_pending FROM public.v_ai_shadow_dashboard;
-- Expected: true, false, false

-- ============================================================
-- ROLLBACK (execute manually — do NOT apply automatically)
-- ============================================================
/*
-- R1. Remove shadow mode gate from client read policy (restore to 000010 state)
DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;
CREATE POLICY client_read_auction_price_estimates
  ON public.ai_predictions FOR SELECT TO authenticated
  USING (
    prediction_type = 'auction_price_estimate'
    AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.account_status = 'active')
    AND EXISTS (SELECT 1 FROM public.auctions a WHERE a.id = auction_id AND a.auction_status IN ('active', 'closed'))
  );

-- R2. Drop monitoring view and tables (WARNING: data loss)
DROP VIEW  IF EXISTS public.v_ai_shadow_dashboard;
DROP TABLE IF EXISTS public.ai_shadow_metrics;
DROP TABLE IF EXISTS public.ai_prediction_comparisons;
DROP TABLE IF EXISTS public.ai_prediction_logs;

-- R3. Remove shadow mode flags (WARNING: leaves app_settings table intact if it existed before)
DELETE FROM public.app_settings WHERE key LIKE 'ai.%';

-- R4. If app_settings was created by this migration (didn't exist before), also:
-- DROP TABLE IF EXISTS public.app_settings;
*/
