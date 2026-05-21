# PRODUCTION OPERATIONS RUNBOOK — E-CYAMUNARA
Last updated: 2026-04-23

This runbook covers day-to-day and week-to-week operational tasks for the system operator.

---

## DAILY CHECKS (5 minutes)

### 1. Open Supabase Dashboard → Logs → Edge Functions
- Filter last 24 hours.
- Look for any `place-bid` error entries.
- If errors exist: check if they are push notification failures (non-critical) or bid commit failures (critical).

### 2. Check for Expired-But-Open Auctions
Run in SQL Editor:
```sql
SELECT id, item_name, end_date, region
FROM auctions
WHERE auction_status = 'active' AND end_date < NOW() - INTERVAL '10 minutes'
ORDER BY end_date;
```
- Empty result: pg_cron is working.
- Non-empty: pg_cron may be down. Manually close affected auctions via the admin app, then investigate pg_cron.

### 3. Check Bid/Auction Sync
Run in SQL Editor:
```sql
SELECT a.id, a.item_name, a.current_highest_bid, MAX(b.bid_amount) as actual_highest,
       a.total_bids, COUNT(b.id) as actual_count
FROM auctions a
LEFT JOIN bids b ON b.auction_id = a.id
WHERE a.auction_status = 'active'
GROUP BY a.id, a.item_name, a.current_highest_bid, a.total_bids
HAVING a.current_highest_bid != COALESCE(MAX(b.bid_amount), a.starting_price)
    OR a.total_bids != COUNT(b.id);
```
- Empty result: healthy.
- Non-empty: run repair SQL (see INCIDENT_RESPONSE_GUIDE.md INCIDENT 4).

---

## WEEKLY CHECKS (15 minutes)

### 1. Confirm Automated Backup Exists
Dashboard → Database → Backups. Latest backup should be < 25 hours old.

### 2. Check OneSignal Delivery Rate
OneSignal Dashboard → Delivery. Review the last 7 days. Delivery rate should be > 75%.
Below 75%: many stale player IDs. Consider running a "please open the app" campaign or implementing External User ID.

### 3. Review DB Size
Dashboard → Settings → Database. Track growth over time. Alert when approaching 80% of plan limit.

### 4. Review Edge Function Invocation Count
Dashboard → Edge Functions. Check total invocations for the week. If approaching the plan limit, plan upgrade.

### 5. Check notifications Table Size
```sql
SELECT COUNT(*) FROM notifications;
SELECT MIN(created_at) FROM notifications;
```
If min created_at is more than 35 days ago, the cleanup-notifications cron may not be running. Trigger it manually:
```
Supabase Dashboard → Edge Functions → cleanup-notifications → Invoke
```

---

## MONTHLY TASKS

### 1. Review RLS Policies
```sql
SELECT tablename, policyname, permissive, roles, cmd, qual
FROM pg_policies WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```
Verify all expected policies exist and none have been accidentally modified.

### 2. Check for Orphan Auth Accounts
```sql
-- Users in auth.users with no matching profile
SELECT u.id, u.email, u.created_at
FROM auth.users u
LEFT JOIN public.users pu ON pu.id = u.id
LEFT JOIN public.region_admins ra ON ra.id = u.id
LEFT JOIN public.super_admins sa ON sa.id = u.id
WHERE pu.id IS NULL AND ra.id IS NULL AND sa.id IS NULL
  AND u.created_at < NOW() - INTERVAL '1 hour';
```
These are orphan accounts from failed registrations. Delete them via:
```
Supabase Dashboard → Authentication → Users → [select orphan] → Delete user
```

### 3. Review Storage Usage
Dashboard → Storage. Check each bucket's size:
- `auction-photos`: main growth driver. Review if old auction photos need archiving.
- `reports`: delete old HTML report files manually if accumulating.
- `national-ids`: should grow proportionally to new users. Verify no unexpected files.

### 4. Test Backup Restore (Optional but Recommended)
Create a temporary Supabase project. Restore the latest backup. Run smoke test queries. Delete the temp project.

---

## ADMIN ACCOUNT LIFECYCLE

### Creating a New Region Admin
1. Super admin opens the ManageAdmins screen.
2. Taps "Add Admin", fills in the form.
3. Submits — this calls `create-admin` Edge Function.
4. The function returns a `temp_password`.
5. The super admin must securely communicate the temp password to the new admin officer.
6. The admin officer logs in for the first time with the temp password.
7. **Action required:** The admin officer should change their password immediately via Supabase Dashboard (until a first-login password change screen is implemented in v1.1).

### Suspending a Region Admin
1. Super admin → ManageAdmins → select admin → Suspend.
2. This calls `suspend-user` Edge Function.
3. The admin's auth account is banned for 10 years. Their `account_status` is set to 'suspended'.
4. Any currently active session for the suspended admin will be redirected to login on the next navigation (GoRouter detects suspension in `_getUserRole()`).

### Reactivating a Suspended Admin
1. Super admin → ManageAdmins → select admin → Activate.
2. This calls `activate-user` Edge Function.
3. The Supabase Auth ban is lifted. `account_status` set to 'active'.
4. The admin can log in again with their existing password.

---

## AUCTION LIFECYCLE

### Posting an Auction
1. Region admin → Post Auction → fill form (item name, category, starting price, end date, photos).
2. App calls `AuctionRepository.postAuction()`.
3. Photos uploaded to `auction-photos` bucket.
4. Auction row inserted with `auction_status = 'draft'`.
5. Admin publishes the auction (changes status to 'active').
6. `on-new-auction` Database Webhook fires → push notifications sent to all clients in the region.

### Closing an Auction
**Auto-close:** `auto-close-auctions` runs every 5 minutes. All auctions with `end_date <= now` are closed automatically.

**Manual close:** Region admin → Manage Auctions → select auction → Close Auction.
This calls `close-auction-manually`. Useful for emergencies (damaged item, fraud detected).

### Resolving a Disputed Auction
If the winner disputes the auction result or a bid was fraudulent:
1. Identify the fraudulent bid's `bidder_uid` and the `auction_id`.
2. Run:
   ```sql
   DELETE FROM bids WHERE bidder_uid = 'uid' AND auction_id = 'auction-id';
   UPDATE auctions SET
     current_highest_bid = COALESCE((SELECT MAX(bid_amount) FROM bids WHERE auction_id = 'auction-id'), starting_price),
     current_winner_uid  = (SELECT bidder_uid FROM bids WHERE auction_id = 'auction-id' ORDER BY bid_amount DESC LIMIT 1),
     total_bids = (SELECT COUNT(*) FROM bids WHERE auction_id = 'auction-id'),
     updated_at = NOW()
   WHERE id = 'auction-id';
   ```
3. Re-run the close-auction logic to notify the correct winner.
4. Document the incident in the admin notes.

---

## PG_CRON SETUP AND VERIFICATION

The following cron jobs must be configured in production. Run in Supabase SQL Editor:

```sql
-- 1. Auto-close expired auctions (every 5 minutes)
SELECT cron.schedule(
  'close-auctions',
  '*/5 * * * *',
  $$
    SELECT net.http_post(
      url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/auto-close-auctions',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body := '{}'::jsonb
    )
  $$
);

-- 2. Cleanup old notifications (every Sunday at midnight Kigali time)
SELECT cron.schedule(
  'cleanup-notifications',
  '0 22 * * 0',
  $$
    SELECT net.http_post(
      url := 'https://YOUR-PROJECT-REF.supabase.co/functions/v1/cleanup-notifications',
      headers := '{"Authorization":"Bearer YOUR_SERVICE_ROLE_KEY","Content-Type":"application/json"}'::jsonb,
      body := '{}'::jsonb
    )
  $$
);
```

**Verify jobs are running:**
```sql
SELECT jobid, jobname, schedule, command, active, last_run_time, next_run_time
FROM cron.job_run_details
ORDER BY last_run_time DESC
LIMIT 10;
```

**Replace** `YOUR-PROJECT-REF` and `YOUR_SERVICE_ROLE_KEY` with production values.
Store the service role key only in Supabase Vault or environment secrets — never in source code.

---

## COMMON SUPPORT SCENARIOS

### "I can't register — it says my phone number is already taken"

Possible causes:
1. User tried registering before and got a partial failure (auth account created, profile not).
2. Someone else registered the same number.

Check:
```sql
-- Find if phone number exists in any table
SELECT 'users' as tbl, id, phone_number FROM users WHERE phone_number = '07XXXXXXXX'
UNION ALL
SELECT 'region_admins', id, phone_number FROM region_admins WHERE phone_number = '07XXXXXXXX';
```

Check Supabase Auth:
```
Dashboard → Authentication → Users → search by email (rw07XXXXXXXX@ecyamunara.rw)
```

If auth account exists but no profile: delete the auth account, let user re-register.

### "I placed a bid but my phone shows 'Bid failed' and I was charged"

The most common scenario is FM-03: the bid was committed to the DB but OneSignal failed, causing `place-bid` to return 500.

Check:
```sql
SELECT * FROM bids WHERE bidder_uid = 'uid' ORDER BY created_at DESC LIMIT 5;
```

If a bid exists in the DB for the claimed amount and time: the bid is valid. Confirm to the user that their bid is registered. The auction detail screen should now show their bid price.

### "Push notifications stopped working"

Likely stale OneSignal player ID. The user must:
1. Force-close and reopen the app.
2. Log out and log back in (this calls `refreshPlayerId()` which updates the DB).

If the problem persists, check OneSignal Dashboard → Users → find by External ID (or player ID) → verify device token is valid.

---

## EMERGENCY CONTACTS QUICK REFERENCE

| Resource | Action |
|----------|--------|
| System down | Check https://status.supabase.com first |
| Halt all bidding | Pause `place-bid` in Dashboard → Edge Functions |
| Block all logins | Dashboard → Authentication → disable sign-ins |
| Push broadcast | OneSignal Dashboard → New Push → All Users |
| DB emergency | Dashboard → Database → enable read-only mode |
| Supabase support | Dashboard → Support (Pro plan ticket) |

For full incident procedures, see `INCIDENT_RESPONSE_GUIDE.md`.
