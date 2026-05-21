# OBSERVABILITY AND ALERTING PLAN — E-CYAMUNARA
Last updated: 2026-04-23

---

## OBSERVABILITY GAPS (CURRENT STATE)

| Area | Current instrumentation | Gap |
|------|------------------------|-----|
| Flutter crashes | None | No crash reporting library |
| Edge Function errors | `console.error()` → Supabase logs | No structured logging, no alerting |
| Bid success/failure rate | None | No metrics |
| DB performance | Supabase Dashboard (manual review) | No automated alerts |
| Realtime connection count | Supabase Dashboard (manual review) | No automated alerts |
| Cron job execution | None | No monitoring |
| Push notification delivery | OneSignal dashboard (manual) | No alerting on delivery failure |
| Authentication failures | Supabase Auth logs | No alerting |

---

## LAYER 1 — SUPABASE BUILT-IN MONITORING

### Database Alerts (set up in Supabase Dashboard → Reports → Alerts)

These must be configured before launch:

| Alert | Threshold | Action |
|-------|-----------|--------|
| CPU usage | > 70% for 5 consecutive minutes | Investigate slow queries; add indexes |
| DB connections | > 80% of max (400/500 on Pro) | Scale up or add connection pooling |
| Storage usage | > 80% of plan limit | Increase plan or archive old data |
| Edge Function error rate | > 5% of invocations | Check function logs, possible redeploy |
| Realtime connection count | > 80% of max (400/500) | Switch home screen to polling |

**How to configure:**
Supabase Dashboard → Reports → Database → set thresholds → enter alert email.

### Supabase Logs (available in Dashboard → Logs)

Useful queries for daily health checks:

```sql
-- Edge Function errors in last 24 hours
-- Filter: Level = ERROR, Time = last 24h
-- Look for: place-bid errors (indicate bid failures)

-- Auth failures in last 24 hours  
-- Filter: auth logs, status 4xx
-- High count suggests brute force or bug

-- Slow queries (> 1 second)
-- Dashboard → Reports → Query Performance
-- Sort by mean_exec_time DESC
```

---

## LAYER 2 — FLUTTER CRASH REPORTING (RECOMMENDED)

**Current state:** No crash reporting. When the app crashes in production, the only signal is users calling support.

**Recommended tool:** Sentry (free tier available)

**Setup:**
```yaml
# pubspec.yaml
dependencies:
  sentry_flutter: ^7.19.0
```

```dart
// main.dart
await SentryFlutter.init(
  (options) {
    options.dsn = const String.fromEnvironment('SENTRY_DSN');
    options.tracesSampleRate = 0.1; // 10% of sessions
    options.environment = const String.fromEnvironment('ENV', defaultValue: 'production');
  },
  appRunner: () => runApp(const App()),
);
```

**Build with DSN:**
```bash
flutter build apk --release --dart-define=SENTRY_DSN=https://your-key@sentry.io/project
```

**What to capture:**
- All unhandled Flutter exceptions (automatic)
- Edge Function call failures (manual: `Sentry.captureException(e)` in bid notifier)
- Registration failures (manual: in `registerClient()` catch block)

---

## LAYER 3 — EDGE FUNCTION STRUCTURED LOGGING

**Current state:** `console.error('place-bid error:', err)` — raw, no context.

**Recommended:** Add a request ID and relevant business context to every log line:

```typescript
// At the top of each function handler
const requestId = crypto.randomUUID().slice(0, 8);
const log = (level: string, msg: string, data?: Record<string, unknown>) =>
  console[level](JSON.stringify({ requestId, ts: new Date().toISOString(), msg, ...data }));

// Usage
log('info', 'bid received', { auction_id, bidder_uid, bid_amount });
log('error', 'bid insert failed', { error: String(e), auction_id });
```

This makes filtering in Supabase Logs much more effective: you can search `requestId` to trace a full bid flow across all log lines.

---

## LAYER 4 — CRITICAL FLOW MONITORING

### Bid Pipeline Health Check

Create a daily scheduled SQL query (or manual check) to detect bid/auction desync:

```sql
-- Run daily: finds auctions where bid counters are wrong
SELECT a.id, a.item_name,
       a.current_highest_bid, MAX(b.bid_amount) as db_highest,
       a.total_bids, COUNT(b.id) as db_count
FROM auctions a
LEFT JOIN bids b ON b.auction_id = a.id
WHERE a.auction_status = 'active'
GROUP BY a.id, a.item_name, a.current_highest_bid, a.total_bids
HAVING a.current_highest_bid != COALESCE(MAX(b.bid_amount), a.starting_price)
    OR a.total_bids != COUNT(b.id);
```

If this query returns any rows, run the repair SQL from INCIDENT_RESPONSE_GUIDE.md INCIDENT 4.

### Expired-But-Open Auction Check

```sql
-- Auctions that should be closed but aren't
-- Indicates auto-close-auctions cron failed
SELECT id, item_name, end_date, auction_status
FROM auctions
WHERE auction_status = 'active' AND end_date < NOW() - INTERVAL '10 minutes';
```

If this returns rows, the pg_cron job may not be configured or is failing. Check Supabase Dashboard → Database → Extensions → pg_cron → job log.

### Auth Anomaly Check

```sql
-- Unusual login volume (possible brute force)
-- Run in Supabase Dashboard → SQL Editor
SELECT DATE_TRUNC('hour', created_at) as hour, COUNT(*) as auth_events
FROM auth.audit_log_entries
WHERE created_at > NOW() - INTERVAL '24 hours'
GROUP BY 1 ORDER BY 1;
```

---

## LAYER 5 — ONESIGNAL MONITORING

**OneSignal Dashboard → Delivery** shows:
- Delivered / Failed / Errored per notification
- Failed devices (stale player IDs)
- Delivery rate trends

**Alerting:** OneSignal Pro plan supports email alerts on delivery failure rate. For free plan: check the dashboard weekly and compare `Delivered / Sent` ratio. Below 70% indicates widespread stale player IDs.

---

## LAYER 6 — PERFORMANCE BASELINES TO ESTABLISH

Before going to 500+ users, record these baselines for future comparison:

| Metric | How to measure | Record |
|--------|---------------|--------|
| `place-bid` p50 latency | Supabase Logs → filter by function | Target: < 2 seconds |
| Home screen load time | Flutter DevTools → Frame timeline | Target: < 3 seconds |
| Auction detail first render | Flutter DevTools | Target: < 1 second |
| DB query p99 time | Supabase → Reports → Query Performance | Target: < 500ms |
| Push notification delivery rate | OneSignal dashboard | Target: > 85% |

---

## ALERTING ESCALATION MATRIX

| Alert | Severity | First responder | Escalation |
|-------|---------|----------------|-----------|
| Supabase down (status.supabase.com) | P2 | Check status page, wait | Notify users via OneSignal |
| Edge Function error rate > 10% | P1 | Check logs, redeploy | Super admin |
| DB CPU > 90% for 5 min | P1 | Identify slow query | Supabase support |
| Bid/auction desync detected | P1 | Run repair SQL | Super admin + RNP |
| Auth failures spike > 100/hour | P2 | Check Supabase Auth logs | Super admin |
| Push delivery rate drops < 50% | P3 | Check OneSignal, refresh player IDs | Non-urgent |
| App crash rate > 1% | P2 | Check Sentry, identify build | Release fix |

---

## MINIMUM VIABLE OBSERVABILITY FOR LAUNCH

Before first public launch, the following MUST be in place:

- [ ] Supabase DB CPU alert configured (> 70%)
- [ ] Supabase DB connection alert configured (> 80%)
- [ ] Edge Function error alerts configured (> 5%)
- [ ] Daily bid/auction desync SQL check scheduled (manual or pg_cron)
- [ ] Expired-but-open auction SQL check scheduled every hour
- [ ] At least one admin has Supabase Dashboard access and email alerts enabled
- [ ] OneSignal dashboard access for the primary operator

Optional but strongly recommended:
- [ ] Sentry integrated in the Flutter build
- [ ] Structured logging added to place-bid and close-auction-manually
