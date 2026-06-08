-- ══════════════════════════════════════════════════════════════════════════════
-- E-CYAMUNARA — SECURITY HARDENING PATCH
-- Run this file ONCE on an existing database in:
--   Supabase Dashboard → SQL Editor → New query → Run
--
-- Safe on existing data:
--   • ALTER TABLE only adds constraints (no existing rows violate them)
--   • CREATE OR REPLACE replaces functions/triggers non-destructively
--   • DROP POLICY + CREATE POLICY swaps policies atomically
--   • No data modifications, no table drops
-- ══════════════════════════════════════════════════════════════════════════════


-- ── STEP 1: Schema integrity fixes ───────────────────────────────────────────

-- super_admins.account_status was missing the CHECK constraint that users and
-- region_admins already had.  All existing rows have 'active' so this is safe.
-- Wrapped in a DO block so re-running this file does not fail with
-- "constraint already exists".
do $$ begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'super_admins_account_status_check'
       and conrelid = 'public.super_admins'::regclass
  ) then
    alter table public.super_admins
      add constraint super_admins_account_status_check
      check (account_status in ('active', 'suspended'));
  end if;
end $$;

-- auctions.current_highest_bid had no DEFAULT.  Omitting it on insert caused
-- a NOT NULL violation instead of a safe fallback.  Existing rows are unaffected.
-- ALTER COLUMN SET DEFAULT is idempotent — safe to re-run as-is.
alter table public.auctions
  alter column current_highest_bid set default 0;


-- ── STEP 2: get_my_role() — suspension-aware ─────────────────────────────────
-- Suspended users now return 'suspended' instead of their role string.
-- Every RLS policy that checks get_my_role() = '<role>' will automatically
-- deny suspended users because 'suspended' never equals any role name.

create or replace function get_my_role()
returns text as $$
  select coalesce(
    (select case when account_status = 'active' then role else 'suspended' end
       from public.super_admins  where id = auth.uid()),
    (select case when account_status = 'active' then role else 'suspended' end
       from public.region_admins where id = auth.uid()),
    (select case when account_status = 'active' then role else 'suspended' end
       from public.users         where id = auth.uid()),
    'unknown'
  );
$$ language sql security definer stable;


-- ── STEP 3: Cross-table role exclusivity ─────────────────────────────────────
-- A single auth.uid() must exist in EXACTLY ONE of: users, region_admins,
-- super_admins.  Fires BEFORE INSERT on all three tables.

create or replace function enforce_single_role()
returns trigger as $$
begin
  case TG_TABLE_NAME
    when 'users' then
      if exists (select 1 from public.super_admins  where id = NEW.id)
      or exists (select 1 from public.region_admins where id = NEW.id) then
        raise exception 'UID % already has a role in another table', NEW.id
          using errcode = 'unique_violation';
      end if;
    when 'region_admins' then
      if exists (select 1 from public.super_admins where id = NEW.id)
      or exists (select 1 from public.users        where id = NEW.id) then
        raise exception 'UID % already has a role in another table', NEW.id
          using errcode = 'unique_violation';
      end if;
    when 'super_admins' then
      if exists (select 1 from public.region_admins where id = NEW.id)
      or exists (select 1 from public.users         where id = NEW.id) then
        raise exception 'UID % already has a role in another table', NEW.id
          using errcode = 'unique_violation';
      end if;
  end case;
  return NEW;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_users_single_role         on public.users;
drop trigger if exists trg_region_admins_single_role on public.region_admins;
drop trigger if exists trg_super_admins_single_role  on public.super_admins;

create trigger trg_users_single_role
  before insert on public.users
  for each row execute function enforce_single_role();

create trigger trg_region_admins_single_role
  before insert on public.region_admins
  for each row execute function enforce_single_role();

create trigger trg_super_admins_single_role
  before insert on public.super_admins
  for each row execute function enforce_single_role();


-- ── STEP 4: Prevent self-unsuspend ───────────────────────────────────────────
-- Users and admins cannot change their own account_status.
-- auth.uid() IS NULL when running under the service role key (Edge Functions),
-- so service role is always permitted.  Regular JWT callers are blocked.

create or replace function prevent_self_account_status_change()
returns trigger as $$
begin
  if auth.uid() is not null and NEW.account_status <> OLD.account_status then
    raise exception 'account_status can only be changed by administrators'
      using errcode = 'insufficient_privilege';
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_users_status_lock         on public.users;
drop trigger if exists trg_region_admins_status_lock on public.region_admins;
drop trigger if exists trg_super_admins_status_lock  on public.super_admins;

create trigger trg_users_status_lock
  before update on public.users
  for each row execute function prevent_self_account_status_change();

create trigger trg_region_admins_status_lock
  before update on public.region_admins
  for each row execute function prevent_self_account_status_change();

create trigger trg_super_admins_status_lock
  before update on public.super_admins
  for each row execute function prevent_self_account_status_change();


-- ── STEP 5: Lock region_admin.region after creation ──────────────────────────
-- A region admin's region cannot be changed by anyone with a JWT.
-- Super admin operations via service role (no JWT → auth.uid() IS NULL) can
-- still reassign a region if ever needed.

create or replace function lock_admin_region()
returns trigger as $$
begin
  if auth.uid() is not null and NEW.region <> OLD.region then
    raise exception 'Region cannot be changed after account creation'
      using errcode = 'check_violation';
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_lock_admin_region on public.region_admins;

create trigger trg_lock_admin_region
  before update on public.region_admins
  for each row execute function lock_admin_region();


-- ── STEP 6: Block direct auction status → closed ─────────────────────────────
-- Only 'closed' transitions must go through the close-auction-manually Edge
-- Function (service role, auth.uid() IS NULL).  'cancelled' is allowed
-- directly — no winner/counter logic is needed for cancellations.

create or replace function prevent_direct_auction_close()
returns trigger as $$
begin
  if auth.uid() is null then
    return NEW;  -- service role: always allow
  end if;
  if NEW.auction_status <> OLD.auction_status
     and NEW.auction_status = 'closed' then
    raise exception
      'Auction closing requires the close-auction-manually function'
      using errcode = 'insufficient_privilege';
  end if;
  return NEW;
end;
$$ language plpgsql;

drop trigger if exists trg_prevent_direct_auction_close on public.auctions;

create trigger trg_prevent_direct_auction_close
  before update on public.auctions
  for each row execute function prevent_direct_auction_close();


-- ── STEP 7: Prevent deletion of the last super_admin ─────────────────────────
-- Guards against accidental system lockout where no super admin remains.

create or replace function prevent_last_super_admin_delete()
returns trigger as $$
begin
  if (select count(*) from public.super_admins) <= 1 then
    raise exception
      'Cannot delete the last super admin — the system would have no administrator'
      using errcode = 'restrict_violation';
  end if;
  return OLD;
end;
$$ language plpgsql security definer;

drop trigger if exists trg_prevent_last_super_admin_delete on public.super_admins;

create trigger trg_prevent_last_super_admin_delete
  before delete on public.super_admins
  for each row execute function prevent_last_super_admin_delete();


-- ── STEP 8: Drop and replace affected RLS policies ───────────────────────────

-- ── 8a. BIDS — remove direct client insert ───────────────────────────────────
-- The place-bid Edge Function uses the service role, which bypasses RLS.
-- Removing this policy closes the bypass path where a client could insert
-- a raw bid row with any amount, skipping all Edge Function validation.
drop policy if exists "bids_client_insert" on public.bids;
-- No replacement: bids are exclusively written by the place-bid Edge Function.


-- ── 8b. FEEDBACK — add region scope for region_admins ────────────────────────
drop policy if exists "feedback_admin_read" on public.feedback;

create policy "feedback_admin_read" on public.feedback for select
  using (
    get_my_role() = 'super_admin'
    or (get_my_role() = 'region_admin' and region = get_my_region())
  );


-- ── 8c. REGION ADMINS — fix fragile WITH CHECK subquery on own update ─────────
-- The original WITH CHECK used a self-referential subquery to prevent region
-- changes; the lock_admin_region trigger (Step 5) does this more safely.
-- Added get_my_role() = 'region_admin' so suspended admins are blocked.
drop policy if exists "admins_own_update" on public.region_admins;

create policy "admins_own_update" on public.region_admins for update
  using (auth.uid() = id and get_my_role() = 'region_admin');
-- account_status changes: blocked by trg_region_admins_status_lock
-- region changes:         blocked by trg_lock_admin_region


-- ── 8d. SUPER ADMINS — split FOR ALL into select + update (no self-delete) ────
drop policy if exists "super_own"        on public.super_admins;
drop policy if exists "super_own_select" on public.super_admins;
drop policy if exists "super_own_update" on public.super_admins;

create policy "super_own_select" on public.super_admins for select
  using (auth.uid() = id);

create policy "super_own_update" on public.super_admins for update
  using  (auth.uid() = id)
  with check (role = 'super_admin');
-- No DELETE policy for own row: service role only.
-- Last-admin deletion: blocked by trg_prevent_last_super_admin_delete.
-- account_status change: blocked by trg_super_admins_status_lock.
