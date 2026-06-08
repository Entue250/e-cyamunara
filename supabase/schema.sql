-- ══════════════════════════════════════════════════════════════════════════════
-- E-CYAMUNARA — Complete Supabase PostgreSQL Schema (HARDENED)
-- Run this entire file for a fresh install:
--   Supabase Dashboard → SQL Editor → New query → Run
-- For existing databases, run schema_hardening_patch.sql instead.
-- ══════════════════════════════════════════════════════════════════════════════

create extension if not exists "uuid-ossp";

-- ══════════════════════════════════════════════════════════════════════════════
-- TABLES
-- ══════════════════════════════════════════════════════════════════════════════

-- ── USERS (clients) ───────────────────────────────────────────────────────────
create table if not exists public.users (
  id                   uuid primary key references auth.users(id) on delete cascade,
  full_names           text not null,
  national_id          text not null,
  phone_number         text not null unique,
  district             text not null,
  province             text not null,
  region               text not null,
  role                 text not null default 'client' check (role = 'client'),
  account_status       text not null default 'active' check (account_status in ('active','suspended')),
  profile_photo_url    text,
  onesignal_player_id  text,
  total_bids_placed    integer not null default 0,
  total_auctions_won   integer not null default 0,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  last_login           timestamptz
);

-- ── REGION ADMINS ─────────────────────────────────────────────────────────────
create table if not exists public.region_admins (
  id                    uuid primary key references auth.users(id) on delete cascade,
  full_names            text not null,
  national_id           text not null,
  phone_number          text not null unique,
  region                text not null unique,
  role                  text not null default 'region_admin' check (role = 'region_admin'),
  account_status        text not null default 'active' check (account_status in ('active','suspended')),
  profile_photo_url     text,
  onesignal_player_id   text,
  permissions           jsonb not null default '{"post_auctions":true,"manage_clients":true,"view_reports":true,"close_auctions":true}',
  total_auctions_posted integer not null default 0,
  total_auctions_closed integer not null default 0,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  last_login            timestamptz,
  created_by            uuid references auth.users(id)
);

-- ── SUPER ADMINS ──────────────────────────────────────────────────────────────
create table if not exists public.super_admins (
  id                   uuid primary key references auth.users(id) on delete cascade,
  full_names           text not null,
  phone_number         text not null unique,
  role                 text not null default 'super_admin' check (role = 'super_admin'),
  account_status       text not null default 'active'
                         check (account_status in ('active','suspended')),
  onesignal_player_id  text,
  created_at           timestamptz not null default now(),
  last_login           timestamptz
);

-- ── AUCTIONS ──────────────────────────────────────────────────────────────────
create table if not exists public.auctions (
  id                   uuid primary key default uuid_generate_v4(),
  item_name            text not null,
  category             text not null check (category in ('car','motorcycle','bicycle')),
  plate_number         text not null,
  condition            text not null check (condition in ('excellent','good','fair','poor')),
  description          text not null,
  photo_urls           text[] not null default '{}',
  starting_price       numeric(15,2) not null check (starting_price > 0),
  current_highest_bid  numeric(15,2) not null default 0,
  current_winner_uid   uuid references public.users(id),
  current_winner_name  text,
  total_bids           integer not null default 0,
  region               text not null,
  posted_by_admin_uid  uuid not null references public.region_admins(id),
  posted_by_admin_name text not null,
  auction_status       text not null default 'draft'
                         check (auction_status in ('draft','active','closed','cancelled')),
  start_date           timestamptz not null,
  end_date             timestamptz not null check (end_date > start_date),
  closed_at            timestamptz,
  winner_uid           uuid references public.users(id),
  winner_name          text,
  winning_amount       numeric(15,2),
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now()
);

-- ── BIDS ──────────────────────────────────────────────────────────────────────
create table if not exists public.bids (
  id               uuid primary key default uuid_generate_v4(),
  auction_id       uuid not null references public.auctions(id) on delete cascade,
  bidder_uid       uuid not null references public.users(id),
  bidder_name      text not null,
  bidder_phone     text not null,
  bidder_district  text not null,
  bid_amount       numeric(15,2) not null check (bid_amount > 0),
  bid_status       text not null default 'winning' check (bid_status in ('winning','outbid')),
  created_at       timestamptz not null default now()
);

-- ── FEEDBACK ──────────────────────────────────────────────────────────────────
create table if not exists public.feedback (
  id              uuid primary key default uuid_generate_v4(),
  client_uid      uuid not null references public.users(id),
  client_name     text not null,
  auction_id      uuid references public.auctions(id),
  item_name       text not null,
  region          text not null,
  star_rating     integer not null check (star_rating between 1 and 5),
  selected_tags   text[] not null default '{}',
  comment         text not null default '' check (char_length(comment) <= 250),
  would_recommend boolean not null default false,
  created_at      timestamptz not null default now()
);

-- ── DISTRICTS ─────────────────────────────────────────────────────────────────
create table if not exists public.districts (
  id            uuid primary key default uuid_generate_v4(),
  district_name text not null unique,
  province      text not null,
  region        text not null
);

-- ── NOTIFICATIONS ─────────────────────────────────────────────────────────────
create table if not exists public.notifications (
  id         uuid primary key default uuid_generate_v4(),
  user_uid   uuid not null references auth.users(id) on delete cascade,
  title      text not null,
  body       text not null,
  type       text not null check (type in ('new_auction','winning','outbid','won','system')),
  is_read    boolean not null default false,
  auction_id uuid references public.auctions(id),
  created_at timestamptz not null default now()
);

-- ── APP SETTINGS ──────────────────────────────────────────────────────────────
create table if not exists public.app_settings (
  id                   text primary key default 'config',
  app_version          text not null default '1.0.0',
  maintenance_mode     boolean not null default false,
  max_bid_increment    numeric(15,2) not null default 10000,
  auction_auto_close   boolean not null default true,
  notification_enabled boolean not null default true,
  updated_at           timestamptz not null default now(),
  updated_by           uuid references auth.users(id)
);

insert into public.app_settings (id) values ('config') on conflict do nothing;

-- ══════════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════

-- Returns the caller's role, or 'suspended' if their account is not active,
-- or 'unknown' if the UID is not found in any role table.
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

create or replace function get_my_region()
returns text as $$
  select region from public.region_admins where id = auth.uid();
$$ language sql security definer stable;

-- ══════════════════════════════════════════════════════════════════════════════
-- INDEXES
-- ══════════════════════════════════════════════════════════════════════════════

create index if not exists idx_auctions_region_status   on public.auctions(region, auction_status);
create index if not exists idx_auctions_region_category on public.auctions(region, category, auction_status);
create index if not exists idx_auctions_status_end      on public.auctions(auction_status, end_date);
create index if not exists idx_auctions_admin           on public.auctions(posted_by_admin_uid);
create index if not exists idx_bids_auction             on public.bids(auction_id);
create index if not exists idx_bids_bidder              on public.bids(bidder_uid, created_at desc);
create index if not exists idx_bids_status              on public.bids(auction_id, bid_status);
create index if not exists idx_feedback_region          on public.feedback(region, created_at desc);
create index if not exists idx_notifications_user       on public.notifications(user_uid, created_at desc);
create index if not exists idx_notifications_unread     on public.notifications(user_uid, is_read);
create index if not exists idx_users_region             on public.users(region, account_status);

-- ══════════════════════════════════════════════════════════════════════════════
-- TRIGGER FUNCTIONS
-- ══════════════════════════════════════════════════════════════════════════════

-- Enforces that a UID can exist in only ONE of the three role tables.
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

-- Blocks account_status changes from JWT-authenticated callers.
-- auth.uid() IS NULL under the service role key, so Edge Functions are exempt.
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

-- Prevents a region_admin from changing their own region via a JWT.
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

-- Blocks direct status transition to 'closed' by JWT callers.
-- 'cancelled' is allowed directly (no winner/counter logic needed).
-- Only service role (close-auction-manually Edge Function) may set 'closed'.
create or replace function prevent_direct_auction_close()
returns trigger as $$
begin
  if auth.uid() is null then return NEW; end if;
  if NEW.auction_status <> OLD.auction_status
     and NEW.auction_status = 'closed' then
    raise exception
      'Auction closing requires the close-auction-manually function'
      using errcode = 'insufficient_privilege';
  end if;
  return NEW;
end;
$$ language plpgsql;

-- Prevents deletion of the final super_admin row (system lockout guard).
create or replace function prevent_last_super_admin_delete()
returns trigger as $$
begin
  if (select count(*) from public.super_admins) <= 1 then
    raise exception
      'Cannot delete the last super admin — system would have no administrator'
      using errcode = 'restrict_violation';
  end if;
  return OLD;
end;
$$ language plpgsql security definer;

-- ══════════════════════════════════════════════════════════════════════════════
-- TRIGGERS
-- DROP IF EXISTS before each CREATE so this file is safe to re-run on an
-- existing database (e.g. after running schema_hardening_patch.sql first).
-- ══════════════════════════════════════════════════════════════════════════════

drop trigger if exists trg_users_single_role         on public.users;
drop trigger if exists trg_region_admins_single_role on public.region_admins;
drop trigger if exists trg_super_admins_single_role  on public.super_admins;
drop trigger if exists trg_users_status_lock         on public.users;
drop trigger if exists trg_region_admins_status_lock on public.region_admins;
drop trigger if exists trg_super_admins_status_lock  on public.super_admins;
drop trigger if exists trg_lock_admin_region         on public.region_admins;
drop trigger if exists trg_prevent_direct_auction_close on public.auctions;
drop trigger if exists trg_prevent_last_super_admin_delete on public.super_admins;

create trigger trg_users_single_role
  before insert on public.users
  for each row execute function enforce_single_role();

create trigger trg_region_admins_single_role
  before insert on public.region_admins
  for each row execute function enforce_single_role();

create trigger trg_super_admins_single_role
  before insert on public.super_admins
  for each row execute function enforce_single_role();

create trigger trg_users_status_lock
  before update on public.users
  for each row execute function prevent_self_account_status_change();

create trigger trg_region_admins_status_lock
  before update on public.region_admins
  for each row execute function prevent_self_account_status_change();

create trigger trg_super_admins_status_lock
  before update on public.super_admins
  for each row execute function prevent_self_account_status_change();

create trigger trg_lock_admin_region
  before update on public.region_admins
  for each row execute function lock_admin_region();

create trigger trg_prevent_direct_auction_close
  before update on public.auctions
  for each row execute function prevent_direct_auction_close();

create trigger trg_prevent_last_super_admin_delete
  before delete on public.super_admins
  for each row execute function prevent_last_super_admin_delete();

-- ══════════════════════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ══════════════════════════════════════════════════════════════════════════════

alter table public.users          enable row level security;
alter table public.region_admins  enable row level security;
alter table public.super_admins   enable row level security;
alter table public.auctions       enable row level security;
alter table public.bids           enable row level security;
alter table public.feedback       enable row level security;
alter table public.districts      enable row level security;
alter table public.notifications  enable row level security;
alter table public.app_settings   enable row level security;

-- Drop all policies before recreating so this file is safe to re-run.

drop policy if exists "users_own_select"    on public.users;
drop policy if exists "users_own_insert"    on public.users;
drop policy if exists "users_own_update"    on public.users;
drop policy if exists "users_admin_select"  on public.users;
drop policy if exists "users_super_all"     on public.users;

drop policy if exists "admins_own_select"   on public.region_admins;
drop policy if exists "admins_own_update"   on public.region_admins;
drop policy if exists "admins_admin_select" on public.region_admins;
drop policy if exists "admins_super_all"    on public.region_admins;

-- Old single policy name (pre-hardening) and new split names
drop policy if exists "super_own"           on public.super_admins;
drop policy if exists "super_own_select"    on public.super_admins;
drop policy if exists "super_own_update"    on public.super_admins;

drop policy if exists "auctions_read_all"      on public.auctions;
drop policy if exists "auctions_admin_insert"  on public.auctions;
drop policy if exists "auctions_admin_update"  on public.auctions;
drop policy if exists "auctions_super_delete"  on public.auctions;

drop policy if exists "bids_read_all"      on public.bids;
drop policy if exists "bids_client_insert" on public.bids;

drop policy if exists "feedback_admin_read"    on public.feedback;
drop policy if exists "feedback_client_insert" on public.feedback;
drop policy if exists "feedback_super_all"     on public.feedback;

drop policy if exists "districts_read_all"    on public.districts;
drop policy if exists "districts_super_write" on public.districts;

drop policy if exists "notif_own_read"   on public.notifications;
drop policy if exists "notif_own_update" on public.notifications;
drop policy if exists "notif_own_delete" on public.notifications;

drop policy if exists "settings_read_all"    on public.app_settings;
drop policy if exists "settings_super_write" on public.app_settings;

-- ── USERS ─────────────────────────────────────────────────────────────────────
create policy "users_own_select" on public.users for select
  using (auth.uid() = id);

create policy "users_own_insert" on public.users for insert
  with check (auth.uid() = id);

create policy "users_own_update" on public.users for update
  using  (auth.uid() = id and get_my_role() = 'client')
  with check (role = 'client');

create policy "users_admin_select" on public.users for select
  using (get_my_role() = 'region_admin' and region = get_my_region());

create policy "users_super_all" on public.users for all
  using (get_my_role() = 'super_admin');

-- ── REGION ADMINS ─────────────────────────────────────────────────────────────
create policy "admins_own_select" on public.region_admins for select
  using (auth.uid() = id);

-- account_status changes: blocked by trg_region_admins_status_lock
-- region changes:         blocked by trg_lock_admin_region
create policy "admins_own_update" on public.region_admins for update
  using (auth.uid() = id and get_my_role() = 'region_admin');

create policy "admins_admin_select" on public.region_admins for select
  using (get_my_role() = 'region_admin');

create policy "admins_super_all" on public.region_admins for all
  using (get_my_role() = 'super_admin');

-- ── SUPER ADMINS ──────────────────────────────────────────────────────────────
-- No self-delete: trg_prevent_last_super_admin_delete guards final row.
-- No DELETE policy for self: only service role may delete super_admin rows.
create policy "super_own_select" on public.super_admins for select
  using (auth.uid() = id);

create policy "super_own_update" on public.super_admins for update
  using  (auth.uid() = id)
  with check (role = 'super_admin');

-- ── AUCTIONS ──────────────────────────────────────────────────────────────────
create policy "auctions_read_all" on public.auctions for select
  using (get_my_role() in ('client', 'region_admin', 'super_admin'));

create policy "auctions_admin_insert" on public.auctions for insert
  with check (
    get_my_role() = 'region_admin'
    and region = get_my_region()
    and posted_by_admin_uid = auth.uid()
  );

-- Direct status → closed/cancelled blocked by trg_prevent_direct_auction_close.
create policy "auctions_admin_update" on public.auctions for update
  using (
    (get_my_role() = 'region_admin' and region = get_my_region())
    or get_my_role() = 'super_admin'
  );

create policy "auctions_super_delete" on public.auctions for delete
  using (get_my_role() = 'super_admin');

-- ── BIDS ──────────────────────────────────────────────────────────────────────
create policy "bids_read_all" on public.bids for select
  using (auth.uid() is not null);

-- No client INSERT policy: bids are exclusively written by the place-bid
-- Edge Function via service role, which bypasses RLS entirely.

-- ── FEEDBACK ──────────────────────────────────────────────────────────────────
-- Region admins see only their own region's feedback.
create policy "feedback_admin_read" on public.feedback for select
  using (
    get_my_role() = 'super_admin'
    or (get_my_role() = 'region_admin' and region = get_my_region())
  );

create policy "feedback_client_insert" on public.feedback for insert
  with check (auth.uid() = client_uid and get_my_role() = 'client');

create policy "feedback_super_all" on public.feedback for all
  using (get_my_role() = 'super_admin');

-- ── DISTRICTS ─────────────────────────────────────────────────────────────────
create policy "districts_read_all" on public.districts for select
  using (auth.uid() is not null);

create policy "districts_super_write" on public.districts for all
  using (get_my_role() = 'super_admin');

-- ── NOTIFICATIONS ─────────────────────────────────────────────────────────────
create policy "notif_own_read" on public.notifications for select
  using (auth.uid() = user_uid);

create policy "notif_own_update" on public.notifications for update
  using (auth.uid() = user_uid);

create policy "notif_own_delete" on public.notifications for delete
  using (auth.uid() = user_uid);

-- ── APP SETTINGS ──────────────────────────────────────────────────────────────
create policy "settings_read_all" on public.app_settings for select
  using (auth.uid() is not null);

create policy "settings_super_write" on public.app_settings for all
  using (get_my_role() = 'super_admin');

-- ══════════════════════════════════════════════════════════════════════════════
-- REALTIME
-- Each ADD TABLE is wrapped in a block that skips silently if the table is
-- already in the publication, making this section safe to re-run.
-- ══════════════════════════════════════════════════════════════════════════════
do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'auctions'
  ) then
    alter publication supabase_realtime add table public.auctions;
  end if;
end $$;

do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'bids'
  ) then
    alter publication supabase_realtime add table public.bids;
  end if;
end $$;

do $$ begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end $$;

-- ══════════════════════════════════════════════════════════════════════════════
-- SEED: ALL 30 RWANDA DISTRICTS
-- ══════════════════════════════════════════════════════════════════════════════
insert into public.districts (district_name, province, region) values
  ('Gasabo',     'Kigali City',        'Central'),
  ('Kicukiro',   'Kigali City',        'Central'),
  ('Nyarugenge', 'Kigali City',        'Central'),
  ('Bugesera',   'Eastern Province',   'Eastern'),
  ('Gatsibo',    'Eastern Province',   'Eastern'),
  ('Kayonza',    'Eastern Province',   'Eastern'),
  ('Kirehe',     'Eastern Province',   'Eastern'),
  ('Ngoma',      'Eastern Province',   'Eastern'),
  ('Nyagatare',  'Eastern Province',   'Eastern'),
  ('Rwamagana',  'Eastern Province',   'Eastern'),
  ('Karongi',    'Western Province',   'Western'),
  ('Ngororero',  'Western Province',   'Western'),
  ('Nyabihu',    'Western Province',   'Western'),
  ('Nyamasheke', 'Western Province',   'Western'),
  ('Rubavu',     'Western Province',   'Western'),
  ('Rusizi',     'Western Province',   'Western'),
  ('Rutsiro',    'Western Province',   'Western'),
  ('Burera',     'Northern Province',  'Northern'),
  ('Gakenke',    'Northern Province',  'Northern'),
  ('Gicumbi',    'Northern Province',  'Northern'),
  ('Musanze',    'Northern Province',  'Northern'),
  ('Rulindo',    'Northern Province',  'Northern'),
  ('Gisagara',   'Southern Province',  'Southern'),
  ('Huye',       'Southern Province',  'Southern'),
  ('Kamonyi',    'Southern Province',  'Southern'),
  ('Muhanga',    'Southern Province',  'Southern'),
  ('Nyamagabe',  'Southern Province',  'Southern'),
  ('Nyanza',     'Southern Province',  'Southern'),
  ('Nyaruguru',  'Southern Province',  'Southern'),
  ('Ruhango',    'Southern Province',  'Southern')
on conflict (district_name) do nothing;
