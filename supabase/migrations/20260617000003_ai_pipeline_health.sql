-- =============================================================================
-- Phase 9J — AI Pipeline Health View + Drift Acknowledgment
-- Run in Supabase Dashboard → SQL Editor after Phase 9G migration is applied.
-- =============================================================================

-- ── Part 1: Extend ai_prediction_logs.event_type CHECK ───────────────────────
-- Adds 'model_rolled_back' so ai-model-rollback can audit to this table.

ALTER TABLE public.ai_prediction_logs
  DROP CONSTRAINT IF EXISTS ai_prediction_logs_event_type_check;

ALTER TABLE public.ai_prediction_logs
  ADD CONSTRAINT ai_prediction_logs_event_type_check
  CHECK (event_type IN (
    'prediction_generated', 'prediction_skipped', 'prediction_error',
    'comparison_computed',  'retrain_trigger',    'metrics_collected',
    'candidate_promoted',   'candidate_rejected',
    'early_retrain_triggered',
    'drift_detected',       'drift_resolved',
    'model_rolled_back'                           -- Phase 9J
  ));

-- ── Part 2: v_ai_pipeline_health ─────────────────────────────────────────────
-- Single-row view that aggregates the overall health of the AI pipeline.
-- Columns:
--   pipeline_health  : 'ok' | 'degraded' | 'critical'
--   health_reason    : human-readable explanation
--   has_high_drift   : any model has high drift in the last 7 days
--   has_low_drift    : any model has low drift in the last 7 days
--   drifted_model_count : count of models with drift detected
--   high_drift_models   : comma-separated names of high-severity models
--   active_mape         : rolling MAPE from the most recent daily metrics
--   coverage_rate       : prediction coverage from the most recent daily metrics
--   candidates_evaluating : how many candidates are currently under evaluation
--   retrain_pending     : 'true' | 'false' — from ai_feature_flags
--   shadow_mode_enabled : 'true' | 'false' — from ai_feature_flags
--   predictions_visible : 'true' | 'false' — from ai_feature_flags
--   last_retrain_at     : timestamp of the most recent retrain trigger event

DROP VIEW IF EXISTS public.v_ai_pipeline_health;

CREATE VIEW public.v_ai_pipeline_health
  WITH (security_invoker = true)
AS
WITH
  recent_drift AS (
    SELECT
      bool_or(drift_severity = 'high')                          AS has_high_drift,
      bool_or(drift_severity = 'low' AND drift_severity != 'none') AS has_low_drift,
      count(*) FILTER (WHERE drift_detected)                    AS drifted_model_count,
      string_agg(model_name, ', ')
        FILTER (WHERE drift_severity = 'high')                  AS high_drift_models
    FROM public.ai_drift_metrics
    WHERE metric_date >= CURRENT_DATE - INTERVAL '7 days'
  ),
  latest_shadow AS (
    -- Pull MAPE and coverage from the most recent daily shadow metrics row.
    SELECT
      rolling_mape_model_a,
      coverage_rate
    FROM public.ai_shadow_metrics
    ORDER BY metric_date DESC
    LIMIT 1
  ),
  candidate_counts AS (
    SELECT count(*) AS evaluating
    FROM public.ai_candidate_models
    WHERE status = 'evaluating'
  ),
  flag_values AS (
    SELECT
      MAX(CASE WHEN key = 'ai.retrain_pending'               THEN value END) AS retrain_pending,
      MAX(CASE WHEN key = 'ai.shadow_mode_enabled'           THEN value END) AS shadow_mode_enabled,
      MAX(CASE WHEN key = 'ai.predictions_visible_to_clients' THEN value END) AS predictions_visible
    FROM public.ai_feature_flags
    WHERE key IN (
      'ai.retrain_pending',
      'ai.shadow_mode_enabled',
      'ai.predictions_visible_to_clients'
    )
  ),
  last_retrain AS (
    SELECT created_at AS retrain_at
    FROM public.ai_prediction_logs
    WHERE event_type IN ('early_retrain_triggered', 'retrain_trigger')
    ORDER BY created_at DESC
    LIMIT 1
  )
SELECT
  -- ── Overall health ────────────────────────────────────────────────────────
  CASE
    WHEN coalesce(d.has_high_drift, false)
         THEN 'critical'
    WHEN coalesce(d.has_low_drift,  false)
      OR  coalesce(s.rolling_mape_model_a, 0)::numeric > 0.25
      OR  coalesce(s.coverage_rate, 1)::numeric         < 0.50
         THEN 'degraded'
    ELSE 'ok'
  END                                                  AS pipeline_health,

  CASE
    WHEN coalesce(d.has_high_drift, false)
         THEN 'High drift on: ' || coalesce(d.high_drift_models, 'unknown model')
    WHEN coalesce(d.has_low_drift, false)
         THEN 'Low drift detected — models diverging from baseline'
    WHEN coalesce(s.rolling_mape_model_a, 0)::numeric > 0.25
         THEN 'Rolling MAPE exceeds 25% — prediction accuracy degraded'
    WHEN coalesce(s.coverage_rate, 1)::numeric < 0.50
         THEN 'Coverage below 50% — most auctions lack AI predictions'
    ELSE 'All systems nominal'
  END                                                  AS health_reason,

  -- ── Drift details ─────────────────────────────────────────────────────────
  coalesce(d.has_high_drift,      false) AS has_high_drift,
  coalesce(d.has_low_drift,       false) AS has_low_drift,
  coalesce(d.drifted_model_count, 0)    AS drifted_model_count,
  d.high_drift_models,

  -- ── Quality metrics ───────────────────────────────────────────────────────
  s.rolling_mape_model_a                AS active_mape,
  s.coverage_rate,

  -- ── Candidate pipeline ────────────────────────────────────────────────────
  coalesce(c.evaluating, 0)             AS candidates_evaluating,

  -- ── Feature flags ─────────────────────────────────────────────────────────
  coalesce(f.retrain_pending,      'false') AS retrain_pending,
  coalesce(f.shadow_mode_enabled,  'false') AS shadow_mode_enabled,
  coalesce(f.predictions_visible,  'false') AS predictions_visible,

  -- ── Last retrain ──────────────────────────────────────────────────────────
  r.retrain_at                          AS last_retrain_at

FROM recent_drift        d
CROSS JOIN candidate_counts c
LEFT JOIN  latest_shadow  s ON true
LEFT JOIN  flag_values    f ON true
LEFT JOIN  last_retrain   r ON true;

-- RLS: same policy as v_ai_shadow_dashboard — super admins only.
-- The view uses security_invoker, so ai_feature_flags/ai_drift_metrics RLS applies.

COMMENT ON VIEW public.v_ai_pipeline_health IS
  'Phase 9J: Single-row aggregate of overall AI pipeline health. '
  'Read by AiDashboardScreen to power the pipeline health banner.';

-- ── Part 3: Verification ──────────────────────────────────────────────────────
SELECT pipeline_health, health_reason, has_high_drift, candidates_evaluating
FROM public.v_ai_pipeline_health;
-- Expected: one row with pipeline_health = 'ok' | 'degraded' | 'critical'

-- =============================================================================
-- ROLLBACK:
--   DROP VIEW IF EXISTS public.v_ai_pipeline_health;
--   (Re-apply old CHECK constraint from 20260617000001 migration if needed)
-- =============================================================================
