# Phase 3 Training Readiness Review

**Generated:** 2026-06-11
**Dataset:** Synthetic bootstrap (Phase 2)
**Validator output:** `backend/ai/data/training_data_quality_report.json`

---

## Section A: Dataset Statistics

### A1. Corpus Overview

| File | Rows | Columns | Quality Score |
|------|------|---------|---------------|
| synthetic_auctions.csv | 200,000 | 37 | 1.0 (PASS) |
| synthetic_bids.csv | 100,000 | 14 | 1.0 (PASS) |
| synthetic_views.csv | 186,026 | 7 | 1.0 (PASS) |
| **Total** | **486,026** | — | — |

Views reached 186,026 instead of the 250,000 target — expected behavior from the popularity-weighted Poisson distribution (low-bid auctions generate few views by design).

### A2. Auction Status Distribution

| Status | Approx Count | Percentage |
|--------|-------------|------------|
| Closed | ~120,000 | 60.0% |
| Active | ~50,000 | 25.0% |
| Draft | ~30,000 | 15.0% |

Closed auctions with `winner_uid` set: **71,460** (35.73% of all auctions; 59.6% of closed).
Closed auctions without a winner: ~48,540 (admin-cancelled or unsold lots).

### A3. Category Distribution

| Category | Approx Count | Percentage |
|---------|-------------|------------|
| Vehicle | ~140,000 | 70.0% |
| Motorcycle | ~40,000 | 20.0% |
| Bicycle | ~20,000 | 10.0% |

### A4. Regional Distribution

| Region | Sampling Weight | Approx Count |
|--------|----------------|-------------|
| Central | 35% | ~70,000 |
| Eastern | 20% | ~40,000 |
| Northern | 15% | ~30,000 |
| Southern | 15% | ~30,000 |
| Western | 15% | ~30,000 |

### A5. Price Distribution (starting_price)

- Range: RWF 0 – RWF 46,000,000
- Q1: RWF 250,000 — Q3: RWF 2,300,000
- IQR upper fence: RWF 8,450,000
- Outliers (luxury — Mercedes/BMW heavy equipment): 7,555 rows (3.78%)
- Distribution is strongly right-skewed across three orders of magnitude

### A6. Bid Data Summary

- 100,000 bid records spanning all non-draft auctions
- `bid_sequence` max observed: 8 (max 8 unique bidders per auction)
- `bid_amount`: Q1 = RWF 250,000, Q3 = RWF 2,650,000; outlier threshold RWF 9,850,000 (3.86%)
- `bid_increment` outliers (> RWF 1,000,000): 4.08%
- `seconds_before_end` range: 2,685 – 2,591,676 (all in-range, no violations)
- Temporal pattern: 25% early bids, 50% last-minute (>80% through auction), 25% mid-auction
- 20% of bid rows have `is_bid_update = true`

### A7. View Data Summary

- 186,026 view records
- Anonymous viewers (`viewer_uid = null`): 55,734 (29.96%)
- Device split: ~80% mobile, ~15% web, ~5% unknown
- `view_duration_seconds`: min=5, Q1=25, Q3=124, max=1,076
- Duration outliers (> 421 seconds): 1,705 rows (0.92%)
- View distribution is popularity-weighted (high-bid auctions accumulate more views)

---

## Section B: Feature Quality

### B1. Null Analysis by Column Group

**Group 1 — Always present (0% null):**
`id`, `item_name`, `category`, `plate_number`, `condition`, `starting_price`,
`current_highest_bid`, `total_bids`, `region`, `posted_by_admin_uid`,
`auction_status`, `start_date`, `end_date`, `is_deleted`, `created_at`,
`updated_at`, `views_count`, `unique_bidder_count`

**Group 2 — Intentionally sparse at ~21% null (completeness probability cp = 0.85/0.70/0.50 per category):**

| Column | Null Count | Null % |
|--------|-----------|--------|
| main_category | 43,211 | 21.61% |
| sub_category | 43,222 | 21.61% |
| brand | 42,904 | 21.45% |
| model | 42,868 | 21.43% |
| manufacturing_year | 42,951 | 21.48% |
| color | 42,830 | 21.41% |
| ownership_history | 42,956 | 21.48% |

**Group 3 — More sparse due to bicycle structural N/A (~24-27% null):**

| Column | Null Count | Null % |
|--------|-----------|--------|
| transmission | 49,087 | 24.54% |
| mileage | 52,933 | 26.47% |
| fuel_type | 53,023 | 26.51% |

Note: for bicycles, `mileage` and `fuel_type` are structurally inapplicable (not missing — unknown). This distinction matters for imputation strategy.

**Group 4 — Intentionally sparser (cp × 0.7 / cp × 0.8 factors):**

| Column | Null Count | Null % |
|--------|-----------|--------|
| insurance_status | 74,106 | 37.05% |
| accident_history | 90,240 | 45.12% |
| description | 20,222 | 10.11% |

**Group 5 — Label-conditional nulls (structurally expected):**

| Column | Null Count | Null % | Condition |
|--------|-----------|--------|-----------|
| winning_amount | 128,540 | 64.27% | Only set when auction closed with winner |
| winner_uid | 128,540 | 64.27% | Same |
| closed_at | 128,540 | 64.27% | Same |
| time_of_first_bid | 109,985 | 54.99% | Only set when at least one bid placed |
| time_of_last_bid | 109,985 | 54.99% | Same |

### B2. Feature Completeness Summary

Checked against 15 core ML fields: region, main_category, sub_category, brand, model, manufacturing_year, mileage, condition, fuel_type, transmission, ownership_history, accident_history, insurance_status, color, starting_price.

| Metric | Value |
|--------|-------|
| Mean completeness | 79.32% |
| Median completeness | 80.0% |
| Records fully complete (all 15 fields) | 5.74% (11,480 rows) |
| Records below 50% completeness | 5.52% (11,040 rows) |

Assessment: The 5.52% very sparse records are predominantly bicycle records (cp=0.50). These should be downweighted via `metadata_completeness_score` rather than dropped.

### B3. Feature Usefulness Ratings

| Feature | Usefulness | Notes |
|---------|-----------|-------|
| main_category | HIGH | Primary price segmentation; Toyota SUV vs Honda Scooter differ by 25x |
| brand | HIGH | Luxury brands (Mercedes, BMW) carry 3x price premium over economy |
| sub_category | HIGH | Body style is the second-strongest predictor after brand |
| manufacturing_year / asset_age | HIGH | Exponential depreciation (15%/yr vehicles, 12%/yr motorcycles, 8%/yr bicycles) |
| condition | HIGH | Excellent:1.05 vs Poor:0.40 multiplier — 2.6x spread |
| mileage | HIGH | _mileage_factor steps: 1.00/0.90/0.80/0.70/0.60 at 50K-interval thresholds |
| region | MEDIUM | 1.21x spread (Central:1.15 vs Northern/Southern:0.95) |
| fuel_type | MEDIUM | Diesel > Petrol for vehicles; Electric scarce |
| transmission | MEDIUM | Automatic > Manual for SUVs; reversed for motorcycles |
| total_bids | MEDIUM | Market interest proxy; correlates with final price premium |
| unique_bidder_count | MEDIUM | Competition signal for winning bid model |
| views_count | MEDIUM | Demand signal; available at scoring time |
| ownership_history | LOW-MEDIUM | Fleet vehicles depreciate differently; signal is noisy |
| accident_history | LOW-MEDIUM | High null rate (45%) dilutes signal; when present, Major Accident is strong negative |
| insurance_status | LOW | 37% null; weak signal in synthetic data |
| color | LOW | Minor signal; high cardinality; drop or group into "neutral/non-neutral" |

### B4. Cardinality Analysis

| Feature | Distinct Values | Encoding Risk |
|---------|----------------|---------------|
| auction_status | 3 | None |
| main_category | 3 | None |
| region | 5 | None |
| condition | 5 | Ordinal — encode 0–4, do not one-hot |
| fuel_type | 5 (incl. N/A) | One-hot safe |
| transmission | 3 (incl. N/A) | One-hot safe |
| ownership_history | 4 | One-hot safe |
| accident_history | 3 | One-hot safe |
| insurance_status | 3 | One-hot safe |
| brand | ~21 | Target encoding recommended |
| sub_category | ~18 | Target encoding recommended |
| color | 9 | One-hot or drop |
| model | ~157,000 unique | DROP — near-unique; will overfit |

### B5. Known Risks

1. **`model` column is near-unique.** Generated as `{brand[:3]}{sub[:3]}{year%100}` (e.g., "TOYSUV23"). Treating this as a categorical feature would create ~157,000 categories. Must be dropped from all feature matrices.

2. **Bicycle structural nulls inflate imputation complexity.** `mileage` and `fuel_type` are not missing for bicycles — they are inapplicable. A global median impute will assign ~125,000 km to a bicycle. Category-specific pipelines or explicit `is_motorized` flag required.

3. **Price range spans three orders of magnitude.** RWF 100,000 (budget bicycle) to RWF 46,000,000 (commercial bus). A single regression without log1p transform will underfit the low-price tail. Log1p transform of both features and targets is mandatory.

4. **Category imbalance (70/20/10).** Models trained on the full corpus will see 7x more vehicle examples than bicycle examples. Stratified sampling or per-category sample weights are required to avoid bicycle predictions being dominated by vehicle signal.

5. **Accident/insurance fields are the highest-value risk signals with the worst null rates.** 45.12% and 37.05% null respectively. In real vehicle auctions, undisclosed accident history is a strong negative signal. Missingness indicators (binary flags for `is_accident_history_known`) must be created before imputation.

---

## Section C: Target Variable Validation

### C1. Model 1 — Starting Price Prediction (Regression)

**Target:** `starting_price` (continuous numeric)
**Available labels:** 200,000 (0% null — all records usable)
**Recommended split:** 80/10/10 stratified by main_category × condition = 160K / 20K / 20K

**Label quality:**
- Generated by: `base_price × (1 - depreciation_rate)^age × condition_mult × mileage_factor × region_demand × noise(0.90, 1.10)`
- All prices rounded to nearest RWF 50,000 — quantization noise is intentional and mirrors real admin rounding behavior
- Outlier handling: 3.78% luxury vehicles exceed the IQR fence at RWF 8,450,000 — validate, do not remove (luxury auctions are genuine)
- Leakage risk: `current_highest_bid` is derived from `starting_price`; must be excluded from Model 1 feature matrix
- Leakage risk: `winning_amount` encodes the outcome — exclude

**Verdict: READY.** 200K clean labels, well-understood generative process. Apply log1p transform to target and to `mileage`.

---

### C2. Model 2 — Winning Bid Prediction (Regression)

**Target:** `winning_amount` (continuous numeric)
**Available labels:** 71,460 (35.73% of corpus)
**Recommended split:** 70/15/15 stratified by main_category = 50K / 10.7K / 10.7K

**Label quality:**
- Generated by: `starting_price × (1 + Exponential(scale=0.18))` rounded to RWF 50,000
- `winning_amount / starting_price` ratio follows an exponential distribution; mean premium ≈ 18%
- Applies only to closed auctions where the random `rng.random() > 0.40` condition was satisfied
- Selection bias: the 40% of closed auctions without a winner represent admin-cancelled or expired lots. These have systematically different characteristics (low engagement, no bids). Training on won-only auctions creates selection bias when scoring all auctions.
- Mitigation: include `is_won` binary column and evaluate separately on "closed-no-winner" auctions after Phase 4 real data arrives

**Verdict: CONDITIONALLY READY.** 71K labels are sufficient for bootstrap. Add explicit `is_won` flag. Evaluate MAPE separately by price tier (< 2M, 2M–10M, > 10M) because auction dynamics differ by tier.

---

### C3. Model 3 — Bid Probability / Interest Score (Binary Classification)

**Target:** `total_bids > 0` (binary: 1 = received at least one bid)
**Available labels:** 200,000 (derived from `total_bids` column, always present)
**Positive rate:** 90,015 / 200,000 = **45.0%** (auctions that attracted at least one bid)
**Class balance:** 45% positive / 55% negative — near-balanced, no resampling required

**Label quality:**
- Draft auctions (15% of corpus) receive 0 bids by construction. They form a structural negative class but are unrealistic inference targets — admins would not request a prediction on a draft.
- Active auctions (25%) have live, incomplete bid counts. Their label at training time is a snapshot, not a final count. As bids arrive, label correctness improves.
- Most reliable labels: closed auctions (60%). These have finalized `total_bids`.
- Recommendation: train Phase 3 Model 3 on closed-only (120K rows: 72K positive / 48K negative), then evaluate generalization when scoring active auctions.

**Verdict: READY with caveat.** Train on closed subset first. Expand to full corpus only after confirming the draft-auction negative class does not inflate precision metrics artificially.

---

## Section D: Feature Engineering Plan

### D1. Required Transformations

| Transformation | Columns | Reason |
|---------------|---------|--------|
| `log1p` | `starting_price`, `winning_amount`, `mileage`, `views_count`, `total_bids` | Right-skewed; prevents large values dominating gradient |
| Ordinal encoding | `condition` (Poor=0, Fair=1, Good=2, Very Good=3, Excellent=4) | Natural order must be preserved — one-hot would lose ordinal information |
| One-hot encoding | `main_category`, `fuel_type`, `transmission`, `ownership_history`, `accident_history`, `insurance_status` | Low cardinality (3–5 values); sparse but safe |
| Target encoding | `brand`, `sub_category`, `region` | Medium cardinality; one-hot would create sparse vectors; target encode with cross-validation to prevent leakage |
| Drop | `model` | Near-unique (~157K distinct values); severe overfitting risk |
| Binary missingness flag | `accident_history`, `insurance_status`, `manufacturing_year`, `mileage` | Missingness pattern carries signal independent of the value |
| Derived: `asset_age` | `manufacturing_year` | Age in years at auction date; more meaningful than raw year |
| Derived: `bid_momentum` | `total_bids / auction_duration_hours` | Bids per hour captures rate of competition, not just volume |
| Derived: `view_to_bid_ratio` | `total_bids / NULLIF(views_count, 0)` | Conversion rate from view to bid; strong interest signal |
| Derived: `price_per_age_year` | `starting_price / GREATEST(asset_age, 1)` | Depreciation rate feature |
| Derived: `won_premium` (Model 2 only) | `winning_amount / starting_price` | Target distribution feature; reveals bid escalation pattern |

### D2. Imputation Strategy

| Column | Null % | Strategy |
|--------|--------|---------|
| `mileage` | 26.47% | Median impute within (main_category, condition) groups; bicycle rows → explicit 0; add `is_mileage_known` flag |
| `fuel_type` | 26.51% | Mode impute within main_category; bicycle rows → "N/A" explicitly |
| `transmission` | 24.54% | Mode impute within (main_category, sub_category) |
| `manufacturing_year` | 21.48% | Median impute within (brand, sub_category); add `is_year_known` flag |
| `brand` | 21.45% | Assign "Unknown" token; target encoding handles it naturally |
| `accident_history` | 45.12% | Add `has_accident_disclosure` flag first; then fill "Unknown" category |
| `insurance_status` | 37.05% | Add `has_insurance_disclosure` flag first; then fill "Unknown" category |
| `description` | 10.11% | Add `has_description` binary flag; text content not used in Phase 3 tabular models |

### D3. Feature Groups Per Model

**Model 1 (Starting Price) — Input features:**
Category: `main_category`, `sub_category`, `brand`, `condition`, `region`, `fuel_type`, `transmission`, `ownership_history`, `accident_history`, `insurance_status`, `has_accident_disclosure`, `has_insurance_disclosure`
Continuous: `asset_age`, `log1p(mileage)`, `auction_duration_hours`, `has_description`, `is_mileage_known`, `is_year_known`
Exclude: `current_highest_bid`, `winning_amount`, `total_bids`, `views_count`, `unique_bidder_count` (all post-publication signals; unavailable at price-setting time)

**Model 2 (Winning Bid) — Input features:**
All Model 1 features PLUS:
`log1p(starting_price)` (now valid — it is the input, not the target)
`log1p(total_bids)`, `unique_bidder_count`, `log1p(views_count)`, `bid_momentum`, `view_to_bid_ratio`, `time_to_first_bid_hours`, `metadata_completeness_score`
Exclude: `current_highest_bid` (real-time state; not available at prediction request time)

**Model 3 (Bid Probability) — Input features:**
All Model 1 features PLUS:
`log1p(starting_price)`, `log1p(views_count)`, `auction_duration_hours`, `has_description`, `metadata_completeness_score`
Exclude: `total_bids` (this IS the target proxy), `winning_amount`, `winner_uid`

---

## Section E: Model Strategy

### E1. Algorithm Selection

**Primary recommendation: XGBoost (gradient-boosted trees)**

XGBoost is the right choice for this dataset because: it handles missing values natively via learned default split directions (eliminates imputation dependency for tree splits); it requires no feature scaling (tree-based, immune to price-magnitude differences); it is robust to right-skewed distributions even before full log-transform; it trains in under 5 minutes on 200K rows on a standard CPU; and it provides built-in feature importance scores that auction admins can inspect.

**Secondary: RandomForestRegressor / RandomForestClassifier (ensemble validation)**

Use as an independent feature importance validator. If RF and XGBoost agree on top-10 features, the signal is robust. If they disagree significantly, investigate whether one model is fitting noise. RF serves as a sanity check, not the production model.

**Binary classification baseline: LogisticRegression (diagnostic only)**

LogisticRegression for Model 3 establishes the linear-separability floor. If it achieves AUC > 0.75, the features contain strong linear signal and XGBoost will improve further. If LR AUC < 0.65, the problem is non-linear and XGBoost becomes essential. Do not ship LR to production.

### E2. Training Configuration (Starting Points)

**Model 1 (Starting Price Regression):**
- `target = log1p(starting_price)`
- Primary metric: RMSE on log scale; report in production as MAPE on original RWF scale
- Stratify folds by: main_category × condition (ensures all condition grades in each fold)
- Starting hyperparameters: `n_estimators=500, max_depth=6, learning_rate=0.05, subsample=0.8, colsample_bytree=0.8, reg_alpha=0.1, reg_lambda=1.0, min_child_weight=5`
- Use early stopping on validation RMSE (patience=50 rounds)

**Model 2 (Winning Bid Regression):**
- `target = log1p(winning_amount)`
- Primary metric: MAPE — percentage accuracy is more interpretable for admins ("off by 18%") than RWF error
- Stratify by: main_category only (71K rows is ~2.5x smaller than Model 1; fewer strata avoid empty cells)
- Reduce max_depth to 5 to compensate for smaller dataset; increase min_child_weight to 10

**Model 3 (Bid Probability Classification):**
- `target = (total_bids > 0).astype(int)`
- Primary metrics: AUC-ROC, Precision-Recall AUC
- Tune classification threshold post-training to optimize F1 for the deployment use case
- LR baseline trained first with `C=1.0, max_iter=1000`

### E3. Evaluation Strategy

| Concern | Mitigation |
|---------|-----------|
| Synthetic distribution shift | Reserve 10% of first real-data batch as a strictly held-out real-data test set; never use synthetic test set as final authority after real data arrives |
| Category imbalance | Stratified 5-fold cross-validation with main_category as stratum |
| Luxury vehicle outliers | Evaluate separately on items > RWF 10M; luxury segment may need a separate model or price-tier indicator feature |
| Temporal leakage | Final test set = most recent 10% by `start_date`, not random split — simulates forward-prediction scenario |
| Label leakage (Model 2) | Audit feature matrix before training: `winner_uid`, `closed_at`, `current_highest_bid` must be absent |
| Bicycle underrepresentation | Report per-category metrics; do not report aggregate MAPE only |

### E4. Acceptance Criteria Before Production Deployment

| Model | Metric | Minimum (bootstrap) | Target (production) |
|-------|--------|--------------------|--------------------|
| Model 1 — Starting Price | MAPE | < 25% | < 15% |
| Model 2 — Winning Bid | MAPE | < 30% | < 20% |
| Model 3 — Bid Probability | AUC-ROC | > 0.70 | > 0.80 |

Thresholds are set conservatively for synthetic-data training. Real-data retrain thresholds should be recalibrated after the first 1,000 closed real auctions are available.

---

## Section F: Real Data Transition Plan

### F1. Transition Triggers

Phase 4 (retire synthetic training data, train on real data) can begin when all of the following hold in the Supabase production database:

- 1,000+ closed auctions with `winner_uid` recorded (minimum for Model 2 label supply)
- 500+ closed auctions per major category (vehicle, motorcycle) for per-category evaluation
- 6+ months of auction history (minimum span for temporal cross-validation)
- 5+ closed auctions per region (minimum for regional demand signal estimation)

### F2. Hybrid Training Strategy

When real data is available but below transition thresholds:
1. Train on full 200K synthetic corpus (Phase 2 baseline)
2. Fine-tune (warm-start) on the real-data subset using `learning_rate=0.01` and the trained synthetic model as the initial checkpoint
3. Evaluate exclusively on a real held-out test set (synthetic test set is no longer the authority)
4. Assign `sample_weight=3.0` to real rows vs `1.0` for synthetic rows to bias learning toward real patterns

When real data exceeds transition thresholds:
1. Retire synthetic training data entirely (retain as diagnostic reference)
2. Full retraining on real corpus with 5-fold temporal cross-validation
3. Synthetic data may be used only for category-level augmentation in underrepresented bins (e.g., bicycle if < 200 real records)

### F3. Fields That Need Priority Collection in Production

These fields have high synthetic null rates and high model feature importance. They must be required or strongly prompted in `PostAuctionScreen` before real data collection begins:

| Field | Current Null % | Collection Point | Action |
|-------|---------------|-----------------|--------|
| `accident_history` | 45.12% | PostAuctionScreen | Make required (non-nullable dropdown) |
| `insurance_status` | 37.05% | PostAuctionScreen | Make required (non-nullable dropdown) |
| `mileage` | 26.47% | PostAuctionScreen | Validate range 0–999,999; N/A for bicycles |
| `fuel_type` | 26.51% | PostAuctionScreen | Required dropdown; N/A for bicycles |
| `transmission` | 24.54% | PostAuctionScreen | Required dropdown; N/A for bicycles |
| `manufacturing_year` | 21.48% | PostAuctionScreen | Validate 1950–current year |
| `view_duration_seconds` | 0% (views table) | record_auction_view RPC | Already captured in Phase 1 |

### F4. Production Model Monitoring

Once `ai_predictions` table contains live inference outputs:

- **Prediction vs actual tracking:** compare `predicted_winning_bid` vs `winning_amount` for auctions that close after prediction was written; compute rolling MAPE per week
- **Confidence calibration:** verify that `predicted_probability = 0.7` leads to actual bid receipt ~70% of the time (reliability diagram)
- **Feature drift:** monitor null rates on incoming real auctions vs synthetic baselines; alert if any feature null rate shifts > 15 percentage points
- **Regional drift:** alert if regional distribution shifts > 20% from training distribution (e.g., sudden Central region saturation)
- **Retraining trigger:** initiate retraining if 90-day rolling MAPE degrades > 5% absolute from the post-training baseline evaluation

---

## Section G: Risks and Mitigations

### G1. Synthetic Data Biases

| Bias | Description | Severity | Mitigation |
|------|------------|---------|-----------|
| Multiplicative price formula | Real prices may have non-multiplicative brand × condition interactions (e.g., poor-condition luxury vehicles have different floors) | High | Validate winning_amount/starting_price ratio histogram on first 200 real closed auctions; recalibrate if distribution differs |
| Bid timing concentration | 50% last-minute bids is an assumption; real bidders on a police auction platform may behave differently (e.g., more early bids from pre-registered buyers) | Medium | Collect bid timing data; retrain Model 3 timing features when 1K real bids available |
| Completeness probability | Vehicle 85%, bicycle 50% are assumed; real admin data entry behavior may differ systematically by admin or region | Medium | Track actual null rates in PostAuctionScreen; adjust imputation group medians if real profile diverges |
| Regional demand factors | Central:1.15, Eastern:1.05, others:0.95–1.00 are estimates; real cross-regional price differentials are unknown | Medium | Estimate real factors from first 50 closed auctions per region; update target encoding accordingly |
| Exponential winning bid premium | The chosen Exponential(scale=0.18) distribution produces a ~18% mean premium; real competitive pressure in police auctions may be higher or lower | High | This is the highest-risk assumption — validate immediately on first 100 real closed auctions |
| No fraud or shill bidding | All synthetic bids are genuine; real production will contain outlier bids from test accounts, admin tests, and potential gaming | Low-Medium | Add data cleaning step to Phase 4: filter bids from admin UIDs; exclude auctions with single-bidder spikes |

### G2. Training Infrastructure Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| Memory: 200K rows × 37 float64 columns ≈ 60MB; manageable on any modern machine | Low | Medium | Use Parquet + chunked reads if extending beyond 500K rows; not a concern for Phase 3 |
| Overfitting to synthetic price formula | Medium | High | Use temporal hold-out (not random split) as the canonical test set; a model that memorized the formula will fail on randomly dated auctions |
| Feature store drift between training and inference | Medium | High | `feature_snapshot JSONB` column is already built into `ai_predictions` table (Phase 2 design); always write the exact feature vector used at inference time |
| Service role key exposure | Medium | Critical | Confirm `supabase/.env` is gitignored; audit `backend/ai/` before running export scripts; never commit `SUPABASE_SERVICE_ROLE_KEY` |
| Auction data recency: synthetic data uses REF_DATE = 2026-06-11; real data will have different temporal spread | Low | Low | Recompute `asset_age` at inference time using `CURRENT_DATE`, not REF_DATE; `v_auction_ml_features` already does this |

### G3. Phase 3 Scope Constraints

The following are explicitly out of scope for Phase 3 and must not be included in the implementation plan:

- Production serving infrastructure (FastAPI, REST prediction endpoints) — Phase 4
- Flutter UI widgets for predictions — Phase 4
- Automated retraining pipelines — Phase 5
- Fraud / shill-bid detection — separate track
- NLP on `description` field — separate track; text features have low marginal value in tabular setting
- XGBoost hyperparameter search at large scale — Phase 3 uses fixed starting parameters; HPO is Phase 4

---

## Readiness Verdict

**Phase 3 can proceed.** All three synthetic datasets pass quality validation with a perfect score of 1.0. Label availability is sufficient for bootstrap training of all three models. Feature engineering requirements are well-defined and grounded in the actual data distributions.

### Adjustments Required Before Training

1. **Apply `log1p` transform to all price and mileage columns.** The starting_price distribution spans 3 orders of magnitude with an IQR upper fence at RWF 8.4M. Models trained on raw prices will underfit the low-price tail. This is the single highest-impact preprocessing step.

2. **Drop the `model` column from all feature matrices.** It encodes `{brand[:3]}{sub[:3]}{year%100}` and has ~157,000 distinct values across 200K rows. It will overfit catastrophically as a categorical feature.

3. **Create missingness indicator flags before imputing `accident_history` and `insurance_status`.** A null `accident_history` is not "No Accidents" — it means the admin did not disclose. The missingness is itself a signal that must be preserved as a binary feature.

4. **Build category-specific preprocessing pipelines for bicycle vs vehicle/motorcycle.** `mileage=null` on a bicycle means "not applicable" not "unknown." Assigning median vehicle mileage (≈ 90,000 km) to a bicycle will introduce significant noise into the mileage feature.

5. **For Model 2 (winning bid), add explicit `won_premium` = `winning_amount / starting_price` as a diagnostic column** and compute the empirical premium distribution. If the Exponential(0.18) assumption is far from what the model learns, Phase 4 recalibration will be necessary.

6. **For Model 3, train on the closed-only subset first (120K rows, 72K positive / 48K negative)** before expanding to all 200K. Draft auctions structurally receive 0 bids by policy — including them inflates the negative class in a way that does not generalize to the inference use case (active auctions).

### Additional Schema Fields

No new database schema changes are required for Phase 3. All 36 columns of `v_auction_ml_features` are sufficient. After Phase 3 model validation, two additive fields are worth planning for Phase 4:

- A `expected_auction_price` estimate surfaced in `AuctionDetailScreen` for clients (reads from `ai_predictions` for `prediction_type = 'auction_price_estimate'`). Model A is a **client-facing** market value estimator — it does not surface suggestions to admins in `PostAuctionScreen` and does not influence the admin-defined starting price.
- A `bid_count_at_close` denormalized column on `auctions` for faster feature retrieval at inference time (avoids a join to `bids` table)

### Questions to Answer Before Model Training Begins

1. **Prediction serving pattern:** Should predictions be written to `ai_predictions` on a schedule (nightly batch for all active auctions) or on-demand when an admin views an auction detail page? This changes which features are valid inputs at scoring time — real-time `views_count` is available on-demand but is a stale nightly snapshot in batch mode.

2. **Accuracy target that is useful:** Is the goal "within RWF 500,000 of the final price" (useful for admins setting reserves), or "directional — above/below a threshold" (useful for flagging undervalued lots)? This determines which acceptance threshold from Section E4 to optimize for and whether MAPE or a custom loss function is more appropriate.

3. **Legally constrained auctions:** Are there vehicle categories — for example, government-seized high-value assets or vehicles from specific criminal cases — that have legally mandated minimum prices regardless of market value? If so, those auctions must be excluded from Model 1 training to avoid the model learning a suppressed price floor.

4. **Training compute environment:** Will Phase 3 scripts run locally (Windows laptop), in a cloud notebook (Colab/Kaggle), or as a Supabase Edge Function? This determines whether model artifacts are stored as `.json` (XGBoost native) in `backend/ai/models/`, uploaded to Supabase Storage `reports` bucket, or handled differently. The answer affects the Phase 3 implementation plan structure.
