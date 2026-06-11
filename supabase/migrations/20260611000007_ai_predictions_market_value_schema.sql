-- supabase/migrations/20260611000007_ai_predictions_market_value_schema.sql
--
-- Alter ai_predictions to reflect Model A's correct role: market value estimation
-- for bidders, NOT starting price recommendation for admins.
--
-- Context:
--   Migration 000006 created ai_predictions with:
--     - prediction_type IN ('price', 'winning_bid', 'interest_score')   [WRONG]
--     - predicted_price column                                           [WRONG NAME]
--     - RLS: only super_admins can read                                  [WRONG - clients need market_value]
--
--   This migration corrects all three issues:
--     1. Renames predicted_price -> estimated_market_value
--     2. Adds value_signal, value_ratio, starting_price_at_prediction
--     3. Drops old prediction_type constraint and adds the correct one
--     4. Renames the old idx_ai_predictions_auction_created index
--     5. Adds client READ policy for market_value predictions
--
-- Apply only if migration 000006 has already been run against your Supabase instance.
-- If starting fresh, migration 000006 already contains the correct schema.
--
-- Idempotency: uses IF EXISTS / IF NOT EXISTS guards throughout.
-- Rollback: see bottom of file.

-- ============================================================
-- Step 1: Rename predicted_price → estimated_market_value
-- ============================================================

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ai_predictions'
      AND column_name = 'predicted_price'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME COLUMN predicted_price TO estimated_market_value;
  END IF;
END;
$$;

-- ============================================================
-- Step 2: Add market-value-specific columns (if not present)
-- ============================================================

ALTER TABLE public.ai_predictions
  ADD COLUMN IF NOT EXISTS value_signal TEXT
    CHECK (value_signal IS NULL OR value_signal IN ('undervalued', 'fairly_priced', 'overpriced')),
  ADD COLUMN IF NOT EXISTS value_ratio NUMERIC
    CHECK (value_ratio IS NULL OR value_ratio >= 0),
  ADD COLUMN IF NOT EXISTS starting_price_at_prediction NUMERIC
    CHECK (starting_price_at_prediction IS NULL OR starting_price_at_prediction >= 0);

-- ============================================================
-- Step 3: Fix prediction_type CHECK constraint
-- ============================================================

-- Drop old constraint (name may vary by Postgres version — use DO block for safety)
DO $$
DECLARE
  _con TEXT;
BEGIN
  SELECT conname INTO _con
  FROM pg_constraint
  WHERE conrelid = 'public.ai_predictions'::regclass
    AND contype = 'c'
    AND conname LIKE '%prediction_type%';
  IF _con IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.ai_predictions DROP CONSTRAINT %I', _con);
  END IF;
END;
$$;

ALTER TABLE public.ai_predictions
  ADD CONSTRAINT ai_predictions_prediction_type_check
    CHECK (prediction_type IN ('market_value', 'winning_bid', 'bid_probability'));

-- ============================================================
-- Step 4: Fix index name (if old name exists)
-- ============================================================

DROP INDEX IF EXISTS idx_ai_predictions_auction_created;

CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_type_created
  ON public.ai_predictions (auction_id, prediction_type, created_at DESC);

-- ============================================================
-- Step 5: Add client READ policy for market_value predictions
-- ============================================================

-- Remove overly-restrictive super-admin-only policy (replaced with two-policy model)
DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;

CREATE POLICY super_admin_read_ai_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.super_admins
      WHERE id = auth.uid() AND account_status = 'active'
    )
  );

DROP POLICY IF EXISTS client_read_market_value_predictions ON public.ai_predictions;

CREATE POLICY client_read_market_value_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    prediction_type = 'market_value'
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.account_status = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.auctions a
      WHERE a.id = auction_id AND a.status IN ('active', 'closed')
    )
  );

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- V1: estimated_market_value column exists, predicted_price does not:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;

-- V2: prediction_type rejects 'price':
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'price', '{}');
-- Expected: ERROR violates check constraint

-- V3: Two policies exist:
-- SELECT policyname FROM pg_policies WHERE tablename = 'ai_predictions';
-- Expected: super_admin_read_ai_predictions, client_read_market_value_predictions

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- -- Reverse Step 5
-- DROP POLICY IF EXISTS client_read_market_value_predictions ON public.ai_predictions;
-- DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;
-- CREATE POLICY super_admin_read_ai_predictions ON public.ai_predictions FOR SELECT TO authenticated
--   USING (EXISTS (SELECT 1 FROM public.super_admins WHERE id = auth.uid() AND account_status = 'active'));
--
-- -- Reverse Step 4
-- DROP INDEX IF EXISTS idx_ai_predictions_auction_type_created;
-- CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_created
--   ON public.ai_predictions (auction_id, created_at DESC);
--
-- -- Reverse Step 3
-- ALTER TABLE public.ai_predictions DROP CONSTRAINT IF EXISTS ai_predictions_prediction_type_check;
-- ALTER TABLE public.ai_predictions ADD CONSTRAINT ai_predictions_prediction_type_check
--   CHECK (prediction_type IN ('price', 'winning_bid', 'interest_score'));
--
-- -- Reverse Step 2
-- ALTER TABLE public.ai_predictions
--   DROP COLUMN IF EXISTS value_signal,
--   DROP COLUMN IF EXISTS value_ratio,
--   DROP COLUMN IF EXISTS starting_price_at_prediction;
--
-- -- Reverse Step 1
-- ALTER TABLE public.ai_predictions RENAME COLUMN estimated_market_value TO predicted_price;
