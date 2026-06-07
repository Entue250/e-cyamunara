-- ══════════════════════════════════════════════════════════════════════════════
-- E-CYAMUNARA — Patch: auction-photos bucket RLS policies
-- 2026-04-28
--
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run (fully idempotent — all DROPs use IF EXISTS).
--
-- Fixes: StorageException 403 when region admins post auctions.
--
-- Root cause: auction-photos bucket existed but had no INSERT/SELECT/DELETE
-- policies, so every upload was rejected by the default-deny RLS.
--
-- Upload path convention (set in auction_repository.dart):
--   {admin_uid}/{auction_id}/{uuid}.jpg
-- The first path component is the admin UID, matching auth.uid(), which is
-- exactly what (storage.foldername(name))[1] checks.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Ensure bucket exists and is public ─────────────────────────────────────
-- Public = true means getPublicUrl() returns an accessible URL with no token.
-- File-level security is still enforced by the RLS policies below.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'auction-photos',
  'auction-photos',
  true,
  10485760,                                              -- 10 MB per photo
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public             = true,
  file_size_limit    = 10485760,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];


-- ── 2. Drop any stale policies before recreating ──────────────────────────────
drop policy if exists "auction_photos_read_all"      on storage.objects;
drop policy if exists "auction_photos_admin_insert"  on storage.objects;
drop policy if exists "auction_photos_admin_update"  on storage.objects;
drop policy if exists "auction_photos_admin_delete"  on storage.objects;


-- ── 3. Public read — anyone can view auction photos ───────────────────────────
create policy "auction_photos_read_all" on storage.objects
  for select
  using (bucket_id = 'auction-photos');


-- ── 4. Region admin INSERT ────────────────────────────────────────────────────
-- Path: {admin_uid}/{auction_id}/{uuid}.jpg
-- (storage.foldername(name))[1] extracts the first path segment = admin_uid.
-- We also verify the caller exists in region_admins and is active, so
-- suspended admins and clients cannot upload.
create policy "auction_photos_admin_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'auction-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.region_admins
      where id = auth.uid()
        and account_status = 'active'
    )
  );


-- ── 5. Region admin UPDATE (upsert support) ───────────────────────────────────
create policy "auction_photos_admin_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'auction-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.region_admins
      where id = auth.uid()
        and account_status = 'active'
    )
  );


-- ── 6. Region admin DELETE ────────────────────────────────────────────────────
-- Admins may only delete from their own folder.
create policy "auction_photos_admin_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'auction-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1 from public.region_admins
      where id = auth.uid()
        and account_status = 'active'
    )
  );
