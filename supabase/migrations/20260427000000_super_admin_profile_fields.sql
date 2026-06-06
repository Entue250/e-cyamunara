-- ══════════════════════════════════════════════════════════════════════════════
-- E-CYAMUNARA — Patch: Super Admin profile fields + Storage RLS
-- 2026-04-27
--
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run (fully idempotent).
--
-- Fixes two production errors:
--   1. PGRST204 "column not found" — super_admins was missing photo_url and
--      updated_at, which the profile update payload writes.
--   2. StorageException 403 — profile-photos bucket had no RLS write policies.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Add missing columns to super_admins ────────────────────────────────────
-- The original super_admins table was created without photo_url and updated_at,
-- which the profile screen writes.  Both users and region_admins have these.
-- ADD COLUMN IF NOT EXISTS is idempotent — safe on a database that already has
-- these columns (e.g. after a partial prior fix).
alter table public.super_admins
  add column if not exists photo_url  text,
  add column if not exists updated_at timestamptz not null default now();


-- ── 2. Ensure the profile-photos bucket is public ────────────────────────────
-- A public bucket is required for getPublicUrl() to return an accessible URL
-- without a signed token.  File-level access (who can upload/delete) is still
-- enforced by the RLS policies in step 3.
-- ON CONFLICT ensures this is a no-op when the bucket already exists.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  true,
  5242880,                                               -- 5 MB per file
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public             = true,
  file_size_limit    = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];


-- ── 3. Storage RLS policies for profile-photos ────────────────────────────────
-- Drop before recreating so this block is safe to re-run.
drop policy if exists "profile_photos_read_all"   on storage.objects;
drop policy if exists "profile_photos_own_insert" on storage.objects;
drop policy if exists "profile_photos_own_update" on storage.objects;
drop policy if exists "profile_photos_own_delete" on storage.objects;

-- Any authenticated user may read profile photos (public URLs are accessible
-- without auth, but this policy covers direct API reads too).
create policy "profile_photos_read_all" on storage.objects
  for select to authenticated
  using (bucket_id = 'profile-photos');

-- Users may only write to their own folder: profile-photos/{uid}/...
-- storage.foldername(name) splits the path by '/' and returns a TEXT[] array.
-- For 'uid/avatar.jpg' → ARRAY['uid'], so [1] = uid.
-- This prevents user A from overwriting user B's photo.
create policy "profile_photos_own_insert" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "profile_photos_own_update" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "profile_photos_own_delete" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
