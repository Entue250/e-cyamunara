# INCIDENT RESPONSE GUIDE — E-CYAMUNARA
Last updated: 2026-04-23

This guide covers emergency procedures for the most likely production incidents.
Each section: DETECT → IMMEDIATE MITIGATION → ROOT CAUSE → RECOVERY.

---

## INCIDENT 1: RLS POLICY BREAKS

**Symptoms:**
- Clients can read other clients' data (bids, profiles, national IDs)
- Clients can insert bids directly (bypassing `place-bid` Edge Function)
- Admins can modify auctions in other regions
- Supabase Dashboard → Logs shows 200 OK on queries that should return 403

**Immediate Mitigation (< 5 minutes):**
1. In Supabase Dashboard → Database → Roles, temporarily REVOKE all SELECT/INSERT/UPDATE/DELETE from the `anon` role on affected tables:
   ```sql
   REVOKE ALL ON TABLE public.users FROM anon;
   REVOKE ALL ON TABLE public.bids FROM anon;
   ```
2. This blocks ALL API access until RLS is repaired. Notify users.

**Root Cause Investigation:**
1. Check when RLS was last changed:
   ```sql
   SELECT schemaname, tablename, rowsecurity
   FROM pg_tables WHERE schemaname = 'public';
   ```
2. Check policy definitions:
   ```sql
   SELECT * FROM pg_policies WHERE schemaname = 'public' ORDER BY tablename;
   ```
3. Check recent SQL editor history in Supabase Dashboard.

**Recovery:**
1. Restore the correct RLS policies from the last known-good migration file
2. Re-run Phase 3 security tests to verify
3. Restore `anon` permissions after RLS is confirmed working
4. Post-incident: add RLS policy change to deployment checklist

---

## INCIDENT 2: ADMIN ACCOUNT COMPROMISED

**Symptoms:**
- Unknown auction posts in a region
- Auction prices manipulated
- Clients being suspended without cause
- Admin logs show activity at unusual hours

**Immediate Mitigation (< 2 minutes):**
1. Super admin logs in → ManageAdmins screen → Suspend the compromised admin immediately
2. This sets `account_status = 'suspended'`. Next time the compromised admin navigates, router detects suspension and signs them out.
3. If super admin account itself is compromised, go to Supabase Dashboard → Authentication → Users → find the super admin's auth user → Disable their account directly.

**Root Cause Investigation:**
1. Check Supabase Dashboard → Logs → API to see what actions the compromised account performed:
   - Filter by auth.uid matching the admin's UID
   - Look for `INSERT`/`UPDATE`/`DELETE` on `auctions`, `bids`, `users`
2. Check Edge Function logs for `close-auction-manually` and `create-admin` invocations
3. Determine if credentials were phished, shared, or brute-forced

**Recovery:**
1. Suspend the compromised admin account (immediate)
2. Audit all actions taken during the compromise window
3. Roll back any unauthorized auction changes via SQL:
   ```sql
   -- Example: restore auction status
   UPDATE auctions SET auction_status = 'active' WHERE id = 'affected-auction-id';
   ```
4. If clients were wrongly suspended, activate them via `activate-user` Edge Function
5. Create a new admin account for the legitimate officer with a new phone number
6. Post-incident: enforce password complexity requirements, consider 2FA

---

## INCIDENT 3: EDGE FUNCTION ABUSED

**Symptoms:**
- `place-bid` invoked thousands of times in minutes (bid flooding)
- `create-admin` called by unauthorized user (new fake admins appear)
- `generate-report` called repeatedly (rate exhaustion)

**Immediate Mitigation:**
1. Go to Supabase Dashboard → Edge Functions → [function-name] → Pause/Disable
2. For `place-bid` abuse: check if bids are from real users or automated:
   ```sql
   SELECT bidder_uid, COUNT(*) as bid_count, MAX(created_at)
   FROM bids
   WHERE created_at > NOW() - INTERVAL '1 hour'
   GROUP BY bidder_uid
   ORDER BY bid_count DESC;
   ```
3. Suspend any bidder_uid with > 50 bids in 1 hour

**Root Cause:**
1. Edge Functions check `Authorization: Bearer <JWT>`. If the JWT validation passes, the caller is authenticated. Check if the abuse comes from:
   - Compromised admin account → see Incident 2
   - Valid but malicious client account → suspend via Edge Function
   - Expired JWT being replayed → Supabase validates JWT expiry automatically; this should not be possible

**Recovery:**
1. Re-enable the Edge Function after rate-limiting is understood
2. Add rate limiting to `place-bid`:
   ```typescript
   // In place-bid/index.ts — check bid frequency
   const recentBids = await supabase
     .from('bids')
     .select('id')
     .eq('bidder_uid', bidderUid)
     .gte('created_at', new Date(Date.now() - 60000).toISOString());
   if (recentBids.data?.length > 5) {
     return new Response(JSON.stringify({ error: 'Too many bids. Wait 1 minute.' }), { status: 429 });
   }
   ```
3. Delete fraudulent bids:
   ```sql
   DELETE FROM bids WHERE bidder_uid = 'fraudulent-uid' AND created_at > 'incident-start-time';
   -- Reset auction's current_highest_bid to actual highest remaining bid
   UPDATE auctions SET current_highest_bid = (
     SELECT MAX(bid_amount) FROM bids WHERE auction_id = 'affected-auction-id'
   ) WHERE id = 'affected-auction-id';
   ```

---

## INCIDENT 4: DATABASE CORRUPTION

**Symptoms:**
- `fromMap()` crashes on model parsing (unexpected null fields)
- Auctions show `current_highest_bid` lower than submitted bids
- `total_bids` counter out of sync with actual bids count
- Foreign key constraint errors in logs

**Immediate Mitigation:**
1. Do NOT make further writes — stop the bleeding
2. Enable Supabase read-only mode if available (Dashboard → Settings)
3. Take an immediate manual backup (Supabase Dashboard → Database → Backups → Create backup)

**Diagnosis:**
```sql
-- Check bid/auction sync
SELECT a.id, a.current_highest_bid, MAX(b.bid_amount) as actual_highest,
       a.total_bids, COUNT(b.id) as actual_bids
FROM auctions a
LEFT JOIN bids b ON b.auction_id = a.id
GROUP BY a.id, a.current_highest_bid, a.total_bids
HAVING a.current_highest_bid != COALESCE(MAX(b.bid_amount), a.starting_price)
   OR a.total_bids != COUNT(b.id);
```

**Recovery — Data Repair:**
```sql
-- Repair current_highest_bid and total_bids for all auctions
UPDATE auctions a
SET current_highest_bid = COALESCE(
    (SELECT MAX(bid_amount) FROM bids WHERE auction_id = a.id),
    a.starting_price
  ),
  total_bids = (SELECT COUNT(*) FROM bids WHERE auction_id = a.id),
  updated_at = NOW()
WHERE auction_status = 'active';
```

**Recovery — Full Restore:**
1. Supabase Dashboard → Database → Backups → Restore to pre-corruption timestamp
2. Re-run all Phase 3 security tests after restore
3. Notify affected users of any bids that were rolled back

---

## INCIDENT 5: AUTH OUTAGE (Supabase Auth down)

**Symptoms:**
- All login attempts fail with network/auth errors
- `AuthException` with "connection refused" or 500 status
- Existing sessions may still work (JWT validation is local)

**Immediate Response:**
1. Check Supabase status page: https://status.supabase.com
2. Do NOT trigger mass sign-outs (would lock out all users when service recovers)
3. Users with active sessions can continue using the app (Realtime + DB queries still work)
4. New logins will fail until Supabase recovers

**User Communication:**
- Push notification via OneSignal: "Login service is temporarily unavailable. If you're already logged in, the app continues to work normally."

**Recovery:**
1. No action needed — Supabase manages their own recovery
2. Once status page shows "operational", test login with a known account
3. Post-incident: consider caching last-known user profile in `shared_preferences` to allow read-only access during auth outages

---

## INCIDENT 6: SUSPENDED USER BYPASSES FRONTEND PROTECTION

**Symptoms:**
- A suspended user is navigating the app (visible in Supabase Realtime connection logs)
- Bids appear from a suspended user's UID

**Diagnosis:**
1. Check if the user is actually suspended:
   ```sql
   SELECT id, account_status FROM users WHERE id = 'suspect-uid';
   ```
2. Check if the bypass is via frontend (JWT still valid, router check failed) or backend (bids inserted directly via Supabase API with valid JWT)

**Frontend Bypass (JWT + router check failed):**
This should not happen after Phase 4 hardening. If it does:
1. Immediately suspend the account again (verify `account_status = 'suspended'` in DB)
2. Invalidate all sessions via Supabase Dashboard → Authentication → Users → [user] → "Sign out all devices"
3. Check if `_getUserRole()` in `app_router.dart` returned the wrong value — check DB for any trigger that might have re-activated the account

**Backend Bypass (direct API call with valid JWT):**
RLS should prevent this. If a bid was successfully inserted:
```sql
-- Remove fraudulent bids
DELETE FROM bids WHERE bidder_uid = 'suspended-uid';
-- Repair auction
UPDATE auctions SET
  current_highest_bid = COALESCE((SELECT MAX(bid_amount) FROM bids WHERE auction_id = 'affected-id'), starting_price),
  total_bids = (SELECT COUNT(*) FROM bids WHERE auction_id = 'affected-id')
WHERE id = 'affected-id';
```
Then immediately audit and tighten the RLS policy that allowed the insert.

**Recovery:**
1. Confirm RLS blocks the suspended user:
   ```sql
   -- Test as the suspended user's role
   SET ROLE authenticated;
   SET request.jwt.claims.sub = 'suspended-uid';
   SELECT * FROM auctions LIMIT 1; -- Should return empty
   ```
2. Re-run Phase 3 security test scenarios 1–4

---

## EMERGENCY CONTACTS & RESOURCES

| Resource | URL / Action |
|----------|-------------|
| Supabase Status | https://status.supabase.com |
| Supabase Dashboard | https://supabase.com/dashboard |
| Disable Edge Function | Dashboard → Edge Functions → [name] → Pause |
| Revoke Auth access | Dashboard → Authentication → Users → [user] → Actions |
| Manual backup | Dashboard → Database → Backups → Create backup |
| OneSignal broadcast | OneSignal Dashboard → Messages → New Push |
| Supabase Support | Dashboard → Support (Pro/Team plan) |

---

## SEVERITY LEVELS

| Severity | Definition | Response Time |
|----------|-----------|---------------|
| P1 CRITICAL | Data breach, suspended user bypass, RLS failure | < 15 min |
| P2 HIGH | Auth outage, bid manipulation, admin compromised | < 1 hour |
| P3 MEDIUM | Push notification failure, report generation failure | < 4 hours |
| P4 LOW | UI bug, cosmetic issue, slow query | Next business day |
