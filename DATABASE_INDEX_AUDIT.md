# DATABASE INDEX AUDIT — E-CYAMUNARA
Last updated: 2026-04-23

All indexes inferred from query patterns in repositories, Edge Functions, and screens.
Run the SQL statements below in Supabase Dashboard → SQL Editor to create missing indexes.

---

## METHODOLOGY

Every query against each table was catalogued from:
- `lib/data/repositories/*.dart`
- `supabase/functions/*/index.ts`
- `lib/presentation/screens/**/*.dart`

The WHERE clauses and ORDER BY columns drive index requirements.
All primary keys (`id` UUID) are automatically indexed by PostgreSQL.

---

## TABLE: auctions

### Queries observed:
| Query | Source | Columns used |
|-------|--------|-------------|
| `.eq('region', region).where(status='active')` | `getAuctionsByRegion()` | region, auction_status |
| `.eq('auction_status','active').lte('end_date', now)` | `auto-close-auctions` | auction_status, end_date |
| `.eq('posted_by_admin_uid', adminUid)` | `getAdminAuctions()` | posted_by_admin_uid |
| `.gte('created_at', start).lte('created_at', end)` | `generate-report` | created_at |
| `.eq('auction_status','active').eq('region', r)` | `generate-report` | auction_status, region |

### Recommended indexes:
```sql
-- For home screen: filter active auctions by region, sort by end_date
CREATE INDEX IF NOT EXISTS idx_auctions_region_status_end
  ON auctions (region, auction_status, end_date ASC);

-- For auto-close-auctions: expired active auctions
CREATE INDEX IF NOT EXISTS idx_auctions_status_end
  ON auctions (auction_status, end_date ASC)
  WHERE auction_status = 'active';

-- For admin's own auctions list
CREATE INDEX IF NOT EXISTS idx_auctions_posted_by
  ON auctions (posted_by_admin_uid, created_at DESC);

-- For report queries
CREATE INDEX IF NOT EXISTS idx_auctions_created_at
  ON auctions (created_at DESC);
```

---

## TABLE: bids

### Queries observed:
| Query | Source | Columns used |
|-------|--------|-------------|
| `.eq('auction_id', id).eq('bidder_uid', uid).eq('bid_status','winning')` | `place-bid` | auction_id, bidder_uid, bid_status |
| `.eq('auction_id', id).eq('bid_status','outbid')` | `auto-close-auctions` | auction_id, bid_status |
| `.eq('bidder_uid', uid)` | `MyBidsScreen` | bidder_uid |
| `SELECT bidder_uid, COUNT(*) ... GROUP BY bidder_uid` | incident response SQL | bidder_uid |
| `SELECT MAX(bid_amount) FROM bids WHERE auction_id = ...` | data repair SQL | auction_id, bid_amount |

### Recommended indexes:
```sql
-- Most critical: bid lookup by auction (used in every bid placement)
CREATE INDEX IF NOT EXISTS idx_bids_auction_id
  ON bids (auction_id, bid_amount DESC);

-- Outbid notification lookup
CREATE INDEX IF NOT EXISTS idx_bids_auction_status
  ON bids (auction_id, bid_status);

-- My bids screen: user's own bids, newest first
CREATE INDEX IF NOT EXISTS idx_bids_bidder
  ON bids (bidder_uid, created_at DESC);

-- Data repair and analytics
CREATE INDEX IF NOT EXISTS idx_bids_auction_bidder
  ON bids (auction_id, bidder_uid, bid_status);

-- Incident response: bid flood detection
CREATE INDEX IF NOT EXISTS idx_bids_created_at
  ON bids (created_at DESC);
```

---

## TABLE: users

### Queries observed:
| Query | Source | Columns used |
|-------|--------|-------------|
| `.eq('id', uid)` | everywhere | id (PK, auto-indexed) |
| `.eq('region', region).eq('account_status','active')` | `on-new-auction` | region, account_status |
| `.eq('account_status','active')` | `ClientManagementScreen` | account_status |
| `.select('account_status').eq('id', uid)` | `loginClient()`, `place-bid` | id (PK) |

### Recommended indexes:
```sql
-- For on-new-auction: find all active clients in a region
CREATE INDEX IF NOT EXISTS idx_users_region_status
  ON users (region, account_status);

-- For ClientManagementScreen: filter by status
CREATE INDEX IF NOT EXISTS idx_users_status
  ON users (account_status);
```

---

## TABLE: notifications

### Queries observed:
| Query | Source | Columns used |
|-------|--------|-------------|
| `.eq('user_uid', uid).order('created_at', ascending: false)` | `NotificationsScreen` | user_uid, created_at |
| `.lt('created_at', cutoff)` | `cleanup-notifications` | created_at |
| `.eq('user_uid', uid)` | in-app notification read | user_uid |

### Recommended indexes:
```sql
-- Most critical: user's notification list, newest first
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON notifications (user_uid, created_at DESC);

-- Cleanup function: delete old notifications efficiently
CREATE INDEX IF NOT EXISTS idx_notifications_created_at
  ON notifications (created_at ASC);
```

---

## TABLE: region_admins

### Queries observed:
| Query | Source | Columns used |
|-------|--------|-------------|
| `.eq('id', uid)` | everywhere | id (PK) |
| `.eq('region', region)` | `create-admin` | region |
| `.eq('id', auction.posted_by_admin_uid)` | `place-bid`, `auto-close` | id (PK) |

### Recommended indexes:
```sql
-- For create-admin duplicate region check
CREATE INDEX IF NOT EXISTS idx_region_admins_region
  ON region_admins (region);
```

---

## TABLE: super_admins / districts / app_settings / feedback

These tables are small (< 100 rows each) and do not require additional indexes beyond the primary key. Full sequential scans on these tables are fast.

---

## MISSING CONSTRAINT: UNIQUE WINNING BID

The TOCTOU race condition (FM-01) can produce multiple `bid_status = 'winning'` rows per auction per bidder. A partial unique index enforces the invariant at the DB level:

```sql
-- Enforce: each bidder can have at most one winning bid per auction
CREATE UNIQUE INDEX IF NOT EXISTS idx_bids_one_winner_per_auction
  ON bids (auction_id, bidder_uid)
  WHERE bid_status = 'winning';
```

This constraint alone would prevent the race condition from producing duplicate winning bids — the second concurrent INSERT would fail with a unique constraint violation, allowing the Edge Function to detect and handle the race gracefully.

---

## PERFORMANCE VERIFICATION QUERY

Run after creating indexes to verify they are being used:

```sql
-- Check index usage (run after some production traffic)
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan AS times_used,
  idx_tup_read AS rows_read,
  idx_tup_fetch AS rows_fetched
FROM pg_stat_user_indexes
WHERE schemaname = 'public'
ORDER BY tablename, idx_scan DESC;
```

Indexes with `times_used = 0` after 24 hours of production traffic should be reviewed and removed if truly unused (they add write overhead with no read benefit).

---

## EXPLAIN PLAN CHECKS TO RUN BEFORE LAUNCH

```sql
-- Should use idx_auctions_region_status_end
EXPLAIN SELECT * FROM auctions 
WHERE region = 'Eastern' AND auction_status = 'active'
ORDER BY end_date ASC;

-- Should use idx_bids_auction_id
EXPLAIN SELECT bid_amount FROM bids 
WHERE auction_id = 'test-id'
ORDER BY bid_amount DESC
LIMIT 1;

-- Should use idx_notifications_user_created
EXPLAIN SELECT * FROM notifications
WHERE user_uid = 'test-uid'
ORDER BY created_at DESC
LIMIT 50;
```

All three should show `Index Scan` in the output, not `Seq Scan`. If you see `Seq Scan` after the index is created, the table may have too few rows for PostgreSQL to prefer the index — this resolves automatically once the table grows.
