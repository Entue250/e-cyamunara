-- =============================================================================
-- E-CYAMUNARA — accept_bid() RPC
-- File: supabase/migrations/20260423000001_accept_bid_rpc.sql
--
-- Run BEFORE deploying the updated place-bid Edge Function.
-- If the Edge Function is deployed first, it will call an RPC that doesn't
-- exist yet and every bid will fail with a DB error.
--
-- Deployment order:
--   1. Run this SQL in Supabase Dashboard → SQL Editor
--   2. Deploy: supabase functions deploy place-bid
--   3. Smoke-test bid placement (see verification block at end of file)
--
-- Safe to re-run: CREATE OR REPLACE + idempotent GRANT/REVOKE.
-- =============================================================================

-- =============================================================================
-- THE accept_bid() FUNCTION
--
-- Concurrency model:
--   SELECT ... FOR UPDATE locks the auction row before any reads that drive
--   mutation decisions. Because the lock is held for the full transaction,
--   two concurrent bids are serialized: the second one waits at the lock,
--   then reads the value the first one committed, and is rejected cleanly
--   if its bid amount is no longer the highest.
--
-- Atomicity model:
--   Every mutation (INSERT bid, UPDATE auction, UPDATE previous winner,
--   UPDATE user stats) happens in one transaction. Either all succeed and
--   commit, or all roll back. There is no intermediate visible state.
--
-- Counter integrity:
--   total_bids and total_bids_placed are incremented server-side
--   (total_bids + 1) — no read-modify-write arithmetic in application code.
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
-- Prevents search_path injection: all unqualified names resolve to public
SET search_path = public
AS $$
DECLARE
  v_auction     RECORD;
  v_prev_winner UUID;
BEGIN
  -- ── Acquire exclusive row lock on the auction ──────────────────────────────
  -- NOWAIT is intentionally NOT used: we want concurrent bids to queue, not
  -- fail immediately. PostgreSQL serializes them at the lock; the second bid
  -- will re-read the committed state from the first bid and be validated
  -- against the updated current_highest_bid.
  SELECT * INTO v_auction
  FROM public.auctions
  WHERE id = p_auction_id
  FOR UPDATE;

  -- ── Re-validate under lock (all checks are now race-free) ─────────────────
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction not found',
      'code',    'NOT_FOUND'
    );
  END IF;

  IF v_auction.auction_status <> 'active' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction is not active',
      'code',    'NOT_ACTIVE'
    );
  END IF;

  -- NOW() is evaluated inside the transaction — consistent with the lock
  IF v_auction.end_date <= NOW() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Auction has ended',
      'code',    'ENDED'
    );
  END IF;

  -- This is the authoritative TOCTOU guard. bid_amount must beat the value
  -- that is current at lock acquisition time, not the value the caller read
  -- before the function was invoked.
  IF p_bid_amount <= v_auction.current_highest_bid THEN
    RETURN jsonb_build_object(
      'success',         false,
      'error',           format(
                           'Bid must be higher than current highest bid of %s',
                           v_auction.current_highest_bid::text
                         ),
      'code',            'BID_TOO_LOW',
      'current_highest', v_auction.current_highest_bid
    );
  END IF;

  IF p_bid_amount < v_auction.starting_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   'Bid must be at least the starting price',
      'code',    'BELOW_START'
    );
  END IF;

  v_prev_winner := v_auction.current_winner_uid;

  -- ── Commit mutations (all within this transaction) ─────────────────────────

  -- 1. Record the new winning bid
  INSERT INTO public.bids (
    auction_id,
    bidder_uid,
    bidder_name,
    bidder_phone,
    bidder_district,
    bid_amount,
    bid_status
  )
  VALUES (
    p_auction_id,
    p_bidder_uid,
    p_bidder_name,
    p_bidder_phone,
    p_bidder_district,
    p_bid_amount,
    'winning'
  );

  -- 2. Update auction state with server-side counter increment (atomic)
  UPDATE public.auctions
  SET
    current_highest_bid = p_bid_amount,
    current_winner_uid  = p_bidder_uid,
    current_winner_name = p_bidder_name,
    total_bids          = total_bids + 1,   -- atomic: no read-modify-write
    updated_at          = NOW()
  WHERE id = p_auction_id;

  -- 3. Downgrade the previous winner's bid to outbid
  IF v_prev_winner IS NOT NULL AND v_prev_winner <> p_bidder_uid THEN
    UPDATE public.bids
    SET bid_status = 'outbid'
    WHERE auction_id  = p_auction_id
      AND bidder_uid  = v_prev_winner
      AND bid_status  = 'winning';
  END IF;

  -- 4. Increment bidder's lifetime stats (atomic)
  UPDATE public.users
  SET total_bids_placed = total_bids_placed + 1   -- atomic: no read-modify-write
  WHERE id = p_bidder_uid;

  -- ── Return context the Edge Function needs for notification delivery ────────
  RETURN jsonb_build_object(
    'success',          true,
    'new_highest_bid',  p_bid_amount,
    'prev_winner_uid',  v_prev_winner,
    'item_name',        v_auction.item_name,
    'admin_uid',        v_auction.posted_by_admin_uid
  );

EXCEPTION
  WHEN unique_violation THEN
    -- The partial unique index idx_bids_one_winner_per_auction fired.
    -- This means this bidder already has a winning bid for this auction
    -- (possible in a very tight race where two requests from the same user
    -- both passed the FOR UPDATE lock before the first INSERT committed).
    -- The subtransaction is rolled back; no partial state is visible.
    RETURN jsonb_build_object(
      'success', false,
      'error',   'You already have the winning bid on this auction',
      'code',    'DUPLICATE_WIN'
    );

  WHEN OTHERS THEN
    -- Unexpected DB error. Subtransaction rolled back. Log via RAISE NOTICE
    -- so it appears in Supabase DB logs for diagnosis.
    RAISE NOTICE 'accept_bid unexpected error: % %', SQLERRM, SQLSTATE;
    RETURN jsonb_build_object(
      'success', false,
      'error',   'An unexpected database error occurred',
      'code',    'DB_ERROR',
      'detail',  SQLERRM
    );
END;
$$;

-- =============================================================================
-- ACCESS CONTROL
--
-- The function uses SECURITY DEFINER but is only intended to be called from
-- the Edge Function using the service role. Revoke all other access so that
-- an authenticated user cannot call it directly via the Supabase REST API
-- and bypass the Edge Function's auth + suspension checks.
-- =============================================================================

-- Revoke default public execute grant (PostgreSQL grants to PUBLIC by default)
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;

-- Explicitly revoke from both Supabase client roles
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM authenticated;

-- Grant only to service_role (used by Edge Functions)
GRANT EXECUTE ON FUNCTION accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO service_role;


-- =============================================================================
-- VERIFICATION — run after creating the function
-- =============================================================================

-- 1. Confirm function exists and has the correct signature
SELECT
  routine_name,
  routine_type,
  security_type,
  routine_definition IS NOT NULL AS has_body
FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name = 'accept_bid';
-- Expected: 1 row, routine_type = 'FUNCTION', security_type = 'DEFINER'

-- 2. Confirm access control (should show no privileges for anon/authenticated)
SELECT grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'accept_bid'
ORDER BY grantee;
-- Expected: only 'service_role' (and possibly 'postgres') with EXECUTE

-- 3. Integration test (run with a known auction_id and bidder_uid from dev data):
-- SELECT accept_bid(
--   'YOUR_AUCTION_UUID'::uuid,
--   'YOUR_BIDDER_UUID'::uuid,
--   999999.00,
--   'Test Bidder',
--   '0781234567',
--   'Gasabo'
-- );


-- =============================================================================
-- ROLLBACK
-- DROP FUNCTION IF EXISTS accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT);
-- =============================================================================
