# Phase 1 — AI Training Data Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Instrument the E-CYAMUNARA platform to passively collect high-quality behavioral and engagement signals (bid timing, view counts, unique bidder counts) needed for future ML training — without building any AI or prediction logic.

**Architecture:** Four idempotent SQL migrations add new columns and create the `auction_views` table + two RPCs. The existing `accept_bid()` RPC is extended (not replaced structurally) to populate bid behavioral fields and update auction engagement counters atomically inside its existing `SELECT … FOR UPDATE` transaction. The `place-bid` Edge Function forwards new fields to Flutter. Flutter models gain new nullable fields with zero breaking changes.

**Tech Stack:** PostgreSQL 15 (Supabase), Deno (Edge Functions), Dart/Flutter, Riverpod

---

## File Map

| Action | File |
|---|---|
| Create | `supabase/migrations/20260610000002_bid_behavioral_fields.sql` |
| Create | `supabase/migrations/20260610000003_auction_views_table.sql` |
| Create | `supabase/migrations/20260610000004_auction_engagement_fields.sql` |
| Create | `supabase/migrations/20260610000005_update_accept_bid_rpc.sql` |
| Modify | `supabase/functions/place-bid/index.ts` |
| Modify | `lib/data/models/models.dart` (AuctionModel + BidModel) |
| Modify | `lib/data/repositories/auction_repository.dart` |

---

## Task 1: Schema Audit

**Files:**
- Read: `supabase/migrations/` (all existing files)

Verify the current state of the database schema before writing any migration. Run these queries in the Supabase SQL Editor. All expected results are documented — if any expected result fails, stop and investigate before proceeding.

- [ ] **Step 1.1: Verify bids table columns**

```sql
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'bids'
ORDER BY ordinal_position;
```

Expected columns: `id, auction_id, bidder_uid, bidder_name, bidder_phone, bidder_district, bid_amount, bid_status, created_at, updated_at`

Columns that must NOT exist yet (will be added in Task 2):
`bid_sequence, seconds_before_end, bid_increment, is_bid_update`

- [ ] **Step 1.2: Verify auctions table columns**

```sql
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'auctions'
ORDER BY ordinal_position;
```

Columns that must NOT exist yet (added in Tasks 3–4):
`views_count, unique_bidder_count, time_of_first_bid, time_of_last_bid`

- [ ] **Step 1.3: Verify auction_views table does not exist**

```sql
SELECT EXISTS (
  SELECT 1 FROM information_schema.tables
  WHERE table_schema = 'public' AND table_name = 'auction_views'
) AS table_exists;
```

Expected: `false`

- [ ] **Step 1.4: Verify accept_bid() signature**

```sql
SELECT pg_get_functiondef(oid)
FROM pg_proc
WHERE proname = 'accept_bid';
```

Confirm the function exists and returns `JSONB`. The return payload currently includes: `success, new_highest_bid, is_winning, is_update, prev_winner_uid, new_winner_uid, item_name, admin_uid`.

- [ ] **Step 1.5: Record baseline bid counts for validation**

```sql
SELECT
  COUNT(*) AS total_bids,
  COUNT(DISTINCT auction_id) AS distinct_auctions,
  COUNT(DISTINCT bidder_uid) AS distinct_bidders
FROM bids;
```

Save these numbers — they will be used to verify data integrity after backfill.

---

## Task 2: Migration 000002 — Bid Behavioral Fields

**Files:**
- Create: `supabase/migrations/20260610000002_bid_behavioral_fields.sql`

Adds four ML behavioral feature columns to the `bids` table. All idempotent. Historical `bid_increment` and `seconds_before_end` are left NULL (cannot reconstruct accurately). `bid_sequence` and `is_bid_update` are backfilled.

- [ ] **Step 2.1: Create the migration file**

```sql
-- =============================================================================
-- E-CYAMUNARA — Phase 1 AI Data: Bid Behavioral Fields
-- File: supabase/migrations/20260610000002_bid_behavioral_fields.sql
--
-- Adds four ML feature columns to the bids table:
--   bid_sequence       — position of this bid in the auction timeline (1-based)
--   seconds_before_end — time remaining when bid was placed (server-side only)
--   bid_increment      — amount above auction's current_highest_bid at placement
--   is_bid_update      — true if bidder raised/lowered their existing bid
--
-- IDEMPOTENT: ADD COLUMN IF NOT EXISTS; backfill WHERE column IS NULL.
-- SAFE: all new columns are nullable (except is_bid_update which defaults false).
-- NO BREAKING CHANGES: existing bids rows are not modified except for backfill.
-- =============================================================================

-- ─── 1. ADD COLUMNS ──────────────────────────────────────────────────────────

ALTER TABLE public.bids
  ADD COLUMN IF NOT EXISTS bid_sequence       INTEGER,
  ADD COLUMN IF NOT EXISTS seconds_before_end INTEGER,
  ADD COLUMN IF NOT EXISTS bid_increment      NUMERIC,
  ADD COLUMN IF NOT EXISTS is_bid_update      BOOLEAN NOT NULL DEFAULT false;

-- ─── 2. BACKFILL is_bid_update ───────────────────────────────────────────────
-- A row was updated if updated_at is more than 1 second after created_at.
-- The 1-second buffer avoids false positives from DB trigger latency.

UPDATE public.bids
SET is_bid_update = true
WHERE updated_at IS NOT NULL
  AND updated_at > created_at + interval '1 second'
  AND is_bid_update = false;

-- ─── 3. BACKFILL bid_sequence ────────────────────────────────────────────────
-- Assigns 1-based sequence numbers ordered by created_at within each auction.
-- Update-only rows (is_bid_update = true) receive the same sequence position
-- as their original insert — there is no separate row for updates.

WITH ranked AS (
  SELECT
    id,
    ROW_NUMBER() OVER (
      PARTITION BY auction_id
      ORDER BY created_at ASC, id ASC
    ) AS seq
  FROM public.bids
  WHERE bid_sequence IS NULL
)
UPDATE public.bids b
SET bid_sequence = r.seq
FROM ranked r
WHERE b.id = r.id;

-- bid_increment and seconds_before_end: left NULL for historical rows.
-- These values depend on the auction state at bid time and cannot be
-- reconstructed retroactively with accuracy.

-- ─── 4. INDEXES ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_bids_auction_sequence
  ON public.bids (auction_id, bid_sequence)
  WHERE bid_sequence IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_bids_seconds_before_end
  ON public.bids (auction_id, seconds_before_end)
  WHERE seconds_before_end IS NOT NULL;

-- ─── 5. VALIDATION QUERIES ───────────────────────────────────────────────────
-- Run these after deployment to confirm correctness.

-- V1: All existing bids have bid_sequence assigned
-- SELECT COUNT(*) AS missing_sequence FROM public.bids WHERE bid_sequence IS NULL;
-- Expected: 0

-- V2: bid_sequence is unique per (auction_id) for rows sharing an auction
-- SELECT auction_id, bid_sequence, COUNT(*) AS cnt
-- FROM public.bids
-- GROUP BY auction_id, bid_sequence
-- HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- V3: is_bid_update distribution check
-- SELECT is_bid_update, COUNT(*) FROM public.bids GROUP BY is_bid_update;
-- Review: is_bid_update=false should be the majority

-- V4: Sequence starts at 1 per auction
-- SELECT auction_id, MIN(bid_sequence) AS min_seq
-- FROM public.bids GROUP BY auction_id HAVING MIN(bid_sequence) <> 1;
-- Expected: 0 rows

-- ─── 6. ROLLBACK ─────────────────────────────────────────────────────────────
-- DROP INDEX IF EXISTS public.idx_bids_auction_sequence;
-- DROP INDEX IF EXISTS public.idx_bids_seconds_before_end;
-- ALTER TABLE public.bids
--   DROP COLUMN IF EXISTS bid_sequence,
--   DROP COLUMN IF EXISTS seconds_before_end,
--   DROP COLUMN IF EXISTS bid_increment,
--   DROP COLUMN IF EXISTS is_bid_update;
```

- [ ] **Step 2.2: Apply the migration in Supabase SQL Editor**

Paste the full file content into the Supabase Dashboard → SQL Editor and run it.
Confirm output: `ALTER TABLE`, `UPDATE X`, `CREATE INDEX` (no errors).

- [ ] **Step 2.3: Run validation queries V1–V4**

All four must return 0 rows / 0 count. If V2 returns rows, stop — the backfill has a bug.

---

## Task 3: Migration 000003 — Auction Views Table + RPCs

**Files:**
- Create: `supabase/migrations/20260610000003_auction_views_table.sql`

Creates the `auction_views` table, adds `views_count` to the `auctions` table (needed by the RPC in this same migration), and creates two `SECURITY DEFINER` RPCs with full ownership checks.

- [ ] **Step 3.1: Create the migration file**

```sql
-- =============================================================================
-- E-CYAMUNARA — Phase 1 AI Data: Auction Views Infrastructure
-- File: supabase/migrations/20260610000003_auction_views_table.sql
--
-- Creates:
--   auction_views table — individual page-view events with 30-min dedup
--   record_auction_view() RPC — dedup check + atomic views_count increment
--   end_auction_view() RPC — write-once view_duration_seconds (for ML)
--
-- Also adds views_count to auctions (required by record_auction_view).
--
-- IDEMPOTENT: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--             CREATE OR REPLACE FUNCTION, DROP POLICY IF EXISTS before CREATE.
-- =============================================================================

-- ─── 1. ADD views_count TO auctions ─────────────────────────────────────────
-- Added here (not in 000004) because record_auction_view() increments it.

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS views_count INTEGER NOT NULL DEFAULT 0;

-- ─── 2. CREATE auction_views TABLE ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.auction_views (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id            UUID         NOT NULL
                          REFERENCES public.auctions(id) ON DELETE CASCADE,
  viewer_uid            UUID
                          REFERENCES public.users(id) ON DELETE SET NULL,
  viewed_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
  region                TEXT,
  device_type           TEXT
                          CHECK (device_type IN ('mobile', 'web', 'unknown')),
  view_duration_seconds INTEGER
                          CHECK (view_duration_seconds >= 0
                             AND view_duration_seconds <= 86400)
);

-- ─── 3. INDEXES ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_auction_views_auction
  ON public.auction_views (auction_id, viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_auction_views_viewer
  ON public.auction_views (viewer_uid)
  WHERE viewer_uid IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_auction_views_region
  ON public.auction_views (region, viewed_at DESC);

-- Supports the 30-minute deduplication lookup in record_auction_view()
CREATE INDEX IF NOT EXISTS idx_auction_views_dedup
  ON public.auction_views (auction_id, viewer_uid, viewed_at DESC)
  WHERE viewer_uid IS NOT NULL;

-- ─── 4. RLS ──────────────────────────────────────────────────────────────────

ALTER TABLE public.auction_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "clients_insert_views" ON public.auction_views;
CREATE POLICY "clients_insert_views" ON public.auction_views
  FOR INSERT TO authenticated
  WITH CHECK (viewer_uid = auth.uid() OR viewer_uid IS NULL);

DROP POLICY IF EXISTS "super_admin_read_views" ON public.auction_views;
CREATE POLICY "super_admin_read_views" ON public.auction_views
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.super_admins
      WHERE id = auth.uid() AND account_status = 'active'
    )
  );

-- ─── 5. RPC: record_auction_view ─────────────────────────────────────────────
-- Called by Flutter when AuctionDetailScreen opens.
-- Returns the view_id (for the follow-up end_auction_view call) and whether
-- this was a new view (true) or was suppressed by the 30-minute dedup (false).

CREATE OR REPLACE FUNCTION public.record_auction_view(
  p_auction_id  UUID,
  p_viewer_uid  UUID,
  p_device_type TEXT DEFAULT 'mobile'
)
RETURNS TABLE (view_id UUID, is_new_view BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_view_id UUID;
  v_new_view_id      UUID;
  v_auction_region   TEXT;
  v_safe_device_type TEXT;
BEGIN
  -- Normalize device_type; reject unknown values silently
  v_safe_device_type := CASE
    WHEN p_device_type IN ('mobile', 'web', 'unknown') THEN p_device_type
    ELSE 'unknown'
  END;

  -- ── Ownership / authentication check ───────────────────────────────────────
  -- p_viewer_uid must match the JWT caller (prevents recording views for others)
  IF p_viewer_uid IS NOT NULL AND p_viewer_uid <> auth.uid() THEN
    RAISE EXCEPTION 'viewer_uid must match authenticated user';
  END IF;

  -- ── 30-minute deduplication check ──────────────────────────────────────────
  SELECT id INTO v_existing_view_id
  FROM public.auction_views
  WHERE auction_id = p_auction_id
    AND viewer_uid = p_viewer_uid
    AND viewed_at  > now() - interval '30 minutes'
  ORDER BY viewed_at DESC
  LIMIT 1;

  -- Return existing view_id without inserting or incrementing counter
  IF v_existing_view_id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing_view_id, false;
    RETURN;
  END IF;

  -- ── Fetch auction region server-side ────────────────────────────────────────
  SELECT region INTO v_auction_region
  FROM public.auctions
  WHERE id = p_auction_id AND is_deleted = false;

  IF v_auction_region IS NULL THEN
    RAISE EXCEPTION 'Auction not found or deleted: %', p_auction_id;
  END IF;

  -- ── Insert new view record ──────────────────────────────────────────────────
  INSERT INTO public.auction_views (auction_id, viewer_uid, viewed_at, region, device_type)
  VALUES (p_auction_id, p_viewer_uid, now(), v_auction_region, v_safe_device_type)
  RETURNING id INTO v_new_view_id;

  -- ── Atomic counter increment ────────────────────────────────────────────────
  -- Only the RPC may update views_count. Direct client UPDATE is blocked by RLS.
  UPDATE public.auctions
  SET views_count = views_count + 1
  WHERE id = p_auction_id;

  RETURN QUERY SELECT v_new_view_id, true;
END;
$$;

-- ─── 6. RPC: end_auction_view ────────────────────────────────────────────────
-- Called by Flutter when AuctionDetailScreen is disposed.
-- Stores view_duration_seconds for ML engagement analysis.
-- Write-once: will not overwrite an already-set duration.
-- Returns true if the update succeeded, false if already set or not owned.

CREATE OR REPLACE FUNCTION public.end_auction_view(
  p_view_id          UUID,
  p_duration_seconds INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows_updated INTEGER;
BEGIN
  -- ── Validate duration range ─────────────────────────────────────────────────
  IF p_duration_seconds < 0 OR p_duration_seconds > 86400 THEN
    RAISE EXCEPTION 'view_duration_seconds must be between 0 and 86400';
  END IF;

  -- ── Update only if caller owns the view and duration not yet set ────────────
  UPDATE public.auction_views
  SET view_duration_seconds = p_duration_seconds
  WHERE id         = p_view_id
    AND viewer_uid = auth.uid()        -- ownership: caller must own this view
    AND view_duration_seconds IS NULL; -- write-once: never overwrite

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;
  RETURN v_rows_updated > 0;
END;
$$;

-- ─── 7. GRANT EXECUTE ────────────────────────────────────────────────────────

GRANT EXECUTE ON FUNCTION public.record_auction_view(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_auction_view(UUID, INTEGER) TO authenticated;

-- ─── 8. VALIDATION QUERIES ───────────────────────────────────────────────────

-- V1: auction_views table exists with correct structure
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auction_views'
-- ORDER BY ordinal_position;
-- Expected columns: id, auction_id, viewer_uid, viewed_at, region, device_type, view_duration_seconds

-- V2: RLS is enabled on auction_views
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'auction_views';
-- Expected: true

-- V3: Both RPCs exist and are SECURITY DEFINER
-- SELECT routine_name, security_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('record_auction_view', 'end_auction_view');
-- Expected: both rows with security_type = 'DEFINER'

-- V4: views_count column added to auctions
-- SELECT column_name, column_default FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name = 'views_count';
-- Expected: 1 row, column_default = '0'

-- V5: No duplicate views within 30-minute windows (will pass on fresh table)
-- SELECT auction_id, viewer_uid, COUNT(*)
-- FROM public.auction_views
-- WHERE viewed_at > now() - interval '30 minutes'
-- GROUP BY auction_id, viewer_uid
-- HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- ─── 9. ROLLBACK ─────────────────────────────────────────────────────────────
-- REVOKE EXECUTE ON FUNCTION public.record_auction_view(UUID, UUID, TEXT) FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION public.end_auction_view(UUID, INTEGER) FROM authenticated;
-- DROP FUNCTION IF EXISTS public.end_auction_view(UUID, INTEGER);
-- DROP FUNCTION IF EXISTS public.record_auction_view(UUID, UUID, TEXT);
-- DROP TABLE IF EXISTS public.auction_views CASCADE;
-- ALTER TABLE public.auctions DROP COLUMN IF EXISTS views_count;
```

- [ ] **Step 3.2: Apply the migration in Supabase SQL Editor**

Confirm output: `ALTER TABLE`, `CREATE TABLE`, `CREATE INDEX` ×4, `CREATE POLICY` ×2, `CREATE FUNCTION` ×2, `GRANT`.

- [ ] **Step 3.3: Run validation queries V1–V5**

V3 is the critical check: both functions must be `security_type = DEFINER`.

---

## Task 4: Migration 000004 — Auction Engagement Fields

**Files:**
- Create: `supabase/migrations/20260610000004_auction_engagement_fields.sql`

Adds `unique_bidder_count`, `time_of_first_bid`, `time_of_last_bid` to auctions with accurate backfill from existing bids data.

- [ ] **Step 4.1: Create the migration file**

```sql
-- =============================================================================
-- E-CYAMUNARA — Phase 1 AI Data: Auction Engagement Fields
-- File: supabase/migrations/20260610000004_auction_engagement_fields.sql
--
-- Adds three engagement tracking columns to the auctions table:
--   unique_bidder_count — distinct bidders who placed at least one bid
--   time_of_first_bid   — when the first bid arrived (immutable after set)
--   time_of_last_bid    — when the most recent bid arrived (updated on every bid)
--
-- views_count was added in migration 000003 (required by record_auction_view RPC).
--
-- IDEMPOTENT: ADD COLUMN IF NOT EXISTS; backfill is guarded by WHERE NULL checks.
-- BACKFILL NOTE: unique_bidder_count and bid timestamps are accurate backfills
--   from the bids table. views_count starts at 0 (no historical view data exists).
-- =============================================================================

-- ─── 1. ADD COLUMNS ──────────────────────────────────────────────────────────

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS unique_bidder_count INTEGER     NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS time_of_first_bid   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS time_of_last_bid    TIMESTAMPTZ;

-- ─── 2. BACKFILL unique_bidder_count ─────────────────────────────────────────
-- Counts distinct bidder_uid values per auction from existing bids.
-- Idempotent: only updates rows where the value is still 0 AND bids exist.

UPDATE public.auctions a
SET unique_bidder_count = (
  SELECT COUNT(DISTINCT bidder_uid)
  FROM public.bids b
  WHERE b.auction_id = a.id
)
WHERE EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id);

-- ─── 3. BACKFILL time_of_first_bid and time_of_last_bid ──────────────────────
-- time_of_first_bid = earliest created_at in bids for this auction.
-- time_of_last_bid  = latest of (updated_at, created_at) across all bids.
-- Both are NULL for auctions with no bids.

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
WHERE EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id);

-- ─── 4. INDEXES ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_auctions_unique_bidder_count
  ON public.auctions (unique_bidder_count DESC)
  WHERE is_deleted = false;

CREATE INDEX IF NOT EXISTS idx_auctions_time_of_first_bid
  ON public.auctions (time_of_first_bid)
  WHERE time_of_first_bid IS NOT NULL AND is_deleted = false;

-- ─── 5. VALIDATION QUERIES ───────────────────────────────────────────────────

-- V1: unique_bidder_count matches actual distinct bidder count
-- SELECT a.id, a.unique_bidder_count,
--        COUNT(DISTINCT b.bidder_uid) AS actual
-- FROM public.auctions a
-- LEFT JOIN public.bids b ON b.auction_id = a.id
-- GROUP BY a.id, a.unique_bidder_count
-- HAVING a.unique_bidder_count <> COUNT(DISTINCT b.bidder_uid);
-- Expected: 0 rows

-- V2: time_of_first_bid matches MIN(bid.created_at) per auction
-- SELECT a.id, a.time_of_first_bid, MIN(b.created_at) AS actual_first
-- FROM public.auctions a
-- JOIN public.bids b ON b.auction_id = a.id
-- GROUP BY a.id, a.time_of_first_bid
-- HAVING a.time_of_first_bid <> MIN(b.created_at);
-- Expected: 0 rows

-- V3: No auction has unique_bidder_count > total_bids (impossible by definition)
-- SELECT id, unique_bidder_count, total_bids
-- FROM public.auctions
-- WHERE unique_bidder_count > total_bids;
-- Expected: 0 rows

-- V4: Auctions with no bids have NULL timestamps and 0 unique_bidder_count
-- SELECT COUNT(*) FROM public.auctions a
-- WHERE NOT EXISTS (SELECT 1 FROM public.bids WHERE auction_id = a.id)
--   AND (time_of_first_bid IS NOT NULL OR unique_bidder_count <> 0);
-- Expected: 0

-- ─── 6. ROLLBACK ─────────────────────────────────────────────────────────────
-- DROP INDEX IF EXISTS public.idx_auctions_unique_bidder_count;
-- DROP INDEX IF EXISTS public.idx_auctions_time_of_first_bid;
-- ALTER TABLE public.auctions
--   DROP COLUMN IF EXISTS unique_bidder_count,
--   DROP COLUMN IF EXISTS time_of_first_bid,
--   DROP COLUMN IF EXISTS time_of_last_bid;
```

- [ ] **Step 4.2: Apply the migration in Supabase SQL Editor**

Confirm output: `ALTER TABLE`, two `UPDATE X` (count must match baseline from Task 1, Step 5), `CREATE INDEX` ×2.

- [ ] **Step 4.3: Run validation queries V1–V4**

V1 and V2 are critical. Zero rows expected in both.

---

## Task 5: Migration 000005 — Updated accept_bid() RPC

**Files:**
- Create: `supabase/migrations/20260610000005_update_accept_bid_rpc.sql`

Full `CREATE OR REPLACE` of `accept_bid()`. Preserves the existing function signature (same 6 parameters), same JSONB return type, same guards, same upsert logic, same notification context fields. Additively populates the four new bid columns and three new auction engagement columns inside the existing `FOR UPDATE` transaction.

- [ ] **Step 5.1: Create the migration file**

```sql
-- =============================================================================
-- E-CYAMUNARA — Phase 1 AI Data: Updated accept_bid() RPC
-- File: supabase/migrations/20260610000005_update_accept_bid_rpc.sql
--
-- Extends accept_bid() to populate ML training data inside the existing
-- SELECT ... FOR UPDATE transaction. No structural change to the function
-- signature or return type (new fields are additive to the JSONB payload).
--
-- New logic added (all server-side):
--   bid_sequence       — 1-based position within auction; kept on UPDATE
--   bid_increment      — p_bid_amount - current_highest_bid at lock time
--   seconds_before_end — GREATEST(0, EXTRACT(EPOCH FROM end_date - now()))
--   is_bid_update      — true on UPDATE path, false on INSERT path
--
--   auctions.unique_bidder_count — incremented only on INSERT (first bid)
--   auctions.time_of_first_bid   — set once via COALESCE (never overwritten)
--   auctions.time_of_last_bid    — updated on every bid (INSERT and UPDATE)
--
-- Prerequisites: migrations 000002, 000003, 000004 must be applied first.
-- IDEMPOTENT: CREATE OR REPLACE FUNCTION is always safe to re-run.
-- =============================================================================

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
  -- ML behavioral feature variables (all computed server-side)
  v_bid_sequence     INTEGER;
  v_bid_increment    NUMERIC;
  v_secs_before_end  INTEGER;
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
      'success', false, 'error', 'Auction not found', 'code', 'NOT_FOUND'
    );
  END IF;

  -- ── Guard: auction must be active ──────────────────────────────────────────
  IF v_auction.auction_status <> 'active' THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Auction is not active', 'code', 'NOT_ACTIVE'
    );
  END IF;

  -- ── Guard: auction must not have ended ─────────────────────────────────────
  IF v_auction.end_date <= NOW() THEN
    RETURN jsonb_build_object(
      'success', false, 'error', 'Auction has ended', 'code', 'ENDED'
    );
  END IF;

  -- ── Guard: bid must be at least the starting price ─────────────────────────
  IF p_bid_amount < v_auction.starting_price THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', format('Bid must be at least %s RWF', v_auction.starting_price::text),
      'code', 'BELOW_START'
    );
  END IF;

  -- Save current winner for notification context
  v_prev_winner := v_auction.current_winner_uid;

  -- ── Compute ML features from locked auction state ─────────────────────────
  -- All computed from server now() and the locked auction row — never from client.
  v_bid_increment   := p_bid_amount - v_auction.current_highest_bid;
  v_secs_before_end := GREATEST(
    0,
    EXTRACT(EPOCH FROM (v_auction.end_date - NOW()))::INTEGER
  );

  -- ── Check for existing bid from this bidder; lock it if found ─────────────
  SELECT id INTO v_existing_bid_id
  FROM public.bids
  WHERE auction_id = p_auction_id
    AND bidder_uid = p_bidder_uid
  FOR UPDATE;

  IF FOUND THEN
    -- ── UPDATE path ───────────────────────────────────────────────────────────
    -- Keep original bid_sequence (bidder updating bid is not a new event).
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
        bid_status         = 'outbid',     -- corrected in bulk-update below
        updated_at         = NOW(),
        bid_increment      = v_bid_increment,
        seconds_before_end = v_secs_before_end,
        is_bid_update      = TRUE
    WHERE id = v_existing_bid_id;

  ELSE
    -- ── INSERT path ───────────────────────────────────────────────────────────
    -- Assign next sequence number (MAX + 1 within this auction).
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

  -- ── Recalculate winner from MAX across all bids (after upsert) ─────────────
  -- Handles bid reductions: if bidder lowers their bid below another bidder,
  -- the other bidder becomes the new winner.
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
    -- Bid update: no counter changes; update engagement timestamps only
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

    -- Increment bidder's lifetime total (first bid only)
    UPDATE public.users
    SET total_bids_placed = total_bids_placed + 1
    WHERE id = p_bidder_uid;
  END IF;

  -- ── Return result payload ──────────────────────────────────────────────────
  -- Additive: existing fields preserved; new ML fields appended.
  RETURN jsonb_build_object(
    'success',            true,
    'new_highest_bid',    v_new_highest,
    'is_winning',         (v_new_winner_uid = p_bidder_uid),
    'is_update',          v_is_update,
    'prev_winner_uid',    v_prev_winner,
    'new_winner_uid',     v_new_winner_uid,
    'item_name',          v_auction.item_name,
    'admin_uid',          v_auction.posted_by_admin_uid,
    -- ML behavioral features (new in Phase 1)
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

-- Access control unchanged: service_role only
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) FROM authenticated;
GRANT  EXECUTE ON FUNCTION public.accept_bid(UUID, UUID, NUMERIC, TEXT, TEXT, TEXT) TO service_role;

-- ─── VALIDATION QUERIES ───────────────────────────────────────────────────────

-- V1: Function returns new ML fields (replace UUIDs with real dev values)
-- SELECT accept_bid(
--   'AUCTION_UUID'::uuid, 'BIDDER_UUID'::uuid,
--   9000000, 'Test Bidder', '0781000001', 'Gasabo'
-- );
-- Expected: success=true, bid_sequence=1 (or N), bid_increment populated,
--           seconds_before_end > 0 (if auction not ended)

-- V2: After a bid, unique_bidder_count incremented on auctions table
-- SELECT id, unique_bidder_count, time_of_first_bid, time_of_last_bid
-- FROM public.auctions WHERE id = 'AUCTION_UUID';

-- V3: bid_sequence, bid_increment, seconds_before_end populated on new bids
-- SELECT bid_sequence, bid_increment, seconds_before_end, is_bid_update
-- FROM public.bids WHERE auction_id = 'AUCTION_UUID' ORDER BY bid_sequence;

-- V4: After second bid from same bidder, bid_sequence unchanged
-- (Place a second bid from same bidder, check bid_sequence is same as first)

-- ─── ROLLBACK ─────────────────────────────────────────────────────────────────
-- To roll back: re-apply migration 20260512000000_bidding_fix.sql
-- (it uses CREATE OR REPLACE, restoring the previous accept_bid body).
-- Note: this will not remove the new columns from bids/auctions tables.
-- Those are rolled back via migrations 000002 and 000004 rollback scripts.
```

- [ ] **Step 5.2: Apply the migration in Supabase SQL Editor**

Confirm output: `CREATE FUNCTION`, `REVOKE` ×3, `GRANT`.

- [ ] **Step 5.3: Run validation query V1 using real auction/bidder UUIDs from dev data**

Confirm the response JSON includes `bid_sequence`, `bid_increment`, `seconds_before_end`.

---

## Task 6: Update place-bid Edge Function

**Files:**
- Modify: `supabase/functions/place-bid/index.ts`

The RPC now returns three new fields (`bid_sequence`, `bid_increment`, `seconds_before_end`). The Edge Function needs to: (1) declare them in the result type, (2) include them in the response to Flutter.

- [ ] **Step 6.1: Update the RPC result type declaration**

In `supabase/functions/place-bid/index.ts`, find the `result` type cast at line 113 and replace it:

```typescript
    const result = rpcResult as {
      success:            boolean;
      error?:             string;
      code?:              string;
      new_highest_bid?:   number;
      is_winning?:        boolean;
      is_update?:         boolean;
      prev_winner_uid?:   string;
      new_winner_uid?:    string;
      item_name?:         string;
      admin_uid?:         string;
      // Phase 1 ML behavioral features
      bid_sequence?:      number;
      bid_increment?:     number;
      seconds_before_end?: number;
    };
```

- [ ] **Step 6.2: Update the success response body**

Find the `return json({...})` at line 162 and replace it:

```typescript
    return json({
      success:            true,
      new_highest_bid:    result.new_highest_bid,
      is_winning:         result.is_winning,
      is_update:          result.is_update,
      // Phase 1 ML behavioral features forwarded to Flutter
      bid_sequence:       result.bid_sequence,
      bid_increment:      result.bid_increment,
      seconds_before_end: result.seconds_before_end,
    });
```

- [ ] **Step 6.3: Deploy the updated Edge Function**

```bash
supabase functions deploy place-bid
```

Expected output: `Deployed place-bid`

- [ ] **Step 6.4: Smoke-test via curl or Supabase Dashboard → Edge Functions → place-bid**

Invoke with a valid auction_id and bidder JWT. Confirm the response body includes `bid_sequence`, `bid_increment`, `seconds_before_end`.

---

## Task 7: Update AuctionModel + Add Repository View Tracking

**Files:**
- Modify: `lib/data/models/models.dart` (AuctionModel section only)
- Modify: `lib/data/repositories/auction_repository.dart`

Adds 4 new nullable fields and 2 computed getters to `AuctionModel`. Adds `recordAuctionView()` and `endAuctionView()` to `AuctionRepository`.

- [ ] **Step 7.1: Add new fields to AuctionModel constructor**

In `lib/data/models/models.dart`, locate the `AuctionModel` class. After the `insuranceStatus` field declaration (line ~239), add:

```dart
  // Phase 1 AI: engagement analytics
  final int viewsCount;
  final int uniqueBidderCount;
  final DateTime? timeOfFirstBid;
  final DateTime? timeOfLastBid;
```

- [ ] **Step 7.2: Add fields to the constructor**

In the `const AuctionModel({...})` constructor, after `this.insuranceStatus,`, add:

```dart
    this.viewsCount = 0,
    this.uniqueBidderCount = 0,
    this.timeOfFirstBid,
    this.timeOfLastBid,
```

- [ ] **Step 7.3: Add fields to fromMap()**

In `AuctionModel.fromMap()`, after the `insuranceStatus:` line, add:

```dart
    viewsCount:         (map['views_count'] as num?)?.toInt() ?? 0,
    uniqueBidderCount:  (map['unique_bidder_count'] as num?)?.toInt() ?? 0,
    timeOfFirstBid:     map['time_of_first_bid'] != null
                          ? DateTime.parse(map['time_of_first_bid'] as String)
                          : null,
    timeOfLastBid:      map['time_of_last_bid'] != null
                          ? DateTime.parse(map['time_of_last_bid'] as String)
                          : null,
```

- [ ] **Step 7.4: Add fields to toMap()**

In `AuctionModel.toMap()`, after the `'insurance_status'` entry:

```dart
    if (viewsCount != 0)           'views_count':          viewsCount,
    if (uniqueBidderCount != 0)    'unique_bidder_count':  uniqueBidderCount,
    if (timeOfFirstBid != null)    'time_of_first_bid':    timeOfFirstBid!.toIso8601String(),
    if (timeOfLastBid != null)     'time_of_last_bid':     timeOfLastBid!.toIso8601String(),
```

- [ ] **Step 7.5: Add fields to copyWith()**

In `AuctionModel.copyWith({...})`, after `String? insuranceStatus,`, add:

```dart
    int? viewsCount,
    int? uniqueBidderCount,
    DateTime? timeOfFirstBid,
    DateTime? timeOfLastBid,
```

In the `AuctionModel(...)` return block of `copyWith`, after `insuranceStatus: insuranceStatus ?? this.insuranceStatus,`, add:

```dart
    viewsCount:        viewsCount ?? this.viewsCount,
    uniqueBidderCount: uniqueBidderCount ?? this.uniqueBidderCount,
    timeOfFirstBid:    timeOfFirstBid ?? this.timeOfFirstBid,
    timeOfLastBid:     timeOfLastBid ?? this.timeOfLastBid,
```

- [ ] **Step 7.6: Add computed getters to AuctionModel**

After the existing `bool get isExpired` getter and `String get resolvedMainCategory` getter, add:

```dart
  Duration get auctionDuration => endDate.difference(startDate);

  Duration? get timeToFirstBid =>
      timeOfFirstBid != null ? timeOfFirstBid!.difference(startDate) : null;
```

- [ ] **Step 7.7: Add view tracking methods to AuctionRepository**

In `lib/data/repositories/auction_repository.dart`, add after the existing `publishDraft()` method:

```dart
  // Records an auction view event. Returns (viewId, isNewView) from the RPC.
  // isNewView = false means the view was suppressed by the 30-minute dedup window.
  Future<(String? viewId, bool isNewView)> recordAuctionView({
    required String auctionId,
    required String viewerUid,
    String deviceType = 'mobile',
  }) async {
    try {
      final result = await _client.rpc('record_auction_view', params: {
        'p_auction_id':  auctionId,
        'p_viewer_uid':  viewerUid,
        'p_device_type': deviceType,
      });
      if (result == null) return (null, false);
      final rows = result as List<dynamic>;
      if (rows.isEmpty) return (null, false);
      final row = rows.first as Map<String, dynamic>;
      return (row['view_id'] as String?, row['is_new_view'] as bool? ?? false);
    } catch (_) {
      // View tracking is non-critical; never throw to the UI
      return (null, false);
    }
  }

  // Stores how long the user viewed the auction detail page.
  // Called on AuctionDetailScreen dispose. Fire-and-forget.
  Future<void> endAuctionView({
    required String viewId,
    required int durationSeconds,
  }) async {
    try {
      await _client.rpc('end_auction_view', params: {
        'p_view_id':          viewId,
        'p_duration_seconds': durationSeconds,
      });
    } catch (_) {
      // Non-critical; silently discard errors
    }
  }
```

---

## Task 8: Update BidModel

**Files:**
- Modify: `lib/data/models/models.dart` (BidModel section only)

Adds 4 new nullable fields to `BidModel` with zero breaking changes.

- [ ] **Step 8.1: Add new fields to BidModel**

In `lib/data/models/models.dart`, locate the `BidModel` class. After `final DateTime? updatedAt;` (line ~509), add:

```dart
  // Phase 1 AI: behavioral features (all nullable; NULL for pre-Phase-1 bids)
  final int? bidSequence;
  final int? secondsBeforeEnd;
  final double? bidIncrement;
  final bool isBidUpdate;
```

- [ ] **Step 8.2: Add to BidModel constructor**

In `const BidModel({...})`, after `this.updatedAt,`, add:

```dart
    this.bidSequence,
    this.secondsBeforeEnd,
    this.bidIncrement,
    this.isBidUpdate = false,
```

- [ ] **Step 8.3: Add to BidModel.fromMap()**

After the `updatedAt:` line in `BidModel.fromMap()`, add:

```dart
    bidSequence:      (map['bid_sequence'] as num?)?.toInt(),
    secondsBeforeEnd: (map['seconds_before_end'] as num?)?.toInt(),
    bidIncrement:     (map['bid_increment'] as num?)?.toDouble(),
    isBidUpdate:      map['is_bid_update'] as bool? ?? false,
```

- [ ] **Step 8.4: Add to BidModel.toMap()**

In `BidModel.toMap()`, after `'bid_status': bidStatus,`, add:

```dart
    if (bidSequence != null)      'bid_sequence':       bidSequence,
    if (secondsBeforeEnd != null) 'seconds_before_end': secondsBeforeEnd,
    if (bidIncrement != null)     'bid_increment':      bidIncrement,
    'is_bid_update':              isBidUpdate,
```

- [ ] **Step 8.5: Run flutter analyze**

```bash
flutter analyze
```

Expected: `No issues found!`

If any issues are found, fix them before proceeding.

- [ ] **Step 8.6: Commit all Flutter changes**

```bash
git add lib/data/models/models.dart lib/data/repositories/auction_repository.dart
git commit -m "feat(data): add Phase 1 AI engagement fields to AuctionModel and BidModel

- AuctionModel: viewsCount, uniqueBidderCount, timeOfFirstBid, timeOfLastBid
- AuctionModel: auctionDuration and timeToFirstBid computed getters
- BidModel: bidSequence, secondsBeforeEnd, bidIncrement, isBidUpdate
- AuctionRepository: recordAuctionView() and endAuctionView() RPCs

All new fields nullable/defaulted — zero breaking changes to existing data.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 9: Full Validation Suite

**Files:**
- Read-only: Supabase SQL Editor, terminal

Run all validation queries from Tasks 2–5 in sequence. Then run the cross-table integrity suite below.

- [ ] **Step 9.1: Cross-table integrity — unique_bidder_count vs bids**

```sql
SELECT a.id AS auction_id,
       a.unique_bidder_count AS stored,
       COUNT(DISTINCT b.bidder_uid) AS actual
FROM public.auctions a
LEFT JOIN public.bids b ON b.auction_id = a.id
GROUP BY a.id, a.unique_bidder_count
HAVING a.unique_bidder_count <> COUNT(DISTINCT b.bidder_uid);
```

Expected: 0 rows.

- [ ] **Step 9.2: Cross-table integrity — views_count vs auction_views**

```sql
SELECT a.id AS auction_id,
       a.views_count AS stored,
       COUNT(v.id) AS actual
FROM public.auctions a
LEFT JOIN public.auction_views v ON v.auction_id = a.id
GROUP BY a.id, a.views_count
HAVING a.views_count <> COUNT(v.id);
```

Expected: 0 rows. (Will also be 0 if auction_views is empty — that is correct.)

- [ ] **Step 9.3: bid_sequence uniqueness per auction**

```sql
SELECT auction_id, bid_sequence, COUNT(*) AS cnt
FROM public.bids
GROUP BY auction_id, bid_sequence
HAVING COUNT(*) > 1;
```

Expected: 0 rows.

- [ ] **Step 9.4: Dedup window integrity — no duplicate views within 30 minutes**

```sql
WITH ranked AS (
  SELECT
    auction_id,
    viewer_uid,
    viewed_at,
    LAG(viewed_at) OVER (
      PARTITION BY auction_id, viewer_uid
      ORDER BY viewed_at ASC
    ) AS prev_view
  FROM public.auction_views
  WHERE viewer_uid IS NOT NULL
)
SELECT *
FROM ranked
WHERE EXTRACT(EPOCH FROM (viewed_at - prev_view)) < 1800;
```

Expected: 0 rows. (Each `(viewer_uid, auction_id)` pair must be at least 1800 seconds apart.)

- [ ] **Step 9.5: time_of_first_bid immutability check**

```sql
-- For any auction that has bids, time_of_first_bid must equal MIN(bid.created_at)
SELECT a.id, a.time_of_first_bid, MIN(b.created_at) AS min_bid_time
FROM public.auctions a
JOIN public.bids b ON b.auction_id = a.id
GROUP BY a.id, a.time_of_first_bid
HAVING a.time_of_first_bid <> MIN(b.created_at);
```

Expected: 0 rows.

- [ ] **Step 9.6: seconds_before_end is always non-negative on new bids**

```sql
SELECT COUNT(*) AS negative_sbe
FROM public.bids
WHERE seconds_before_end IS NOT NULL
  AND seconds_before_end < 0;
```

Expected: 0.

- [ ] **Step 9.7: Final flutter analyze**

```bash
flutter analyze
```

Expected: `No issues found!`

- [ ] **Step 9.8: Commit migration files**

```bash
git add supabase/migrations/20260610000002_bid_behavioral_fields.sql
git add supabase/migrations/20260610000003_auction_views_table.sql
git add supabase/migrations/20260610000004_auction_engagement_fields.sql
git add supabase/migrations/20260610000005_update_accept_bid_rpc.sql
git add supabase/functions/place-bid/index.ts
git commit -m "feat(ai-data): Phase 1 training data infrastructure

Migrations:
  - 000002: bid_sequence, seconds_before_end, bid_increment, is_bid_update on bids
  - 000003: auction_views table, record_auction_view() RPC, end_auction_view() RPC
  - 000004: unique_bidder_count, time_of_first_bid, time_of_last_bid on auctions
  - 000005: accept_bid() extended with ML feature population

Edge Function:
  - place-bid: forwards bid_sequence, bid_increment, seconds_before_end to client

All migrations idempotent. No AI models. Data collection only.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Deployment Checklist

- [ ] Migration 000002 applied + V1–V4 pass
- [ ] Migration 000003 applied + V1–V5 pass
- [ ] Migration 000004 applied + V1–V4 pass
- [ ] Migration 000005 applied + V1–V4 pass
- [ ] `place-bid` Edge Function deployed
- [ ] Flutter app updated with new model fields
- [ ] `flutter analyze` returns no issues
- [ ] Cross-table integrity queries (Task 9.1–9.6) all return 0 rows
- [ ] Smoke-test: place a bid in dev → confirm `bid_sequence`, `bid_increment`, `seconds_before_end` in response
- [ ] Smoke-test: open an auction detail in dev → confirm `auction_views` row inserted and `views_count` incremented
- [ ] Smoke-test: open same auction again within 30 min → confirm `is_new_view = false`, no duplicate row, `views_count` unchanged

---

## Rollback Order (if needed)

1. Re-deploy previous `place-bid` Edge Function (git revert + `supabase functions deploy place-bid`)
2. Re-apply `20260512000000_bidding_fix.sql` in SQL Editor (restores previous `accept_bid()`)
3. Run Task 4 rollback script (drops `unique_bidder_count`, `time_of_first_bid`, `time_of_last_bid`)
4. Run Task 3 rollback script (drops `auction_views` table, RPCs, `views_count`)
5. Run Task 2 rollback script (drops `bid_sequence`, `seconds_before_end`, `bid_increment`, `is_bid_update`)
6. Revert Flutter model changes (`git revert <flutter-commit-hash>`)
