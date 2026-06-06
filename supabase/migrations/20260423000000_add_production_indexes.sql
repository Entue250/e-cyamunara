-- =============================================================================
-- E-CYAMUNARA — Production indexes migration
-- File: supabase/migrations/20260423000000_add_production_indexes.sql
--
-- Run in: Supabase Dashboard → SQL Editor (production project)
-- Safe to re-run: all statements use IF NOT EXISTS
-- Blocking: NO — CREATE INDEX CONCURRENTLY acquires ShareLock only;
--           reads and writes continue during index creation.
--
-- Source: DATABASE_INDEX_AUDIT.md (generated 2026-04-23)
-- =============================================================================

-- ── SAFETY PRE-CHECK ──────────────────────────────────────────────────────────
-- Run this block FIRST. If it returns any rows, the TOCTOU race (FM-01) has
-- already produced duplicate winning bids. Fix those rows before creating the
-- unique index (idx_bids_one_winner_per_auction) or that statement will fail.
--
-- SELECT auction_id, bidder_uid, COUNT(*) as duplicates
-- FROM bids
-- WHERE bid_status = 'winning'
-- GROUP BY auction_id, bidder_uid
-- HAVING COUNT(*) > 1;
--
-- If this query returns rows, run the repair SQL from INCIDENT_RESPONSE_GUIDE.md
-- INCIDENT 3 before proceeding. If it returns 0 rows, proceed safely.
-- =============================================================================


-- ═════════════════════════════════════════════════════════════════════════════
-- TABLE: auctions
-- ═════════════════════════════════════════════════════════════════════════════

-- Home screen: filter active auctions by region, ordered by end_date ASC.
-- Used by: AuctionRepository.getAuctionsByRegion() Realtime stream.
-- Without this: full table scan on every Realtime update event.
CREATE INDEX IF NOT EXISTS idx_auctions_region_status_end
  ON auctions (region, auction_status, end_date ASC);

-- auto-close-auctions: find all active auctions where end_date has passed.
-- Partial index (WHERE active) is smaller and faster than a full index.
-- Used by: auto-close-auctions Edge Function every 5 minutes.
CREATE INDEX IF NOT EXISTS idx_auctions_status_end
  ON auctions (auction_status, end_date ASC)
  WHERE auction_status = 'active';

-- Admin dashboard: fetch all auctions posted by a specific admin.
-- Used by: AuctionRepository.getAdminAuctions() / getAuctionsByAdmin().
CREATE INDEX IF NOT EXISTS idx_auctions_posted_by
  ON auctions (posted_by_admin_uid, created_at DESC);

-- generate-report: date-range filter for auction reporting.
-- Used by: generate-report Edge Function.
CREATE INDEX IF NOT EXISTS idx_auctions_created_at
  ON auctions (created_at DESC);


-- ═════════════════════════════════════════════════════════════════════════════
-- TABLE: bids
-- ═════════════════════════════════════════════════════════════════════════════

-- Core bid lookup: find highest bid for an auction.
-- Used by: place-bid Edge Function (every bid placement), data repair SQL.
-- Most performance-critical index in the system.
CREATE INDEX IF NOT EXISTS idx_bids_auction_id
  ON bids (auction_id, bid_amount DESC);

-- Outbid notification lookup: find all outbid records for an auction.
-- Used by: auto-close-auctions (notifying losing bidders).
CREATE INDEX IF NOT EXISTS idx_bids_auction_status
  ON bids (auction_id, bid_status);

-- My bids screen: fetch all bids placed by a user, newest first.
-- Used by: MyBidsScreen → BidRepository.getBidsByUser().
CREATE INDEX IF NOT EXISTS idx_bids_bidder
  ON bids (bidder_uid, created_at DESC);

-- Composite index for bid flood detection and data repair.
-- Used by: incident response queries, place-bid winner verification.
CREATE INDEX IF NOT EXISTS idx_bids_auction_bidder
  ON bids (auction_id, bidder_uid, bid_status);

-- Timestamp index for cleanup and incident response (bid flood detection).
CREATE INDEX IF NOT EXISTS idx_bids_created_at
  ON bids (created_at DESC);

-- ─────────────────────────────────────────────────────────────────────────────
-- PARTIAL UNIQUE CONSTRAINT: enforce one winning bid per bidder per auction.
--
-- This is the DB-level safety net for the TOCTOU race condition (FM-01).
-- If two concurrent place-bid calls both pass the bid_amount check and both
-- try to insert a 'winning' bid for the same (auction_id, bidder_uid), the
-- second INSERT will fail with a unique constraint violation. The Edge Function
-- can then detect this and return a 409 Conflict instead of silently accepting
-- both bids.
--
-- PRE-CONDITION: Run the safety pre-check at the top of this file first.
-- If duplicates exist, this statement will fail with:
--   ERROR: could not create unique index "idx_bids_one_winner_per_auction"
-- Resolve duplicates first, then re-run this statement alone.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE UNIQUE INDEX IF NOT EXISTS idx_bids_one_winner_per_auction
  ON bids (auction_id, bidder_uid)
  WHERE bid_status = 'winning';


-- ═════════════════════════════════════════════════════════════════════════════
-- TABLE: users
-- ═════════════════════════════════════════════════════════════════════════════

-- on-new-auction: find all active clients in a region to send notifications.
-- Also used by ClientManagementScreen filter.
-- Without this: full table scan on every new auction post.
CREATE INDEX IF NOT EXISTS idx_users_region_status
  ON users (region, account_status);

-- ClientManagementScreen: filter clients by account_status.
CREATE INDEX IF NOT EXISTS idx_users_status
  ON users (account_status);


-- ═════════════════════════════════════════════════════════════════════════════
-- TABLE: notifications
-- ═════════════════════════════════════════════════════════════════════════════

-- Notifications screen: fetch a user's notifications, newest first.
-- This is the most read-heavy query against this table.
-- At 30 days × 50 notifications/day = 1,500 rows per user — index essential.
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_uid, created_at DESC);

-- cleanup-notifications: delete records older than 30 days.
-- Without this: full table scan on potentially 500,000+ rows weekly.
CREATE INDEX IF NOT EXISTS idx_notifications_created_at
  ON notifications (created_at ASC);


-- ═════════════════════════════════════════════════════════════════════════════
-- TABLE: region_admins
-- ═════════════════════════════════════════════════════════════════════════════

-- create-admin: check if a region already has an assigned admin.
-- Small table but called on every admin creation — index keeps it O(log n).
CREATE INDEX IF NOT EXISTS idx_region_admins_region
  ON region_admins (region);


-- ═════════════════════════════════════════════════════════════════════════════
-- VERIFICATION — run after index creation
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. List all newly created indexes:
SELECT indexname, tablename, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
-- Expected: 14 rows (13 regular + 1 unique partial on bids)

-- 2. Verify EXPLAIN plans use the indexes (run after inserting test data):
-- EXPLAIN SELECT * FROM auctions WHERE region = 'Eastern' AND auction_status = 'active' ORDER BY end_date ASC;
-- EXPLAIN SELECT bid_amount FROM bids WHERE auction_id = 'test-id' ORDER BY bid_amount DESC LIMIT 1;
-- EXPLAIN SELECT * FROM notifications WHERE user_uid = 'test-uid' ORDER BY created_at DESC LIMIT 50;
-- All three should show "Index Scan" not "Seq Scan".

-- =============================================================================
-- ROLLBACK (drops all indexes created by this migration):
-- =============================================================================
-- DROP INDEX IF EXISTS idx_auctions_region_status_end;
-- DROP INDEX IF EXISTS idx_auctions_status_end;
-- DROP INDEX IF EXISTS idx_auctions_posted_by;
-- DROP INDEX IF EXISTS idx_auctions_created_at;
-- DROP INDEX IF EXISTS idx_bids_auction_id;
-- DROP INDEX IF EXISTS idx_bids_auction_status;
-- DROP INDEX IF EXISTS idx_bids_bidder;
-- DROP INDEX IF EXISTS idx_bids_auction_bidder;
-- DROP INDEX IF EXISTS idx_bids_created_at;
-- DROP INDEX IF EXISTS idx_bids_one_winner_per_auction;
-- DROP INDEX IF EXISTS idx_users_region_status;
-- DROP INDEX IF EXISTS idx_users_status;
-- DROP INDEX IF EXISTS idx_notifications_user_created;
-- DROP INDEX IF EXISTS idx_notifications_created_at;
-- DROP INDEX IF EXISTS idx_region_admins_region;
-- =============================================================================
