-- supabase/migrations/20260610000004_auction_engagement_fields.sql
--
-- Phase 1 AI Data: Auction Engagement Fields
--
-- Adds three engagement tracking columns to the auctions table:
--   unique_bidder_count — distinct bidders who placed at least one bid
--   time_of_first_bid   — when the first bid arrived (immutable after set)
--   time_of_last_bid    — when the most recent bid arrived (updated on every bid)
--
-- views_count was added in migration 000003 (required by record_auction_view RPC).
--
-- Safety: ADD COLUMN IF NOT EXISTS; backfill guarded by WHERE IS NULL or EXISTS.
-- Prerequisites: migrations 000002 and 000003 must be applied first.

-- ============================================================
-- BEFORE Validation Queries (run manually before applying)
-- ============================================================

-- V0-1: Confirm the three columns do NOT yet exist on auctions:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name IN ('unique_bidder_count','time_of_first_bid','time_of_last_bid');
-- Expected: 0 rows

-- V0-2: Record baseline auction count with bids for post-migration comparison:
-- SELECT COUNT(DISTINCT a.id) AS auctions_with_bids
-- FROM public.auctions a
-- WHERE EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id);
-- Save this number.

-- ============================================================
-- Part A: Add columns
-- ============================================================

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS unique_bidder_count INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS time_of_first_bid   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS time_of_last_bid    TIMESTAMPTZ;

-- ============================================================
-- Part B: Backfill unique_bidder_count
-- ============================================================
-- Counts distinct bidder_uid values per auction.
-- WHERE clause: only updates auctions that have at least one bid.
-- The CASE ensures auctions with no bids keep the default of 0.

UPDATE public.auctions a
SET unique_bidder_count = (
  SELECT COUNT(DISTINCT bidder_uid)
  FROM public.bids b
  WHERE b.auction_id = a.id
)
WHERE EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id)
  AND unique_bidder_count = 0;

-- ============================================================
-- Part C: Backfill time_of_first_bid and time_of_last_bid
-- ============================================================
-- time_of_first_bid = MIN(created_at) across all bids for the auction.
-- time_of_last_bid  = MAX(COALESCE(updated_at, created_at)) — captures
--   the most recent bid event, whether it was a new bid or an update.
-- Both remain NULL for auctions with no bids.

UPDATE public.auctions a
SET
  time_of_first_bid = (
    SELECT MIN(created_at)
    FROM public.bids
    WHERE auction_id = a.id
  ),
  time_of_last_bid = (
    SELECT MAX(COALESCE(updated_at, created_at))
    FROM public.bids
    WHERE auction_id = a.id
  )
WHERE EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id)
  AND time_of_first_bid IS NULL;

-- ============================================================
-- Part D: Indexes
-- ============================================================

-- Supports "most contested auctions" analytics queries
CREATE INDEX IF NOT EXISTS idx_auctions_unique_bidder_count
  ON public.auctions (unique_bidder_count DESC)
  WHERE is_deleted = false;

-- Supports "time-to-first-interest" ML feature queries
CREATE INDEX IF NOT EXISTS idx_auctions_time_of_first_bid
  ON public.auctions (time_of_first_bid)
  WHERE time_of_first_bid IS NOT NULL AND is_deleted = false;

-- ============================================================
-- AFTER Validation Queries (run manually after applying)
-- ============================================================

-- V1: Three columns exist with correct types and defaults:
-- SELECT column_name, data_type, is_nullable, column_default
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name IN ('unique_bidder_count','time_of_first_bid','time_of_last_bid')
-- ORDER BY column_name;
-- Expected: 3 rows; unique_bidder_count: NOT NULL DEFAULT 0; timestamps: nullable

-- V2: unique_bidder_count matches actual distinct bidder count:
-- SELECT a.id, a.unique_bidder_count AS stored,
--        COUNT(DISTINCT b.bidder_uid) AS actual
-- FROM public.auctions a
-- LEFT JOIN public.bids b ON b.auction_id = a.id
-- GROUP BY a.id, a.unique_bidder_count
-- HAVING a.unique_bidder_count <> COUNT(DISTINCT b.bidder_uid);
-- Expected: 0 rows

-- V3: time_of_first_bid matches MIN(bid.created_at) per auction:
-- SELECT a.id, a.time_of_first_bid, MIN(b.created_at) AS actual_first
-- FROM public.auctions a
-- JOIN public.bids b ON b.auction_id = a.id
-- GROUP BY a.id, a.time_of_first_bid
-- HAVING a.time_of_first_bid <> MIN(b.created_at);
-- Expected: 0 rows

-- V4: Auctions with no bids have NULL timestamps and 0 unique_bidder_count:
-- SELECT COUNT(*) FROM public.auctions a
-- WHERE NOT EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id)
--   AND (time_of_first_bid IS NOT NULL
--     OR time_of_last_bid IS NOT NULL
--     OR unique_bidder_count <> 0);
-- Expected: 0

-- V5: unique_bidder_count never exceeds total_bids:
-- SELECT id, unique_bidder_count, total_bids
-- FROM public.auctions
-- WHERE unique_bidder_count > total_bids;
-- Expected: 0 rows

-- V6: Both indexes exist:
-- SELECT indexname FROM pg_indexes
-- WHERE tablename = 'auctions'
--   AND indexname IN ('idx_auctions_unique_bidder_count','idx_auctions_time_of_first_bid');
-- Expected: 2 rows

-- ============================================================
-- ROLLBACK Script (run in reverse order of deployment)
-- ============================================================

-- DROP INDEX IF EXISTS public.idx_auctions_time_of_first_bid;
-- DROP INDEX IF EXISTS public.idx_auctions_unique_bidder_count;
-- ALTER TABLE public.auctions
--   DROP COLUMN IF EXISTS time_of_last_bid,
--   DROP COLUMN IF EXISTS time_of_first_bid,
--   DROP COLUMN IF EXISTS unique_bidder_count;
