# E-CYAMUNARA — PRODUCTION AUDIT SUMMARY AND REMEDIATION ROADMAP
Last updated: 2026-04-23

Full audit covering: Flutter Frontend, Supabase Database, Edge Functions, Realtime, Storage, Operations.
Source documents: FAILURE_MODE_ANALYSIS.md, SCALABILITY_AND_LOAD_RISKS.md, DATABASE_INDEX_AUDIT.md,
REALTIME_STABILITY_REPORT.md, EDGE_FUNCTION_RESILIENCE_REPORT.md, BACKUP_AND_DISASTER_RECOVERY_PLAN.md,
OBSERVABILITY_AND_ALERTING_PLAN.md, PRODUCTION_OPERATIONS_RUNBOOK.md

---

## TOP 10 PRODUCTION RISKS

### RISK 1 — RACE CONDITION IN PLACE-BID (TOCTOU)
**Category:** Data integrity  
**Impact:** Two simultaneous bids can both be accepted as winners. The auction records the wrong winner. Payment disputes arise.  
**Probability at launch:** LOW (unlikely with few users). HIGH at national scale during peak bidding.  
**Must fix before:** Any live auction with concurrent bidders.  
**Fix location:** `place-bid/index.ts` steps 6–7 — use atomic conditional UPDATE.

---

### RISK 2 — AUTO-CLOSE-AUCTIONS HAS NO AUTHENTICATION
**Category:** Security  
**Impact:** Anyone who discovers the function URL can trigger mass closure of all active auctions. All auction results would be permanently wrong, requiring a full DB restore.  
**Probability:** LOW but catastrophic if exploited.  
**Must fix before:** pg_cron is configured (immediately — before the function is live).  
**Fix location:** `auto-close-auctions/index.ts` — add service role key verification.

---

### RISK 3 — SUPABASE FREE PLAN REALTIME LIMIT (200 CONNECTIONS)
**Category:** Availability  
**Impact:** After the 200th concurrent user, auction lists stop updating in real time. Users see stale bid prices. Bidding decisions are based on wrong data.  
**Probability:** HIGH — a modest-size auction event (200 users watching simultaneously) triggers this.  
**Must fix before:** First public launch.  
**Fix location:** Upgrade to Supabase Pro plan + optionally switch home screen to polling.

---

### RISK 4 — PUSH NOTIFICATION FAILURE CAUSES BID TO APPEAR FAILED
**Category:** Data consistency  
**Impact:** Bid is committed to the database. OneSignal times out. `place-bid` returns 500. User sees "Bid failed." User re-bids. Duplicate bids and inflated counters.  
**Probability:** LOW-MEDIUM (OneSignal is generally reliable, but network partitions happen).  
**Must fix before:** National rollout.  
**Fix location:** `place-bid/index.ts` lines 156–200 — decouple push from bid commit.

---

### RISK 5 — ENCRYPTION SERVICE: STATIC IV + KEY LOSS ON REINSTALL
**Category:** Data security + data loss  
**Two linked issues:**  
(a) Static IV makes CBC encryption semantically insecure — equal National IDs produce equal ciphertexts, enabling correlation attacks.  
(b) Encryption key in device Keystore is lost on app reinstall — stored National IDs become permanently undecryptable.  
**Probability of (b):** HIGH over 12 months at any meaningful user base.  
**Impact:** Violation of Rwandan data protection law for (a); permanent user data loss for (b).  
**Must fix before:** Legal go-live.  
**Fix location:** `encryption_service.dart` — random IV per encrypt; server-side key via Supabase Vault.

---

### RISK 6 — 2-STEP REGISTRATION CREATES ORPHAN AUTH ACCOUNTS
**Category:** Availability  
**Impact:** User gets "Registration failed" due to INSERT failure. Their phone number is permanently reserved in Supabase Auth (mapped to `rw07XXXXXXXX@ecyamunara.rw`). They cannot register again.  
**Probability:** LOW (INSERT failures are uncommon), but when it happens the impact is total — user cannot self-recover.  
**Must fix before:** Any public-facing registration.  
**Fix location (proper):** DB trigger on `auth.users` INSERT to auto-create `users` row. Documented in PRODUCTION_DEPLOYMENT_CHECKLIST.md.

---

### RISK 7 — AUTO-CLOSE N+1 QUERIES WILL TIME OUT AT SCALE
**Category:** Scalability  
**Impact:** Edge Function makes one DB query per bidder per expired auction. With 20 expired auctions at 50 bidders each, the function times out (150-second limit). Some auctions are never auto-closed. Bidders are not notified.  
**Probability:** LOW at launch, HIGH within year 1 of national operation.  
**Must fix before:** Nationwide launch.  
**Fix location:** `auto-close-auctions/index.ts` — bulk-fetch bidder IDs with `.in()`.

---

### RISK 8 — SUPER ADMIN DASHBOARD FETCHES ENTIRE BIDS TABLE
**Category:** Scalability  
**Impact:** `select('id')` on the bids table downloads all bid IDs to the device. At 100,000 bids (~1.6 MB), the dashboard is slow. At 1M bids, it can crash the app on low-end devices.  
**Probability:** LOW at launch, CERTAIN within 12–18 months.  
**Must fix before:** 50,000 bids in the database.  
**Fix location:** `super_admin_screens.dart` line 52 — use `count: 'exact'` with `head: true`.

---

### RISK 9 — NO CRASH REPORTING IN PRODUCTION
**Category:** Observability  
**Impact:** When the app crashes in production (and it will — FM-12 assert crash, Null exceptions, unexpected Supabase response shapes), the only signal is users calling support. Root cause analysis is done blind.  
**Probability of crashes:** MEDIUM-HIGH in first 90 days.  
**Must fix before:** Launch.  
**Fix location:** `pubspec.yaml` + `main.dart` — add Sentry or Firebase Crashlytics.

---

### RISK 10 — PG_CRON NOT YET CONFIGURED
**Category:** Operations  
**Impact:** Without pg_cron, `auto-close-auctions` never runs. All auctions expire without closing. Winners are never announced. Admins must manually close every auction.  
**Probability of missing this:** HIGH — it is a manual setup step not enforced by code.  
**Must fix before:** First live auction.  
**Fix location:** Supabase SQL Editor — run the pg_cron setup SQL from PRODUCTION_OPERATIONS_RUNBOOK.md.

---

## LAUNCH CONFIDENCE SCORE: 58 / 100

**Scoring method:** Each of 10 risk areas rated 0–10 (10 = fully addressed, 0 = not addressed).

| Area | Score | Rationale |
|------|-------|-----------|
| Authentication & session security | 9/10 | Phase 4 hardening complete. Minor: assert() not replaced. |
| RLS & data isolation | 8/10 | Policies appear correct. Needs Phase 3 verification run. |
| Bid integrity | 3/10 | TOCTOU race + non-atomic counters unresolved. |
| Edge function security | 4/10 | Auth on most functions, but auto-close and cleanup unprotected. |
| Encryption & PII protection | 3/10 | Static IV + key loss risk unresolved. |
| Scalability | 5/10 | Works at pilot scale. Known failure points at 500+ users. |
| Observability | 2/10 | No crash reporting. No structured logs. No alerting. |
| Backup & recovery | 6/10 | Supabase managed backups + PITR with Pro plan. No off-site storage backup. |
| Operations readiness | 6/10 | Runbook and checklists complete. pg_cron not yet set up. |
| Registration & user lifecycle | 5/10 | Orphan account risk documented. Backend trigger not implemented. |

**Interpretation:**
- Score < 60: NOT recommended for public launch without addressing at minimum the Critical and HIGH items.
- Score 60–80: Acceptable for limited pilot with close monitoring.
- Score > 80: Production-ready.

---

## OPERATIONAL MATURITY SCORE: 55 / 100

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Runbooks and documentation | 9/10 | Incident guide, deployment checklist, runbook complete. |
| Monitoring and alerting | 2/10 | No automated alerts configured. No crash reporting. |
| Backup and DR tested | 4/10 | Plan documented. Restore never tested. |
| Cron jobs configured | 0/10 | pg_cron not set up yet. |
| Audit logging | 2/10 | No suspension audit trail. Supabase logs only. |
| Incident response readiness | 8/10 | Playbooks written. RNP team not yet trained on them. |

---

## SCALE READINESS SCORE: 35 / 100

| Dimension | Score | Rationale |
|-----------|-------|-----------|
| Database indexes | 5/10 | Indexes not yet created. Queries will do full table scans. |
| Realtime connections | 3/10 | 200-connection limit on free plan. Must upgrade before launch. |
| Edge function atomicity | 2/10 | TOCTOU race + non-atomic increments. Will cause corruption at scale. |
| Notification fan-out | 5/10 | Batched inserts exist. Will timeout at 10,000+ clients per region. |
| Counter queries | 2/10 | Full table scans for bids/users count in super admin dashboard. |
| Error isolation | 4/10 | Some functions continue on error, others fail completely. |

---

## PRIORITIZED REMEDIATION ROADMAP

### PHASE A — IMMEDIATE (Before first live auction, ~1–2 days of work)

| ID | Fix | Where | Why now |
|----|-----|-------|---------|
| A1 | Add auth guard to auto-close-auctions | `auto-close-auctions/index.ts` L11 | Any URL discovery = mass auction closure |
| A2 | Configure pg_cron for auto-close | Supabase SQL Editor | Without it, no auctions ever auto-close |
| A3 | Upgrade Supabase to Pro plan | Dashboard → Billing | Realtime limit = 200 connections on Free |
| A4 | Create all database indexes | Supabase SQL Editor | All queries do full table scans without them |
| A5 | Replace assert() with explicit guard in EncryptionService | `encryption_service.dart` | Release crash on registration |
| A6 | Add crash reporting (Sentry) | `pubspec.yaml` + `main.dart` | Cannot debug production crashes without it |
| A7 | Configure Supabase alerts (CPU, connections, error rate) | Dashboard → Reports | No visibility into production health |

---

### PHASE B — PRE-PUBLIC-LAUNCH (Before opening to external users, ~3–5 days)

| ID | Fix | Where | Why before launch |
|----|-----|-------|------------------|
| B1 | Fix TOCTOU race in place-bid | `place-bid/index.ts` | Will produce wrong winners under concurrent load |
| B2 | Make counter increments atomic | `place-bid/index.ts` | Counters drift under any concurrent load |
| B3 | Decouple push from bid commit | `place-bid/index.ts` | Push failure = bid appears failed = duplicate bids |
| B4 | Replace Math.random() with crypto.getRandomValues() | `create-admin/index.ts` | Admin passwords are predictable |
| B5 | Fix created_by from JWT, not body | `create-admin/index.ts` | Audit trail integrity |
| B6 | Add suspension check to generate-report | `generate-report/index.ts` | Suspended admins can access all data |
| B7 | Fix super admin stats count query | `super_admin_screens.dart` | Will crash at 100K bids |
| B8 | Add auth guard to cleanup-notifications | `cleanup-notifications/index.ts` | Malicious notification wipe |
| B9 | Add webhook signature verification | `on-new-auction/index.ts` | Fake notifications sent to all users |
| B10 | Fix create-admin orphan auth cleanup | `create-admin/index.ts` | Locked phone numbers on insert failure |
| B11 | Replace print() with debugPrint() | `notification_service.dart` | Operational data in production logs |
| B12 | Run Phase 3 security test checklist | Manual (database + app) | Verify RLS policies are in place |

---

### PHASE C — PRE-PROVINCIAL SCALE (Before expanding to all 5 provinces, ~1–2 weeks)

| ID | Fix | Where | Why at this stage |
|----|-----|-------|-----------------|
| C1 | Implement random IV in EncryptionService | `encryption_service.dart` | Legal compliance + semantic security |
| C2 | Move encryption key to Supabase Vault | `encryption_service.dart` + backend | Survive device reinstall |
| C3 | Add pending route consumption | `notification_service.dart` + router | Push taps must deep-link to auction |
| C4 | Fix auto-close N+1 queries | `auto-close-auctions/index.ts` | Timeout at 20+ expired auctions |
| C5 | Add error isolation in auto-close loop | `auto-close-auctions/index.ts` | One auction failure should not block others |
| C6 | Add concurrent-close guard (atomic update) | `close-auction-manually/index.ts` + `auto-close` | Double-close + double notification |
| C7 | Add bid rate limiting to place-bid | `place-bid/index.ts` | Prevent bid flooding |
| C8 | Add structured logging to all functions | All Edge Functions | Diagnostic capability at scale |
| C9 | Add Realtime reconnection fallback to auction detail | `auction_detail_screen.dart` | Users see stale price on network drop |
| C10 | Add DB trigger on auth.users for profile creation | Supabase SQL Editor | Permanent fix for orphan auth accounts |
| C11 | Implement suspension audit log | DB + suspend-user/activate-user | Accountability for admin actions |

---

### PHASE D — PRE-NATIONWIDE LAUNCH (All 5 regions, 10,000+ users)

| ID | Fix | Where | Why at this stage |
|----|-----|-------|-----------------|
| D1 | Switch on-new-auction to OneSignal tag segments | `on-new-auction/index.ts` | include_player_ids times out at 5,000+ clients |
| D2 | Switch home screen from Realtime to polling | `auction_repository.dart` + `home_screen.dart` | 500 Pro connections exhausted at 300+ dual-screen users |
| D3 | Add report date range validation | `generate-report/index.ts` | Unbounded date range = full table scan |
| D4 | Consider DB partitioning for bids table | Supabase migrations | 1M+ bids table needs partition strategy |
| D5 | Add read replica for report queries | Supabase Dashboard | Isolate heavy read queries from transactional writes |
| D6 | Implement External User ID in OneSignal | Flutter + Edge Functions | Stale player IDs at scale → silent push failures |
| D7 | Add `deleteAuction` guard (draft only) | `auction_repository.dart` | Prevent deletion of auctions with bid history |
| D8 | Monthly backup restore test | Operations | Disaster recovery SLA verification |

---

## CHANGES ALREADY COMPLETED (PHASES 1–3 + FLUTTER AUTH HARDENING)

The following were implemented in earlier sessions:

- Phase 3: RLS policies, triggers (`prevent_bid_manipulation`, `on_user_suspended`), SECURITY_TEST_CHECKLIST.md
- Phase 4 Flutter: `loginClient()` suspension check, `loginAdmin()` direct table lookup, `getUserRole()` returning 'suspended', `_safeSignOut()` helper, router 'unknown' role handling, router super_admin suspension check, provider stale-data fix (authStateProvider watch), photo upload prefix fix, `_deletePhotos()` fix, `RealtimeLogLevel.error`, `_showBidDialog` loading guard
- Documentation: PRODUCTION_DEPLOYMENT_CHECKLIST.md, INCIDENT_RESPONSE_GUIDE.md

These are considered DONE and not repeated in the remediation roadmap above.

---

## SUMMARY TABLE: WHAT WORKS, WHAT DOESN'T

### Works well
- Three-role authentication architecture (JWT → role lookup → suspend check)
- GoRouter RBAC: suspended/unknown accounts are signed out on navigation
- Riverpod state invalidation on auth change
- RLS-backed data isolation (region_admin can only see their region)
- Edge Function authorization (most functions correctly verify caller role and status)
- Bid placement validates amount server-side (cannot bid below current highest)
- Photo storage with auctionId prefix (deletion works correctly)
- Validators: phone, National ID, password, bid amount all validated client-side

### Works but fragile
- Registration (2-step; orphan account risk on INSERT failure)
- Place-bid (correct logic, but race condition under concurrent load)
- Auto-close auctions (correct logic, but no auth guard + N+1 queries)
- Push notifications (correct delivery, but stale player IDs + no deep-link)

### Doesn't work / not yet set up
- pg_cron (documented but not configured)
- Database indexes (documented but not created)
- Crash reporting (not installed)
- Production alerting (not configured)
- Encryption key persistence across device reinstalls (by design gap)
