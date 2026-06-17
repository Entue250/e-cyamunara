-- supabase/migrations/20260617000001_ai_drift_metrics.sql
--
-- Phase 9G — Drift Detection Infrastructure
--
-- Changes:
--   Part 1 — Expand ai_prediction_logs.event_type CHECK constraint
--             to include Phase 9F events (candidate_promoted, candidate_rejected)
--             and Phase 9G events (drift_detected, drift_resolved,
--             early_retrain_triggered). The original constraint was too narrow
--             and caused silent write failures in Phase 9F promote-candidate.
--   Part 2 — ai_drift_metrics table: stores daily per-model drift signals and
--             severity, populated by check-model-drift Edge Function.
--
-- Drift signals computed from existing ai_prediction_comparisons data:
--   mape_spike        — 7d MAPE > 30d MAPE * 1.20 (recent quality drop)
--   residual_bias     — |mean_residual| / mean_actual > 0.15 (systematic bias)
--   high_error_rate   — >10% of recent predictions have APE > 0.50
--
-- Severity:
--   none  — 0 signals
--   low   — 1 signal (logged, no action)
--   high  — 2+ signals (logged + early retraining triggered)
--
-- Idempotency:
--   DROP CONSTRAINT IF EXISTS, ADD CONSTRAINT,
--   CREATE TABLE IF NOT EXISTS, CREATE INDEX IF NOT EXISTS
-- Prerequisites: migration 20260616000001_ai_candidate_models applied.
-- Rollback: see bottom of file.

-- ============================================================
-- Part 1: Expand ai_prediction_logs.event_type CHECK constraint
-- ============================================================
-- The original constraint (from 20260611000011) was too narrow.
-- Phase 9F needed candidate_promoted / candidate_rejected; Phase 9G needs
-- drift_detected, drift_resolved, early_retrain_triggered.
-- Drop-and-recreate is the standard PostgreSQL approach.

ALTER TABLE public.ai_prediction_logs
  DROP CONSTRAINT IF EXISTS ai_prediction_logs_event_type_check;

ALTER TABLE public.ai_prediction_logs
  ADD CONSTRAINT ai_prediction_logs_event_type_check
  CHECK (event_type IN (
    'prediction_generated',
    'prediction_skipped',
    'prediction_error',
    'comparison_computed',
    'retrain_trigger',
    'metrics_collected',
    'candidate_promoted',        -- Phase 9F: promote-candidate
    'candidate_rejected',        -- Phase 9F: promote-candidate
    'early_retrain_triggered',   -- Phase 9G: check-model-drift → trigger-early-retraining
    'drift_detected',            -- Phase 9G: check-model-drift (severity high)
    'drift_resolved'             -- Phase 9G: check-model-drift (severity drops to none)
  ));

-- ============================================================
-- Part 2: ai_drift_metrics — daily per-model drift state
-- ============================================================
-- One row per (model_name, checked_at::date) pair.
-- Populated at 04:00 UTC by check-model-drift Edge Function.
-- Upserted on (model_name, metric_date) — safe to re-trigger.

CREATE TABLE IF NOT EXISTS public.ai_drift_metrics (
  id                        UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  model_name                TEXT          NOT NULL
                              CHECK (model_name IN ('model_a', 'model_b', 'model_c')),
  metric_date               DATE          NOT NULL,

  -- Input statistics (snapshot for audit)
  comparisons_7d            INTEGER       NOT NULL DEFAULT 0,   -- rows used for 7d window
  comparisons_30d           INTEGER       NOT NULL DEFAULT 0,   -- rows used for 30d window

  -- MAPE trend signal
  mape_7d                   NUMERIC,      -- mean APE over last 7 days
  mape_30d                  NUMERIC,      -- mean APE over last 30 days
  mape_spike_ratio          NUMERIC,      -- mape_7d / mape_30d
  mape_spike_detected       BOOLEAN       NOT NULL DEFAULT FALSE,

  -- Residual bias signal
  mean_residual             NUMERIC,      -- mean of (predicted - actual)
  mean_actual               NUMERIC,      -- mean of actual values (baseline)
  residual_bias_ratio       NUMERIC,      -- |mean_residual| / mean_actual
  residual_bias_detected    BOOLEAN       NOT NULL DEFAULT FALSE,

  -- High error rate signal
  high_error_count          INTEGER       NOT NULL DEFAULT 0,   -- predictions with APE > 0.50
  high_error_total          INTEGER       NOT NULL DEFAULT 0,   -- total recent predictions
  high_error_rate           NUMERIC,      -- high_error_count / high_error_total
  high_error_rate_detected  BOOLEAN       NOT NULL DEFAULT FALSE,

  -- Overall verdict
  drift_detected            BOOLEAN       NOT NULL DEFAULT FALSE,
  drift_severity            TEXT          NOT NULL DEFAULT 'none'
                              CHECK (drift_severity IN ('none', 'low', 'high')),
  signals_triggered         TEXT[],       -- names of triggered signals
  early_retrain_triggered   BOOLEAN       NOT NULL DEFAULT FALSE,
  notes                     TEXT,

  created_at                TIMESTAMPTZ   NOT NULL DEFAULT NOW(),

  UNIQUE (model_name, metric_date)
);

COMMENT ON TABLE public.ai_drift_metrics IS
  'Daily drift detection results per model. Populated at 04:00 UTC by '
  'check-model-drift Edge Function. Severity ''high'' triggers early retraining '
  'via trigger-early-retraining Edge Function. '
  'Source data: ai_prediction_comparisons (model_stage=''shadow'').';

ALTER TABLE public.ai_drift_metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS super_admin_read_drift_metrics ON public.ai_drift_metrics;
CREATE POLICY super_admin_read_drift_metrics
  ON public.ai_drift_metrics FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

CREATE INDEX IF NOT EXISTS idx_ai_drift_metrics_model_date
  ON public.ai_drift_metrics (model_name, metric_date DESC);

CREATE INDEX IF NOT EXISTS idx_ai_drift_metrics_severity
  ON public.ai_drift_metrics (drift_severity, metric_date DESC)
  WHERE drift_detected = TRUE;

-- ============================================================
-- VALIDATION Queries (run after applying)
-- ============================================================

-- V1: Constraint was replaced — confirm new event types are accepted:
-- INSERT INTO public.ai_prediction_logs (event_type, metadata)
-- VALUES ('candidate_promoted', '{"test": true}');
-- Expected: 1 row inserted (or 422 if check fails — means constraint not applied)
-- DELETE FROM public.ai_prediction_logs WHERE metadata->>'test' = 'true';

-- V2: ai_drift_metrics table exists with expected columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ai_drift_metrics'
-- ORDER BY ordinal_position;
-- Expected: id, model_name, metric_date, comparisons_7d, comparisons_30d,
--           mape_7d, mape_30d, mape_spike_ratio, mape_spike_detected,
--           mean_residual, mean_actual, residual_bias_ratio, residual_bias_detected,
--           high_error_count, high_error_total, high_error_rate,
--           high_error_rate_detected, drift_detected, drift_severity,
--           signals_triggered, early_retrain_triggered, notes, created_at

-- V3: RLS enabled and policy exists:
-- SELECT relrowsecurity FROM pg_class WHERE relname='ai_drift_metrics';
-- Expected: true
-- SELECT policyname FROM pg_policies WHERE tablename='ai_drift_metrics';
-- Expected: super_admin_read_drift_metrics

-- V4: Both indexes exist:
-- SELECT indexname FROM pg_indexes WHERE tablename='ai_drift_metrics'
-- ORDER BY indexname;
-- Expected: ai_drift_metrics_pkey, ai_drift_metrics_model_name_metric_date_key,
--           idx_ai_drift_metrics_model_date, idx_ai_drift_metrics_severity

-- ============================================================
-- ROLLBACK
-- ============================================================

-- -- Restore original CHECK constraint:
-- ALTER TABLE public.ai_prediction_logs
--   DROP CONSTRAINT IF EXISTS ai_prediction_logs_event_type_check;
-- ALTER TABLE public.ai_prediction_logs
--   ADD CONSTRAINT ai_prediction_logs_event_type_check
--   CHECK (event_type IN (
--     'prediction_generated', 'prediction_skipped', 'prediction_error',
--     'comparison_computed', 'retrain_trigger', 'metrics_collected'
--   ));
--
-- DROP TABLE IF EXISTS public.ai_drift_metrics CASCADE;
