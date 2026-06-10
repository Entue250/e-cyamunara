-- supabase/migrations/20260610000003_auction_views_table.sql
--
-- Phase 1 AI Data: Auction views infrastructure
--
-- Creates:
--   • views_count INTEGER column on auctions (default 0, no backfill)
--   • auction_views table — individual view events with 30-min dedup
--   • record_auction_view() SECURITY DEFINER RPC — dedup + atomic counter
--   • end_auction_view() SECURITY DEFINER RPC — write-once duration tracking
--
-- Safety: CREATE TABLE IF NOT EXISTS, ADD COLUMN IF NOT EXISTS,
--         CREATE OR REPLACE FUNCTION, DROP POLICY IF EXISTS before CREATE POLICY.
-- Prerequisites: migration 000002 must be applied first.

-- ============================================================
-- BEFORE Validation Queries (run manually before applying)
-- ============================================================

-- V0-1: Confirm views_count column does NOT yet exist on auctions:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name = 'views_count';
-- Expected: 0 rows

-- V0-2: Confirm auction_views table does NOT yet exist:
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'auction_views'
-- ) AS table_exists;
-- Expected: false

-- V0-3: Confirm record_auction_view function does NOT yet exist:
-- SELECT proname FROM pg_proc WHERE proname = 'record_auction_view';
-- Expected: 0 rows

-- ============================================================
-- Part A: Add views_count to auctions
-- ============================================================

ALTER TABLE public.auctions
  ADD COLUMN IF NOT EXISTS views_count INTEGER NOT NULL DEFAULT 0;

-- No backfill required — views_count starts at 0 for all existing auctions
-- (no historical view data exists prior to this migration).

-- ============================================================
-- Part B: Create auction_views table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.auction_views (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id            UUID         NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
  viewer_uid            UUID         REFERENCES public.users(id) ON DELETE SET NULL,
  viewed_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
  region                TEXT,
  device_type           TEXT         CHECK (device_type IN ('mobile', 'web', 'unknown')),
  view_duration_seconds INTEGER      CHECK (view_duration_seconds >= 0 AND view_duration_seconds <= 86400)
);

-- ============================================================
-- Part C: Indexes
-- ============================================================

-- Primary analytics query: views per auction in time order
CREATE INDEX IF NOT EXISTS idx_auction_views_auction
  ON public.auction_views (auction_id, viewed_at DESC);

-- Viewer history lookups
CREATE INDEX IF NOT EXISTS idx_auction_views_viewer
  ON public.auction_views (viewer_uid)
  WHERE viewer_uid IS NOT NULL;

-- Regional analytics
CREATE INDEX IF NOT EXISTS idx_auction_views_region
  ON public.auction_views (region, viewed_at DESC);

-- 30-minute deduplication lookup (the hot path in record_auction_view)
CREATE INDEX IF NOT EXISTS idx_auction_views_dedup
  ON public.auction_views (auction_id, viewer_uid, viewed_at DESC)
  WHERE viewer_uid IS NOT NULL;

-- ============================================================
-- Part D: RLS
-- ============================================================

ALTER TABLE public.auction_views ENABLE ROW LEVEL SECURITY;

-- No INSERT policy: all inserts must go through record_auction_view() SECURITY DEFINER RPC.
-- The function owner bypasses RLS; direct REST inserts from authenticated/anon roles are blocked.
DROP POLICY IF EXISTS clients_insert_views ON public.auction_views;

-- Policy: only active super_admins may SELECT view records (for analytics)
DROP POLICY IF EXISTS super_admin_read_views ON public.auction_views;
CREATE POLICY super_admin_read_views
  ON public.auction_views
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.super_admins
      WHERE id = auth.uid()
        AND account_status = 'active'
    )
  );

-- ============================================================
-- Part E: RPC record_auction_view
-- ============================================================

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
  v_existing_id   UUID;
  v_auction_region TEXT;
  v_new_view_id   UUID;
  v_normalized_device TEXT;
BEGIN
  -- Step 1: Normalize device_type
  IF p_device_type NOT IN ('mobile', 'web', 'unknown') THEN
    v_normalized_device := 'unknown';
  ELSE
    v_normalized_device := p_device_type;
  END IF;

  -- Step 2: Ownership check — caller may not forge another user's viewer_uid
  IF p_viewer_uid IS NOT NULL AND p_viewer_uid <> auth.uid() THEN
    RAISE EXCEPTION 'viewer_uid must match authenticated user';
  END IF;

  -- Step 2b: Serialize concurrent dedup checks for the same (auction_id, viewer_uid) pair.
  -- The lock is released automatically at transaction end.
  -- Uses two int4 args so distinct (auction_id, viewer_uid) pairs get distinct locks.
  IF p_viewer_uid IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(
      ('x' || left(p_auction_id::text, 8))::bit(32)::int,
      ('x' || left(p_viewer_uid::text, 8))::bit(32)::int
    );
  END IF;

  -- Step 3: 30-minute dedup check (only meaningful for authenticated viewers)
  IF p_viewer_uid IS NOT NULL THEN
    SELECT id
      INTO v_existing_id
      FROM public.auction_views
     WHERE auction_id = p_auction_id
       AND viewer_uid = p_viewer_uid
       AND viewed_at > now() - interval '30 minutes'
     ORDER BY viewed_at DESC
     LIMIT 1;

    IF v_existing_id IS NOT NULL THEN
      -- Duplicate within 30-minute window — do NOT insert, do NOT increment counter
      RETURN QUERY SELECT v_existing_id, false;
      RETURN;
    END IF;
  END IF;

  -- Step 4: Fetch auction region server-side (also validates auction exists and is not deleted)
  SELECT region
    INTO v_auction_region
    FROM public.auctions
   WHERE id = p_auction_id
     AND is_deleted = false;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Auction not found or deleted: %', p_auction_id;
  END IF;

  -- Step 5: Insert view record
  INSERT INTO public.auction_views (auction_id, viewer_uid, viewed_at, region, device_type)
  VALUES (p_auction_id, p_viewer_uid, now(), v_auction_region, v_normalized_device)
  RETURNING id INTO v_new_view_id;

  -- Step 6: Atomic counter increment
  UPDATE public.auctions
     SET views_count = views_count + 1
   WHERE id = p_auction_id;

  -- Step 7: Return new view id with is_new_view = true
  RETURN QUERY SELECT v_new_view_id, true;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_auction_view(UUID, UUID, TEXT) TO authenticated;

-- ============================================================
-- Part F: RPC end_auction_view
-- ============================================================

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
  -- Step 1: Validate duration range
  IF p_duration_seconds < 0 OR p_duration_seconds > 86400 THEN
    RAISE EXCEPTION 'view_duration_seconds must be between 0 and 86400';
  END IF;

  -- Step 2: UPDATE with ownership check + write-once guard
  -- viewer_uid = auth.uid()          → caller owns this view record
  -- view_duration_seconds IS NULL    → duration has not been set yet (write-once)
  UPDATE public.auction_views
     SET view_duration_seconds = p_duration_seconds
   WHERE id = p_view_id
     AND viewer_uid = auth.uid()
     AND view_duration_seconds IS NULL;

  GET DIAGNOSTICS v_rows_updated = ROW_COUNT;

  -- Step 3: Return true if a row was actually updated
  RETURN v_rows_updated > 0;
END;
$$;

GRANT EXECUTE ON FUNCTION public.end_auction_view(UUID, INTEGER) TO authenticated;

-- ============================================================
-- AFTER Validation Queries (run manually after applying)
-- ============================================================

-- V1: views_count column added with DEFAULT 0 and NOT NULL:
-- SELECT column_name, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name = 'views_count';
-- Expected: 1 row, column_default = '0', is_nullable = 'NO'

-- V2: auction_views table exists with correct columns:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auction_views'
-- ORDER BY ordinal_position;
-- Expected: 7 columns in order: id, auction_id, viewer_uid, viewed_at, region, device_type, view_duration_seconds

-- V3: RLS enabled on auction_views:
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'auction_views';
-- Expected: true

-- V4: Both RPCs are SECURITY DEFINER:
-- SELECT routine_name, security_type
-- FROM information_schema.routines
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('record_auction_view', 'end_auction_view');
-- Expected: 2 rows, both with security_type = 'DEFINER'

-- V5: Both RPCs are executable by authenticated role:
-- SELECT grantee, routine_name, privilege_type
-- FROM information_schema.routine_privileges
-- WHERE routine_schema = 'public'
--   AND routine_name IN ('record_auction_view', 'end_auction_view');
-- Expected: 2 rows with grantee = 'authenticated', privilege_type = 'EXECUTE'

-- V6: RLS policy exists on auction_views:
-- SELECT policyname, cmd FROM pg_policies
-- WHERE tablename = 'auction_views';
-- Expected: 1 row: 'super_admin_read_views' (SELECT)
-- Note: no INSERT policy — inserts are handled exclusively by SECURITY DEFINER record_auction_view()

-- V7: 30-minute dedup index exists:
-- SELECT indexname FROM pg_indexes
-- WHERE tablename = 'auction_views' AND indexname = 'idx_auction_views_dedup';
-- Expected: 1 row

-- ============================================================
-- ROLLBACK Script (run in reverse order of deployment)
-- ============================================================

-- REVOKE EXECUTE ON FUNCTION public.end_auction_view(UUID, INTEGER) FROM authenticated;
-- REVOKE EXECUTE ON FUNCTION public.record_auction_view(UUID, UUID, TEXT) FROM authenticated;
-- DROP FUNCTION IF EXISTS public.end_auction_view(UUID, INTEGER);
-- DROP FUNCTION IF EXISTS public.record_auction_view(UUID, UUID, TEXT);
-- DROP TABLE IF EXISTS public.auction_views CASCADE;
-- ALTER TABLE public.auctions DROP COLUMN IF EXISTS views_count;
