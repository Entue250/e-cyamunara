# PRODUCTION DEPLOYMENT CHECKLIST — E-CYAMUNARA
Last updated: 2026-04-23

Run this checklist top-to-bottom before every production deployment.
Mark each item [x] DONE or leave [ ] TODO with a note.

---

## 1. ENVIRONMENT & CREDENTIALS

### 1.1 Supabase Project
- [ ] Confirm `SupabaseConstants.supabaseUrl` points to PRODUCTION project (not dev/staging)
- [ ] Confirm `SupabaseConstants.supabaseAnonKey` is the PRODUCTION anon key
- [ ] Confirm the anon key has not been rotated since last deploy (check Supabase Dashboard → Settings → API)
- [ ] Verify no service-role key is present anywhere in Flutter source code or `pubspec.yaml`
- [ ] Verify `.env` files (if any) are in `.gitignore`

### 1.2 OneSignal
- [ ] Confirm `SupabaseConstants.oneSignalAppId` is the PRODUCTION OneSignal app ID
- [ ] Confirm FCM/APNs push certificates are uploaded and valid in OneSignal dashboard
- [ ] Test push notification delivery to at least one real Android and one iOS device

### 1.3 Flutter Build Config
- [ ] Run `flutter build apk --release` (Android) — confirm no compile errors
- [ ] Run `flutter build ios --release` (iOS, if applicable) — confirm no compile errors
- [ ] Confirm `debugShowCheckedModeBanner: false` in `app.dart` ✓ (already set)
- [ ] Confirm `RealtimeLogLevel.error` in `main.dart` ✓ (already set)
- [ ] Run `flutter analyze` — confirm zero errors, zero warnings

---

## 2. SUPABASE BACKEND VERIFICATION

### 2.1 Database
- [ ] Run `SELECT COUNT(*) FROM auth.users` and `SELECT COUNT(*) FROM users` — counts should match (no orphan auth accounts from dev/testing)
- [ ] Verify all tables exist: `users`, `region_admins`, `super_admins`, `auctions`, `bids`, `feedback`, `districts`, `app_settings`, `notifications`
- [ ] Verify all columns have NOT NULL constraints where appropriate
- [ ] Run `supabase/migrations/20260423000000_add_production_indexes.sql` — confirm 15 indexes created
  - Pre-check: run the safety query at the top of the file first; must return 0 rows before proceeding
- [ ] Verify indexes exist: `SELECT indexname FROM pg_indexes WHERE schemaname = 'public' AND indexname LIKE 'idx_%' ORDER BY indexname;`
  - Expected: 15 rows
- [ ] Run a sample query to confirm RLS is enabled on every table:
  ```sql
  SELECT schemaname, tablename, rowsecurity
  FROM pg_tables
  WHERE schemaname = 'public'
  ORDER BY tablename;
  ```
  All `rowsecurity` values should be `true`.

### 2.2 RLS Policies
- [ ] Verify suspended client cannot read auctions (Phase 3 test: scenario 1)
- [ ] Verify suspended admin cannot update auction status (Phase 3 test: scenario 2)
- [ ] Verify client cannot insert bids directly (must use `place-bid` Edge Function)
- [ ] Verify client cannot read other clients' `national_id` data
- [ ] Verify region_admin can only read auctions in their own region

### 2.3 Triggers
- [ ] Verify `on_user_suspended` trigger fires on `account_status` update to 'suspended'
- [ ] Verify `prevent_bid_manipulation` trigger blocks direct bid inserts/updates

### 2.4 Edge Functions
Run each function deployment check:
- [ ] `supabase functions deploy place-bid` — confirm 200 OK with valid bid payload
- [ ] `supabase functions deploy close-auction-manually` — confirm 200 OK
- [ ] `supabase functions deploy create-admin` — confirm 200 OK with service-role key
- [ ] `supabase functions deploy suspend-user` — confirm 200 OK
- [ ] `supabase functions deploy activate-user` — confirm 200 OK
- [ ] `supabase functions deploy send-auction-notification` — confirm 200 OK
- [ ] `supabase functions deploy generate-report` — confirm 200 OK
- [ ] `supabase functions deploy auto-close-auctions` — confirm 401 with no/wrong key, 200 with correct service role key
- [ ] Verify Edge Function JWT verification is enabled (Supabase Dashboard → Edge Functions → Settings)
- [ ] Verify `place-bid` rejects bids below current highest (server-side test)
- [ ] Verify `close-auction-manually` sets winner correctly

### 2.4a pg_cron setup (REQUIRED before first live auction)
- [ ] Enable `pg_cron` extension: Dashboard → Database → Extensions → pg_cron → Enable
- [ ] Enable `pg_net` extension: Dashboard → Database → Extensions → pg_net → Enable
- [ ] Run `supabase/pg_cron_setup.sql` in SQL Editor (replace `YOUR_SERVICE_ROLE_KEY` first)
- [ ] Wait 5 minutes and verify: `SELECT jobname, status FROM cron.job_run_details ORDER BY run_started_at DESC LIMIT 5;`
  - Expected: `close-auctions` with `succeeded` status
- [ ] Confirm no auctions are stuck in `active` status past their `end_date`:
  `SELECT id, end_date FROM auctions WHERE auction_status = 'active' AND end_date < NOW();`
  - Expected: 0 rows

### 2.5 Storage Buckets
- [ ] Verify `auction-photos` bucket exists and is PUBLIC (photos are embedded in auction listings)
- [ ] Verify `profile-photos` bucket exists
- [ ] Verify `national-ids` bucket is PRIVATE (contains encrypted National IDs)
- [ ] Verify `reports` bucket is PRIVATE
- [ ] Verify storage RLS: only authenticated users can upload to their own paths
- [ ] Confirm no sensitive files in `auction-photos` or `profile-photos` buckets from dev testing

---

## 3. SUPER ADMIN ACCOUNT

- [ ] At least one super_admin row exists in `super_admins` table with `account_status = 'active'`
- [ ] Super admin can log in via `/admin/login` on the production build
- [ ] Super admin can access `/super/dashboard`
- [ ] Super admin can create a test region_admin (via `create-admin` Edge Function)
- [ ] Delete the test region_admin after verification

---

## 4. PRE-DEPLOY SMOKE TESTS

Run these manually on the release APK against the production Supabase instance:

### 4.1 Auth Flow
- [ ] Client registration (new phone number) → profile created in `users` table
- [ ] Client login → navigates to region select or home
- [ ] Admin login → navigates to admin dashboard
- [ ] Super admin login → navigates to super dashboard
- [ ] Incorrect password → error snackbar, no navigation
- [ ] Suspended account login → suspended error, no navigation

### 4.2 Bidding Flow
- [ ] Active auction loads with real-time bid price
- [ ] Place bid > current highest → success, bid confirmation screen
- [ ] Place bid ≤ current highest → rejected by Edge Function, error shown
- [ ] Auction detail shows correct countdown

### 4.3 Admin Flow
- [ ] Region admin can post a draft auction
- [ ] Region admin can publish the auction (change status to active)
- [ ] Region admin can view bids
- [ ] Region admin can close an auction manually

### 4.4 Super Admin Flow
- [ ] Super admin can view all region admins
- [ ] Super admin can create a new region admin

### 4.5 Notifications
- [ ] New auction posted → push notification received by clients in the region
- [ ] Outbid notification received when another bid is placed

---

## 5. DATABASE BACKUP

- [ ] Enable point-in-time recovery in Supabase Dashboard → Database → Backups
- [ ] Manually trigger a backup before deploying
- [ ] Confirm backup timestamp is recent (within 1 hour of deploy)
- [ ] Confirm backup restoration procedure has been tested at least once
- [ ] Document the backup retention policy (default: 7 days on Pro plan)

---

## 6. MONITORING

- [ ] Enable Supabase Dashboard → Reports → Database Usage alerts
- [ ] Set alert for: DB CPU > 70% for > 5 minutes
- [ ] Set alert for: DB connections > 80% of max
- [ ] Set alert for: Storage usage > 80% of plan limit
- [ ] Set alert for: Edge Function error rate > 5%
- [ ] Confirm at least one admin has email alerts configured

### Sentry crash reporting (REQUIRED — integrated in Phase A)
Sentry is now wired into `lib/main.dart`. You must supply the DSN at build time:
- [ ] Create a project at https://sentry.io (free tier covers pilot launch)
- [ ] Copy the Flutter DSN from Sentry → Project Settings → Client Keys
- [ ] Build with: `flutter build apk --release --dart-define=SENTRY_DSN=https://YOUR_KEY@sentry.io/PROJECT`
- [ ] Trigger a test error in a staging build and confirm it appears in Sentry within 60 seconds
- [ ] Set Sentry alert: email on first occurrence of any new issue

Without `--dart-define=SENTRY_DSN=...`, the app builds and runs normally but Sentry is inactive.

---

## 7. ROLLBACK PLAN

If the deployment causes critical issues:

### Step 1 — Immediate mitigation (< 5 minutes)
1. In Supabase Dashboard → Edge Functions, disable `place-bid` to halt new bids
2. In Supabase Dashboard → Authentication, disable new sign-ups temporarily
3. Notify users via OneSignal broadcast: "System maintenance in progress"

### Step 2 — App rollback (if Flutter build is the issue)
1. Publish the previous APK to the distribution channel
2. The previous APK targets the same Supabase backend — no DB changes needed

### Step 3 — Database rollback (if schema change caused the issue)
1. Go to Supabase Dashboard → Database → Backups
2. Restore to the most recent pre-deploy backup
3. Re-enable Edge Functions after restore is confirmed

### Step 4 — Verification after rollback
1. Test client login with a known-good account
2. Test bid placement on a live auction
3. Confirm push notifications are working
4. Re-enable sign-ups and `place-bid` Edge Function

---

## 8. POST-DEPLOY VERIFICATION

After deploying to production, verify within the first hour:

- [ ] Supabase Dashboard → Logs → API logs show no spike in 4xx/5xx errors
- [ ] Supabase Dashboard → Realtime shows active connections (not 0)
- [ ] `place-bid` Edge Function invocations appear in function logs
- [ ] At least one real user successfully logs in and views auctions
- [ ] Push notification test broadcast received on Android device
- [ ] No crash reports in the first 100 sessions (check Sentry → Issues; zero unhandled exceptions expected)
- [ ] Check `users.last_login` updates are being written correctly

---

## 9. KNOWN PRODUCTION RISKS (non-blocking)

These issues are documented and accepted for v1.0. They should be addressed in v1.1:

| Risk | Impact | Mitigation |
|------|--------|------------|
| Registration 2-step (signUp + INSERT can get out of sync) | User locked out permanently | Backend fix needed: DB trigger on `auth.users` to auto-create profile. Currently: user gets "contact support" error after INSERT failure. Orphan accounts must be cleaned up via admin intervention. |
| No query timeout handling | Loading spinners on slow connections | Add `.timeout(const Duration(seconds: 15))` to all async DB queries in v1.1 |
| Photos uploaded before v1.0 use random UUID paths | Cannot be deleted via `deleteAuction` | Grandfathered — only affects dev/test data. Production data will use `auctionId/` prefix. |
| `bidNotifierProvider` is global (not per-auction) | Stale `AsyncError` from one auction visible in another | Low impact — only affects error state display, not bid submission. Fix in v1.1 by converting to `StateNotifierProvider.family`. |
