-- supabase/migrations/20260611000006_ai_prediction_storage.sql
--
-- Phase 2 AI Dataset Foundation: ai_predictions storage table
--
-- Purpose: Stores ML model inference outputs per auction.
--          Table is EMPTY until Phase 4 inference pipeline is built.
--          This is PREPARATION ONLY — no prediction logic is implemented here.
--
-- Model A (market_value):  estimated_market_value, value_signal, value_ratio columns.
-- Model B (winning_bid):   predicted_winning_bid column.
-- Model C (bid_probability): predicted_probability column.
--
-- NOTE: Model A does NOT set or suggest the starting_price. starting_price is the
--       minimum allowed bid, set manually by region admins. Model A estimates fair
--       market value to help CLIENTS (bidders) assess whether an auction is
--       undervalued, fairly priced, or overpriced.
--
-- Security:
--   RLS enabled:
--     - super_admins: full SELECT on all predictions
--     - active clients: SELECT on market_value predictions for auctions they can see
--     - service_role bypasses RLS for INSERT (FastAPI inference layer)
--
-- Idempotency: CREATE TABLE IF NOT EXISTS, DROP/CREATE POLICY, CREATE INDEX IF NOT EXISTS.
-- Prerequisites: migrations 000000-000005 applied.
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
  id                          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id                  UUID         NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
  model_version               TEXT         NOT NULL,
  prediction_type             TEXT         NOT NULL
                                CHECK (prediction_type IN ('market_value', 'winning_bid', 'bid_probability')),

  -- Model A: market value estimation
  estimated_market_value      NUMERIC      CHECK (estimated_market_value IS NULL OR estimated_market_value >= 0),
  value_signal                TEXT         CHECK (value_signal IS NULL OR value_signal IN ('undervalued', 'fairly_priced', 'overpriced')),
  value_ratio                 NUMERIC      CHECK (value_ratio IS NULL OR value_ratio >= 0),
  starting_price_at_prediction NUMERIC     CHECK (starting_price_at_prediction IS NULL OR starting_price_at_prediction >= 0),

  -- Model B: winning bid regression
  predicted_winning_bid       NUMERIC      CHECK (predicted_winning_bid IS NULL OR predicted_winning_bid >= 0),

  -- Model C: bid probability classification
  predicted_probability       NUMERIC      CHECK (predicted_probability IS NULL OR (predicted_probability >= 0 AND predicted_probability <= 1)),

  -- Shared
  confidence_score            NUMERIC      CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
  feature_snapshot            JSONB        NOT NULL DEFAULT '{}',
  created_at                  TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================
-- Part B: Enable RLS
-- ============================================================

ALTER TABLE public.ai_predictions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Part C: RLS Policies
-- ============================================================

-- Super admins: read all predictions
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

-- Clients: read market_value predictions for auctions that are published (visible to them)
-- This allows the Flutter AuctionDetailScreen to display estimated_market_value,
-- value_signal, and value_ratio to bidders without exposing winning_bid or
-- bid_probability predictions.
DROP POLICY IF EXISTS client_read_market_value_predictions ON public.ai_predictions;
CREATE POLICY client_read_market_value_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    prediction_type = 'market_value'
    AND EXISTS (
      SELECT 1
      FROM public.users u
      WHERE u.id = auth.uid()
        AND u.account_status = 'active'
    )
    AND EXISTS (
      SELECT 1
      FROM public.auctions a
      WHERE a.id = auction_id
        AND a.status IN ('active', 'closed')
    )
  );

-- No INSERT/UPDATE/DELETE for authenticated/anon — only service_role (bypasses RLS) writes.
-- This prevents client-side prediction injection.

-- ============================================================
-- Part D: Indexes
-- ============================================================

-- Most common query: latest prediction for a given auction by type
CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_type_created
  ON public.ai_predictions (auction_id, prediction_type, created_at DESC);

-- Audit trail: all predictions from a given model version
CREATE INDEX IF NOT EXISTS idx_ai_predictions_model_version
  ON public.ai_predictions (model_version, prediction_type, created_at DESC);

-- Analytical: all predictions of a given type
CREATE INDEX IF NOT EXISTS idx_ai_predictions_type
  ON public.ai_predictions (prediction_type, created_at DESC);

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- V1: Table exists with 14 columns:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- Expected: 14 columns (id, auction_id, model_version, prediction_type,
--   estimated_market_value, value_signal, value_ratio, starting_price_at_prediction,
--   predicted_winning_bid, predicted_probability, confidence_score,
--   feature_snapshot, created_at — note: 13 listed + id = 14 total)

-- V2: RLS is enabled:
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'ai_predictions';
-- Expected: true

-- V3: Two policies exist:
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'ai_predictions';
-- Expected: 2 rows — super_admin_read_ai_predictions (SELECT),
--                     client_read_market_value_predictions (SELECT)

-- V4: Three indexes exist (plus PK):
-- SELECT indexname FROM pg_indexes WHERE tablename = 'ai_predictions'
-- ORDER BY indexname;
-- Expected: ai_predictions_pkey, idx_ai_predictions_auction_type_created,
--           idx_ai_predictions_model_version, idx_ai_predictions_type

-- V5: prediction_type CHECK rejects old value:
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'price', '{}');
-- Expected: ERROR violates check constraint "ai_predictions_prediction_type_check"

-- V6: prediction_type CHECK accepts new value:
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (<valid_auction_uuid>, 'v1.0.4-synthetic', 'market_value', '{}');
-- Expected: 1 row inserted (via service_role)

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DROP TABLE IF EXISTS public.ai_predictions CASCADE;
