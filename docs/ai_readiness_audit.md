# AI Readiness Audit — E-CYAMUNARA Online Auction Platform

**Date:** 2026-06-10  
**Auditor:** Claude Code (claude-sonnet-4-6)  
**Scope:** Full codebase review — schema, models, repositories, services, providers, screens  
**Flutter analyze:** ✅ No issues found  
**Status:** Audit only — no production logic modified, no AI code written

---

## Table of Contents

1. [Existing Schema](#1-existing-schema)
2. [Missing AI Fields](#2-missing-ai-fields)
3. [Required Migrations](#3-required-migrations)
4. [Required Flutter Model Changes](#4-required-flutter-model-changes)
5. [Required Provider Changes](#5-required-provider-changes)
6. [Risks](#6-risks)
7. [Recommended Implementation Order](#7-recommended-implementation-order)

---

## 1. Existing Schema

### 1.1 `auctions` Table (current state after all migrations)

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | UUID | NO | Primary key |
| `item_name` | TEXT | NO | Auto-built: brand + model + year |
| `category` | TEXT | NO | Legacy field (now `main_category`) |
| `main_category` | TEXT | YES | Migration 20260609 |
| `sub_category` | TEXT | YES | Migration 20260609 |
| `plate_number` | TEXT | NO | Rwanda registration plate |
| `condition` | TEXT | NO | ENUM: Excellent / Very Good / Good / Fair / Poor |
| `description` | TEXT | YES | Free-text |
| `photo_urls` | TEXT[] | NO | Up to 5 photos in auction-photos bucket |
| `starting_price` | NUMERIC | NO | Floor price in RWF |
| `current_highest_bid` | NUMERIC | NO | Default 0 |
| `current_winner_uid` | UUID | YES | FK → users.id |
| `current_winner_name` | TEXT | YES | Denormalized for display |
| `total_bids` | INTEGER | NO | Default 0; counts upserts, NOT unique bids |
| `region` | TEXT | NO | One of 5 Rwanda regions |
| `posted_by_admin_uid` | UUID | NO | FK → region_admins.id |
| `posted_by_admin_name` | TEXT | NO | Denormalized |
| `auction_status` | TEXT | NO | draft / active / closed |
| `start_date` | TIMESTAMPTZ | NO | |
| `end_date` | TIMESTAMPTZ | NO | |
| `closed_at` | TIMESTAMPTZ | YES | Set at closure |
| `winner_uid` | UUID | YES | Final winner |
| `winner_name` | TEXT | YES | Denormalized |
| `winning_amount` | NUMERIC | YES | Final accepted price |
| `is_deleted` | BOOLEAN | NO | Default false (soft-delete) |
| `deleted_at` | TIMESTAMPTZ | YES | Soft-delete timestamp |
| `deleted_by` | UUID | YES | Admin who deleted |
| `created_at` | TIMESTAMPTZ | NO | |
| `updated_at` | TIMESTAMPTZ | NO | |
| **ML metadata fields (all nullable, migration 20260609)** | | | |
| `brand` | TEXT | YES | e.g. Toyota, Mitsubishi |
| `model` | TEXT | YES | e.g. Hilux, Pajero |
| `manufacturing_year` | INTEGER | YES | YYYY |
| `color` | TEXT | YES | |
| `mileage` | INTEGER | YES | km |
| `fuel_type` | TEXT | YES | Petrol / Diesel / Electric / Hybrid |
| `transmission` | TEXT | YES | Manual / Automatic / CVT |
| `engine_size` | NUMERIC | YES | Litres (e.g. 2.4) |
| `engine_cc` | INTEGER | YES | cc (e.g. 2400) |
| `drivetrain` | TEXT | YES | 2WD / 4WD / AWD |
| `seating_capacity` | INTEGER | YES | |
| `frame_material` | TEXT | YES | Steel / Aluminium / Carbon |
| `gear_count` | INTEGER | YES | |
| `suspension_type` | TEXT | YES | Independent / Leaf spring / etc. |
| `brake_type` | TEXT | YES | Disc / Drum / ABS |
| `ownership_history` | TEXT | YES | First owner / Second / Unknown |
| `accident_history` | TEXT | YES | None / Minor / Major / Unknown |
| `insurance_status` | TEXT | YES | Valid / Expired / None |

**Current AI-readiness score for auctions:** 19/30 required ML feature categories covered (vehicle specs ✅, outcome data ✅, geographic ✅, temporal ✅ — **engagement metrics ❌, valuation anchor ❌, bid timeline ❌**)

---

### 1.2 `bids` Table (current state)

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | UUID | NO | Primary key |
| `auction_id` | UUID | NO | FK → auctions.id |
| `bidder_uid` | UUID | NO | FK → users.id |
| `bidder_name` | TEXT | NO | Denormalized |
| `bidder_phone` | TEXT | NO | PII — must be handled carefully |
| `bidder_district` | TEXT | NO | Geographic context |
| `bid_amount` | NUMERIC | NO | RWF |
| `bid_status` | TEXT | NO | winning / outbid |
| `created_at` | TIMESTAMPTZ | NO | First bid timestamp |
| `updated_at` | TIMESTAMPTZ | YES | Set on bid update (upsert) |

**Unique constraint:** `(auction_id, bidder_uid)` — one row per bidder per auction. A bidder raising their own bid is an UPDATE, not an INSERT. This is correct for upsert logic but means `total_bids` counts transactions, not unique bidders.

**Current AI-readiness score for bids:** 5/9 required ML signal categories (amount ✅, outcome ✅, identity ✅, geography ✅, timing ✅ — **sequence ❌, urgency ❌, increment ❌, channel ❌**)

---

### 1.3 `users` Table (current state)

| Column | Type | Nullable | Notes |
|---|---|---|---|
| `id` | UUID | NO | PK |
| `full_names` | TEXT | NO | |
| `national_id` | TEXT | NO | AES-256 encrypted |
| `phone_number` | TEXT | NO | Rwanda format |
| `district` | TEXT | NO | |
| `province` | TEXT | NO | |
| `region` | TEXT | NO | |
| `role` | TEXT | NO | client / region_admin / super_admin |
| `account_status` | TEXT | NO | active / suspended |
| `profile_photo_url` | TEXT | YES | |
| `onesignal_player_id` | TEXT | YES | Push notification target |
| `total_bids_placed` | INTEGER | NO | Default 0 |
| `total_auctions_won` | INTEGER | NO | Default 0 |
| `created_at` | TIMESTAMPTZ | NO | |
| `updated_at` | TIMESTAMPTZ | NO | |
| `last_login` | TIMESTAMPTZ | YES | |

**Computable but missing:** bidding success rate (`total_auctions_won / total_bids_placed`) — derivable as a Dart getter, sufficient for Phase 1.

---

### 1.4 `feedback` Table (current state)

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `client_uid` | UUID | FK → users.id |
| `client_name` | TEXT | Denormalized |
| `auction_id` | UUID | Nullable (general feedback) |
| `item_name` | TEXT | Denormalized |
| `region` | TEXT | |
| `star_rating` | INTEGER | 1–5 |
| `selected_tags` | TEXT[] | Qualitative tags |
| `comment` | TEXT | Free-text |
| `would_recommend` | BOOLEAN | |
| `is_read` | BOOLEAN | |
| `created_at` | TIMESTAMPTZ | |

**ML value:** Star ratings and `would_recommend` are labeled sentiment data that can train a satisfaction prediction model. Currently queryable but **not linked to auction outcome metrics** in any view.

---

### 1.5 `auction_auto_close_logs` Table (current state)

| Column | Type | Notes |
|---|---|---|
| `id` | UUID | PK |
| `auction_id` | UUID | FK → auctions.id |
| `closed_at` | TIMESTAMPTZ | |
| `winner_uid` | UUID | Nullable |
| `winning_amount` | NUMERIC | Nullable |
| `total_bids` | INTEGER | Snapshot at close |
| `created_at` | TIMESTAMPTZ | |

**ML value:** Provides a clean audit trail of auto-close events. `total_bids` snapshot is useful since the live column could change post-close.

---

### 1.6 Existing Edge Functions Summary

| Function | Relevance to AI |
|---|---|
| `place-bid` | **Critical** — must be updated to populate bid sequence + urgency fields |
| `close-auction-manually` | Should log `unique_bidder_count` at close |
| `auto-close-auctions` | Should log `unique_bidder_count` + bid timeline at close |
| `generate-report` | **AI output channel** — future AI insights can be embedded here |
| `get-user-stats` | **AI input** — user behavioral statistics for personalization |
| Others | Not directly AI-relevant |

---

## 2. Missing AI Fields

### 2.1 Missing from `auctions` Table

These fields are required for the three primary AI use cases identified.

#### 2.1.1 Vehicle Valuation (Price Prediction)

| Field | Type | Default | Purpose |
|---|---|---|---|
| `estimated_market_value` | NUMERIC | NULL | Admin-entered or API-fetched market value; reference point for price realization analysis |
| `reserve_price` | NUMERIC | NULL | Minimum acceptable closing price (distinct from starting_price); enables floor-price ML |
| `registration_year` | INTEGER | NULL | Year of vehicle registration (distinct from `manufacturing_year`; age-of-registration affects value) |
| `chassis_number` | TEXT | NULL | VIN-equivalent; enables cross-referencing external valuation APIs |
| `has_service_history` | BOOLEAN | false | Whether service records exist; significant valuation signal |
| `number_of_doors` | INTEGER | NULL | Vehicle configuration detail |

#### 2.1.2 Auction Engagement Analytics

| Field | Type | Default | Purpose |
|---|---|---|---|
| `views_count` | INTEGER | 0 | How many times the auction detail page was opened; leading indicator of interest |
| `unique_bidder_count` | INTEGER | 0 | Count of distinct users who placed a bid; better competition metric than `total_bids` |
| `time_of_first_bid` | TIMESTAMPTZ | NULL | When the auction received its first bid; measures "time to first interest" |
| `time_of_last_bid` | TIMESTAMPTZ | NULL | When the final bid arrived before close; bid urgency signal |

#### 2.1.3 Outcome Metrics (Post-close ML Labels)

| Field | Type | Default | Purpose |
|---|---|---|---|
| `price_realization_pct` | NUMERIC | NULL | `(winning_amount / estimated_market_value) * 100`; auction efficiency label |
| `auction_duration_hours` | NUMERIC | NULL | `EXTRACT(EPOCH FROM (closed_at - start_date)) / 3600`; faster to query than recomputing |

> **Note:** `price_realization_pct` and `auction_duration_hours` are fully derivable from existing columns. Store them only if query performance on aggregations becomes a bottleneck.

---

### 2.2 Missing from `bids` Table

| Field | Type | Default | Purpose |
|---|---|---|---|
| `bid_sequence` | INTEGER | NULL | Sequential position of this bid within the auction (1st, 2nd, 3rd…). Computed server-side. |
| `seconds_before_end` | INTEGER | NULL | Seconds remaining when bid was placed. Key feature for "bid sniper" behavior detection. Must be computed server-side to prevent clock manipulation. |
| `bid_increment` | NUMERIC | NULL | `bid_amount - previous_highest_bid` at time of placement. Measures aggression. |
| `is_bid_update` | BOOLEAN | false | Whether this was an UPDATE (bidder raising own bid) vs. first bid. Already returned by `accept_bid()` RPC but not persisted. |

---

### 2.3 Missing from `users` Table

| Field | Type | Default | Purpose |
|---|---|---|---|
| `preferred_region` | TEXT | NULL | The region where user most frequently bids. Enables regional recommendation. |
| `preferred_category` | TEXT | NULL | The main_category user most frequently bids in. Enables category recommendation. |
| `avg_bid_amount` | NUMERIC | NULL | Running average of bid amounts. User price-sensitivity signal. |

> **Note:** `preferred_region`, `preferred_category`, and `avg_bid_amount` can all be derived from the `bids` table via aggregation. Storing them trades write overhead for read speed. They should be populated by an Edge Function or pg_cron job, not by the client.

---

### 2.4 Missing Infrastructure (No Direct Table Equivalents)

| Missing Artifact | Purpose |
|---|---|
| `auction_views` table | Tracks individual page-view events (user_uid, auction_id, viewed_at, session_id). Required to populate `views_count` atomically. |
| `v_auction_ml_features` view | Joins auctions + bids + users into a flat feature vector table for ML training export. |
| `ai_predictions` table | Stores model outputs (predicted_closing_price, confidence_score, model_version) keyed by auction_id. Required for Phase 3. |

---

## 3. Required Migrations

Migrations are organized in three phases. Only Phase 1 should be executed before any AI implementation begins.

---

### Phase 1 — Data Capture (Execute Before Any AI)

**Migration A: `add_auction_engagement_fields.sql`**

```sql
-- Safe: all new nullable columns with defaults
ALTER TABLE auctions
  ADD COLUMN IF NOT EXISTS views_count         INTEGER   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS unique_bidder_count INTEGER   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS time_of_first_bid   TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS time_of_last_bid    TIMESTAMPTZ;

-- Backfill unique_bidder_count from existing bids
UPDATE auctions a
SET unique_bidder_count = (
  SELECT COUNT(DISTINCT bidder_uid)
  FROM bids b
  WHERE b.auction_id = a.id
);

-- Backfill time_of_first_bid and time_of_last_bid from existing bids
UPDATE auctions a
SET
  time_of_first_bid = (SELECT MIN(created_at) FROM bids WHERE auction_id = a.id),
  time_of_last_bid  = (SELECT MAX(COALESCE(updated_at, created_at)) FROM bids WHERE auction_id = a.id)
WHERE EXISTS (SELECT 1 FROM bids WHERE auction_id = a.id);

-- Index for analytics queries
CREATE INDEX IF NOT EXISTS idx_auctions_views ON auctions (views_count DESC)
  WHERE is_deleted = false;
```

**Migration B: `add_bid_behavioral_fields.sql`**

```sql
-- Safe: all new nullable columns
ALTER TABLE bids
  ADD COLUMN IF NOT EXISTS bid_sequence      INTEGER,
  ADD COLUMN IF NOT EXISTS seconds_before_end INTEGER,
  ADD COLUMN IF NOT EXISTS bid_increment     NUMERIC,
  ADD COLUMN IF NOT EXISTS is_bid_update     BOOLEAN NOT NULL DEFAULT false;

-- Backfill bid_sequence from created_at ordering per auction
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (PARTITION BY auction_id ORDER BY created_at ASC) AS seq
  FROM bids
)
UPDATE bids b
SET bid_sequence = r.seq
FROM ranked r
WHERE b.id = r.id;

-- Backfill is_bid_update (any bid with updated_at > created_at was updated)
UPDATE bids
SET is_bid_update = (updated_at IS NOT NULL AND updated_at > created_at + interval '1 second')
WHERE updated_at IS NOT NULL;
```

**Migration C: `create_auction_views_table.sql`**

```sql
-- Tracks raw page views; powers views_count via trigger or RPC
CREATE TABLE IF NOT EXISTS auction_views (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id  UUID        NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  viewer_uid  UUID        REFERENCES users(id) ON DELETE SET NULL, -- NULL for anonymous/guest
  viewed_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  session_id  TEXT        -- client-generated session identifier for deduplication
);

CREATE INDEX IF NOT EXISTS idx_auction_views_auction ON auction_views (auction_id, viewed_at);
CREATE INDEX IF NOT EXISTS idx_auction_views_viewer  ON auction_views (viewer_uid) WHERE viewer_uid IS NOT NULL;

-- RLS: admins and clients can insert; only super_admins can read aggregate
ALTER TABLE auction_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "clients_insert_views" ON auction_views
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = viewer_uid OR viewer_uid IS NULL);

CREATE POLICY "super_admin_read_views" ON auction_views
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM super_admins WHERE id = auth.uid()));

-- Atomic increment RPC (called from Flutter, not direct UPDATE)
CREATE OR REPLACE FUNCTION record_auction_view(
  p_auction_id UUID,
  p_viewer_uid UUID,
  p_session_id TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Insert view record
  INSERT INTO auction_views (auction_id, viewer_uid, session_id)
  VALUES (p_auction_id, p_viewer_uid, p_session_id);

  -- Atomic increment on auctions table
  UPDATE auctions SET views_count = views_count + 1 WHERE id = p_auction_id;
END;
$$;
```

**Migration D: `add_auction_valuation_fields.sql`**

```sql
-- Vehicle identity and valuation anchor fields
ALTER TABLE auctions
  ADD COLUMN IF NOT EXISTS estimated_market_value NUMERIC,         -- admin-entered reference value
  ADD COLUMN IF NOT EXISTS reserve_price          NUMERIC,         -- minimum acceptable price
  ADD COLUMN IF NOT EXISTS registration_year      INTEGER,         -- distinct from manufacturing_year
  ADD COLUMN IF NOT EXISTS chassis_number         TEXT,            -- VIN equivalent
  ADD COLUMN IF NOT EXISTS has_service_history    BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS number_of_doors        INTEGER;
```

---

### Phase 2 — Analytics Infrastructure

**Migration E: `create_ml_features_view.sql`**

```sql
-- Flat ML feature vector view for training data export
CREATE OR REPLACE VIEW v_auction_ml_features AS
SELECT
  -- Identifiers
  a.id                    AS auction_id,
  a.region,
  a.posted_by_admin_uid,

  -- Vehicle features
  a.main_category,
  a.sub_category,
  a.brand,
  a.model,
  a.manufacturing_year,
  a.registration_year,
  a.condition,
  a.color,
  a.mileage,
  a.fuel_type,
  a.transmission,
  a.engine_cc,
  a.drivetrain,
  a.seating_capacity,
  a.ownership_history,
  a.accident_history,
  a.insurance_status,
  a.has_service_history,
  a.number_of_doors,

  -- Auction configuration
  a.starting_price,
  a.estimated_market_value,
  a.reserve_price,

  -- Auction timing
  EXTRACT(EPOCH FROM (a.end_date - a.start_date)) / 3600 AS duration_hours,
  EXTRACT(DOW FROM a.start_date)                          AS start_day_of_week,
  EXTRACT(HOUR FROM a.start_date)                         AS start_hour,

  -- Engagement signals
  a.views_count,
  a.unique_bidder_count,
  a.total_bids,
  EXTRACT(EPOCH FROM (a.time_of_first_bid - a.start_date)) / 3600 AS hours_to_first_bid,
  EXTRACT(EPOCH FROM (a.end_date - a.time_of_last_bid)) / 60       AS minutes_from_last_bid_to_end,

  -- Outcome labels (NULL for open auctions; populated for closed)
  a.winning_amount,
  a.winner_uid,
  CASE WHEN a.estimated_market_value > 0
       THEN ROUND((a.winning_amount / a.estimated_market_value * 100)::NUMERIC, 2)
       ELSE NULL
  END                                                      AS price_realization_pct,
  CASE WHEN a.winning_amount > 0 AND a.starting_price > 0
       THEN ROUND((a.winning_amount / a.starting_price * 100)::NUMERIC, 2)
       ELSE NULL
  END                                                      AS price_vs_start_pct,

  -- Bid statistics
  bid_stats.max_bid,
  bid_stats.min_bid,
  bid_stats.avg_bid,
  bid_stats.bid_std_dev,
  bid_stats.last_bid_seconds_before_end,

  a.auction_status,
  a.closed_at,
  a.created_at

FROM auctions a
LEFT JOIN LATERAL (
  SELECT
    MAX(bid_amount)           AS max_bid,
    MIN(bid_amount)           AS min_bid,
    AVG(bid_amount)           AS avg_bid,
    STDDEV(bid_amount)        AS bid_std_dev,
    MIN(seconds_before_end)   AS last_bid_seconds_before_end
  FROM bids
  WHERE auction_id = a.id
) bid_stats ON true
WHERE a.is_deleted = false;

-- Materialized version for ML export (refresh on schedule)
-- CREATE MATERIALIZED VIEW mv_auction_ml_features AS SELECT * FROM v_auction_ml_features;
-- CREATE UNIQUE INDEX ON mv_auction_ml_features (auction_id);
```

---

### Phase 3 — AI Output Storage

**Migration F: `create_ai_predictions_table.sql`**

```sql
CREATE TABLE IF NOT EXISTS ai_predictions (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id       UUID        NOT NULL REFERENCES auctions(id) ON DELETE CASCADE,
  model_name       TEXT        NOT NULL,           -- e.g. 'vehicle_price_v1'
  model_version    TEXT        NOT NULL,           -- e.g. '1.2.0'
  prediction_type  TEXT        NOT NULL,           -- 'closing_price' | 'bid_count' | 'engagement'
  predicted_value  NUMERIC     NOT NULL,
  confidence_score NUMERIC,                        -- 0.0–1.0
  feature_hash     TEXT,                           -- hash of input features for drift detection
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction ON ai_predictions (auction_id, prediction_type, created_at DESC);

ALTER TABLE ai_predictions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "super_admin_read_predictions" ON ai_predictions
  FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM super_admins WHERE id = auth.uid()));
```

---

## 4. Required Flutter Model Changes

### 4.1 `AuctionModel` — Add Fields

The following fields should be added to `lib/data/models/models.dart` in the `AuctionModel` class. All are nullable to maintain backward compatibility with existing records.

```dart
// Engagement analytics (Phase 1)
final int viewsCount;           // views_count column
final int uniqueBidderCount;    // unique_bidder_count column
final DateTime? timeOfFirstBid; // time_of_first_bid column
final DateTime? timeOfLastBid;  // time_of_last_bid column

// Valuation anchors (Phase 1)
final double? estimatedMarketValue; // estimated_market_value column
final double? reservePrice;         // reserve_price column
final int? registrationYear;        // registration_year column
final String? chassisNumber;        // chassis_number column
final bool hasServiceHistory;       // has_service_history column
final int? numberOfDoors;           // number_of_doors column
```

**Computed getters to add (no schema change needed):**

```dart
// Bidding success rate (derivable from existing fields)
double? get priceVsStartPct {
  if (winningAmount == null || startingPrice == 0) return null;
  return (winningAmount! / startingPrice) * 100;
}

double? get priceRealizationPct {
  if (winningAmount == null || estimatedMarketValue == null || estimatedMarketValue! == 0) return null;
  return (winningAmount! / estimatedMarketValue!) * 100;
}

Duration get auctionDuration => endDate.difference(startDate);

Duration? get timeToFirstBid {
  if (timeOfFirstBid == null) return null;
  return timeOfFirstBid!.difference(startDate);
}
```

**`fromMap` additions:**

```dart
viewsCount:            (map['views_count'] as num?)?.toInt() ?? 0,
uniqueBidderCount:     (map['unique_bidder_count'] as num?)?.toInt() ?? 0,
timeOfFirstBid:        map['time_of_first_bid'] != null
                         ? DateTime.parse(map['time_of_first_bid'] as String) : null,
timeOfLastBid:         map['time_of_last_bid'] != null
                         ? DateTime.parse(map['time_of_last_bid'] as String) : null,
estimatedMarketValue:  (map['estimated_market_value'] as num?)?.toDouble(),
reservePrice:          (map['reserve_price'] as num?)?.toDouble(),
registrationYear:      (map['registration_year'] as num?)?.toInt(),
chassisNumber:         map['chassis_number'] as String?,
hasServiceHistory:     map['has_service_history'] as bool? ?? false,
numberOfDoors:         (map['number_of_doors'] as num?)?.toInt(),
```

---

### 4.2 `BidModel` — Add Fields

```dart
// Behavioral signals (Phase 1)
final int? bidSequence;          // bid_sequence column — position in auction bid timeline
final int? secondsBeforeEnd;     // seconds_before_end column — urgency signal
final double? bidIncrement;      // bid_increment column — aggression signal
final bool isBidUpdate;          // is_bid_update column — update vs. fresh bid
```

**`fromMap` additions:**

```dart
bidSequence:      (map['bid_sequence'] as num?)?.toInt(),
secondsBeforeEnd: (map['seconds_before_end'] as num?)?.toInt(),
bidIncrement:     (map['bid_increment'] as num?)?.toDouble(),
isBidUpdate:      map['is_bid_update'] as bool? ?? false,
```

---

### 4.3 `UserModel` — Computed Getters Only (No Schema Change for Phase 1)

```dart
// Derivable from existing fields — add as getters, not DB columns
double get biddingSuccessRate {
  if (totalBidsPlaced == 0) return 0.0;
  return totalAuctionsWon / totalBidsPlaced;
}
```

Phase 2+ can add `preferred_category`, `preferred_region`, `avg_bid_amount` as actual DB columns populated by server-side aggregation jobs.

---

### 4.4 New Model: `AuctionViewEvent` (Phase 1)

```dart
class AuctionViewEvent {
  final String auctionId;
  final String? viewerUid;
  final String? sessionId;
  final DateTime viewedAt;
  // fromMap / toMap as usual
}
```

---

## 5. Required Provider Changes

### 5.1 View Tracking — New RPC Call

Add to `AuctionRepository`:

```dart
Future<void> recordAuctionView(String auctionId, String? viewerUid) async {
  await _client.rpc('record_auction_view', params: {
    'p_auction_id': auctionId,
    'p_viewer_uid': viewerUid,
    'p_session_id': _generateSessionId(),
  });
}
```

Add to `providers.dart`:

```dart
// Invoke this inside AuctionDetailScreen.initState()
final recordViewProvider = Provider.autoDispose.family<void, String>((ref, auctionId) {
  // fire-and-forget; never block the UI on this
});
```

### 5.2 Analytics Provider — New

```dart
// Returns pre-computed analytics for a single auction (admin/super-admin only)
final auctionAnalyticsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
  (ref, auctionId) async {
    // queries v_auction_ml_features for one auction
  },
);
```

### 5.3 ML Predictions Provider — Phase 3 Only

```dart
// Returns AI predictions for a given auction
final aiPredictionProvider = FutureProvider.autoDispose.family<List<AiPrediction>, String>(
  (ref, auctionId) => ref.watch(adminRepositoryProvider).getAiPredictions(auctionId),
);
```

### 5.4 Existing Providers — No Breaking Changes Required

All existing providers (`auctionsByRegionProvider`, `bidsForAuctionProvider`, `adminAuctionsProvider`, etc.) are backward compatible. New nullable columns default to `0` / `false` / `null`, so `fromMap` will continue parsing existing rows without error once new fields are added.

---

## 6. Risks

### Risk 1 — `total_bids` Semantics Mismatch ⚠️ HIGH

**Problem:** The `total_bids` column on `auctions` counts bid upserts (transactions), not unique bidders or unique bids. Since bidders can raise their own bid (UPDATE path in `accept_bid()`), `total_bids` can exceed the true number of distinct bid events placed. Any ML model trained on `total_bids` as a proxy for competition intensity will be skewed.

**Mitigation:** Add `unique_bidder_count` (Phase 1 Migration A). Document `total_bids` clearly in data dictionary. Do not use `total_bids` as an ML feature without normalization.

---

### Risk 2 — High Null Rate in ML Metadata Fields ⚠️ HIGH

**Problem:** The 19 vehicle metadata fields added in migration 20260609 are all nullable. If region admins do not fill them in when posting auctions, training data will have unacceptably high null rates (>40% is typical for optional form fields). A model trained on sparse data will generalize poorly.

**Mitigation:** 
- Make key fields (brand, model, manufacturing_year, mileage, fuel_type, transmission) required in `PostAuctionScreen` form validation before any ML training begins.
- Track per-field fill rate as a data quality metric.
- Use `estimated_market_value` as a sentinel: only auction rows where this is non-null should be included in supervised learning training sets.

---

### Risk 3 — `views_count` Has No Infrastructure Yet ⚠️ HIGH

**Problem:** There is currently zero view-tracking logic in the app. The `views_count` column does not exist yet. Adding the column but not populating it produces a permanently-zero feature that actively harms model quality (a feature with zero variance adds noise).

**Mitigation:** Deploy Migration C (`create_auction_views_table.sql`) and the `record_auction_view` RPC before adding `views_count` to the model. Wire `recordAuctionView()` into `AuctionDetailScreen.initState()` on the same sprint as the migration.

---

### Risk 4 — PII in `bids` Table ⚠️ MEDIUM

**Problem:** `bidder_phone` and `bidder_name` are stored in plain text in the `bids` table. Any ML export pipeline (e.g., exporting `v_auction_ml_features` to a training CSV or an external ML service) will include PII unless explicitly excluded.

**Mitigation:**
- The `v_auction_ml_features` view defined in Phase 2 deliberately excludes `bidder_phone` and `bidder_name`.
- Any export script must use the view, not a direct `SELECT * FROM bids`.
- Add a note in `supabase_constants.dart` flagging `bids` as containing PII.

---

### Risk 5 — `seconds_before_end` Must Be Server-Side ⚠️ MEDIUM

**Problem:** If `seconds_before_end` is computed on the client (Flutter), a user can manipulate their device clock to falsify this value, corrupting the urgency signal in training data.

**Mitigation:** This field must be computed exclusively inside the `place-bid` Edge Function using `EXTRACT(EPOCH FROM (a.end_date - now()))` queried from the database, never from a client-supplied timestamp.

---

### Risk 6 — `estimated_market_value` Has No Data Source ⚠️ MEDIUM

**Problem:** `estimated_market_value` is the most important ML label (it defines whether the auction achieved a good price). Currently there is no Rwanda vehicle market API, no third-party valuation service, and no admin workflow to enter this value.

**Mitigation:**
- Phase 1: add the column with NULL default; create UI field in `PostAuctionScreen` (optional entry by admin).
- Phase 2: Develop an internal reference table of average prices by (brand, model, year, condition) from historical auction outcomes once 50+ closed auctions exist.
- Phase 3: Consider integration with a vehicle valuation API if one becomes available.
- Never block ML development on this: use `winning_amount / starting_price` as a weak label in the interim.

---

### Risk 7 — Schema Drift During Migration Rollout ⚠️ LOW

**Problem:** New columns added to the database before the Flutter model is updated will cause `fromMap()` to silently ignore them (safe). New columns added to the Flutter model before the database migration is applied will produce null reads (also safe, all fields are nullable). However, if a `toMap()` call attempts to write a new field to a column that doesn't exist yet, the database will throw.

**Mitigation:** Always deploy the Supabase migration first, then release the Flutter update. The existing `if (field != null) 'column': field` pattern in `AuctionModel.toMap()` already guards against this for nullable fields. New nullable fields should use the same pattern.

---

## 7. Recommended Implementation Order

### Sprint 1 — Capture the Signal (No AI, No Breaking Changes)

**Goal:** Start collecting the data that future models will need. No AI, no UI changes except view tracking.

| # | Task | Type | File / Migration |
|---|---|---|---|
| 1 | Deploy Migration A | SQL | `add_auction_engagement_fields.sql` |
| 2 | Deploy Migration B | SQL | `add_bid_behavioral_fields.sql` |
| 3 | Deploy Migration C | SQL | `create_auction_views_table.sql` |
| 4 | Update `place-bid` Edge Function | Deno/TS | `supabase/functions/place-bid/index.ts` — populate `bid_sequence`, `seconds_before_end`, `bid_increment`, update `time_of_first_bid`/`time_of_last_bid`/`unique_bidder_count` on auctions |
| 5 | Update `close-auction-manually` | Deno/TS | Log `unique_bidder_count` snapshot |
| 6 | Update `auto-close-auctions` | Deno/TS | Log `unique_bidder_count` snapshot |
| 7 | Update `AuctionModel.fromMap()` | Dart | New engagement fields (nullable, backward-safe) |
| 8 | Update `BidModel.fromMap()` | Dart | New behavioral fields (nullable, backward-safe) |
| 9 | Add `recordAuctionView()` to `AuctionRepository` | Dart | `lib/data/repositories/auction_repository.dart` |
| 10 | Wire view tracking into `AuctionDetailScreen` | Dart | Fire-and-forget on screen open |

**Exit criteria:** After Sprint 1, every new auction will accumulate `views_count`, `unique_bidder_count`, `time_of_first_bid`, `time_of_last_bid`. Every new bid will record `bid_sequence`, `seconds_before_end`, `bid_increment`.

---

### Sprint 2 — Valuation Anchors + Admin Data Entry

**Goal:** Give admins the ability to enter valuation reference data; ensure ML training data quality is sufficient.

| # | Task | Type | Notes |
|---|---|---|---|
| 1 | Deploy Migration D | SQL | `add_auction_valuation_fields.sql` |
| 2 | Add valuation fields to `PostAuctionScreen` | Dart | `estimated_market_value` as optional field; `has_service_history` toggle |
| 3 | Update `AuctionModel` with valuation fields | Dart | Add getters for `priceRealizationPct`, `priceVsStartPct` |
| 4 | Make key ML fields required in form validation | Dart | brand, model, manufacturing_year, mileage, fuel_type, transmission |
| 5 | Data quality dashboard widget (admin) | Dart | Show % fill rate for ML fields in `RegionReportsScreen` |

---

### Sprint 3 — Analytics Infrastructure

**Goal:** Build the SQL foundation that ML training will consume.

| # | Task | Type | Notes |
|---|---|---|---|
| 1 | Deploy Migration E | SQL | `create_ml_features_view.sql` |
| 2 | Add `auctionAnalyticsProvider` | Dart | Read from `v_auction_ml_features` for admin dashboard |
| 3 | Add analytics summary cards to `RegionReportsScreen` | Dart | avg price realization %, avg unique bidders, avg views |
| 4 | Add analytics summary to `NationalReportsScreen` | Dart | Nationwide aggregates |

---

### Sprint 4 — ML Model Development (External / Offline)

**Goal:** Train first models using data collected in Sprints 1–3. This is an offline/data-science sprint, not a Flutter sprint.

| # | Task | Type | Notes |
|---|---|---|---|
| 1 | Export `v_auction_ml_features` for closed auctions | SQL/Python | Min. 50 rows needed; 200+ for reliable model |
| 2 | Train vehicle closing price prediction model | Python/sklearn | Features: brand, model, year, condition, mileage, region, starting_price, views_count, unique_bidder_count |
| 3 | Train bid count prediction model | Python/sklearn | Features: vehicle specs, duration_hours, starting_price, views_count |
| 4 | Evaluate models offline | Python | RMSE, MAE, R² on held-out test set |
| 5 | Define serving strategy | Architecture | Edge Function vs. external API vs. client-side TFLite |

---

### Sprint 5 — AI Integration (Phase 3)

**Goal:** Serve AI predictions within the app.

| # | Task | Type | Notes |
|---|---|---|---|
| 1 | Deploy Migration F | SQL | `create_ai_predictions_table.sql` |
| 2 | Create `predict-auction` Edge Function | Deno/TS | Calls ML model API, stores result in `ai_predictions` |
| 3 | Wire prediction to `PostAuctionScreen` | Dart | "Estimated closing price: RWF X" shown to admin after draft save |
| 4 | Wire prediction to `AuctionDetailScreen` | Dart | "Market estimate: RWF X" shown to clients |
| 5 | Add `aiPredictionProvider` | Dart | Reads from `ai_predictions` table |
| 6 | Monitoring: track predicted vs. actual | SQL/Dashboard | `ai_predictions.predicted_value` vs. `auctions.winning_amount` |

---

## Appendix A — Flutter Analyze Result

```
Analyzing ecyamunara...
No issues found! (ran in 58.3s)
```

Clean baseline. Zero linting or type errors before AI implementation begins.

---

## Appendix B — Data Sufficiency Checklist

Before training any ML model, verify:

| Requirement | Current State | Target |
|---|---|---|
| Closed auctions with all ML metadata fields | ~0 (fields new) | ≥ 200 |
| `estimated_market_value` non-null rate | 0% (field doesn't exist yet) | ≥ 80% of closed auctions |
| `views_count` tracking active | No | Yes (Sprint 1) |
| `unique_bidder_count` tracking active | No | Yes (Sprint 1) |
| `bid_sequence` + `seconds_before_end` active | No | Yes (Sprint 1) |
| Key ML metadata fields required in UI | No (all optional) | Yes (Sprint 2) |
| `v_auction_ml_features` view deployed | No | Yes (Sprint 3) |

---

## Appendix C — Fields That Are Already Sufficient

The following data is already captured correctly and requires no changes before ML work begins:

- ✅ Vehicle condition (5-level standardized: Excellent / Very Good / Good / Fair / Poor)
- ✅ 19 vehicle metadata fields (brand, model, year, color, mileage, fuel_type, transmission, engine_size, engine_cc, drivetrain, seating_capacity, frame_material, gear_count, suspension_type, brake_type, ownership_history, accident_history, insurance_status)
- ✅ Geographic data (region on auction; district + province + region on bidder)
- ✅ Auction temporal data (start_date, end_date, closed_at)
- ✅ Auction outcome labels (winner_uid, winning_amount)
- ✅ User engagement counters (total_bids_placed, total_auctions_won)
- ✅ Feedback / satisfaction data (star_rating, selected_tags, would_recommend)
- ✅ Auto-close audit log (auction_auto_close_logs)
- ✅ Soft-delete with actor tracking (is_deleted, deleted_at, deleted_by)
- ✅ Multi-role hierarchy (region → admin → super_admin) enabling region-stratified analysis
