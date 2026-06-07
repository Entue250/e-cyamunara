-- ══════════════════════════════════════════════════════════════════════════════
-- E-CYAMUNARA — Patch: Region admin read-access RLS policies
-- 2026-04-28
--
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run (idempotent — all DROPs use IF EXISTS).
--
-- Fixes:
--   1. Dashboard stat cards always show 0 for "Registered Clients" and
--      "Bids Today" — region admins could not SELECT from `users` or `bids`.
--   2. Client Management screen shows empty stat strip — same root cause.
--
-- Root cause: No RLS policy allowed region admins to read client rows from
-- the `users` table or bid rows from the `bids` table. Supabase defaults to
-- DENY for rows not explicitly allowed by a policy.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Drop stale policies before recreating ──────────────────────────────────
drop policy if exists "region_admins_read_own_region_clients" on public.users;
drop policy if exists "region_admins_read_auction_bids"       on public.bids;


-- ── 2. Region admins may SELECT clients in their own region ───────────────────
-- Subquery compares the authenticated UID against region_admins to get the
-- admin's assigned region, then allows access only to rows where the client's
-- region matches. Suspended admins are excluded.
create policy "region_admins_read_own_region_clients" on public.users
  for select to authenticated
  using (
    role = 'client'
    and region = (
      select ra.region
      from public.region_admins ra
      where ra.id = auth.uid()
        and ra.account_status = 'active'
      limit 1
    )
  );


-- ── 3. Region admins may SELECT bids for auctions they posted ─────────────────
-- This allows bidsToday count and CloseAuctionScreen bid list to load.
create policy "region_admins_read_auction_bids" on public.bids
  for select to authenticated
  using (
    exists (
      select 1
      from public.auctions a
      where a.id = bids.auction_id
        and a.posted_by_admin_uid = auth.uid()
    )
  );
