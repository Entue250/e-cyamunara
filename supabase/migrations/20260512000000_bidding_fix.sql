-- =============================================================================
-- E-CYAMUNARA — Bidding Fix
-- File: supabase/migrations/20260512000000_bidding_fix.sql
--
-- Changes:
--   1. Add updated_at column to bids table
--   2. Deduplicate existing (auction_id, bidder_uid) pairs (keep highest bid)
--   3. Drop old partial unique index; add full UNIQUE(auction_id, bidder_uid)
--   4. Rewrite accept_bid() RPC:
--        - REMOVES BID_TOO_LOW guard (bid > current_highest_bid)
--        - ADDS upsert: UPDATE if user has existing bid, INSERT otherwise
--        - ADDS winner recalculation from MAX(bid_amount) after every upsert
--        - ADDS is_winning / is_update flags in return payload
--        - KEEPS BELOW_START, NOT_ACTIVE, ENDED, NOT_FOUND guards
--        - KEEPS total_bids / total_bids_placed incremented on first bid only
--
-- Safe to re-run: idempotent DDL (ADD COLUMN IF NOT EXISTS, DROP IF EXISTS,
-- DROP CONSTRAINT IF EXISTS) + CREATE OR REPLACE function.
-- =============================================================================

-- =============================================================================
-- 1. Add updated_at column
-- =============================================================================
ALTER TABLE public.bids
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- =============================================================================
-- 2. Deduplicate existing rows
--    Keep the row with the highest bid_amount per (auction_id, bidder_uid).
--    On a tie, keep the most recently created row.
--    This MUST run before the UNIQUE constraint is added.
-- =============================================================================
DELETE FROM public.bids
WHERE id IN (
  SELECT id FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY auction_id, bidder_uid
        ORDER BY bid_amount DESC, created_at DESC
      ) AS rn
    FROM public.bids
  ) ranked
  WHERE rn > 1
);

-- =============================================================================
-- 3. Replace old partial unique index with a full UNIQUE constraint
-- =============================================================================
DROP INDEX IF EXISTS public.idx_bids_one_winner_per_auction;

ALTER TABLE public.bids
  DROP CONSTRAINT IF EXISTS bids_auction_id_bidder_uid_key;
ALTER TABLE public.bids
  ADD CONSTRAINT bids_auction_id_bidder_uid_key
  UNIQUE (auction_id, bidder_uid);

-- =============================================================================
-- 4. Rewrite accept_bid()
--
-- Concurrency model:
--   SELECT ... FOR UPDATE on both the auction row and the existing bid row
--   (when one exists). All mutations commit in a single transaction — no
--   intermediate state is visible to concurrent requests.
--
-- Validation change:
--   REMOVED: p_bid_amount <= current_highest_bid  (BID_TOO_LOW)
--   Any bid >= starting_price is now valid regardless of other bids.
--   The highest bid at auction close still determines the winner.
--
-- Upsert logic:
--   UPDATE if the bidder already has a row for this auction.
--   INSERT if this is the bidder's first bid.
--   total_bids / total_bids_placed incremented only on INSERT.
--
-- Winner recalculation:
--   After every upsert, SELECT MAX(bid_amount) across all bids to find the
--   new winner. This correctly handles bid reductions (e.g. 10M → 6M).
-- =============================================================================

CREATE OR REPLACE FUNCTION accept_bid(
  p_auction_id      UUID,
  p_bidder_uid      UUID,
  p_bid_amount      NUMERIC,
  p_bidder_name     TEXT,
  p_bidder_phone    TEXT,
  p_bidder_district TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_auction          RECORD;
  v_existing_bid_id  UUID;
  v_is_update        BOOLEAN := FALSE;
  v_new_winner_uid   UUID;
  v_new_winner_name  TEXT;
  v_new_highest      NUMERIC;
  v_prev_winner      UUID;
BEGIN
  -- ── Acquire exclusive row lock on the auction ──────────────────────────────
  -- NOWAIT intentionally NOT used: concurrent bids queue here, ensuring the
  -- second bid reads the committed state of the first.
  SELECT * INTO v_auction
  FROM public.auctions
  WHERE id = p_auction_id
  FOR UPDATE;

  -- ── Guard: auction must exist ──────────────────────────────────────────────
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction not found',
      'code',    'NOT_FOUND'
    );
  END IF;

  -- ── Guard: auction must be active ──────────────────────────────────────────
  IF v_auction.auction_status <> 'active' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction is not active',
      'code',    'NOT_ACTIVE'
    );
  END IF;

  -- ── Guard: auction must not have ended ─────────────────────────────────────
  IF v_auction.end_date <= NOW() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction has ended',
      'code',    'ENDED'
    );
  END IF;

  -- ── Guard: bid must be at least the starting price ─────────────────────────
  -- BID_TOO_LOW (bid > current_highest_bid) intentionally removed.
  -- Any amount >= starting_price is a valid bid.
  IF p_bid_amount < v_auction.starting_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   format(
                   'Bid must be at least %s RWF',
                   v_auction.starting_price::text
                 ),
      'code',    'BELOW_START'
    );
  END IF;

  -- Save current winner for notification context
  v_prev_winner := v_auction.current_winner_uid;

  -- ── Check for an existing bid from this bidder; lock it if found ───────────
  SELECT id INTO v_existing_bid_id
  FROM public.bids
  WHERE auction_id = p_auction_id
    AND bidder_uid = p_bidder_uid
  FOR UPDATE;

  IF FOUND THEN
    -- ── UPDATE existing bid in place ─────────────────────────────────────────
    v_is_update := TRUE;
    UPDATE public.bids
    SET bid_amount      = p_bid_amount,
        bidder_name     = p_bidder_name,
        bidder_phone    = p_bidder_phone,
        bidder_district = p_bidder_district,
        bid_status      = 'outbid',   -- corrected in bulk-update below
        updated_at      = NOW()
    WHERE id = v_existing_bid_id;

  ELSE
    -- ── INSERT first bid from this bidder ────────────────────────────────────
    v_is_update := FALSE;
    INSERT INTO public.bids (
      auction_id, bidder_uid, bidder_name, bidder_phone,
      bidder_district, bid_amount, bid_status
    )
    VALUES (
      p_auction_id, p_bidder_uid, p_bidder_name, p_bidder_phone,
      p_bidder_district, p_bid_amount, 'outbid'
    );
  END IF;

  -- ── Recalculate winner from MAX across all bids (after upsert) ─────────────
  -- This handles bid reductions: if user lowers their bid below another
  -- bidder's amount, the other bidder becomes the new winner.
  SELECT bidder_uid, bidder_name, bid_amount
  INTO   v_new_winner_uid, v_new_winner_name, v_new_highest
  FROM   public.bids
  WHERE  auction_id = p_auction_id
  ORDER BY bid_amount DESC, updated_at DESC
  LIMIT 1;

  -- ── Bulk-update all bid statuses for this auction ──────────────────────────
  UPDATE public.bids
  SET bid_status = CASE
    WHEN bidder_uid = v_new_winner_uid THEN 'winning'
    ELSE 'outbid'
  END
  WHERE auction_id = p_auction_id;

  -- ── Update the auction record ───────────────────────────────────────────────
  IF v_is_update THEN
    -- No counter changes on update
    UPDATE public.auctions
    SET current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        updated_at          = NOW()
    WHERE id = p_auction_id;
  ELSE
    -- Increment total_bids atomically on first bid only
    UPDATE public.auctions
    SET total_bids          = total_bids + 1,
        current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        updated_at          = NOW()
    WHERE id = p_auction_id;

    -- Increment bidder's lifetime stats (first bid only)
    UPDATE public.users
    SET total_bids_placed = total_bids_placed + 1
    WHERE id = p_bidder_uid;
  END IF;

  -- ── Return result payload ──────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'success',         true,
    'new_highest_bid', v_new_highest,
    'is_winning',      (v_new_winner_uid = p_bidder_uid),
    'is_update',       v_is_update,
    'prev_winner_uid', v_prev_winner,
    'new_winner_uid',  v_new_winner_uid,   -- needed for bid-reduction winner-change notifications
    'item_name',       v_auction.item_name,
    'admin_uid',       v_auction.posted_by_admin_uid
  );

EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'accept_bid error: % %', SQLERRM, SQLSTATE;
    RETURN jsonb_build_object(
      'success', false,
      'error',   'An unexpected database error occurred',
      'code',    'DB_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

-- =============================================================================
-- Access control — service_role only (same policy as before)
-- =============================================================================
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO service_role;

-- =============================================================================
-- Verification queries (run manually in Supabase SQL Editor after applying)
-- =============================================================================
-- 1. Confirm updated_at column exists:
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'bids' AND column_name = 'updated_at';
--
-- 2. Confirm unique constraint:
-- SELECT constraint_name, constraint_type FROM information_schema.table_constraints
--   WHERE table_name = 'bids' AND constraint_type = 'UNIQUE';
--
-- 3. Confirm function security:
-- SELECT grantee, privilege_type FROM information_schema.routine_privileges
--   WHERE routine_name = 'accept_bid' ORDER BY grantee;
-- Expected: only service_role (and postgres) with EXECUTE
--
-- 4. Smoke-test (replace UUIDs with real dev values):
-- SELECT accept_bid(
--   'YOUR_AUCTION_UUID'::uuid, 'BIDDER_A_UUID'::uuid, 9000000, 'Bidder A', '0781000001', 'Gasabo'
-- );
-- SELECT accept_bid(
--   'YOUR_AUCTION_UUID'::uuid, 'BIDDER_B_UUID'::uuid, 7000000, 'Bidder B', '0781000002', 'Kicukiro'
-- );
-- Both should return success:true. A should be winning, B should be outbid.
-- =============================================================================

-- =============================================================================
-- ROLLBACK
-- ALTER TABLE public.bids DROP CONSTRAINT IF EXISTS bids_auction_id_bidder_uid_key;
-- ALTER TABLE public.bids DROP COLUMN IF EXISTS updated_at;
-- DROP FUNCTION IF EXISTS accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT);
-- (Then re-apply the previous migration to restore the old function.)
-- =============================================================================
