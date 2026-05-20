# EDGE FUNCTION RESILIENCE REPORT — E-CYAMUNARA
Last updated: 2026-04-23

---

## FUNCTION INVENTORY

| Function | Trigger | Auth Required | Critical |
|----------|---------|--------------|---------|
| place-bid | Client Flutter call | JWT (client) | YES — money |
| close-auction-manually | Admin Flutter call | JWT (admin) | YES — legal |
| create-admin | Super admin Flutter call | JWT (super_admin) | YES — access |
| suspend-user | Admin Flutter call | JWT (admin) | HIGH |
| activate-user | Admin Flutter call | JWT (admin) | HIGH |
| auto-close-auctions | pg_cron every 5 min | Service role key | YES — legal |
| on-new-auction | DB Webhook on INSERT | None (see FM-10) | MEDIUM |
| generate-report | Admin Flutter call | JWT (admin) | MEDIUM |
| send-auction-notification | DB Webhook/manual | None documented | MEDIUM |
| get-user-stats | Flutter call | JWT | LOW |
| cleanup-notifications | pg_cron weekly | None (see FM-09) | LOW |

---

## FUNCTION: place-bid

### Resilience issues

**Issue 1: Non-atomic bid + auction update**  
Steps 6 (insert bid) and 7 (update auction) are separate operations. If step 7 fails (e.g., DB timeout), the bid row exists with `bid_status = 'winning'` but the auction still shows the old `current_highest_bid`. The next bid will be calculated against wrong data.  
**Status:** No retry or rollback mechanism.  
**Fix:** Use a PostgreSQL stored procedure or advisory lock to make steps 6–7 atomic.

**Issue 2: Push notification failure in critical path**  
OneSignal calls are inside the main try/catch. A network error causes a 500 response even though the bid succeeded. Flutter shows "Bid failed". User re-bids, creating a duplicate.  
**Status:** Not fixed.  
**Fix:** Decouple push from bid commit. Return success after DB write; push asynchronously.

**Issue 3: No rate limiting**  
No check for how many bids a user has placed recently.  
**Status:** Not implemented.  
**Fix (when ready):**
```typescript
const { count } = await supabase.from('bids')
  .select('id', { count: 'exact', head: true })
  .eq('bidder_uid', bidder_uid)
  .gte('created_at', new Date(Date.now() - 60000).toISOString());
if (count && count >= 5) return json({ error: 'Too many bids. Wait 1 minute.' }, 429);
```

**Issue 4: Deno std@0.168.0 is pinned to an old version**  
Supabase's current Deno runtime uses `deno.land/std@0.224.0+`. Version 0.168.0 works but does not receive security patches.  
**Fix:** Update to `https://deno.land/std@0.224.0/http/server.ts` in all functions.

### Current resilience: POOR
Critical race conditions. Push failures cascade to bid failures. No idempotency key.

---

## FUNCTION: close-auction-manually

### Resilience issues

**Issue 1: Request body parsed after expensive auth queries**  
`req.json()` is called AFTER the auth and admin lookup queries (lines 33–65). If the request body is malformed, 3 DB queries are wasted.  
**Lower priority** — wasteful but not harmful.

**Issue 2: No guard against double-close (concurrent calls)**  
Two callers (e.g., admin + pg_cron timer) can both pass the `auction_status = 'active'` check before either commits the update. Winner is notified twice.  
**Status:** Not fixed.  
**Fix:** Atomic conditional UPDATE (see FM-18).

**Issue 3: No idempotency**  
If the Flutter client retries after a network timeout (the close succeeded but the response was lost), the second call gets "Auction is not active" (400) — reasonable behaviour, but the Flutter side should handle 400 gracefully as a possible success scenario.

### Current resilience: FAIR
Auth and suspension checks are solid. Double-close race exists.

---

## FUNCTION: create-admin

### Resilience issues

**Issue 1: Orphan auth account on insert failure**  
`auth.admin.createUser()` can succeed while `region_admins.insert()` fails. The phone number becomes permanently locked in Supabase Auth.  
**Status:** Not fixed.  
**Fix:** Catch insert failure, delete the orphan auth account, re-throw.

**Issue 2: temp_password in plaintext response**  
The temporary password is returned in the JSON response body. It is visible to anyone who can intercept the HTTP response (though Supabase Edge Functions always use HTTPS). There is no mechanism to force the admin to change the password on first login.  
**Status:** Accepted risk for v1.0.  
**Mitigation for v1.1:** Add `password_must_change: true` flag to `region_admins` table. Detect this in the router and force a password-change screen.

**Issue 3: created_by from request body, not JWT**  
The `created_by` field in the new admin's record is taken from the request body, not from the verified JWT of the calling super admin. A malicious super admin could attribute the creation to someone else.  
**Fix:**
```typescript
// Use user.id from the JWT, not from the body
await supabase.from('region_admins').insert({ ...adminData, created_by: user.id });
```

### Current resilience: FAIR
Auth and region uniqueness checks are good. Orphan account risk on failure.

---

## FUNCTION: suspend-user / activate-user

### Resilience issues

**Issue 1: ban_duration: '87600h' (10 years) vs permanent**  
The suspension sets a 10-year Supabase Auth ban. After 10 years, the auth ban auto-lifts even if `account_status` remains 'suspended'. The Flutter-side check reads `account_status` from the DB, which still says 'suspended'. So in practice this is fine, but it creates an inconsistency between Supabase Auth state and DB state after 2036.  
**Recommendation:** Use `ban_duration: 'none'` to remove a ban (already done in activate-user) and document that the auth ban is informational — the authoritative status is always `account_status` in the DB.

**Issue 2: No audit log**  
There is no record of WHO suspended WHOM and WHEN. If an admin abuses the suspend function, there is no trail beyond Supabase's API logs.  
**Fix:** Add an `account_actions` table or a `reason` + `suspended_by` + `suspended_at` column to the users table and write to it on every status change.

### Current resilience: GOOD
Auth checks are solid. Minor operational audit gap.

---

## FUNCTION: auto-close-auctions

### Resilience issues

**Issue 1: No authentication guard (CRITICAL)**  
Any HTTP POST to the function URL triggers mass auction closure.  
**Status:** Not fixed.  
**Fix:** Verify Authorization header matches service role key (see FM-06).

**Issue 2: No error isolation between auctions**  
Sequential loop — if one auction's processing throws (e.g., winner lookup fails), subsequent auctions may still be processed. But the winner for the failed auction is never notified, and the error is silently swallowed (the outer catch only catches errors from the whole `for` loop, not per-iteration).  
Actually looking at the code: the `for` loop has no try/catch around individual iterations. A throw from auction 3 would propagate to the outer catch and return a 500 — auctions 4–N are not processed.  
**Fix:** Wrap each auction's processing in its own try/catch. Log failed auctions. Return `{ closed: N, failed: M }`.

**Issue 3: No concurrency protection (pg_cron overlap)**  
If the cron fires at T+0 and the function is still running at T+5, the next cron fires and starts a new invocation. Both instances query `SELECT ... WHERE auction_status = 'active' AND end_date <= now`. They may select some of the same auctions. Both commit status = 'closed'. Winners notified twice, stats double-incremented.  
**Fix:** Use a Supabase advisory lock or an `is_closing` flag on the auction row, set atomically with the close.

**Issue 4: pg_cron is not configured**  
The function comment documents the pg_cron setup SQL but this must be manually executed. It is not automated. If it is never configured, auctions never auto-close.  
**Status:** Needs production setup verification.

### Current resilience: POOR (before fixes)
Missing authentication is a critical gap. Loop error handling is incomplete.

---

## FUNCTION: generate-report

### Resilience issues

**Issue 1: Suspended admin can generate reports (see FM-08)**  
Not fixed.

**Issue 2: Report is HTML, not true PDF**  
The function generates an HTML file named `.html` and describes it as "PDF-like". This is fine for a browser's print-to-PDF, but `download_url` returns a signed URL to an HTML file. If Flutter opens this URL expecting a PDF viewer, it will fail on iOS (which requires a `.pdf` MIME type for the PDF viewer).  
**Recommendation:** Either rename the file `.html` and open in a WebView, or integrate a real PDF service (e.g., Gotenberg, Puppeteer/Browserless) and return `application/pdf`.

**Issue 3: No pagination — report silently truncates at 100 rows**  
The HTML builder calls `auctions.slice(0, 100)`. Stats use all auctions. Detail table shows only 100.  
**Fix:** Add a note in the report: "Showing 100 of N auctions. Download full data as JSON for complete records."

### Current resilience: FAIR

---

## SHARED RESILIENCE GAPS (ALL FUNCTIONS)

1. **Deno std version is 0.168.0** — upgrade all functions to current stable.
2. **`esm.sh/@supabase/supabase-js@2`** — pinned to major version only. `@2` resolves to whatever the latest v2.x is at Deno cache time. Pin to a specific minor version (e.g., `@supabase/supabase-js@2.39.3`) for reproducible builds.
3. **No structured logging** — `console.error('error:', err)` dumps raw error objects. Supabase logs capture this but without request IDs or correlation to specific users/auctions. Add a request ID to every log line:
   ```typescript
   const requestId = crypto.randomUUID();
   console.error(JSON.stringify({ requestId, error: String(err), auction_id }));
   ```
4. **CORS allows all origins (`*`)** — appropriate for mobile SDK usage where Origin is not sent, but should be reviewed if the platform later serves web clients.

---

## RESILIENCE SCORES

| Function | Auth | Error isolation | Atomicity | Rate limit | Overall |
|----------|------|----------------|-----------|-----------|---------|
| place-bid | ✓ | ✗ | ✗ | ✗ | POOR |
| close-auction-manually | ✓ | ✓ | ✗ | N/A | FAIR |
| create-admin | ✓ | ✗ | ✗ | N/A | FAIR |
| suspend-user | ✓ | ✓ | ✓ | N/A | GOOD |
| activate-user | ✓ | ✓ | ✓ | N/A | GOOD |
| auto-close-auctions | ✗ | ✗ | ✗ | N/A | POOR |
| on-new-auction | ✗ | ✓ | N/A | ✗ | POOR |
| generate-report | partial | ✓ | N/A | N/A | FAIR |
| cleanup-notifications | ✗ | ✓ | N/A | N/A | POOR |
