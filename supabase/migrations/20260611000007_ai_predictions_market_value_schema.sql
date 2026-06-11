-- supabase/migrations/20260611000007_ai_predictions_market_value_schema.sql
--
-- Alter ai_predictions to reflect Model A's correct role: estimating the expected
-- auction selling price for bidders, NOT recommending starting prices to admins.
--
-- Context:
--   Earlier versions of migration 000006 created ai_predictions with different schemas.
--   This migration brings any already-applied instance to the canonical final state.
--
--   Schema history for the Model A output column:
--     v1 (original 000006): predicted_price              [wrong name]
--     v2 (interim 000006):  estimated_market_value       [wrong name — implies independent appraisal]
--     v3 (final 000006):    expected_auction_price       [correct — this is the target state]
--
--   Schema history for prediction_type values:
--     v1: 'price' / 'winning_bid' / 'interest_score'    [wrong]
--     v2: 'market_value' / 'winning_bid' / 'bid_probability'   [wrong value for Model A]
--     v3: 'auction_price_estimate' / 'winning_bid' / 'bid_probability'  [correct]
--
--   This migration corrects all three issues idempotently, regardless of which
--   historical version of 000006 was applied:
--     1. Renames the Model A output column to expected_auction_price
--     2. Adds value_signal, value_ratio, starting_price_at_prediction (if absent)
--     3. Replaces prediction_type CHECK with the correct allowed values
--     4. Ensures the correct index exists
--     5. Replaces client READ policy with the correctly named and filtered version
--
-- Apply only if migration 000006 has already been run against your Supabase instance.
-- If starting fresh, migration 000006 already contains the final correct schema.
--
-- Idempotency: uses IF EXISTS / IF NOT EXISTS guards throughout.
-- Rollback: see bottom of file.

-- ============================================================
-- Step 1: Rename Model A output column to expected_auction_price
-- Handles all three historical states idempotently.
-- ============================================================

DO $$
BEGIN
  -- v1 instance: column is still named predicted_price
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ai_predictions'
      AND column_name = 'predicted_price'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME COLUMN predicted_price TO expected_auction_price;

  -- v2 instance: column was renamed to estimated_market_value
  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'ai_predictions'
      AND column_name = 'estimated_market_value'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME COLUMN estimated_market_value TO expected_auction_price;

  -- v3 instance (fresh 000006): column is already expected_auction_price — no-op
  END IF;
END;
$$;

-- ============================================================
-- Step 2: Add auction-price-estimate-specific columns (if not present)
-- ============================================================

ALTER TABLE public.ai_predictions
  ADD COLUMN IF NOT EXISTS value_signal TEXT
    CHECK (value_signal IS NULL OR value_signal IN ('undervalued', 'fairly_priced', 'overpriced')),
  ADD COLUMN IF NOT EXISTS value_ratio NUMERIC
    CHECK (value_ratio IS NULL OR value_ratio >= 0),
  ADD COLUMN IF NOT EXISTS starting_price_at_prediction NUMERIC
    CHECK (starting_price_at_prediction IS NULL OR starting_price_at_prediction >= 0);

-- ============================================================
-- Step 3: Replace prediction_type CHECK with correct allowed values
-- Drops any existing prediction_type constraint regardless of its current values.
-- ============================================================

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
    CHECK (prediction_type IN ('auction_price_estimate', 'winning_bid', 'bid_probability'));

-- ============================================================
-- Step 4: Ensure correct index exists (drop any legacy name)
-- ============================================================

DROP INDEX IF EXISTS idx_ai_predictions_auction_created;

CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_type_created
  ON public.ai_predictions (auction_id, prediction_type, created_at DESC);

-- ============================================================
-- Step 5: Replace client READ policy with correctly named version
-- Drops all previous variants by name before recreating.
-- ============================================================

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

-- Drop both historical policy names before creating the correct one
DROP POLICY IF EXISTS client_read_market_value_predictions ON public.ai_predictions;
DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;

CREATE POLICY client_read_auction_price_estimates
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    prediction_type = 'auction_price_estimate'
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

-- V1: expected_auction_price column exists; predicted_price and estimated_market_value do not:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- Expected: expected_auction_price present; predicted_price and estimated_market_value absent

-- V2: prediction_type rejects all historical values:
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'price', '{}');
-- Expected: ERROR violates check constraint
-- (also test 'market_value' — must also be rejected)

-- V3: Two policies exist with correct names:
-- SELECT policyname FROM pg_policies WHERE tablename = 'ai_predictions';
-- Expected: super_admin_read_ai_predictions, client_read_auction_price_estimates

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- -- Reverse Step 5
-- DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;
-- DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;
-- CREATE POLICY super_admin_read_ai_predictions ON public.ai_predictions FOR SELECT TO authenticated
--   USING (EXISTS (SELECT 1 FROM public.super_admins WHERE id = auth.uid() AND account_status = 'active'));
-- CREATE POLICY client_read_market_value_predictions ON public.ai_predictions FOR SELECT TO authenticated
--   USING (
--     prediction_type = 'market_value'
--     AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.account_status = 'active')
--     AND EXISTS (SELECT 1 FROM public.auctions a WHERE a.id = auction_id AND a.status IN ('active', 'closed'))
--   );
--
-- -- Reverse Step 4
-- DROP INDEX IF EXISTS idx_ai_predictions_auction_type_created;
-- CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_created
--   ON public.ai_predictions (auction_id, created_at DESC);
--
-- -- Reverse Step 3
-- ALTER TABLE public.ai_predictions DROP CONSTRAINT IF EXISTS ai_predictions_prediction_type_check;
-- ALTER TABLE public.ai_predictions ADD CONSTRAINT ai_predictions_prediction_type_check
--   CHECK (prediction_type IN ('market_value', 'winning_bid', 'bid_probability'));
--
-- -- Reverse Step 2
-- ALTER TABLE public.ai_predictions
--   DROP COLUMN IF EXISTS value_signal,
--   DROP COLUMN IF EXISTS value_ratio,
--   DROP COLUMN IF EXISTS starting_price_at_prediction;
--
-- -- Reverse Step 1 (to v2 intermediate state)
-- ALTER TABLE public.ai_predictions RENAME COLUMN expected_auction_price TO estimated_market_value;
