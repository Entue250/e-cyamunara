-- supabase/migrations/20260610000005_update_accept_bid_rpc.sql
--
-- Phase 1 AI Data: Updated accept_bid() RPC
--
-- Extends accept_bid() to populate ML training fields inside the existing
-- SELECT ... FOR UPDATE transaction. No structural change to the function
-- signature (same 6 parameters) or return type (JSONB — new keys are additive).
--
-- New ML logic (all server-side, never from client):
--   bid_sequence       — 1-based position within auction; kept unchanged on UPDATE
--   bid_increment      — p_bid_amount - current_highest_bid at lock time
--   seconds_before_end — GREATEST(0, EPOCH(end_date - now()))
--   is_bid_update      — true on UPDATE path, false on INSERT path
--
--   auctions.unique_bidder_count — incremented on INSERT (first bid) only
--   auctions.time_of_first_bid   — set once via COALESCE (write-once)
--   auctions.time_of_last_bid    — updated on every bid (INSERT and UPDATE)
--
-- Prerequisites: migrations 000002, 000003, 000004 must be applied first.
-- IDEMPOTENT: CREATE OR REPLACE FUNCTION is always safe to re-run.

-- ============================================================
-- BEFORE Validation Queries (run manually before applying)
-- ============================================================

-- V0-1: Confirm current accept_bid() exists (will be replaced):
-- SELECT proname, pronargs FROM pg_proc WHERE proname = 'accept_bid';
-- Expected: 1 row with 6 arguments

-- V0-2: Confirm migration 000004 columns exist on auctions:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name IN ('unique_bidder_count','time_of_first_bid','time_of_last_bid');
-- Expected: 3 rows

-- V0-3: Confirm migration 000002 columns exist on bids:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'bids'
--   AND column_name IN ('bid_sequence','bid_increment','seconds_before_end','is_bid_update');
-- Expected: 4 rows

-- ============================================================
-- Migration
-- ============================================================

CREATE OR REPLACE FUNCTION public.accept_bid(
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
  -- Phase 1 ML behavioral feature variables (all server-side)
  v_bid_sequence     INTEGER;
  v_bid_increment    NUMERIC;
  v_secs_before_end  INTEGER;
BEGIN
  -- ── Acquire exclusive row lock on the auction ──────────────────────────────
  -- NOWAIT intentionally NOT used: concurrent bids queue behind the lock,
  -- ensuring each bid reads the committed state of all prior bids.
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
  IF p_bid_amount < v_auction.starting_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'error',   format('Bid must be at least %s RWF', v_auction.starting_price::text),
      'code',    'BELOW_START'
    );
  END IF;

  -- Save current winner for notification context
  v_prev_winner := v_auction.current_winner_uid;

  -- ── Compute ML features from locked auction state ─────────────────────────
  -- Always server-side — never from client. Computed after lock so they
  -- reflect the true state at the moment this bid is processed.
  v_bid_increment   := p_bid_amount - v_auction.current_highest_bid;
  v_secs_before_end := GREATEST(
    0,
    EXTRACT(EPOCH FROM (v_auction.end_date - NOW()))::INTEGER
  );

  -- ── Check for existing bid from this bidder (lock it if found) ─────────────
  SELECT id INTO v_existing_bid_id
  FROM public.bids
  WHERE auction_id = p_auction_id
    AND bidder_uid = p_bidder_uid
  FOR UPDATE;

  IF FOUND THEN
    -- ── UPDATE path ───────────────────────────────────────────────────────────
    -- Bidder is raising or lowering their existing bid.
    -- bid_sequence kept at its original position (a bid update is not a new event).
    -- is_bid_update = TRUE.
    v_is_update := TRUE;

    SELECT bid_sequence INTO v_bid_sequence
    FROM public.bids
    WHERE id = v_existing_bid_id;

    UPDATE public.bids
    SET bid_amount         = p_bid_amount,
        bidder_name        = p_bidder_name,
        bidder_phone       = p_bidder_phone,
        bidder_district    = p_bidder_district,
        bid_status         = 'outbid',      -- corrected by bulk-update below
        updated_at         = NOW(),
        bid_increment      = v_bid_increment,
        seconds_before_end = v_secs_before_end,
        is_bid_update      = TRUE
        -- bid_sequence intentionally NOT updated (immutable once assigned)
    WHERE id = v_existing_bid_id;

  ELSE
    -- ── INSERT path ───────────────────────────────────────────────────────────
    -- First bid from this bidder on this auction.
    -- bid_sequence = MAX existing sequence + 1 (or 1 if no bids yet).
    -- is_bid_update = FALSE.
    v_is_update := FALSE;

    SELECT COALESCE(MAX(bid_sequence), 0) + 1 INTO v_bid_sequence
    FROM public.bids
    WHERE auction_id = p_auction_id;

    INSERT INTO public.bids (
      auction_id, bidder_uid, bidder_name, bidder_phone,
      bidder_district, bid_amount, bid_status,
      bid_sequence, bid_increment, seconds_before_end, is_bid_update
    )
    VALUES (
      p_auction_id, p_bidder_uid, p_bidder_name, p_bidder_phone,
      p_bidder_district, p_bid_amount, 'outbid',
      v_bid_sequence, v_bid_increment, v_secs_before_end, FALSE
    );
  END IF;

  -- ── Recalculate winner from MAX across all bids ────────────────────────────
  -- Done after the upsert so bid reductions are handled correctly:
  -- if a bidder lowers below another bidder, the other becomes winner.
  -- Tie-break by most recent updated_at.
  SELECT bidder_uid, bidder_name, bid_amount
  INTO   v_new_winner_uid, v_new_winner_name, v_new_highest
  FROM   public.bids
  WHERE  auction_id = p_auction_id
  ORDER BY bid_amount DESC, updated_at DESC
  LIMIT 1;

  -- ── Bulk-update bid statuses for this auction ──────────────────────────────
  UPDATE public.bids
  SET bid_status = CASE
    WHEN bidder_uid = v_new_winner_uid THEN 'winning'
    ELSE 'outbid'
  END
  WHERE auction_id = p_auction_id;

  -- ── Update the auction record ──────────────────────────────────────────────
  IF v_is_update THEN
    -- Bid update: counters unchanged; only update engagement timestamp
    UPDATE public.auctions
    SET current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        time_of_last_bid    = NOW(),
        updated_at          = NOW()
    WHERE id = p_auction_id;

  ELSE
    -- First bid from this bidder: increment all counters
    UPDATE public.auctions
    SET total_bids          = total_bids + 1,
        current_highest_bid = v_new_highest,
        current_winner_uid  = v_new_winner_uid,
        current_winner_name = v_new_winner_name,
        unique_bidder_count = unique_bidder_count + 1,
        time_of_first_bid   = COALESCE(time_of_first_bid, NOW()),  -- write-once
        time_of_last_bid    = NOW(),
        updated_at          = NOW()
    WHERE id = p_auction_id;

    -- Increment bidder's lifetime total (first bid on this auction only)
    UPDATE public.users
    SET total_bids_placed = total_bids_placed + 1
    WHERE id = p_bidder_uid;
  END IF;

  -- ── Return result payload ──────────────────────────────────────────────────
  -- Existing fields preserved; Phase 1 ML fields appended (additive).
  RETURN jsonb_build_object(
    'success',            true,
    'new_highest_bid',    v_new_highest,
    'is_winning',         (v_new_winner_uid = p_bidder_uid),
    'is_update',          v_is_update,
    'prev_winner_uid',    v_prev_winner,
    'new_winner_uid',     v_new_winner_uid,
    'item_name',          v_auction.item_name,
    'admin_uid',          v_auction.posted_by_admin_uid,
    -- Phase 1 ML behavioral features
    'bid_sequence',       v_bid_sequence,
    'bid_increment',      v_bid_increment,
    'seconds_before_end', v_secs_before_end
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

-- ── Access control: service_role only (unchanged from previous version) ───────
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO service_role;

-- ============================================================
-- AFTER Validation Queries (run manually after applying)
-- ============================================================

-- V1: Function exists and is SECURITY DEFINER:
-- SELECT routine_name, security_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public' AND routine_name = 'accept_bid';
-- Expected: 1 row, security_type = 'DEFINER'

-- V2: Only service_role has EXECUTE (authenticated and anon must NOT appear):
-- SELECT grantee, privilege_type
-- FROM information_schema.routine_privileges
-- WHERE routine_schema = 'public' AND routine_name = 'accept_bid';
-- Expected: 1 row — grantee = 'service_role', privilege_type = 'EXECUTE'

-- V3: Place a test bid and confirm new ML fields in response:
-- SELECT accept_bid(
--   'AUCTION_UUID'::uuid, 'BIDDER_UUID'::uuid,
--   9000000, 'Test Bidder', '0781000001', 'Gasabo'
-- );
-- Expected JSON includes: bid_sequence (integer >= 1), bid_increment (numeric),
-- seconds_before_end (integer >= 0)

-- V4: After V3, confirm bid row populated:
-- SELECT bid_sequence, bid_increment, seconds_before_end, is_bid_update
-- FROM public.bids WHERE auction_id = 'AUCTION_UUID' ORDER BY bid_sequence;
-- Expected: bid_sequence non-null, bid_increment = bid_amount (first bid),
--           seconds_before_end >= 0, is_bid_update = false

-- V5: After second bid from same bidder, bid_sequence unchanged:
-- (Place a second bid from same bidder with higher amount, re-run V4)
-- Expected: bid_sequence same as first bid, is_bid_update = true

-- V6: unique_bidder_count and time_of_first_bid updated on first bid:
-- SELECT unique_bidder_count, time_of_first_bid, time_of_last_bid
-- FROM public.auctions WHERE id = 'AUCTION_UUID';
-- Expected: unique_bidder_count = N, time_of_first_bid IS NOT NULL, time_of_last_bid IS NOT NULL

-- ============================================================
-- ROLLBACK
-- ============================================================

-- To roll back: re-apply 20260512000000_bidding_fix.sql in Supabase SQL Editor.
-- That file uses CREATE OR REPLACE and restores the previous accept_bid() body.
-- Note: this does NOT remove the new columns from bids/auctions tables.
-- Those are rolled back via migration 000002/000004 rollback scripts separately.
