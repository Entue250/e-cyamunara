# Phase 1 — AI Training Data Infrastructure Design

**Date:** 2026-06-10  
**Project:** E-CYAMUNARA Online Auction Platform  
**Phase:** 1 of 5 — Data Collection Only  
**Status:** Approved for implementation

---

## Goal

Instrument the platform to passively collect high-quality behavioral and engagement signals during normal operation. No AI models are built in this phase. The output is a populated, indexed dataset ready for ML training in Phase 4.

**Out of scope:** AI prediction, FastAPI, Flutter AI cards, dashboards, estimated_market_value logic, materialized ML views (those are Phase 2–3).

---

## Design Decisions

| Decision | Choice | Reason |
|---|---|---|
| Synchronization strategy | RPC-only (Approach B) | Consistent with existing architecture; explicit, debuggable, atomic |
| View deduplication | 30-minute window per `(viewer_uid, auction_id)` | Balances uniqueness with legitimate re-engagement |
| `seconds_before_end` source | Server-side `now()` inside `accept_bid()` RPC | Client clock manipulation cannot be trusted |
| `bid_sequence` on update | Unchanged — original sequence position kept | A bidder updating their bid is not a new competitive event |
| `unique_bidder_count` trigger | First bid only (`is_bid_update = false`) | Measures number of distinct competitors, not transactions |
| `time_of_first_bid` | Set once, never overwritten | Measures time-to-first-interest; immutable label |
| RPC security | `SECURITY DEFINER` + ownership checks | Consistent with `accept_bid()` and existing Edge Function patterns |
| Counter drift prevention | `views_count` only via `record_auction_view()` RPC | Direct UPDATE bypasses deduplication logic |

---

## Component 1 — Bids Table Enhancements

### New Columns

| Column | Type | Nullable | Default | Constraint |
|---|---|---|---|---|
| `bid_sequence` | INTEGER | YES | NULL | Positive integer; set once on first bid, unchanged on updates |
| `seconds_before_end` | INTEGER | YES | NULL | `>= 0`; computed server-side |
| `bid_increment` | NUMERIC | YES | NULL | `p_bid_amount - current_highest_bid`; equals full bid amount on first bid (baseline 0), negative on reduction |
| `is_bid_update` | BOOLEAN | NO | false | true = bidder raising/lowering own bid |

### Population

All four fields are populated inside `accept_bid()` PostgreSQL RPC within the existing `SELECT … FOR UPDATE` transaction. No client values accepted.

### Backfill

- `is_bid_update`: `true` where `updated_at > created_at + interval '1 second'`
- `bid_sequence`: `ROW_NUMBER() OVER (PARTITION BY auction_id ORDER BY created_at ASC)` — update-only rows (is_bid_update = true) are excluded from sequence increment but still assigned their original sequence number
- `bid_increment` and `seconds_before_end`: left NULL for historical rows (cannot reconstruct `current_highest_bid` at time of bid)

### Indexes

```sql
CREATE INDEX idx_bids_auction_sequence ON bids (auction_id, bid_sequence) WHERE bid_sequence IS NOT NULL;
CREATE INDEX idx_bids_seconds_before_end ON bids (auction_id, seconds_before_end) WHERE seconds_before_end IS NOT NULL;
```

---

## Component 2 — `auction_views` Table

### Schema

```sql
CREATE TABLE auction_views (
  id                    UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id            UUID         NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  viewer_uid            UUID         REFERENCES users(id) ON DELETE SET NULL,
  viewed_at             TIMESTAMPTZ  NOT NULL DEFAULT now(),
  region                TEXT,        -- copied from auction row at insert time
  device_type           TEXT         CHECK (device_type IN ('mobile', 'web', 'unknown')),
  view_duration_seconds INTEGER      -- NULL until end_auction_view() is called
);
```

### Indexes

```sql
CREATE INDEX idx_auction_views_auction   ON auction_views (auction_id, viewed_at DESC);
CREATE INDEX idx_auction_views_viewer    ON auction_views (viewer_uid) WHERE viewer_uid IS NOT NULL;
CREATE INDEX idx_auction_views_region    ON auction_views (region, viewed_at DESC);
```

### RLS

- **INSERT**: authenticated users can insert rows where `viewer_uid = auth.uid()` or `viewer_uid IS NULL`
- **SELECT**: super_admins only
- **UPDATE**: `end_auction_view()` RPC uses `SECURITY DEFINER` — no direct UPDATE policy needed

### RPC: `record_auction_view(p_auction_id, p_viewer_uid, p_device_type)`

```
SECURITY DEFINER, called by authenticated clients
1. Validate p_device_type IN ('mobile', 'web', 'unknown')
2. Check: SELECT id FROM auction_views
          WHERE auction_id = p_auction_id
            AND viewer_uid = p_viewer_uid
            AND viewed_at > now() - interval '30 minutes'
          LIMIT 1
   → If found: return existing view_id, do NOT insert, do NOT increment
3. Fetch auction region from auctions WHERE id = p_auction_id
4. INSERT INTO auction_views (auction_id, viewer_uid, viewed_at, region, device_type)
5. UPDATE auctions SET views_count = views_count + 1 WHERE id = p_auction_id
6. RETURN new view_id
```

### RPC: `end_auction_view(p_view_id, p_duration_seconds)`

```
SECURITY DEFINER, called by authenticated clients
1. Validate p_duration_seconds >= 0 AND <= 86400 (max 24 hours)
2. UPDATE auction_views
   SET view_duration_seconds = p_duration_seconds
   WHERE id = p_view_id
     AND viewer_uid = auth.uid()  -- ownership check
     AND view_duration_seconds IS NULL  -- only set once
```

---

## Component 3 — Auctions Table Enhancements

### New Columns

| Column | Type | Default | Updated by |
|---|---|---|---|
| `views_count` | INTEGER | 0 | `record_auction_view()` only |
| `unique_bidder_count` | INTEGER | 0 | `accept_bid()` — first bid only |
| `time_of_first_bid` | TIMESTAMPTZ | NULL | `accept_bid()` — set once |
| `time_of_last_bid` | TIMESTAMPTZ | NULL | `accept_bid()` — every bid |

### Backfill

```sql
UPDATE auctions a SET unique_bidder_count = (
  SELECT COUNT(DISTINCT bidder_uid) FROM bids WHERE auction_id = a.id
);
UPDATE auctions a SET
  time_of_first_bid = (SELECT MIN(created_at) FROM bids WHERE auction_id = a.id),
  time_of_last_bid  = (SELECT MAX(COALESCE(updated_at, created_at)) FROM bids WHERE auction_id = a.id)
WHERE EXISTS (SELECT 1 FROM bids WHERE auction_id = a.id);
-- views_count: no backfill possible (no historical view data)
```

### Indexes

```sql
CREATE INDEX idx_auctions_views_count         ON auctions (views_count DESC) WHERE is_deleted = false;
CREATE INDEX idx_auctions_unique_bidder_count ON auctions (unique_bidder_count DESC) WHERE is_deleted = false;
```

---

## Component 4 — `accept_bid()` RPC Additions

All additions are inside the existing `SELECT … FOR UPDATE` transaction block. No structural change to the function signature or return type.

### New Logic (additive)

```sql
-- Before the upsert: capture current state
v_is_update     := (SELECT EXISTS (SELECT 1 FROM bids WHERE auction_id = p_auction_id AND bidder_uid = p_bidder_uid));
v_bid_increment := p_bid_amount - a.current_highest_bid;
v_seq           := CASE WHEN v_is_update THEN
                     (SELECT bid_sequence FROM bids WHERE auction_id = p_auction_id AND bidder_uid = p_bidder_uid)
                   ELSE
                     (SELECT COUNT(*) + 1 FROM bids WHERE auction_id = p_auction_id)
                   END;
v_secs_before   := GREATEST(0, EXTRACT(EPOCH FROM (a.end_date - now()))::INTEGER);

-- In the upsert: set new fields
  bid_sequence         = v_seq,
  bid_increment        = v_bid_increment,
  seconds_before_end   = v_secs_before,
  is_bid_update        = v_is_update

-- After the upsert: update auctions row
UPDATE auctions SET
  unique_bidder_count = unique_bidder_count + CASE WHEN v_is_update THEN 0 ELSE 1 END,
  time_of_first_bid   = COALESCE(time_of_first_bid, now()),   -- SET ONCE
  time_of_last_bid    = now()                                  -- ALWAYS UPDATE
WHERE id = p_auction_id;

-- Return payload: add is_bid_update to existing return fields
```

---

## Component 5 — `place-bid` Edge Function

Minimal change. The function calls `accept_bid()` and forwards its return payload to the Flutter client. Add `is_bid_update` to the forwarded response fields so `BidNotifier` can display "Bid updated" vs "Bid placed" in the UI.

No new business logic. No new server-side computation. The Edge Function stays as a thin validation + dispatch layer.

---

## Component 6 — Flutter Model Updates

### `AuctionModel` — new fields

```dart
// Engagement analytics
final int viewsCount;
final int uniqueBidderCount;
final DateTime? timeOfFirstBid;
final DateTime? timeOfLastBid;

// Computed getters (no DB columns)
Duration get auctionDuration => endDate.difference(startDate);
Duration? get timeToFirstBid => timeOfFirstBid?.difference(startDate);
```

### `BidModel` — new fields

```dart
final int? bidSequence;
final int? secondsBeforeEnd;
final double? bidIncrement;
final bool isBidUpdate;
```

All changes: backward-safe, nullable defaults, `fromMap` / `toMap` / `copyWith` updated.

---

## Migration File Plan

| File | Content |
|---|---|
| `20260610000002_bid_behavioral_fields.sql` | ADD COLUMN bid_sequence/seconds_before_end/bid_increment/is_bid_update + backfill + indexes |
| `20260610000003_auction_views_table.sql` | CREATE TABLE auction_views + RLS + indexes + record_auction_view() + end_auction_view() |
| `20260610000004_auction_engagement_fields.sql` | ADD COLUMN views_count/unique_bidder_count/time_of_first_bid/time_of_last_bid + backfill + indexes |
| `20260610000005_update_accept_bid_rpc.sql` | Full rewrite of accept_bid() with new logic; preserves function signature |

---

## Validation Queries

Included in each migration file and documented separately. Key checks:

- `bid_sequence` is null-free for new bids and unique per `(auction_id, bid_sequence)` for non-update bids
- `unique_bidder_count` matches `SELECT COUNT(DISTINCT bidder_uid) FROM bids WHERE auction_id = ?`
- `views_count` matches `SELECT COUNT(*) FROM auction_views WHERE auction_id = ?`
- `time_of_first_bid` equals `SELECT MIN(created_at) FROM bids WHERE auction_id = ?`
- No duplicate `(viewer_uid, auction_id)` rows within 30-minute windows

---

## Rollback Strategy

Every migration includes a `-- ROLLBACK` section. The sequence is:

1. Rollback `accept_bid()` → restore previous version (saved in migration comment)
2. Rollback `auction_engagement_fields` → DROP COLUMN views_count, unique_bidder_count, time_of_first_bid, time_of_last_bid
3. Rollback `auction_views` → DROP TABLE auction_views CASCADE; DROP FUNCTION record_auction_view; DROP FUNCTION end_auction_view
4. Rollback `bid_behavioral_fields` → DROP COLUMN bid_sequence, seconds_before_end, bid_increment, is_bid_update

Flutter models are backward-compatible. Rollback of Flutter app is not required for DB-only rollback.

---

## Deployment Order

1. Deploy migration 000002 (bids fields)
2. Deploy migration 000003 (auction_views + RPCs)
3. Deploy migration 000004 (auctions fields)
4. Deploy migration 000005 (updated accept_bid RPC)
5. Deploy updated place-bid Edge Function
6. Release Flutter update with new model fields
7. Run validation queries
8. Confirm `flutter analyze` passes

Steps 1–4 are safe to deploy before the Flutter release (new columns are nullable/defaulted). Step 5 must come after Step 4. Step 6 can be released any time after Steps 1–4.
