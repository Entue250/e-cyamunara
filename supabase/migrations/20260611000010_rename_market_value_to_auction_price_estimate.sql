-- supabase/migrations/20260611000008_rename_market_value_to_auction_price_estimate.sql
--
-- Purpose: Rename ai_predictions.estimated_market_value → expected_auction_price
--          and update prediction_type CHECK from 'market_value' → 'auction_price_estimate'.
--          Update RLS policy name and filter to match.
--
-- Context:
--   This migration is the canonical, standalone record of the Model A output column
--   rename. It is safe to apply on any instance regardless of which version of
--   migrations 000006 or 000007 brought the schema to its current state.
--
--   Schema history for the Model A output column:
--     v1 (original 000006): predicted_price              — wrong name
--     v2 (interim 000006):  estimated_market_value       — wrong name (implies independent appraisal)
--     v3 (final 000006/007): expected_auction_price      — correct (target state)
--
--   Schema history for prediction_type allowed values:
--     v1: 'price' / 'winning_bid' / 'interest_score'
--     v2: 'market_value' / 'winning_bid' / 'bid_probability'
--     v3: 'auction_price_estimate' / 'winning_bid' / 'bid_probability'  ← correct
--
--   An instance already in v3 state (expected_auction_price, 'auction_price_estimate',
--   client_read_auction_price_estimates) will experience no-ops for column rename,
--   constraint rename, and constraint update steps. The RLS policy is always
--   DROP + CREATE within one transaction (atomic, no security window).
--
-- Invariant preserved throughout:
--   starting_price is set manually by region admins and is the minimum allowed bid.
--   Model A (auction_price_estimate) estimates the expected selling price for CLIENTS
--   (bidders). It never influences or overrides the admin-defined starting_price.
--   This migration does not touch the auctions table or starting_price in any way.
--
-- Data safety:
--   RENAME COLUMN is a pure catalog update — zero rows are rewritten or removed.
--   RENAME CONSTRAINT is a pure catalog update.
--   DROP + ADD CHECK CONSTRAINT is a catalog-only operation on an empty-or-populated
--   table; rows are not rewritten. Existing rows that would violate the new constraint
--   would cause the ADD CONSTRAINT to fail, but since 'market_value' is a subset of
--   the prior CHECK and 'auction_price_estimate' replaces it, any row with
--   prediction_type = 'market_value' would be rejected after the migration. See the
--   CAUTION note in section D.
--
-- Idempotency:
--   Every step uses IF EXISTS / pg_constraint lookup / DROP IF EXISTS guards.
--   Re-applying this migration to a v3 instance is safe and produces an identical result.
--
-- Rollback: see section D at the bottom of this file.
-- Apply order: after 000007 (depends on ai_predictions table existing).

-- ============================================================
-- A. BEFORE Validation Queries
--    Run these manually BEFORE applying this migration to
--    document the starting state and verify prerequisites.
--    None of these modify any data.
-- ============================================================

-- A1. Confirm ai_predictions table exists (prerequisite):
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ) AS table_exists;
-- Expected: true

-- A2. Current column names — identify which schema version is present:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- v2 instance: includes 'estimated_market_value', NOT 'expected_auction_price'
-- v3 instance: includes 'expected_auction_price', NOT 'estimated_market_value'

-- A3. Current CHECK constraints — identify whether prediction_type allows 'market_value':
-- SELECT conname, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE conrelid = 'public.ai_predictions'::regclass AND contype = 'c'
-- ORDER BY conname;
-- v2: ai_predictions_prediction_type_check definition includes 'market_value'
-- v3: ai_predictions_prediction_type_check definition includes 'auction_price_estimate'

-- A4. Current RLS policies:
-- SELECT policyname, cmd, qual AS using_expression
-- FROM pg_policies
-- WHERE tablename = 'ai_predictions'
-- ORDER BY policyname;
-- v2: client_read_market_value_predictions with qual containing prediction_type = 'market_value'
-- v3: client_read_auction_price_estimates  with qual containing prediction_type = 'auction_price_estimate'

-- A5. Pre-migration row count — compare with C7 to confirm data integrity:
-- SELECT COUNT(*) AS row_count FROM public.ai_predictions;
-- Save this number. It must equal the count after migration.

-- A6. Current indexes:
-- SELECT indexname, indexdef FROM pg_indexes
-- WHERE tablename = 'ai_predictions'
-- ORDER BY indexname;

-- A7. Triggers on ai_predictions (expected: none):
-- SELECT trigger_name, event_manipulation, action_statement
-- FROM information_schema.triggers
-- WHERE event_object_schema = 'public' AND event_object_table = 'ai_predictions';

-- A8. Table-level grants (unaffected by this migration):
-- SELECT grantee, privilege_type FROM information_schema.role_table_grants
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY grantee, privilege_type;

-- ============================================================
-- B. Migration SQL
-- ============================================================

-- ------------------------------------------------------------
-- B0. Capture pre-migration row count.
--
--     Creates a transaction-scoped temp table (ON COMMIT DROP removes it
--     automatically when this migration's transaction commits). Inserts the
--     current row count for comparison in B6.
--
--     RENAME COLUMN, RENAME CONSTRAINT, DROP/ADD CONSTRAINT, and DROP/CREATE
--     POLICY are all pure catalog operations — they cannot modify, add, or
--     remove rows. The B6 assertion is a safety proof of that guarantee.
--
--     IF NOT EXISTS on the CREATE: safe if the migration is retried within
--     the same session (e.g. after a failure). The DELETE clears any prior
--     count from a previous attempt before inserting the current one.
-- ------------------------------------------------------------
DO $$
BEGIN
  CREATE TEMP TABLE IF NOT EXISTS _mig_008_row_check (
    before_count BIGINT NOT NULL
  ) ON COMMIT DROP;

  DELETE FROM _mig_008_row_check;   -- clear any residue from a previous attempt

  INSERT INTO _mig_008_row_check
    SELECT COUNT(*) FROM public.ai_predictions;
END;
$$;

-- ------------------------------------------------------------
-- B1. Rename the Model A output column to expected_auction_price.
--
--     Checks information_schema.columns to determine which of the three
--     historical column names is currently present, then renames accordingly.
--
--     ALTER TABLE … RENAME COLUMN:
--       • Is a pure catalog update (pg_attribute entry is relabelled)
--       • Never rewrites any row data
--       • Automatically updates any CHECK constraint EXPRESSIONS that
--         reference the column (e.g. "estimated_market_value IS NULL OR
--         estimated_market_value >= 0" becomes "expected_auction_price IS
--         NULL OR expected_auction_price >= 0") — but does NOT rename the
--         constraint itself; that happens in B2
--       • Automatically updates index definitions that reference the column
--       • Automatically updates RLS policy USING/WITH CHECK expressions
--         that reference the column (our policies reference prediction_type,
--         not this column, so nothing changes there)
--       • Takes ACCESS EXCLUSIVE lock for the duration of the catalog write,
--         which completes in milliseconds regardless of table row count
--
--     Three-state handling:
--       1. 'estimated_market_value' present (v2) → rename to expected_auction_price
--       2. 'predicted_price' present (v1 residual) → rename to expected_auction_price
--       3. 'expected_auction_price' present (v3) → no-op, RAISE NOTICE only
-- ------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'ai_predictions'
      AND column_name  = 'estimated_market_value'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME COLUMN estimated_market_value TO expected_auction_price;
    RAISE NOTICE 'B1: Renamed estimated_market_value → expected_auction_price (v2→v3)';

  ELSIF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'ai_predictions'
      AND column_name  = 'predicted_price'
  ) THEN
    -- v1-state instance: missed both prior rename migrations
    ALTER TABLE public.ai_predictions
      RENAME COLUMN predicted_price TO expected_auction_price;
    RAISE NOTICE 'B1: Renamed predicted_price → expected_auction_price (v1→v3)';

  ELSE
    -- expected_auction_price already exists — no-op
    RAISE NOTICE 'B1: Column already named expected_auction_price — no-op';
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- B2. Rename the column-level CHECK constraint to match the new column name.
--
--     When PostgreSQL auto-names a CHECK constraint defined inline in
--     CREATE TABLE, it uses the pattern <table>_<column>_check.
--
--     Migration 000006 v2 created the column as estimated_market_value,
--     producing constraint name ai_predictions_estimated_market_value_check.
--     After B1 renames the column, the constraint EXPRESSION is updated
--     automatically (see B1 notes), but the constraint NAME stays as
--     ai_predictions_estimated_market_value_check — a misleading mismatch.
--
--     ALTER TABLE … RENAME CONSTRAINT is a pure catalog update. It acquires
--     ACCESS EXCLUSIVE lock briefly. No row data is affected.
--
--     Two historical names are checked (v1 and v2). If neither exists, the
--     constraint is already correctly named (fresh 000006 generates
--     ai_predictions_expected_auction_price_check directly). No-op in that case.
-- ------------------------------------------------------------
DO $$
BEGIN
  -- v2 constraint name
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ai_predictions'::regclass
      AND contype  = 'c'
      AND conname  = 'ai_predictions_estimated_market_value_check'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME CONSTRAINT ai_predictions_estimated_market_value_check
      TO ai_predictions_expected_auction_price_check;
    RAISE NOTICE 'B2: Renamed column CHECK constraint → ai_predictions_expected_auction_price_check (v2 name)';

  -- v1 constraint name
  ELSIF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.ai_predictions'::regclass
      AND contype  = 'c'
      AND conname  = 'ai_predictions_predicted_price_check'
  ) THEN
    ALTER TABLE public.ai_predictions
      RENAME CONSTRAINT ai_predictions_predicted_price_check
      TO ai_predictions_expected_auction_price_check;
    RAISE NOTICE 'B2: Renamed column CHECK constraint → ai_predictions_expected_auction_price_check (v1 name)';

  ELSE
    RAISE NOTICE 'B2: Column CHECK constraint already correctly named — no-op';
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- B3. Replace the prediction_type CHECK constraint.
--
--     The existing constraint may allow 'market_value' (v2), 'price' (v1),
--     or already allow 'auction_price_estimate' (v3). We discover the
--     constraint by searching pg_constraint dynamically — this handles all
--     historical auto-generated names without hardcoding.
--
--     Logic:
--       • If constraint found AND already contains 'auction_price_estimate': no-op
--       • If constraint found with wrong values: DROP it, then ADD correct version
--       • If no constraint found: ADD correct version
--
--     DROP CONSTRAINT acquires ACCESS EXCLUSIVE lock. Within a transaction,
--     the old constraint is absent and the new one is present atomically from
--     the perspective of any concurrent session — there is no window where
--     neither exists.
--
--     CAUTION: If any row currently has prediction_type = 'auction_price_estimate'
--     (which would only exist if inserted via service_role into a v3 instance),
--     those rows satisfy the new constraint. But if a v2 instance somehow has
--     rows with prediction_type = 'market_value', those rows would VIOLATE the
--     new constraint and cause ADD CONSTRAINT to fail (PostgreSQL validates
--     existing rows). In that case: UPDATE the rows to 'auction_price_estimate'
--     before running this migration, then re-run.
--
--     Inner dollar-quoting uses $sql$ tag (distinct from outer $$ tag) to
--     avoid nesting conflicts. This is valid standard PostgreSQL syntax.
-- ------------------------------------------------------------
DO $$
DECLARE
  _con_name TEXT;
  _con_def  TEXT;
BEGIN
  SELECT conname, pg_get_constraintdef(oid)
    INTO _con_name, _con_def
  FROM   pg_constraint
  WHERE  conrelid = 'public.ai_predictions'::regclass
    AND  contype  = 'c'
    AND  conname  LIKE '%prediction_type%';

  IF _con_name IS NOT NULL AND _con_def LIKE '%auction_price_estimate%' THEN
    -- Already in final state — no-op
    RAISE NOTICE 'B3: prediction_type CHECK already correct ("%") — no-op', _con_name;

  ELSIF _con_name IS NOT NULL THEN
    -- Constraint exists with wrong values — drop and replace
    RAISE NOTICE 'B3: Dropping % (was: %)', _con_name, _con_def;
    EXECUTE format('ALTER TABLE public.ai_predictions DROP CONSTRAINT %I', _con_name);
    EXECUTE $sql$
      ALTER TABLE public.ai_predictions
        ADD CONSTRAINT ai_predictions_prediction_type_check
          CHECK (prediction_type IN ('auction_price_estimate', 'winning_bid', 'bid_probability'))
    $sql$;
    RAISE NOTICE 'B3: Added ai_predictions_prediction_type_check with correct values';

  ELSE
    -- No constraint at all — add it
    EXECUTE $sql$
      ALTER TABLE public.ai_predictions
        ADD CONSTRAINT ai_predictions_prediction_type_check
          CHECK (prediction_type IN ('auction_price_estimate', 'winning_bid', 'bid_probability'))
    $sql$;
    RAISE NOTICE 'B3: Added missing ai_predictions_prediction_type_check';
  END IF;
END;
$$;

-- ------------------------------------------------------------
-- B4. Replace client RLS policy with correctly named and filtered version.
--
--     Two historical policy names may exist on any given instance:
--       client_read_market_value_predictions  — v2: wrong name, USING filter
--                                               contains prediction_type = 'market_value'
--       client_read_auction_price_estimates   — v3: correct name, but may have been
--                                               created with old filter if 000007 was
--                                               applied before this migration's edits
--
--     Strategy: DROP both historical names unconditionally (DROP POLICY IF EXISTS
--     is a no-op if the policy does not exist), then CREATE the correct policy.
--
--     DROP + CREATE within one transaction is atomic from concurrent sessions:
--     they see the old policy OR the new policy, never neither. PostgreSQL
--     wraps each migration file in a transaction when applied via supabase db push.
--
--     Policy semantics:
--       - Clients (authenticated users) may SELECT only 'auction_price_estimate'
--         predictions (not 'winning_bid' or 'bid_probability' — those are admin data).
--       - Client must be an active user (account_status = 'active').
--       - The auction must be active or closed (not draft/cancelled).
--       - INSERT/UPDATE/DELETE are not covered by any policy → blocked for all
--         authenticated/anon roles. Only service_role (FastAPI inference layer)
--         can INSERT, bypassing RLS entirely.
--
--     super_admin policy is also refreshed for consistency. Its USING clause
--     does not reference prediction_type, so this is identical to 000007's version.
-- ------------------------------------------------------------

-- Drop both historical client policy names before recreating the correct one
DROP POLICY IF EXISTS client_read_market_value_predictions ON public.ai_predictions;
DROP POLICY IF EXISTS client_read_auction_price_estimates  ON public.ai_predictions;

CREATE POLICY client_read_auction_price_estimates
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    prediction_type = 'auction_price_estimate'
    AND EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid()
        AND u.account_status = 'active'
    )
    AND EXISTS (
      SELECT 1 FROM public.auctions a
      WHERE a.id = auction_id
        AND a.auction_status IN ('active', 'closed')
    )
  );

-- Refresh super_admin policy for consistency
DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;

CREATE POLICY super_admin_read_ai_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.super_admins
      WHERE id = auth.uid()
        AND account_status = 'active'
    )
  );

-- ------------------------------------------------------------
-- B5. Ensure all required indexes exist.
--
--     CREATE INDEX IF NOT EXISTS is a no-op if an index with the given name
--     already exists, regardless of column name changes applied in B1.
--
--     After RENAME COLUMN in B1, PostgreSQL automatically updates the index
--     definition stored in pg_index / pg_attribute to reference the new column
--     name. The index NAME does not change. Therefore:
--       - If the index was created by 000007 with the old column name:
--           its definition now references expected_auction_price (auto-updated),
--           CREATE INDEX IF NOT EXISTS is a no-op (name already exists)
--       - If the index was created by fresh 000006 with the correct name:
--           CREATE INDEX IF NOT EXISTS is a no-op
--       - If the index somehow does not exist:
--           CREATE INDEX creates it now
--
--     CONCURRENTLY is intentionally omitted: this migration runs inside a
--     transaction (supabase db push wraps each file in BEGIN/COMMIT), and
--     CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
--     The table is empty at migration time, so non-concurrent index creation
--     completes instantly and causes no blocking in practice.
-- ------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_type_created
  ON public.ai_predictions (auction_id, prediction_type, created_at DESC);

-- Audit trail: all predictions from a given model version
CREATE INDEX IF NOT EXISTS idx_ai_predictions_model_version
  ON public.ai_predictions (model_version, prediction_type, created_at DESC);

-- Analytical: all predictions of a given type
CREATE INDEX IF NOT EXISTS idx_ai_predictions_type
  ON public.ai_predictions (prediction_type, created_at DESC);

-- ------------------------------------------------------------
-- B6. Data integrity assertion.
--
--     Reads the pre-migration row count captured in B0 and compares it
--     to the current count. Every operation in B1–B5 is a catalog change;
--     none can modify, add, or delete rows. If this assertion fires,
--     something unexpected happened and the transaction is rolled back.
--
--     _mig_008_row_check is automatically dropped when the transaction
--     commits (ON COMMIT DROP from B0). No manual cleanup is needed.
-- ------------------------------------------------------------
DO $$
DECLARE
  _before BIGINT;
  _after  BIGINT;
BEGIN
  SELECT before_count INTO _before FROM _mig_008_row_check;
  SELECT COUNT(*) INTO _after FROM public.ai_predictions;

  IF _before IS DISTINCT FROM _after THEN
    RAISE EXCEPTION
      'DATA INTEGRITY VIOLATION in migration 000008: '
      'row count changed from % to % — rolling back',
      _before, _after;
  END IF;

  RAISE NOTICE 'B6: Integrity OK — % row(s) preserved', _after;
END;
$$;

-- ============================================================
-- C. AFTER Validation Queries
--    Run these manually AFTER the migration commits to confirm
--    the final state. None modify any data.
-- ============================================================

-- C1. Verify column names — expected_auction_price present, old names absent:
-- SELECT column_name
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- MUST contain:     expected_auction_price
-- MUST NOT contain: estimated_market_value, predicted_price

-- C2. Verify CHECK constraint names and definitions:
-- SELECT conname, pg_get_constraintdef(oid) AS definition
-- FROM pg_constraint
-- WHERE conrelid = 'public.ai_predictions'::regclass AND contype = 'c'
-- ORDER BY conname;
-- ai_predictions_expected_auction_price_check:
--   definition → "expected_auction_price IS NULL OR expected_auction_price >= 0"
-- ai_predictions_prediction_type_check:
--   definition → "prediction_type = ANY (ARRAY['auction_price_estimate', 'winning_bid', 'bid_probability'])"
--   MUST NOT contain: 'market_value', 'price', 'interest_score'

-- C3. Verify RLS policies:
-- SELECT policyname, cmd, qual AS using_expression
-- FROM pg_policies
-- WHERE tablename = 'ai_predictions'
-- ORDER BY policyname;
-- MUST have:     client_read_auction_price_estimates, super_admin_read_ai_predictions
-- MUST NOT have: client_read_market_value_predictions
-- client_read_auction_price_estimates.qual must contain:
--   prediction_type = 'auction_price_estimate'

-- C4. Verify four indexes exist (three explicit + primary key):
-- SELECT indexname FROM pg_indexes
-- WHERE tablename = 'ai_predictions'
-- ORDER BY indexname;
-- Expected: ai_predictions_pkey
--           idx_ai_predictions_auction_type_created
--           idx_ai_predictions_model_version
--           idx_ai_predictions_type

-- C5. Smoke test — prediction_type CHECK rejects all superseded values
--     (execute via service_role or psql to bypass RLS):
-- INSERT INTO public.ai_predictions
--   (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'market_value', '{}');
-- Expected: ERROR — violates check constraint "ai_predictions_prediction_type_check"
--
-- INSERT INTO public.ai_predictions
--   (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'price', '{}');
-- Expected: ERROR — violates check constraint "ai_predictions_prediction_type_check"
--
-- INSERT INTO public.ai_predictions
--   (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v-test', 'interest_score', '{}');
-- Expected: ERROR — violates check constraint "ai_predictions_prediction_type_check"

-- C6. Smoke test — prediction_type CHECK accepts the correct value
--     (execute via service_role; requires a valid auction UUID):
-- INSERT INTO public.ai_predictions
--   (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES ('<valid_auction_uuid>', 'v1.0.4-synthetic', 'auction_price_estimate', '{}');
-- Expected: 1 row inserted

-- C7. Confirm row count unchanged (must equal A5):
-- SELECT COUNT(*) FROM public.ai_predictions;

-- ============================================================
-- D. Rollback SQL
--    Reverts to the v2 intermediate state (estimated_market_value /
--    'market_value' / client_read_market_value_predictions).
--
--    CAUTION: If any rows have prediction_type = 'auction_price_estimate',
--    they will VIOLATE the rolled-back CHECK constraint (which only allows
--    'market_value', 'winning_bid', 'bid_probability'). You must UPDATE
--    those rows BEFORE running the rollback, or the ADD CONSTRAINT step will
--    fail and roll back.
--
--    Only apply this rollback as a last resort. Re-apply migration 000008
--    once the root cause is resolved.
-- ============================================================

-- -- D1. Restore RLS policies to v2 names and filters
-- DROP POLICY IF EXISTS client_read_auction_price_estimates ON public.ai_predictions;
-- DROP POLICY IF EXISTS super_admin_read_ai_predictions     ON public.ai_predictions;
--
-- CREATE POLICY super_admin_read_ai_predictions
--   ON public.ai_predictions FOR SELECT TO authenticated
--   USING (
--     EXISTS (
--       SELECT 1 FROM public.super_admins
--       WHERE id = auth.uid() AND account_status = 'active'
--     )
--   );
--
-- CREATE POLICY client_read_market_value_predictions
--   ON public.ai_predictions FOR SELECT TO authenticated
--   USING (
--     prediction_type = 'market_value'
--     AND EXISTS (
--       SELECT 1 FROM public.users u
--       WHERE u.id = auth.uid() AND u.account_status = 'active'
--     )
--     AND EXISTS (
--       SELECT 1 FROM public.auctions a
--       WHERE a.id = auction_id AND a.auction_status IN ('active', 'closed')
--     )
--   );
--
-- -- D2. Restore prediction_type CHECK to v2 allowed values
-- DO $$
-- DECLARE _con TEXT;
-- BEGIN
--   SELECT conname INTO _con FROM pg_constraint
--   WHERE conrelid = 'public.ai_predictions'::regclass
--     AND contype = 'c' AND conname LIKE '%prediction_type%';
--   IF _con IS NOT NULL THEN
--     EXECUTE format('ALTER TABLE public.ai_predictions DROP CONSTRAINT %I', _con);
--   END IF;
-- END;
-- $$;
-- ALTER TABLE public.ai_predictions
--   ADD CONSTRAINT ai_predictions_prediction_type_check
--     CHECK (prediction_type IN ('market_value', 'winning_bid', 'bid_probability'));
--
-- -- D3. Rename column-level CHECK constraint back to v2 name (if B2 renamed it)
-- DO $$
-- BEGIN
--   IF EXISTS (
--     SELECT 1 FROM pg_constraint
--     WHERE conrelid = 'public.ai_predictions'::regclass
--       AND contype = 'c'
--       AND conname = 'ai_predictions_expected_auction_price_check'
--   ) THEN
--     ALTER TABLE public.ai_predictions
--       RENAME CONSTRAINT ai_predictions_expected_auction_price_check
--       TO ai_predictions_estimated_market_value_check;
--   END IF;
-- END;
-- $$;
--
-- -- D4. Rename column back to estimated_market_value (idempotent guard)
-- DO $$
-- BEGIN
--   IF EXISTS (
--     SELECT 1 FROM information_schema.columns
--     WHERE table_schema = 'public'
--       AND table_name   = 'ai_predictions'
--       AND column_name  = 'expected_auction_price'
--   ) THEN
--     ALTER TABLE public.ai_predictions
--       RENAME COLUMN expected_auction_price TO estimated_market_value;
--   END IF;
-- END;
-- $$;
