# SCALABILITY AND LOAD RISKS — E-CYAMUNARA
Last updated: 2026-04-23

---

## LOAD PROFILE ASSUMPTIONS

| Metric | Launch (pilot) | Year 1 (provincial) | Year 2 (national) |
|--------|---------------|---------------------|-------------------|
| Concurrent users | 50–200 | 500–1,000 | 2,000–5,000 |
| Active auctions at once | 5–10 | 20–50 | 50–200 |
| Bids/day | 100–500 | 1,000–5,000 | 10,000–50,000 |
| Total bids (cumulative) | 5,000 | 200,000 | 2,000,000 |
| Clients registered | 500 | 5,000 | 50,000 |
| Notifications/day | 1,000 | 20,000 | 200,000 |

---

## RISK 1 — REALTIME CONNECTION HARD LIMIT

**What breaks:** `getAuctionsByRegion()` and `watchAuction()` use Supabase `.stream()` which holds a persistent WebSocket connection per active subscription.
**Limit:** Free plan = 200 concurrent connections. Pro plan = 500.
**Breaks at:** 201 concurrent users on Free; 501 on Pro.
**Impact:** Users over the limit see a static auction list that never updates. They do not see live bid price changes. They can still bid (via Edge Function), but may underbid a just-updated price.
**Mitigation for launch:** Upgrade to Pro before launch (500 connections). For national scale (2,000+ users):
- Limit Realtime to auction-detail screen only (one connection = one auction watched).
- Replace home screen `.stream()` with polling via `FutureProvider` + `ref.refresh()` every 30 seconds.
- This reduces connections to `(users viewing auction detail)`, a much smaller fraction of active users.

---

## RISK 2 — ON-NEW-AUCTION: O(N) NOTIFICATION INSERTS

**What breaks:** When a new auction is posted, `on-new-auction` queries ALL clients in the region and inserts one notification row per client, in batches of 500.
**Scale math:**
- 1,000 clients in Eastern region: 2 × 500-row inserts + 1 OneSignal call of 1,000 IDs. Completes in ~3 seconds. Acceptable.
- 10,000 clients nationally: 20 × 500-row inserts. Each insert is a separate DB round-trip. ~30 seconds. Edge Function timeout is 150 seconds — still OK but approaching limit.
- 50,000 clients: 100 × 500-row inserts. ~150 seconds. Function times out. Only partial notifications sent.
**Mitigation:** At 5,000+ clients per region, switch to OneSignal's tag-based segments instead of `include_player_ids`. OneSignal's infrastructure handles fan-out natively with no size limit. The function sends one API call; OneSignal delivers to all matching devices:
```typescript
body: JSON.stringify({
  app_id: appId,
  filters: [{ field: 'tag', key: 'region', relation: '=', value: auction.region }],
  headings: { en: title },
  contents: { en: body },
  data: { type: 'new_auction', auction_id: auction.id },
})
```
Notification DB inserts can be removed entirely and replaced with a single broadcast row.

---

## RISK 3 — AUTO-CLOSE-AUCTIONS: SEQUENTIAL N+1 QUERIES

**What breaks:** `auto-close-auctions` loops over expired auctions and for each makes individual queries per bidder.
**Scale math:**
- 5 expired auctions, 10 bidders each: ~60 DB queries. Completes in ~5 seconds. Fine.
- 20 expired auctions, 50 bidders each: ~1,200 queries. Takes 60–120 seconds. Approaches function timeout.
- 50 expired auctions (busy nationwide auction day): function times out. Some auctions are auto-closed with partial notifications.
**Mitigation:**
1. Bulk-fetch all unique bidder UIDs across ALL expired auctions in one `.in()` query.
2. Use a single OneSignal tag-based broadcast per auction instead of individual player IDs.
3. Move total_auctions_won increment to a DB trigger instead of application code.

---

## RISK 4 — SUPER ADMIN STATS: FULL TABLE FETCH

**What breaks:** `_localNationalStatsProvider` fetches `select('id')` from the `bids` table and counts rows in Dart.
**Scale math:**
- 10,000 bids: 160 KB response. 1–2 seconds on mobile. Slow but acceptable.
- 100,000 bids: 1.6 MB response. 5–10 seconds. User sees loading spinner.
- 1,000,000 bids: 16 MB. Dart heap pressure. App may crash with OOM on low-end devices.
**Mitigation:** Use `count: 'exact'` + `head: true`. No rows transferred, just the count header. Works at any table size with zero performance change.
```dart
final bidsRes = await client.from('bids').select('id', const FetchOptions(count: CountOption.exact, head: true));
final totalBids = bidsRes.count ?? 0;
```
Same fix needed for `auctions` and `users` counts.

---

## RISK 5 — PLACE-BID UNDER HIGH CONCURRENT LOAD

**What breaks:** No rate limiting, no connection pooling strategy, no debounce.
**Scale math:** If 100 users bid on the same auction simultaneously (e.g., a popular vehicle in the last 60 seconds), `place-bid` is invoked 100 times concurrently. Each invocation:
1. Creates a Supabase service-role client.
2. Creates an anon client for JWT verification.
3. Makes 3–4 DB queries.
4. Makes 2–3 HTTP calls to OneSignal.
That is 300–400 DB queries and 200–300 outbound HTTP calls per second.
**Supabase limits (Pro plan):** 500 DB connections max. Unprotected parallel bids could exhaust connections.
**Mitigation:**
1. Supabase Edge Functions run in Deno Deploy's distributed infrastructure — connection pooling is handled by Supabase's PgBouncer. Each function invocation gets a pooled connection, not a direct connection.
2. Add application-level rate limiting in `place-bid`: max 3 bids per user per minute.
3. The TOCTOU fix (FM-01) also reduces wasted concurrent writes by making only the first bid atomic winner.

---

## RISK 6 — GENERATE-REPORT: UNBOUNDED DATE RANGE QUERY

**What breaks:** No validation on `start_date` / `end_date` range size.
**Scale math:** An admin passes `start_date = '2020-01-01'` and `end_date = '2030-12-31'`. Supabase fetches every auction row ever created (`select('*')` — all columns including photo URLs). At 10,000 auctions, this is ~10 MB of data transferred to the Edge Function, which then tries to build an HTML table of 100 auctions. The other 9,900 are silently discarded.
**Mitigation:**
1. Validate that `end_date - start_date <= 365 days`.
2. Add server-side pagination to the report query.
3. Use `select()` with only the columns needed for the report, not `select('*')`.

---

## RISK 7 — NOTIFICATIONS TABLE GROWTH

**Scenario:** `on-new-auction` inserts one row per client per new auction. `place-bid` inserts 2 rows per bid (winning + outbid). `cleanup-notifications` runs weekly and deletes rows older than 30 days.
**Scale math:**
- 5,000 clients, 3 new auctions/day, 100 bids/day: 5,000 × 3 + 200 = 15,200 inserts/day.
- Over 30 days (before cleanup): 456,000 rows.
- At 500 bytes/row: ~228 MB for notifications alone.
- This is within Supabase Pro storage limits, but queries against this table (user's notification list) become slow without proper indexing on `user_uid` + `created_at`.
**Mitigation:** Ensure `notifications(user_uid, created_at DESC)` composite index is present (see DATABASE_INDEX_AUDIT.md).

---

## RISK 8 — SUPABASE FREE PLAN LIMITS (IF NOT UPGRADED)

| Resource | Free limit | Breaks when |
|----------|-----------|-------------|
| DB size | 500 MB | ~50,000 auctions with photos URLs stored in DB |
| Realtime connections | 200 | 201st concurrent user |
| Edge Function invocations | 500,000/month | ~17,000 bids/month |
| Storage | 1 GB | After ~10,000 auction photos at ~100 KB/photo |
| Bandwidth | 2 GB/month | Any meaningful production usage |

**Action required:** Upgrade to Supabase Pro ($25/month) before public launch. This unlocks 500 Realtime connections, 5 GB DB, 100 GB storage, 2M Edge Function invocations/month, and point-in-time recovery.

---

## PRE-1,000 USER CHECKLIST

These must be done before reaching 1,000 registered users:

- [ ] Upgrade Supabase to Pro plan
- [ ] Fix FM-01: TOCTOU race in place-bid (before ANY concurrent bidding)
- [ ] Fix FM-02: Atomic counter increments
- [ ] Fix FM-06: Auth check on auto-close-auctions
- [ ] Fix FM-15: Replace full bids table scan with count query
- [ ] Verify all indexes from DATABASE_INDEX_AUDIT.md are created
- [ ] Set up pg_cron for auto-close-auctions
- [ ] Configure OneSignal production app with FCM/APNs credentials
- [ ] Test Realtime with 50+ concurrent connections under load
- [ ] Set Supabase DB connection alerts (CPU > 70%, connections > 80%)

---

## PRE-10,000 USER CHECKLIST

These must be done before reaching 10,000 registered users:

- [ ] Switch on-new-auction from include_player_ids to OneSignal tag segments
- [ ] Fix auto-close N+1 query (bulk-fetch bidder IDs)
- [ ] Add application-level rate limiting to place-bid (max 3 bids/user/minute)
- [ ] Implement per-auction Realtime connections only (home screen polling)
- [ ] Add report date range validation and column projection
- [ ] Add database partitioning strategy for bids table (partition by created_at year)
- [ ] Add composite index on notifications(user_uid, created_at DESC)
- [ ] Implement Sentry or equivalent crash reporting
- [ ] Load test the bidding flow with 100 concurrent bids on one auction
- [ ] Add Supabase read replica for report queries (isolate read load)
