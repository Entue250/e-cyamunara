-- supabase/migrations/20260610000002_bid_behavioral_fields.sql
--
-- Task 1 — Bid behavioral fields for ML training data collection.
--
-- Adds four columns to public.bids:
--   bid_sequence        INTEGER  — 1-based position of this bid within its auction (set once on INSERT)
--   seconds_before_end  INTEGER  — seconds remaining on the auction clock when the bid was placed
--   bid_increment       NUMERIC  — how much this bid exceeded the prior highest bid
--   is_bid_update       BOOLEAN  — true if the row was updated after its initial INSERT
--
-- Safety notes:
--   • All ADD COLUMN statements use IF NOT EXISTS — idempotent, safe to re-run.
--   • No rows are inserted or deleted; only UPDATE statements are used for backfill.
--   • bid_sequence is backfilled from existing rows via ROW_NUMBER().
--   • seconds_before_end and bid_increment CANNOT be backfilled (server-side data
--     unavailable for historical rows) — they remain NULL for all pre-migration rows.
--   • is_bid_update is backfilled heuristically: true where updated_at > created_at + 1 second.
--   • Indexes use IF NOT EXISTS — safe to re-run.
--
-- Prerequisites: none — this is the first bid behavioral migration in the series.
-- Apply: supabase db push  (or paste into Supabase SQL Editor)

-- ─────────────────────────────────────────────────────────────────────────────
-- BEFORE VALIDATION — run these queries BEFORE applying the migration
-- ─────────────────────────────────────────────────────────────────────────────
--
-- V-PRE-1: Confirm the four columns do NOT yet exist (expected: 0 rows)
--
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'bids'
--   AND column_name IN ('bid_sequence','seconds_before_end','bid_increment','is_bid_update');
-- -- Expected: 0 rows
--
-- V-PRE-2: Record baseline row / auction / bidder counts (save for post-migration V5)
--
-- SELECT COUNT(*) AS total_bids,
--        COUNT(DISTINCT auction_id) AS distinct_auctions,
--        COUNT(DISTINCT bidder_uid) AS distinct_bidders
-- FROM public.bids;
-- -- Save these numbers for post-migration comparison
--
-- V-PRE-3: Preview backfill result (review before applying)
--
-- SELECT auction_id,
--        id,
--        created_at,
--        updated_at,
--        ROW_NUMBER() OVER (PARTITION BY auction_id ORDER BY created_at ASC, id ASC) AS would_be_sequence,
--        CASE WHEN updated_at IS NOT NULL AND updated_at > created_at + interval '1 second'
--             THEN true ELSE false END AS would_be_update
-- FROM public.bids
-- ORDER BY auction_id, created_at ASC
-- LIMIT 50;
-- -- Review: sequence should be consecutive (1, 2, 3, …) per auction

-- ─────────────────────────────────────────────────────────────────────────────
-- MIGRATION
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Add columns ────────────────────────────────────────────────────────────

ALTER TABLE public.bids
  ADD COLUMN IF NOT EXISTS bid_sequence        INTEGER,
  ADD COLUMN IF NOT EXISTS seconds_before_end  INTEGER,
  ADD COLUMN IF NOT EXISTS bid_increment       NUMERIC,
  ADD COLUMN IF NOT EXISTS is_bid_update       BOOLEAN NOT NULL DEFAULT false;

-- ── 2. Backfill bid_sequence ──────────────────────────────────────────────────
--
-- Assign a 1-based sequence number to every existing bid, partitioned by auction
-- and ordered by (created_at ASC, id ASC) so ties are broken deterministically.
-- This UPDATE only runs once per migration; future INSERTs are handled by the
-- updated place-bid Edge Function (which sets bid_sequence on the first write
-- and never touches it again on subsequent bid updates).

UPDATE public.bids AS b
SET bid_sequence = seq.rn
FROM (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY auction_id
           ORDER BY created_at ASC, id ASC
         ) AS rn
  FROM public.bids
) AS seq
WHERE b.id = seq.id
  AND b.bid_sequence IS NULL;

-- ── 3. Backfill is_bid_update ─────────────────────────────────────────────────
--
-- A bid row was updated if updated_at exists and is more than 1 second after
-- created_at (the 1-second buffer absorbs DB trigger timestamps that fire
-- fractionally after INSERT).
-- Rows where updated_at IS NULL or within 1 second of created_at keep the
-- default value of false.

UPDATE public.bids
SET is_bid_update = true
WHERE updated_at IS NOT NULL
  AND updated_at > created_at + interval '1 second'
  AND is_bid_update = false;

-- ── 4. seconds_before_end and bid_increment ───────────────────────────────────
--
-- These fields CANNOT be backfilled for historical rows because the auction
-- end-time snapshot and the prior-highest-bid snapshot at placement time are
-- not stored anywhere accessible post-fact.
-- They remain NULL for all pre-migration rows and will be populated by the
-- updated place-bid Edge Function for all bids placed after this migration.

-- (no UPDATE statement needed — NULL is the correct value for historical rows)

-- ── 5. Indexes ────────────────────────────────────────────────────────────────
--
-- Partial index on (auction_id, bid_sequence): supports ML feature queries that
-- join bids in sequence order within an auction; partial because bid_sequence
-- will always be set for post-migration rows but guards against future NULLs.

CREATE INDEX IF NOT EXISTS idx_bids_auction_sequence
  ON public.bids (auction_id, bid_sequence)
  WHERE bid_sequence IS NOT NULL;

-- Partial index on (auction_id, seconds_before_end): supports time-pressure
-- analysis queries; partial because historical rows are NULL.

CREATE INDEX IF NOT EXISTS idx_bids_seconds_before_end
  ON public.bids (auction_id, seconds_before_end)
  WHERE seconds_before_end IS NOT NULL;

-- ─────────────────────────────────────────────────────────────────────────────
-- AFTER VALIDATION — run these queries AFTER applying the migration
-- ─────────────────────────────────────────────────────────────────────────────
--
-- V1: All existing bids have bid_sequence assigned (expected: 0)
--
-- SELECT COUNT(*) AS missing_sequence FROM public.bids WHERE bid_sequence IS NULL;
-- -- Expected: 0
--
-- V2: bid_sequence is unique per auction — no duplicates (expected: 0 rows)
--
-- SELECT auction_id, bid_sequence, COUNT(*) AS cnt
-- FROM public.bids
-- GROUP BY auction_id, bid_sequence
-- HAVING COUNT(*) > 1;
-- -- Expected: 0 rows
--
-- V3: bid_sequence starts at 1 per auction (expected: 0 rows)
--
-- SELECT auction_id, MIN(bid_sequence) AS min_seq
-- FROM public.bids
-- GROUP BY auction_id
-- HAVING MIN(bid_sequence) <> 1;
-- -- Expected: 0 rows
--
-- V4: is_bid_update distribution (review: false should be the majority)
--
-- SELECT is_bid_update, COUNT(*) FROM public.bids GROUP BY is_bid_update;
-- -- Review: is_bid_update=false should be the majority
--
-- V5: Row count unchanged — no rows added or deleted by migration
--
-- SELECT COUNT(*) AS total_bids FROM public.bids;
-- -- Must equal the baseline count recorded in BEFORE V-PRE-2
--
-- V6: seconds_before_end and bid_increment are NULL for all historical rows (expected: 0)
--
-- SELECT COUNT(*) FROM public.bids WHERE seconds_before_end IS NOT NULL OR bid_increment IS NOT NULL;
-- -- Expected: 0 (only set by the updated place-bid Edge Function going forward)

-- ─────────────────────────────────────────────────────────────────────────────
-- ROLLBACK — run in reverse order of deployment if a rollback is needed
-- ─────────────────────────────────────────────────────────────────────────────
--
-- DROP INDEX IF EXISTS public.idx_bids_seconds_before_end;
-- DROP INDEX IF EXISTS public.idx_bids_auction_sequence;
-- ALTER TABLE public.bids
--   DROP COLUMN IF EXISTS is_bid_update,
--   DROP COLUMN IF EXISTS bid_increment,
--   DROP COLUMN IF EXISTS seconds_before_end,
--   DROP COLUMN IF EXISTS bid_sequence;
