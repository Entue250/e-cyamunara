-- supabase/migrations/20260611000011_shadow_mode_infrastructure.sql
--
-- Phase 4 Pre-work: Shadow-Mode AI Prediction Infrastructure
-- REDESIGNED 2026-06-12: uses ai_feature_flags instead of app_settings
-- HARDENED   2026-06-12: SECURITY DEFINER gate function, restricted RLS,
--                        view guard, safe boolean evaluation
--
-- Background:
--   Pre-deployment audit confirmed public.app_settings exists in production
--   with a single-row config schema (id, app_version, maintenance_mode,
--   max_bid_increment, auction_auto_close, notification_enabled, updated_at,
--   updated_by) used by Flutter's AppSettingsRepository. This migration does
--   not touch app_settings in any way.
--
--   public.ai_feature_flags is a new, dedicated key-value store for AI/ML
--   operational flags only. Clients never read it directly — the gate check
--   is delegated to a STABLE SECURITY DEFINER function that bypasses RLS
--   internally.
--
-- Creates:
--   Part 1  — ai_feature_flags table + shadow mode feature flag seeds
--   Part 1b — ai_shadow_mode_gate() STABLE SECURITY DEFINER helper function
--   Part 2  — Modify client_read_auction_price_estimates RLS to enforce gate
--   Part 3  — ai_prediction_logs (per-prediction event audit)
--   Part 4  — ai_prediction_comparisons (ground-truth vs predicted)
--   Part 5  — ai_shadow_metrics (daily aggregate health)
--   Part 6  — v_ai_shadow_dashboard (super-admin monitoring view)
--
-- Shadow mode invariant: predictions ARE generated and stored, NOT visible to
--   clients. Gate: ai_feature_flags WHERE key = 'ai.predictions_visible_to_clients'
--   AND value = 'true' (currently seeded 'false' — no client visibility).
-- To graduate to live:
--   UPDATE public.ai_feature_flags SET value = 'true', updated_at = NOW()
--   WHERE key = 'ai.predictions_visible_to_clients';
--
-- service_role write assumption: Edge Functions MUST use SUPABASE_SERVICE_ROLE_KEY.
--   Using SUPABASE_ANON_KEY results in silent write failures (RLS deny, no
--   error raised by Supabase client). This cannot be enforced by the migration.
--
-- Idempotency: CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION,
--   INSERT ON CONFLICT DO NOTHING/UPDATE, DROP POLICY IF EXISTS before CREATE
--   POLICY, CREATE INDEX IF NOT EXISTS, CREATE OR REPLACE VIEW.
-- Prerequisites: migrations 000000-000010 applied.
-- Rollback: see bottom of file.

-- ============================================================
-- BEFORE Validation Queries
-- ============================================================

-- V1: ai_feature_flags must not yet exist (CREATE IF NOT EXISTS is safe either way):
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'ai_feature_flags'
-- ) AS table_exists;
-- Expected: false

-- V2: app_settings schema is unchanged — confirm no regression target:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'app_settings'
-- ORDER BY ordinal_position;
-- Expected: id, app_version, maintenance_mode, max_bid_increment,
--           auction_auto_close, notification_enabled, updated_at, updated_by
-- STOP if any deviation — investigate before proceeding.

-- V3: New tables must not yet exist:
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('ai_prediction_logs','ai_prediction_comparisons','ai_shadow_metrics');
-- Expected: 0 rows

-- V4: ai_shadow_mode_gate function must not yet exist:
-- SELECT EXISTS (
--   SELECT 1 FROM pg_proc
--   JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
--   WHERE nspname = 'public' AND proname = 'ai_shadow_mode_gate'
-- ) AS fn_exists;
-- Expected: false

-- ============================================================
-- Part 1: ai_feature_flags — dedicated AI/ML feature flag store
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_feature_flags (
  key        TEXT        PRIMARY KEY,
  value      TEXT        NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_feature_flags IS
  'Key-value feature flags for AI/ML shadow-mode operations. '
  'Written by service_role only (Edge Functions via SUPABASE_SERVICE_ROLE_KEY). '
  'Clients never read this table directly — gate check goes through '
  'ai_shadow_mode_gate() SECURITY DEFINER function. '
  'DO NOT merge with public.app_settings (super-admin app config).';

ALTER TABLE public.ai_feature_flags ENABLE ROW LEVEL SECURITY;

-- Super admins only: read all flags (required for v_ai_shadow_dashboard view).
-- Clients do not need direct access — ai_shadow_mode_gate() handles the gate.
DROP POLICY IF EXISTS ai_feature_flags_super_admin_read ON public.ai_feature_flags;
CREATE POLICY ai_feature_flags_super_admin_read
  ON public.ai_feature_flags FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.super_admins sa
      WHERE sa.id = auth.uid() AND sa.account_status = 'active'
    )
  );

-- No INSERT/UPDATE/DELETE policy for any authenticated/anon role.
-- service_role (BYPASSRLS) writes via Edge Functions.

-- ── Seed shadow mode feature flags ────────────────────────────────────────────
-- Config flags: DO UPDATE — keeps model version defaults current on re-run.
INSERT INTO public.ai_feature_flags (key, value, updated_at) VALUES
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

-- Operational flags: DO NOTHING — never overwrite live state on re-run.
-- Note: ai.last_retrain_date and ai.retrain_trigger_reason are seeded as ''
-- (empty string = "no retrain yet"). Edge Functions must treat '' as the
-- not-yet-retrained sentinel rather than expecting a parseable date.
INSERT INTO public.ai_feature_flags (key, value, updated_at) VALUES
  ('ai.retrain_pending',        'false', NOW()),
  ('ai.last_retrain_date',      '',      NOW()),
  ('ai.retrain_trigger_reason', '',      NOW())
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- Part 1b: ai_shadow_mode_gate() — STABLE SECURITY DEFINER helper
-- ============================================================

-- Purpose: Evaluates the client-visibility flag without requiring clients to
--   have any direct SELECT access to ai_feature_flags.
--
-- SECURITY DEFINER: runs as the function owner (postgres), bypasses RLS on
--   ai_feature_flags. Clients never touch the table directly.
--
-- STABLE: PostgreSQL caches the result for the duration of a single query.
--   A SELECT on ai_predictions that checks thousands of rows calls this
--   function exactly once per statement, not once per row.
--
-- SET search_path = public: prevents schema-injection attacks where a
--   malicious schema could shadow public.ai_feature_flags.
--
-- EXISTS (... AND value = 'true'): always returns boolean, never errors.
--   Resilient to: empty string value, missing row, unexpected content.
--   Contrast with (value)::boolean which ERRORs on empty string input.
--
-- Default when flag row is absent: EXISTS returns FALSE — gate stays closed.

CREATE OR REPLACE FUNCTION public.ai_shadow_mode_gate()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.ai_feature_flags
    WHERE key   = 'ai.predictions_visible_to_clients'
      AND value = 'true'
  );
$$;

-- Restrict execution: authenticated role only. anon cannot invoke this function.
REVOKE ALL     ON FUNCTION public.ai_shadow_mode_gate() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.ai_shadow_mode_gate() TO authenticated;

COMMENT ON FUNCTION public.ai_shadow_mode_gate() IS
  'Returns TRUE when ai.predictions_visible_to_clients = ''true'' in '
  'ai_feature_flags. Used inside client_read_auction_price_estimates RLS '
  'policy on ai_predictions. SECURITY DEFINER — runs as postgres, bypasses '
  'RLS on ai_feature_flags so clients need no direct table access. '
  'STABLE — result cached once per query statement.';

-- ============================================================
-- Part 2: Modify client RLS policy to enforce shadow mode gate
-- ============================================================

-- Replaces the policy from migrations 000009/000010.
-- Gate now calls ai_shadow_mode_gate() rather than an inline scalar subquery:
--   - Clients need no direct access to ai_feature_flags.
--   - Gate evaluates once per SELECT statement (STABLE cache), not per row.
--   - Gate defaults to FALSE on missing row or unexpected value — safe default.

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
    AND public.ai_shadow_mode_gate()
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
  models_run                 TEXT[],                  -- e.g. ARRAY['model_a', 'model_b', 'model_c']
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
  'No PII. Written by service_role only (SUPABASE_SERVICE_ROLE_KEY).';

CREATE INDEX IF NOT EXISTS idx_ai_logs_auction_id
  ON public.ai_prediction_logs (auction_id);
CREATE INDEX IF NOT EXISTS idx_ai_logs_event_type_created
  ON public.ai_prediction_logs (event_type, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_logs_created_at
  ON public.ai_prediction_logs (created_at DESC);

ALTER TABLE public.ai_prediction_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS super_admin_read_ai_logs ON public.ai_prediction_logs;
CREATE POLICY super_admin_read_ai_logs
  ON public.ai_prediction_logs FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

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
  actual_signal             TEXT,
  signal_correct            BOOLEAN,
  -- Timestamps (for prediction lag analysis)
  prediction_created_at     TIMESTAMPTZ,
  auction_closed_at         TIMESTAMPTZ,
  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_prediction_comparisons IS
  'Ground-truth comparison: Model A predicted price vs actual winning_amount. '
  'One row per closed auction (UNIQUE on auction_id — idempotent on webhook re-fire). '
  'Populated by compute-prediction-comparison Edge Function. '
  'prediction_id SET NULL on cascade — comparison row survives prediction cleanup.';

-- UNIQUE on auction_id: one comparison record per auction
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
  -- Volume
  predictions_generated       INTEGER      NOT NULL DEFAULT 0,
  predictions_skipped         INTEGER      NOT NULL DEFAULT 0,
  predictions_error           INTEGER      NOT NULL DEFAULT 0,
  -- Coverage
  eligible_auctions           INTEGER      NOT NULL DEFAULT 0,
  covered_auctions            INTEGER      NOT NULL DEFAULT 0,
  coverage_rate               FLOAT,
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
-- Part 6: v_ai_shadow_dashboard — super-admin monitoring view
-- ============================================================

-- SECURITY INVOKER: each underlying table's RLS applies to the caller.
--   ai_feature_flags:   super-admin-only read policy → only super admins see flags
--   ai_prediction_logs: super-admin-only read policy → only super admins see logs
--   ai_shadow_metrics:  super-admin-only read policy → only super admins see metrics
--
-- WHERE EXISTS (super admin check) in the final SELECT:
--   Non-super-admins receive 0 rows rather than a row of NULLs.
--   This is a defense-in-depth layer: even if the ai_feature_flags RLS policy
--   is relaxed by a future migration, the view itself still returns nothing to
--   non-admins.

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
  FROM public.ai_feature_flags
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
LEFT JOIN latest_metrics m ON TRUE
WHERE EXISTS (
  SELECT 1 FROM public.super_admins sa
  WHERE sa.id = auth.uid() AND sa.account_status = 'active'
);

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- A1: app_settings is untouched (regression guard — run this first)
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'app_settings'
-- ORDER BY ordinal_position;
-- Expected: id, app_version, maintenance_mode, max_bid_increment,
--           auction_auto_close, notification_enabled, updated_at, updated_by
-- STOP and rollback immediately if any column is missing or unexpected.

-- A2: All 4 new tables created
-- SELECT table_name FROM information_schema.tables
-- WHERE table_schema = 'public'
--   AND table_name IN ('ai_feature_flags','ai_prediction_logs',
--                      'ai_prediction_comparisons','ai_shadow_metrics')
-- ORDER BY table_name;
-- Expected: 4 rows

-- A3: Gate function exists, is SECURITY DEFINER and STABLE
-- SELECT proname, prosecdef, provolatile
-- FROM pg_proc JOIN pg_namespace ON pg_namespace.oid = pg_proc.pronamespace
-- WHERE nspname = 'public' AND proname = 'ai_shadow_mode_gate';
-- Expected: 1 row — prosecdef = true, provolatile = 's'

-- A4: Gate function returns false (shadow mode is closed)
-- SELECT public.ai_shadow_mode_gate();
-- Expected: false

-- A5: All 13 flags seeded
-- SELECT COUNT(*) FROM public.ai_feature_flags WHERE key LIKE 'ai.%';
-- Expected: 13

-- A6: Default flag state is correct
-- SELECT key, value FROM public.ai_feature_flags
-- WHERE key IN ('ai.shadow_mode_enabled','ai.predictions_visible_to_clients','ai.retrain_pending')
-- ORDER BY key;
-- Expected:
--   ai.predictions_visible_to_clients = 'false'
--   ai.retrain_pending                = 'false'
--   ai.shadow_mode_enabled            = 'true'

-- A7: Client policy references ai_shadow_mode_gate(), not app_settings or ai_feature_flags
-- SELECT qual FROM pg_policies
-- WHERE tablename = 'ai_predictions' AND policyname = 'client_read_auction_price_estimates';
-- Expected: qual contains 'ai_shadow_mode_gate' — must NOT contain 'app_settings'

-- A8: Shadow gate blocks all client reads (run as authenticated client JWT, not service_role)
-- SELECT COUNT(*) FROM public.ai_predictions WHERE prediction_type = 'auction_price_estimate';
-- Expected: 0 rows

-- A9: Non-super-admin gets 0 rows from dashboard view (run as client JWT)
-- SELECT COUNT(*) FROM public.v_ai_shadow_dashboard;
-- Expected: 0

-- A10: Super admin gets 1 row from dashboard view with correct flag state (run as super_admin JWT)
-- SELECT shadow_mode_enabled, predictions_visible, retrain_pending
-- FROM public.v_ai_shadow_dashboard;
-- Expected: 1 row — 'true', 'false', 'false'

-- A11: RLS enabled on all new tables
-- SELECT relname, relrowsecurity FROM pg_class
-- WHERE relname IN ('ai_feature_flags','ai_prediction_logs',
--                   'ai_prediction_comparisons','ai_shadow_metrics')
--   AND relnamespace = 'public'::regnamespace;
-- Expected: relrowsecurity = true on all 4

-- A12: All 7 new indexes present
-- SELECT tablename, indexname FROM pg_indexes
-- WHERE tablename IN ('ai_prediction_logs','ai_prediction_comparisons','ai_shadow_metrics')
-- ORDER BY tablename, indexname;
-- Expected:
--   ai_prediction_comparisons: idx_ai_comparisons_auction_unique,
--                               idx_ai_comparisons_model_version_created,
--                               idx_ai_comparisons_created_at
--   ai_prediction_logs:        idx_ai_logs_auction_id,
--                               idx_ai_logs_event_type_created,
--                               idx_ai_logs_created_at
--   ai_shadow_metrics:         idx_ai_shadow_metrics_date

-- A13: app_settings AppSettingsRepository still works (run as super_admin JWT)
-- SELECT id, app_version, maintenance_mode FROM public.app_settings WHERE id = 'config';
-- Expected: 1 row with current config values — proves no regression

-- ============================================================
-- ROLLBACK (execute manually — do NOT apply automatically)
-- ============================================================
/*
-- R1. Restore pre-shadow client policy on ai_predictions (removes gate)
DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;
CREATE POLICY client_read_auction_price_estimates
  ON public.ai_predictions FOR SELECT TO authenticated
  USING (
    prediction_type = 'auction_price_estimate'
    AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.account_status = 'active')
    AND EXISTS (SELECT 1 FROM public.auctions a WHERE a.id = auction_id AND a.auction_status IN ('active', 'closed'))
  );

-- R2. Drop gate function
DROP FUNCTION IF EXISTS public.ai_shadow_mode_gate();

-- R3. Drop monitoring view and shadow tables (WARNING: any written data is lost)
DROP VIEW  IF EXISTS public.v_ai_shadow_dashboard;
DROP TABLE IF EXISTS public.ai_shadow_metrics;
DROP TABLE IF EXISTS public.ai_prediction_comparisons;
DROP TABLE IF EXISTS public.ai_prediction_logs;

-- R4. Drop AI feature flag table (WARNING: all flag state is lost)
DROP TABLE IF EXISTS public.ai_feature_flags;

-- R5. Mark migration as reverted in Supabase tracking (run in terminal):
-- supabase migration repair --status reverted 20260611000011
*/
