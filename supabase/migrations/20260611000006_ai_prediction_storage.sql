-- supabase/migrations/20260611000006_ai_prediction_storage.sql
--
-- Phase 2 AI Dataset Foundation: ai_predictions storage table
--
-- Purpose: Stores ML model inference outputs per auction.
--          Table is EMPTY until Phase 3 inference pipeline is built.
--          This is PREPARATION ONLY — no prediction logic is implemented here.
--
-- Security:
--   RLS enabled: only super_admins can SELECT, only service_role can INSERT.
--   No direct INSERT from authenticated/anon clients.
--
-- Idempotency: CREATE TABLE IF NOT EXISTS, DROP/CREATE POLICY, CREATE INDEX IF NOT EXISTS.
-- Prerequisites: migrations 000000–000005 applied.
-- Rollback: see bottom of file.

-- ============================================================
-- BEFORE Validation Queries
-- ============================================================

-- V0-1: Confirm ai_predictions does NOT yet exist:
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ) AS table_exists;
-- Expected: false

-- ============================================================
-- Part A: Create ai_predictions table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_predictions (
  id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id             UUID         NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
  model_version          TEXT         NOT NULL,
  prediction_type        TEXT         NOT NULL
                           CHECK (prediction_type IN ('price', 'winning_bid', 'interest_score')),
  predicted_price        NUMERIC      CHECK (predicted_price IS NULL OR predicted_price >= 0),
  predicted_winning_bid  NUMERIC      CHECK (predicted_winning_bid IS NULL OR predicted_winning_bid >= 0),
  predicted_probability  NUMERIC      CHECK (predicted_probability IS NULL OR (predicted_probability >= 0 AND predicted_probability <= 1)),
  confidence_score       NUMERIC      CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
  feature_snapshot       JSONB        NOT NULL DEFAULT '{}',
  created_at             TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================
-- Part B: Enable RLS
-- ============================================================

ALTER TABLE public.ai_predictions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Part C: RLS Policies
-- ============================================================

-- Only active super_admins may read predictions
DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;
CREATE POLICY super_admin_read_ai_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.super_admins
      WHERE id = auth.uid()
        AND account_status = 'active'
    )
  );

-- No INSERT/UPDATE/DELETE for authenticated/anon — only service_role (bypasses RLS) writes.
-- This prevents client-side prediction injection.

-- ============================================================
-- Part D: Indexes
-- ============================================================

-- Most common query: latest prediction for a given auction
CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_created
  ON public.ai_predictions (auction_id, created_at DESC);

-- Audit trail: all predictions from a given model version
CREATE INDEX IF NOT EXISTS idx_ai_predictions_model_version
  ON public.ai_predictions (model_version, prediction_type, created_at DESC);

-- Analytical: all predictions of a given type
CREATE INDEX IF NOT EXISTS idx_ai_predictions_type
  ON public.ai_predictions (prediction_type, created_at DESC);

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- V1: Table exists with 10 columns:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- Expected: 10 columns

-- V2: RLS is enabled:
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'ai_predictions';
-- Expected: true

-- V3: Policy exists:
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'ai_predictions';
-- Expected: 1 row — super_admin_read_ai_predictions, SELECT

-- V4: Three indexes exist (plus PK):
-- SELECT indexname FROM pg_indexes WHERE tablename = 'ai_predictions'
-- ORDER BY indexname;
-- Expected: idx_ai_predictions_auction_created, idx_ai_predictions_model_version,
--           idx_ai_predictions_type, ai_predictions_pkey

-- V5: FK constraint works — bad auction_id fails:
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v0-test', 'price', '{}');
-- Expected: ERROR violates foreign key constraint

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DROP TABLE IF EXISTS public.ai_predictions CASCADE;
