# AI Dataset Architecture — E-CYAMUNARA

## Phase Context

| Phase | Status | Scope |
|-------|--------|-------|
| Phase 0 | Complete | AI readiness audit |
| Phase 1 | Complete | Passive data collection — bid behavioral fields, auction views, engagement metrics |
| **Phase 2** | **Complete** | **Dataset foundation — storage schema, feature view, synthetic data, export/validate scripts** |
| Phase 3 | Planned | Feature engineering, model training (XGBoost/Random Forest) |
| Phase 4 | Planned | Prediction APIs (FastAPI) and Flutter AI widgets |

---

## Schema Feature Audit

### Existing ML Features (Post Phase 1 + Phase 2)

#### auctions — Direct Features

| Feature | Type | ML Role | Notes |
|---------|------|---------|-------|
| region | TEXT | Categorical input | 100% present |
| main_category | TEXT | Categorical input | ~85% present |
| sub_category | TEXT | Categorical input | ~80% present |
| brand | TEXT | Categorical input | ~75% present |
| model | TEXT | Categorical input | ~70% present |
| manufacturing_year | INTEGER | Ordinal/continuous | ~75% present |
| mileage | INTEGER | Continuous (vehicle/moto) | ~65% present |
| condition | TEXT | Ordinal input | 100% present |
| fuel_type | TEXT | Categorical input | ~70% present |
| transmission | TEXT | Categorical input | ~70% present |
| ownership_history | TEXT | Categorical input | ~60% present |
| accident_history | TEXT | Categorical input | ~55% present |
| insurance_status | TEXT | Categorical input | ~60% present |
| color | TEXT | Low-signal categorical | ~65% present |
| starting_price | NUMERIC | Continuous input + price anchor | 100% present |

#### auctions — Phase 1 Engagement Features

| Feature | Type | ML Role |
|---------|------|---------|
| views_count | INTEGER | Market interest proxy |
| unique_bidder_count | INTEGER | Competition intensity |
| total_bids | INTEGER | Engagement depth |
| time_of_first_bid | TIMESTAMPTZ | Demand immediacy signal |
| time_of_last_bid | TIMESTAMPTZ | Engagement recency |

#### bids — Phase 1 Behavioral Features

| Feature | Type | ML Role |
|---------|------|---------|
| bid_sequence | INTEGER | Bidding position |
| bid_increment | NUMERIC | Bidder aggressiveness |
| seconds_before_end | INTEGER | Urgency/sniping signal |
| is_bid_update | BOOLEAN | Bid revision behavior |

#### auction_views — Phase 1 View Events

| Feature | Type | ML Role |
|---------|------|---------|
| view_duration_seconds | INTEGER | Intent depth signal |
| device_type | TEXT | Platform signal |
| region | TEXT | Geographic demand |

### Derived Features (v_auction_ml_features view)

| Feature | Derivation | ML Role |
|---------|-----------|---------|
| asset_age | EXTRACT(YEAR FROM NOW()) - manufacturing_year | Depreciation proxy |
| auction_duration_hours | (end_date - start_date) / 3600 | Competition window |
| bids_per_view_ratio | total_bids / views_count | Conversion quality |
| days_until_close | (end_date - NOW()) / 86400 | Urgency signal |
| time_to_first_bid_hours | (time_of_first_bid - start_date) / 3600 | Demand immediacy |
| metadata_completeness_score | count(non-null ML fields) / 10 | Prediction confidence weight |
| has_images | array_length(photo_urls) > 0 | Presentation quality |
| has_description | len(trim(description)) > 0 | Presentation quality |

### Missing Features (future data collection opportunities)

| Feature | Why Useful | How to Collect |
|---------|-----------|---------------|
| inspector_condition_score | Numeric RNP inspector grade | Add field to PostAuction screen |
| accident_severity_score | Quantified damage level | Expand accident_history options |
| service_history_present | Whether service book is available | Add to vehicle metadata form |
| past_auction_count_for_asset | How often same plate was auctioned | Query by plate_number |
| photos_quality_score | Auto-assessed image quality | Phase 4 computer vision |

---

## ai_predictions Table

Stores ML inference outputs per auction. **Empty until Phase 4 inference pipeline is built.**

| Column | Purpose |
|--------|---------|
| auction_id | Which auction this prediction covers |
| model_version | Semantic version string (e.g. "v1.0.4-synthetic") |
| prediction_type | `"auction_price_estimate"` / `"winning_bid"` / `"bid_probability"` |
| expected_auction_price | Model A: expected selling price in RWF (`auction_price_estimate` rows) |
| value_signal | `"undervalued"` / `"fairly_priced"` / `"overpriced"` (derived from `starting_price / expected_auction_price`) |
| value_ratio | `starting_price / expected_auction_price` numeric ratio |
| starting_price_at_prediction | Admin-set `starting_price` captured at inference time (immutable snapshot) |
| predicted_winning_bid | Model B: predicted final winning amount in RWF |
| predicted_probability | Model C: P(auction receives ≥1 bid) — range [0, 1] |
| confidence_score | Model confidence — range [0, 1] |
| feature_snapshot | JSONB snapshot of features used at inference time |
| created_at | Timestamp of prediction |

**Security:** `service_role` only writes (bypasses RLS). Active `super_admins` read all rows. Active clients read `auction_price_estimate` rows only for auctions with status `active` or `closed`.

---

## Synthetic Data Assumptions

### Why Synthetic Data

The application is still under development. No meaningful real-world auction history
exists. Synthetic data enables ML architecture experiments, feature engineering
validation, and pipeline smoke tests before production data is available.

### Generation Model

**Volume:**
- 200,000 auction records (spanning ~730 days, 5 regions, 3 categories)
- ~85,000–100,000 bid records (Poisson sparse — avg ~0.5 bids/eligible auction)
- ~200,000–250,000 view records (proportional to auction popularity)

**Price simulation** (multiplicative model):

```
starting_price = base_price(brand, sub_category)
               x (1 - depreciation_rate)^asset_age
               x condition_multiplier
               x mileage_factor              [vehicles/motorcycles only]
               x regional_demand_factor
               x uniform_noise(0.90, 1.10)
```

Rounded to nearest 50,000 RWF (matches RNP auction floor practice).

**Depreciation rates per year:** vehicle 15%, motorcycle 12%, bicycle 8%.

**Condition multipliers:** Excellent 1.05 down to Poor 0.40.

**Regional demand:** Central +15%, Eastern +5%, Western baseline, Northern/Southern -5%.

**Bid timing:** clustered 25% in first 15% of auction window + 50% in last 20%
(simulates real sniping behavior observed in online auctions).

### Known Biases in Synthetic Data

1. **Artificial distributions** — category weights (70/20/10) are assumed, not measured.
2. **No seasonal effects** — real RNP auctions may cluster around police operations.
3. **No repeat bidders** — each synthetic bid has a fresh UUID bidder.
4. **No admin behavior patterns** — posting frequency is random, not admin-specific.
5. **No geographic micro-variation** — Rwanda regions have complex local economies not captured.

These biases are corrected as real data accumulates.

---

## Dataset Lifecycle

### Current (Phase 2): Bootstrap with Synthetic Data

```
generate_synthetic_dataset.py
  -> backend/ai/data/synthetic_auctions.csv   (200K rows)
  -> backend/ai/data/synthetic_bids.csv       (~85K rows)
  -> backend/ai/data/synthetic_views.csv      (~220K rows)

validate_training_data.py
  -> backend/ai/data/training_data_quality_report.json
```

### Near-term (Phase 3): Hybrid Approach

As real auctions close, supplement synthetic data:

```
export_training_dataset.py --status closed
  -> backend/ai/data/training_snapshot_YYYYMMDD.csv (real data)
  -> merge with synthetic data for augmentation
  -> feature engineering transforms (Phase 3)
  -> model training (XGBoost / Random Forest)
```

### Long-term (Phase 4+): Real Data Dominates

Phase 1 passive sensors continuously collect real signals:
- `accept_bid()` populates bid behavioral fields (sequence, increment, secs_before_end)
- `record_auction_view()` populates view events and views_count
- `v_auction_ml_features` is always-current feature snapshot

`ai_predictions` stores inference outputs. Quarterly retraining triggered by
100+ new closed auctions.

---

## Transition: Synthetic to Real Data

### Trigger Conditions for Retiring Synthetic Data

1. 1,000 or more real closed auctions with complete metadata
2. 500 or more auctions per major category (vehicle, motorcycle)
3. At least 6 months of real auction history in the database

### Validation Before Transition

Run `validate_training_data.py` on the real export. Compare:
- `metadata_completeness_score` distribution (real vs synthetic assumptions)
- `bids_per_view_ratio` distribution (real competition patterns)
- Regional price distributions (actual demand vs assumed factors)

Update `generate_synthetic_dataset.py` simulation parameters if the real
distributions diverge significantly, or retire synthetic data entirely.

---

## Future Retraining Flow (Phase 3+)

```
[Trigger: quarterly OR >100 new closed auctions]
  |
  +-- Export:    export_training_dataset.py --status closed
  +-- Validate:  validate_training_data.py
  +-- Features:  (Phase 3) feature engineering transforms
  +-- Train:     (Phase 3) XGBoost / Random Forest
  +-- Evaluate:  holdout set metrics
  +-- Version:   bump model_version tag
  +-- Store:     write predictions to ai_predictions via service_role
```
