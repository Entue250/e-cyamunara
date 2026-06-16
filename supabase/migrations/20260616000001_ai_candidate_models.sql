-- supabase/migrations/20260616000001_ai_candidate_models.sql
--
-- Phase 9E — Shadow Candidate Evaluation Infrastructure
--
-- Purpose:
--   Track newly trained real-data models as "candidates" in shadow evaluation
--   before promotion. Candidates serve predictions alongside the active model,
--   tagged model_stage='candidate' in ai_predictions. Promotion is Phase 9F.
--
-- Changes:
--   Part 1 — ai_candidate_models table (candidate lifecycle tracking)
--   Part 2 — ai_prediction_comparisons.model_stage column (per-stage comparisons)
--   Part 3 — Replace (auction_id) UNIQUE with (auction_id, model_stage) UNIQUE
--   Part 4 — Index on ai_candidate_models for active evaluations
--
-- Idempotency:
--   CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--   DROP INDEX / CREATE INDEX, CREATE INDEX IF NOT EXISTS
--
-- Prerequisites: migrations 000000–20260614000001 applied.
-- Rollback: see bottom of file.

-- ============================================================
-- Part 1: ai_candidate_models — candidate lifecycle tracking
-- ============================================================
-- One row per (model_name, candidate_version) pair.
-- Inserted by the register-candidate-model Edge Function after Phase 9D training.
-- Status transitions:
--   evaluating  → collecting comparison rows (Phase 9E)
--   promoted    → Phase 9F gate passed, model_stage='production'
--   rejected    → Phase 9F gate failed (candidate_mape worse than active)
--   expired     → evaluation window exceeded without enough comparisons

CREATE TABLE IF NOT EXISTS public.ai_candidate_models (
  id                           UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  model_name                   TEXT          NOT NULL
                                 CHECK (model_name IN ('model_a', 'model_b', 'model_c')),
  candidate_version            TEXT          NOT NULL,
  active_version_at_registration TEXT        NOT NULL,
  status                       TEXT          NOT NULL DEFAULT 'evaluating'
                                 CHECK (status IN ('evaluating', 'promoted', 'rejected', 'expired')),
  registered_at                TIMESTAMPTZ   NOT NULL DEFAULT now(),
  min_comparisons_needed       INTEGER       NOT NULL DEFAULT 100,
  comparisons_count            INTEGER       NOT NULL DEFAULT 0,
  -- Populated by collect-candidate-metrics (Phase 9F pre-requisite)
  candidate_mape               NUMERIC,
  active_mape                  NUMERIC,
  candidate_auc                NUMERIC,
  active_auc                   NUMERIC,
  evaluation_started_at        TIMESTAMPTZ   NOT NULL DEFAULT now(),
  evaluation_ended_at          TIMESTAMPTZ,
  notes                        TEXT,
  UNIQUE (model_name, candidate_version)
);

ALTER TABLE public.ai_candidate_models ENABLE ROW LEVEL SECURITY;

-- Super admins: full access to candidate tracking
DROP POLICY IF EXISTS super_admin_manage_candidates ON public.ai_candidate_models;
CREATE POLICY super_admin_manage_candidates
  ON public.ai_candidate_models
  TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.super_admins sa
    WHERE sa.id = auth.uid() AND sa.account_status = 'active'
  ));

CREATE INDEX IF NOT EXISTS idx_ai_candidates_status
  ON public.ai_candidate_models (model_name, status, registered_at DESC);

-- ============================================================
-- Part 2: ai_prediction_comparisons.model_stage column
-- ============================================================
-- Distinguishes comparison rows for the active-shadow model ('shadow')
-- from rows for a candidate model under evaluation ('candidate').
-- Default 'shadow' preserves the semantics of all existing rows.

ALTER TABLE public.ai_prediction_comparisons
  ADD COLUMN IF NOT EXISTS model_stage TEXT NOT NULL DEFAULT 'shadow'
    CHECK (model_stage IN ('shadow', 'candidate'));

-- ============================================================
-- Part 3: Replace (auction_id) UNIQUE with (auction_id, model_stage) UNIQUE
-- ============================================================
-- Allows one comparison row per auction per model_stage:
--   • (auction_id, 'shadow')    — active model accuracy
--   • (auction_id, 'candidate') — candidate model accuracy
--
-- Note: Supabase's UPSERT requires a UNIQUE INDEX (not UNIQUE CONSTRAINT)
-- for onConflict to work via the PostgREST client. We recreate as indexes.

DROP INDEX IF EXISTS public.idx_ai_comparisons_auction_unique;

CREATE UNIQUE INDEX IF NOT EXISTS idx_ai_comparisons_auction_stage_unique
  ON public.ai_prediction_comparisons (auction_id, model_stage);

-- ============================================================
-- VALIDATION Queries (run after applying)
-- ============================================================

-- V1: ai_candidate_models exists with expected columns:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ai_candidate_models'
-- ORDER BY ordinal_position;
-- Expected: id, model_name, candidate_version, active_version_at_registration,
--           status, registered_at, min_comparisons_needed, comparisons_count,
--           candidate_mape, active_mape, candidate_auc, active_auc,
--           evaluation_started_at, evaluation_ended_at, notes

-- V2: ai_prediction_comparisons has model_stage:
-- SELECT column_name, column_default FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ai_prediction_comparisons'
-- AND column_name='model_stage';
-- Expected: model_stage | 'shadow'::text

-- V3: New unique index exists:
-- SELECT indexname FROM pg_indexes WHERE tablename='ai_prediction_comparisons'
-- AND indexname='idx_ai_comparisons_auction_stage_unique';
-- Expected: 1 row

-- V4: Old unique index is gone:
-- SELECT indexname FROM pg_indexes WHERE tablename='ai_prediction_comparisons'
-- AND indexname='idx_ai_comparisons_auction_unique';
-- Expected: 0 rows

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DROP TABLE IF EXISTS public.ai_candidate_models CASCADE;
-- DROP INDEX IF EXISTS public.idx_ai_comparisons_auction_stage_unique;
-- ALTER TABLE public.ai_prediction_comparisons DROP COLUMN IF EXISTS model_stage;
-- CREATE UNIQUE INDEX idx_ai_comparisons_auction_unique
--   ON public.ai_prediction_comparisons (auction_id);
