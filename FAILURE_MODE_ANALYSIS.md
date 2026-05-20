# FAILURE MODE ANALYSIS — E-CYAMUNARA
Last updated: 2026-04-23
Scope: Full system — Flutter Frontend, Edge Functions, Supabase DB, Realtime, Storage, Operations

Each finding: Component → Risk → How it fails in production → Severity → Safest fix → Implementation location.

---

## SCOPE 1: EDGE FUNCTIONS

### FM-01 — RACE CONDITION IN PLACE-BID (TOCTOU)
**Component:** `supabase/functions/place-bid/index.ts`
**Risk:** Two simultaneous bids can both pass the `bid_amount > current_highest_bid` check and both be accepted, producing two "winning" bids on the same auction.
**How it fails:** User A sends bid 500,000. User B sends bid 510,000. Both requests reach step 5 (validation) before either commits step 7 (UPDATE auction). Both see the current highest as 490,000 and both pass. Both bids are inserted. Auction `current_highest_bid` is set to whichever UPDATE runs last — the other bid is silently accepted but the auction shows the wrong winner.
**Severity:** CRITICAL
**Safest fix:** Wrap steps 6–7 in a PostgreSQL advisory lock or use an atomic UPDATE that only fires if `current_highest_bid` has not changed:
```sql
UPDATE auctions
SET current_highest_bid = $bid_amount, current_winner_uid = $bidder_uid, ...
WHERE id = $auction_id AND current_highest_bid < $bid_amount
RETURNING *;
```
If the RETURNING result is empty, the bid was beaten by a concurrent bid — return 409 Conflict.
**Location:** `place-bid/index.ts` lines 87–109 (steps 6–7)

---

### FM-02 — NON-ATOMIC COUNTER INCREMENTS IN PLACE-BID
**Component:** `supabase/functions/place-bid/index.ts`
**Risk:** `total_bids` on the auction and `total_bids_placed` on the user are updated with read-modify-write arithmetic, not atomic SQL increments.
**How it fails:** Two concurrent bids both read `total_bids = 10`, both compute `10 + 1 = 11`, and both write 11. The counter ends at 11 instead of 12. At high bid frequency, counters permanently drift from reality.
**Severity:** HIGH
**Safest fix:** Use PostgreSQL atomic increment:
```sql
UPDATE auctions SET total_bids = total_bids + 1 WHERE id = $auction_id;
UPDATE users SET total_bids_placed = total_bids_placed + 1 WHERE id = $bidder_uid;
```
**Location:** `place-bid/index.ts` line 105 (`total_bids: auction.total_bids + 1`) and line 125 (`total_bids_placed: bidder.total_bids_placed + 1`)

---

### FM-03 — PUSH NOTIFICATION FAILURE ROLLS BACK SUCCESSFUL BID
**Component:** `supabase/functions/place-bid/index.ts`
**Risk:** The OneSignal push calls are inside the main try/catch. A network timeout to OneSignal causes the entire function to return 500, even though the bid was already committed to the database.
**How it fails:** Bid is inserted and auction is updated (steps 6–7 succeeded). Network call to OneSignal times out after 30 seconds. Function throws, returns `{ success: false, error: "..." }`. Flutter shows "Bid failed" to the user. The bid is in the database. The user re-bids. Now there are two bids. Auction data drifts.
**Severity:** HIGH
**Safest fix:** Move push notification calls outside the critical path. Use a fire-and-forget wrapper or catch push errors independently so they cannot cause a bid-commit rollback.
```typescript
// After returning success response, fire notifications silently
Promise.all([
  sendPush(...).catch(e => console.error('push failed:', e)),
  ...
]);
```
**Location:** `place-bid/index.ts` lines 156–200

---

### FM-04 — CREATE-ADMIN ORPHAN AUTH ACCOUNT ON INSERT FAILURE
**Component:** `supabase/functions/create-admin/index.ts`
**Risk:** If `auth.admin.createUser()` succeeds but the `region_admins.insert()` fails, a Supabase Auth account exists with no admin profile. The super admin sees an error but the phone number is now taken in Supabase Auth.
**How it fails:** Database constraint violation (e.g., phone number format mismatch) causes the insert to fail. The auth account is already created. Re-trying admin creation with the same phone number gets "email already registered" error. The super admin cannot create the account without contacting Supabase support.
**Severity:** HIGH
**Safest fix:** On insert failure, call `supabase.auth.admin.deleteUser(uid)` to clean up the orphan auth account:
```typescript
try {
  await supabase.from('region_admins').insert({...});
} catch (e) {
  await supabase.auth.admin.deleteUser(uid).catch(console.error);
  throw e;
}
```
**Location:** `create-admin/index.ts` line 87 (insert call)

---

### FM-05 — TEMP PASSWORD GENERATED WITH MATH.RANDOM()
**Component:** `supabase/functions/create-admin/index.ts`
**Risk:** `Math.random()` is not cryptographically secure. Passwords can be predicted if the random seed is known or guessed.
**How it fails:** An attacker who knows the approximate time the admin account was created can brute-force the seed space of `Math.random()` (which uses a non-CSPRNG V8 seed) and reproduce the generated password, potentially before the admin changes it.
**Severity:** MEDIUM
**Safest fix:** Use the Deno/Web Crypto API:
```typescript
function generatePassword(): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789!@#';
  const bytes = new Uint8Array(12);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, b => chars[b % chars.length]).join('');
}
```
**Location:** `create-admin/index.ts` lines 120–123

---

### FM-06 — AUTO-CLOSE-AUCTIONS HAS NO AUTHENTICATION
**Component:** `supabase/functions/auto-close-auctions/index.ts`
**Risk:** The function accepts any HTTP POST request without verifying the caller is authorized (no auth header check). Anyone who discovers the function URL can trigger mass auction closure.
**How it fails:** An attacker or misconfigured client posts to the function URL. All active auctions with `end_date <= now` are immediately closed, their winners recorded and notified. Auctions that were intended to stay active are closed prematurely. No way to undo without manual SQL.
**Severity:** CRITICAL
**Safest fix:** Verify the Authorization header contains the service role key:
```typescript
const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const authHeader = req.headers.get('Authorization') ?? '';
if (authHeader !== `Bearer ${expectedKey}`) {
  return new Response('Unauthorized', { status: 401 });
}
```
**Location:** `auto-close-auctions/index.ts` line 11 (top of serve function, before any logic)

---

### FM-07 — AUTO-CLOSE N+1 QUERY PROBLEM
**Component:** `supabase/functions/auto-close-auctions/index.ts`
**Risk:** For each expired auction, the function makes individual DB queries per unique bidder to fetch their OneSignal player ID. With 20 expired auctions each having 50 bidders, this is 1,000+ sequential queries.
**How it fails:** At 5-minute intervals with heavy bidding, the function runs longer than 5 minutes, causing overlapping executions. DB connection pool exhaustion. The function times out (Edge Functions have a 150-second wall time limit), leaving some auctions partially processed (closed in DB but bidders not notified).
**Severity:** HIGH
**Safest fix:** Bulk-fetch all bidder player IDs in one query using `.in()`:
```typescript
const bidderUids = [...new Set(otherBids.map(b => b.bidder_uid))];
const { data: bidders } = await supabase
  .from('users').select('id, onesignal_player_id').in('id', bidderUids);
const playerMap = Object.fromEntries(bidders.map(u => [u.id, u.onesignal_player_id]));
```
**Location:** `auto-close-auctions/index.ts` lines 96–118

---

### FM-08 — GENERATE-REPORT DOES NOT CHECK ADMIN SUSPENSION
**Component:** `supabase/functions/generate-report/index.ts`
**Risk:** Authorization check only verifies the caller exists in an admin table, not whether their account is active.
**How it fails:** A suspended admin whose JWT has not yet expired can call `generate-report` and receive full auction and revenue data for any region or nationally.
**Severity:** MEDIUM
**Safest fix:** Add `account_status` to the admin lookup and reject suspended callers:
```typescript
const { data: isAdmin } = await supabase
  .from('region_admins').select('id, account_status').eq('id', user.id).maybeSingle();
const { data: isSuper } = await supabase
  .from('super_admins').select('id, account_status').eq('id', user.id).maybeSingle();
if (!isAdmin && !isSuper) return json({ error: 'Admin only' }, 403);
if ((isAdmin?.account_status ?? isSuper?.account_status) !== 'active')
  return json({ error: 'Account suspended' }, 403);
```
**Location:** `generate-report/index.ts` lines 37–47

---

### FM-09 — CLEANUP-NOTIFICATIONS HAS NO AUTHENTICATION
**Component:** `supabase/functions/cleanup-notifications/index.ts`
**Risk:** No auth check — any POST to this URL deletes all notifications older than 30 days.
**How it fails:** Malicious actor calls the endpoint and clears all notifications. Users lose their notification history. Not data-destructive to auctions or bids, but a trust/UX incident.
**Severity:** MEDIUM (data loss, not integrity)
**Safest fix:** Same service role key verification as FM-06.
**Location:** `cleanup-notifications/index.ts` line 20

---

### FM-10 — ON-NEW-AUCTION WEBHOOK IS UNAUTHENTICATED
**Component:** `supabase/functions/on-new-auction/index.ts`
**Risk:** No verification of the Supabase webhook signing secret.
**How it fails:** Attacker crafts a fake webhook payload with an arbitrary `auction.region`, triggering mass push notifications to all clients in that region for a non-existent auction. Clients click the notification, see "Auction not found" — trust eroded.
**Severity:** MEDIUM
**Safest fix:** Verify the `x-webhook-secret` header Supabase sends when a webhook signing secret is configured:
```typescript
const secret = Deno.env.get('WEBHOOK_SECRET');
if (secret && req.headers.get('x-webhook-secret') !== secret) {
  return new Response('Unauthorized', { status: 401 });
}
```
**Location:** `on-new-auction/index.ts` line 21 (top of serve)

---

## SCOPE 2: FLUTTER FRONTEND

### FM-11 — ENCRYPTION SERVICE: STATIC IV IN CBC MODE
**Component:** `lib/core/services/encryption_service.dart`
**Risk:** AES-256 CBC encryption uses a fixed IV stored in `flutter_secure_storage`. CBC with a static IV is semantically insecure: the same plaintext always produces the same ciphertext.
**How it fails:** If two users have the same National ID (e.g., a data entry error), their encrypted values in the database are identical. This reveals equality of plaintext to anyone with DB access. More critically, this makes the encryption vulnerable to known-plaintext attacks — anyone who knows one National ID and its ciphertext can infer patterns about other IDs.
**Severity:** HIGH (weakens encryption of PII protected by law)
**Safest fix:** Generate a random IV per encryption operation and prepend it to the ciphertext. On decrypt, extract the first 16 bytes as the IV:
```dart
// Encrypt: IV = random 16 bytes | ciphertext
// Decrypt: IV = first 16 bytes, ciphertext = remainder
```
This requires a migration for existing encrypted data.
**Location:** `lib/core/services/encryption_service.dart`

---

### FM-12 — ENCRYPTION SERVICE: ASSERT() SILENCED IN RELEASE BUILD
**Component:** `lib/core/services/encryption_service.dart`
**Risk:** The `encrypt()` method uses `assert(_enc != null)` to guard against calling encrypt before initialization. In release builds, all `assert()` statements are compiled out.
**How it fails:** If `EncryptionService.instance.initialize()` is not called before `encrypt()`, `_enc` is null. The `assert` is skipped in release. The next line `_enc!.encrypt(...)` throws `Null check operator used on a null value` — an unhandled crash with no clear error message.
**Severity:** HIGH (crash in registration flow)
**Safest fix:** Replace `assert` with an explicit `if (_enc == null) throw StateError('EncryptionService not initialized')`.
**Location:** `lib/core/services/encryption_service.dart` `encrypt()` method

---

### FM-13 — REGISTRATION: 2-STEP SIGN-UP CAN PRODUCE ORPHAN AUTH ACCOUNT
**Component:** `lib/data/repositories/auth_repository.dart` `registerClient()`
**Risk:** If `signUp()` succeeds but `INSERT INTO users` fails, a Supabase Auth account exists with no user profile. The session is cleaned up (via `_safeSignOut()`), but the auth account persists.
**How it fails:** User gets "Registration failed" message and tries again. The second `signUp()` attempt returns "Email already registered" because the phone-derived email is taken in Supabase Auth. The user cannot register. They must contact support.
**Severity:** HIGH (permanent account lockout without admin intervention)
**Safest fix (proper, backend):** Add a PostgreSQL trigger on `auth.users` INSERT that automatically creates the `users` row. This makes registration atomic.
**Safest fix (current, Flutter-side):** Already applied — `_safeSignOut()` in catch. The orphan auth account still exists, but at least the user is not stuck in an authenticated state.
**Status:** Partially mitigated. Backend trigger needed for full fix. Documented in `PRODUCTION_DEPLOYMENT_CHECKLIST.md`.
**Location:** `auth_repository.dart` lines 77–87

---

### FM-14 — PROVIDER STALE DATA AFTER FORCED SIGN-OUT
**Component:** `lib/data/repositories/repositories.dart`
**Risk:** `currentUserProvider` and `currentAdminProvider` serve cached data until explicitly invalidated. If the router forces a sign-out (e.g., suspended user), the providers still return the suspended user's data on the next screen build.
**How it fails:** Router detects suspension, calls `signOut()`, redirects to login. Login screen builds. A widget that still holds a reference to `currentUserProvider.value` renders the suspended user's name instead of empty state.
**Severity:** MEDIUM (data leak between sessions, UX inconsistency)
**Safest fix:** Already applied — `ref.watch(authStateProvider)` added to both providers. Verify this fix is in place.
**Status:** Fixed.
**Location:** `repositories.dart` `currentUserProvider` and `currentAdminProvider`

---

### FM-15 — SUPER ADMIN STATS: FULL TABLE SCAN FOR COUNT
**Component:** `lib/presentation/screens/super_admin/super_admin_screens.dart` `_localNationalStatsProvider`
**Risk:** `await client.from('bids').select('id')` fetches ALL bid IDs from the database into Dart memory to count them.
**How it fails:** At 100,000 bids (easily reached in first year), this response is ~3 MB of UUIDs. On a mobile connection, the dashboard takes 5–10 seconds to load. At 1M bids, it OOMs the device or triggers a 408 timeout.
**Severity:** HIGH (production crash at scale)
**Safest fix:** Use `count: 'exact'` to get the count server-side:
```dart
final bidsRes = await client.from('bids').select('id', const FetchOptions(count: CountOption.exact, head: true));
final totalBids = bidsRes.count ?? 0;
```
**Location:** `super_admin_screens.dart` line 52

---

### FM-16 — NOTIFICATION SERVICE: PRINT() IN PRODUCTION
**Component:** `lib/core/services/notification_service.dart`
**Risk:** Uses `print()` instead of `debugPrint()`. In Flutter release builds, `debugPrint()` is a no-op. `print()` still writes to the system log.
**How it fails:** OneSignal player IDs, region subscription names, and notification click payloads appear in Android logcat on production devices. On rooted devices or via ADB, this leaks notification routing data.
**Severity:** MEDIUM (log leakage of non-secret but operational data)
**Safest fix:** Replace all `print()` calls with `debugPrint()` in `notification_service.dart`.
**Location:** `notification_service.dart` line 48

---

### FM-17 — BID NOTIFIER IS GLOBAL, NOT PER-AUCTION
**Component:** `lib/presentation/providers/providers.dart` `bidNotifierProvider`
**Risk:** `BidNotifier` is a single global `StateNotifierProvider`, not a `StateNotifierProvider.family`.
**How it fails:** User places a bid on Auction A (bid fails with an error). User navigates to Auction B. The `bidNotifierProvider` still holds the `AsyncError` state from Auction A. Auction B's bid button shows the error from Auction A.
**Severity:** LOW (UX bug, not data corruption)
**Safest fix:** Convert to `StateNotifierProvider.family<BidNotifier, AsyncValue<void>, String>` keyed by auction ID.
**Location:** `providers.dart` `bidNotifierProvider`; documented in deployment checklist as v1.1 item.

---

## SCOPE 3: SUPABASE DATABASE

### FM-18 — NO RACE CONDITION GUARD ON AUCTION CLOSE
**Component:** `supabase/functions/close-auction-manually/index.ts`
**Risk:** Two region admins (or an admin + pg_cron timer) could attempt to close the same auction simultaneously. Both pass the `auction_status === 'active'` check before either commits the update.
**How it fails:** Auction ends. Admin manually closes it. At the same moment, `auto-close-auctions` triggers for the same auction. Both read `auction_status = 'active'`. Both write `auction_status = 'closed'`. Winner is notified twice. `total_auctions_won` is incremented twice.
**Severity:** MEDIUM (duplicate notifications, wrong stats)
**Safest fix:** Use an atomic conditional UPDATE:
```sql
UPDATE auctions SET auction_status = 'closed', ... 
WHERE id = $auction_id AND auction_status = 'active'
RETURNING *;
```
Return 409 if the RETURNING result is empty (already closed).
**Location:** `close-auction-manually/index.ts` lines 88–99; `auto-close-auctions/index.ts` lines 41–52

---

### FM-19 — NO FOREIGN KEY CASCADE HANDLING FOR DELETED AUCTIONS
**Component:** Database schema (inferred from `auction_repository.dart`)
**Risk:** Deleting an auction with active bids does not automatically clean up the `bids` table if there is no `ON DELETE CASCADE` on `bids.auction_id`.
**How it fails:** Admin deletes a draft auction that somehow acquired bids. If no CASCADE, the DELETE fails with a FK constraint violation and the user sees a generic database error. If CASCADE is set, bids are silently deleted — acceptable for drafts, risky for closed auctions where bids are a record of payment obligation.
**Severity:** MEDIUM
**Safest fix:** Only allow deletion of auctions in `draft` status. Add a guard in `deleteAuction()`:
```dart
if (auction.auctionStatus != 'draft') {
  throw const ValidationException('Only draft auctions can be deleted');
}
```
**Location:** `auction_repository.dart` `deleteAuction()` line 140

---

## SCOPE 4: REALTIME

### FM-20 — REALTIME CONNECTION LIMIT AT SCALE
**Component:** Supabase Realtime (via `auction_repository.dart` `.stream()`)
**Risk:** Supabase free plan allows 200 concurrent Realtime connections. Pro plan allows 500. Each user viewing the auction list holds one Realtime connection.
**How it fails:** 201st concurrent user (free plan) or 501st (Pro plan) cannot establish a Realtime connection. Their auction list does not update in real time. They do not see new bids, price changes, or auction status changes. If they bid, they may be working with stale data.
**Severity:** HIGH (core feature failure at moderate user count)
**Safest fix:** Upgrade to Pro plan before launch. For nationwide scale, implement connection pooling or replace Realtime streams on list screens with periodic `FutureProvider` refresh every 30 seconds. Reserve Realtime connections for auction-detail screens only.
**Location:** `auction_repository.dart` `getAuctionsByRegion()` and `watchAuction()`

---

## SCOPE 5: STORAGE

### FM-21 — REPORTS BUCKET GROWS INDEFINITELY
**Component:** `supabase/functions/generate-report/index.ts`, `reports` storage bucket
**Risk:** Each `generate-report` call uploads an HTML file to the `reports` bucket. There is no cleanup mechanism.
**How it fails:** After 1 year of weekly reports per region (5 regions × 52 weeks × any format), the bucket has 260+ files. Storage costs grow. More critically, signed URLs for old reports (valid 7 days) expire, but the HTML files persist indefinitely, accessible to anyone who knows the file path (since signed URLs use predictable naming: `reports/{region}_{timestamp}.html`).
**Severity:** LOW (cost/cleanup issue)
**Safest fix:** Add a cleanup step in `cleanup-notifications` to also delete report files older than 30 days from the `reports` bucket.

---

### FM-22 — NATIONAL ID BUCKET: KEY LOSS ON DEVICE REINSTALL
**Component:** `lib/core/services/encryption_service.dart`, `national-ids` bucket
**Risk:** The AES encryption key is stored in `flutter_secure_storage`. On Android, `flutter_secure_storage` is backed by the Android Keystore. If the user reinstalls the app or resets their phone, the Keystore entry is deleted.
**How it fails:** User reinstalls the app. The encryption key is gone. The app generates a new key. The stored National ID ciphertext cannot be decrypted. `decrypt()` throws. Any screen that tries to display or verify the National ID crashes or shows garbage.
**Severity:** HIGH (permanent data loss of a legally required identity document reference)
**Safest fix (complete):** Store the encryption key encrypted by a user-derived password, or store the key in Supabase's Vault (server-side), accessed via the authenticated JWT. National ID ciphertext stored in DB + key in Supabase Vault = data survives device loss.
**Safest fix (minimal):** On decryption failure, show "National ID data unavailable. Please re-submit your National ID." and allow re-entry.
**Location:** `encryption_service.dart` decrypt path

---

## SEVERITY SUMMARY

| ID | Description | Severity |
|----|-------------|----------|
| FM-01 | Race condition in place-bid (TOCTOU) | CRITICAL |
| FM-06 | auto-close-auctions has no authentication | CRITICAL |
| FM-02 | Non-atomic counter increments | HIGH |
| FM-03 | Push failure rolls back committed bid | HIGH |
| FM-04 | create-admin orphan auth account | HIGH |
| FM-07 | auto-close N+1 query | HIGH |
| FM-11 | Static IV in CBC encryption | HIGH |
| FM-12 | assert() silenced in release build | HIGH |
| FM-13 | 2-step registration orphan account | HIGH |
| FM-15 | Full table scan for bid count | HIGH |
| FM-20 | Realtime connection limit | HIGH |
| FM-22 | Encryption key lost on reinstall | HIGH |
| FM-05 | Math.random() for password generation | MEDIUM |
| FM-08 | generate-report ignores suspension | MEDIUM |
| FM-09 | cleanup-notifications unauthenticated | MEDIUM |
| FM-10 | on-new-auction webhook unauthenticated | MEDIUM |
| FM-14 | Provider stale data after sign-out | MEDIUM (fixed) |
| FM-16 | print() in production | MEDIUM |
| FM-18 | No race guard on auction close | MEDIUM |
| FM-19 | No guard on deleting auctioned items | MEDIUM |
| FM-17 | BidNotifier is global | LOW (v1.1) |
| FM-21 | Reports bucket grows indefinitely | LOW |
