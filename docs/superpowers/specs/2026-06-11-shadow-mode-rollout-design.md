# Shadow-Mode AI Prediction Rollout — Design Spec

## Context

The `ai_predictions` table is live (migrations 000006–000010 applied). Three trained models
are registered (`v1.0.4-synthetic` / `v1.0.0-synthetic`). The schema supports
`expected_auction_price`, `value_signal`, `value_ratio`, `starting_price_at_prediction`.

Shadow mode: **generate predictions silently, store them in DB, never expose to clients.**
When the system is validated, flipping one feature flag exposes predictions to users.

---

## 1. Feature Flags

Storage: `app_settings` table (key-value, TEXT). Service_role writes via Edge Functions.
All authenticated users can read (flags are non-sensitive; reading is needed by the
RLS subquery on `ai_predictions`).

| Key | Default | Purpose |
|-----|---------|---------|
| `ai.shadow_mode_enabled` | `'true'` | Master switch — if false, no predictions generated |
| `ai.predictions_visible_to_clients` | `'false'` | RLS gate on `ai_predictions` client reads |
| `ai.model_a_active_version` | `'v1.0.4-synthetic'` | Which model artifact to load for inference |
| `ai.model_b_active_version` | `'v1.0.0-synthetic'` | |
| `ai.model_c_active_version` | `'v1.0.0-synthetic'` | |
| `ai.min_feature_completeness_score` | `'0.5'` | Skip prediction below this completeness |
| `ai.inference_timeout_ms` | `'5000'` | Max inference call duration |
| `ai.retrain_min_new_closed_auctions` | `'100'` | Volume threshold for retrain review |
| `ai.retrain_mape_trigger_threshold` | `'0.25'` | Rolling MAPE above this flags retrain |
| `ai.coverage_alert_threshold` | `'0.80'` | Alert if prediction coverage drops below |
| `ai.retrain_pending` | `'false'` | Set true when threshold breached (reviewed manually) |
| `ai.last_retrain_date` | `''` | ISO date of last retrain |
| `ai.retrain_trigger_reason` | `''` | `'mape_degraded'` / `'data_volume'` |

**Shadow mode gate in RLS:** The `client_read_auction_price_estimates` policy on
`ai_predictions` includes a subquery that checks `predictions_visible_to_clients`.
While this is `'false'`, all client reads of `ai_predictions` return 0 rows — at the
DB level, not the application level. No Flutter code change is needed to enforce this.

To graduate from shadow mode: `UPDATE public.app_settings SET value = 'true' WHERE key = 'ai.predictions_visible_to_clients';`

---

## 2. Prediction Storage Flow

### Trigger: `generate-ai-predictions` Edge Function

**Activation:** Database Webhook on `auctions` table — INSERT events + UPDATE events
where `new.auction_status = 'active'`.

**Flow (per auction):**
```
Webhook payload received
  ↓
auction_status = 'active'? → NO → return 200 "skipped: auction_not_active"
  ↓ YES
app_settings: ai.shadow_mode_enabled = 'true'? → NO → log skip, return 200
  ↓ YES
ai_predictions already has rows for this auction_id? → YES → return 200 "skipped: already_predicted"
  ↓ NO
Call FastAPI: POST /predict/auction/{auction_id}
  ↓
FastAPI:
  1. Query v_auction_ml_features for auction_id
  2. Check feature_completeness_score ≥ min threshold → NO → log skip, return skip response
  3. Run Model A pipeline → expected_auction_price, confidence_score
  4. Compute value_ratio = starting_price / expected_auction_price
  5. Derive value_signal from ratio thresholds
  6. Run Model B pipeline → predicted_winning_bid
  7. Run Model C pipeline → predicted_probability
  8. INSERT 3 rows into ai_predictions (service_role)
  9. INSERT 1 row into ai_prediction_logs (event_type='prediction_generated')
  10. Return summary JSON
Edge Function logs result, returns 200
```

**Value signal derivation** (from `InferenceConfig` thresholds):
- `value_ratio < 0.75` → `"undervalued"` (starting_price is < 75% of expected)
- `0.75 ≤ value_ratio ≤ 1.25` → `"fairly_priced"`
- `value_ratio > 1.25` → `"overpriced"` (starting_price exceeds expected by 25%+)

### Batch backfill: `backfill-ai-predictions` Edge Function

On-demand function (called manually by super_admin or via pg_cron once).
Fetches all `auction_status IN ('active', 'closed')` auctions without predictions,
processes in batches of 50, calls FastAPI `/predict/batch`.

---

## 3. Logging Strategy

Table: `ai_prediction_logs`

Every prediction attempt — success, skip, or error — writes one row.

| Field | Values |
|-------|--------|
| `event_type` | `prediction_generated`, `prediction_skipped`, `prediction_error`, `comparison_computed`, `retrain_trigger`, `metrics_collected` |
| `models_run` | `ARRAY['model_a', 'model_b', 'model_c']` or subset |
| `model_versions` | `{"model_a": "v1.0.4-synthetic", ...}` JSONB |
| `duration_ms` | Wall-clock time of FastAPI call |
| `error_code` | HTTP status or internal code (null on success) |
| `skip_reason` | `shadow_mode_disabled`, `feature_completeness_low`, `already_predicted`, `auction_not_active`, `inference_timeout`, `no_winning_amount` |
| `feature_completeness_score` | Captured from `v_auction_ml_features` |
| `metadata` | JSONB — feature snapshot, partial results, model response |

Sentry captures exceptions at the Edge Function and FastAPI layers with auction_id context.

**No PII in logs.** Auction IDs are UUIDs. No user data in metadata.

---

## 4. Monitoring Strategy

### Daily aggregate table: `ai_shadow_metrics`

Populated at 02:00 UTC by the `collect-ai-shadow-metrics` Edge Function (pg_cron).

### Coverage monitoring
- Eligible: auctions with `auction_status IN ('active', 'closed')`
- Covered: eligible auctions with at least one `ai_predictions` row
- Alert trigger: `coverage_rate < ai.coverage_alert_threshold` (default 0.80)
- Response: trigger backfill, investigate Edge Function failures

### Latency monitoring
- Source: `duration_ms` in `ai_prediction_logs` WHERE `event_type = 'prediction_generated'`
- Metrics collected: `avg_inference_ms`, `p95_inference_ms`
- Alert trigger: avg > 2000ms or P95 > 5000ms
- Response: check FastAPI server resources, model load time, Supabase query latency

### Error rate monitoring
- Rolling 24h: `prediction_error` events / (`prediction_generated` + `prediction_error`) events
- Alert trigger: > 5%
- Response: check Edge Function logs, FastAPI health endpoint, Supabase connectivity

### Prediction distribution monitoring
- `value_signal` distribution should be roughly: 60% fairly_priced, 20% undervalued, 20% overpriced
- Extreme skew (>80% in any bucket) signals a model or data issue

### Dashboard: `v_ai_shadow_dashboard` view
Queryable by super_admins. Shows current flags, latest daily metrics, all-time totals.

---

## 5. Metrics Collection

### Daily collection by `collect-ai-shadow-metrics` Edge Function

```
Run at 02:00 UTC (pg_cron)
  ↓
Aggregate yesterday's ai_prediction_logs:
  - COUNT by event_type
  - AVG and PERCENTILE_CONT(0.95) of duration_ms
  ↓
Count eligible/covered auctions (coverage_rate)
  ↓
Query ai_prediction_comparisons for rolling MAPE:
  - Last 100 closed auctions with had_bids = TRUE
  - AVG(absolute_percentage_error) = rolling_mape_model_a
  - AVG(absolute_error_rwf) = rolling_mae_rwf_model_a
  - COUNT(signal_correct) / COUNT(*) = signal_accuracy_rate
  ↓
Check retrain triggers (see §7)
  ↓
INSERT into ai_shadow_metrics (one row per day, UNIQUE on metric_date)
```

---

## 6. Ground-Truth Comparison

### Trigger: `compute-prediction-comparison` Edge Function

**Activation:** Database Webhook on `auctions` UPDATE where `new.auction_status = 'closed'`.
Also called from `auto-close-auctions` after each auction close (belt-and-suspenders).

**Flow:**
```
Auction closed event received (auction_id, winning_amount)
  ↓
Find ai_predictions WHERE auction_id = X AND prediction_type = 'auction_price_estimate'
  ↓
No prediction found? → log (comparison_computed with null predicted_value), return
  ↓
had_bids = (winning_amount IS NOT NULL AND winning_amount > 0)
  ↓
If had_bids:
  absolute_error = ABS(predicted_value - actual_value)
  ape = absolute_error / actual_value
  residual = predicted_value - actual_value
  actual_signal = compute_value_signal(starting_price, actual_value)
  signal_correct = (predicted_value_signal = actual_signal)
  ↓
INSERT into ai_prediction_comparisons (UNIQUE on auction_id — idempotent)
  ↓
INSERT into ai_prediction_logs (event_type='comparison_computed', metadata={ape, residual, signal_correct})
```

**Value signal thresholds for actual signal computation** — same 0.75/1.25 thresholds as prediction.

---

## 7. Retraining Triggers

Checked daily by `collect-ai-shadow-metrics`. All triggers are advisory — they set a flag
and log a reason. Retrain is a manual human decision.

### Trigger 1: Data volume threshold
```
New closed auctions since ai.last_retrain_date
  > ai.retrain_min_new_closed_auctions (100)
→ set ai.retrain_pending = 'true'
   ai.retrain_trigger_reason = 'data_volume'
```

### Trigger 2: MAPE degradation
```
rolling_mape_model_a (last 100 closed auctions with bids)
  > ai.retrain_mape_trigger_threshold (0.25)
→ set ai.retrain_pending = 'true'
   ai.retrain_trigger_reason = 'mape_degraded'
```

### Retrain workflow (out of scope for Phase 4)
1. ML team sees `ai.retrain_pending = 'true'` in dashboard
2. Run `export_training_dataset.py --status closed`
3. Merge with synthetic data (until real data > 1000 closed auctions)
4. Run `run_all_models.py` — acceptance gates must pass
5. Update `app_settings` with new model versions
6. Set `ai.retrain_pending = 'false'`, `ai.last_retrain_date = today`

**Auto-retrain is explicitly NOT designed** — synthetic data biases make automated retraining
risky until real auction data dominates.

---

## SQL Deliverable

See: `supabase/migrations/20260611000011_shadow_mode_infrastructure.sql`

Tables created:
- `app_settings` — feature flags (CREATE TABLE IF NOT EXISTS, safe on re-run)
- `ai_prediction_logs` — per-prediction event log
- `ai_prediction_comparisons` — ground-truth records (UNIQUE on auction_id)
- `ai_shadow_metrics` — daily aggregates (UNIQUE on metric_date)

Views created:
- `v_ai_shadow_dashboard` — monitoring summary (SECURITY INVOKER)

Policy modified:
- `client_read_auction_price_estimates` on `ai_predictions` — adds feature flag gate

---

## FastAPI Deliverable

See: `docs/superpowers/plans/2026-06-11-shadow-mode-rollout.md` — Tasks 2–9

Directory: `backend/ai/inference/`

Endpoints:
- `GET /health` — model load status, DB connectivity, active model versions
- `POST /predict/auction/{auction_id}` — single prediction (requires `X-API-Key` header)
- `POST /predict/batch` — bulk prediction for backfill (max 100 per call)
- `GET /shadow/metrics?days=30` — last N days of `ai_shadow_metrics`

---

## Flutter Deliverable

See: `docs/superpowers/plans/2026-06-11-shadow-mode-rollout.md` — Tasks 13–16

Changes:
- `SupabaseConstants`: 4 new table constants + 3 new Edge Function constants
- `AIPredictionModel`: Dart data class mirroring `ai_predictions` columns
- `AIPredictionRepository`: read methods (NOT wired to any screen yet)
- `providers.dart`: `aiPredictionRepositoryProvider` exported (no UI consumer)

**No screen changes. No widget changes.** The DB-level RLS gate enforces invisibility.

---

## Validation Tests

See: `docs/superpowers/plans/2026-06-11-shadow-mode-rollout.md` — Task 18

SQL validation queries verify:
1. All 13 `app_settings` flags seeded correctly
2. `client_read_auction_price_estimates` policy contains feature flag subquery
3. Client reads return 0 rows while `predictions_visible_to_clients = 'false'`
4. All 4 new tables exist with correct column counts
5. `v_ai_shadow_dashboard` returns current flag state

Python tests verify:
1. `compute_value_signal()` thresholds (0.75 / 1.25)
2. POST `/predict/auction/{id}` returns correct structure
3. Unauthenticated requests return 401
4. `shadow_mode_enabled = false` returns skip response without calling models
5. `feature_completeness_score < 0.5` returns skip response
6. Logs are written for both success and skip cases

Dart tests verify:
1. `AIPredictionModel.fromJson()` round-trips all fields
2. `AIPredictionRepository.getPredictionForAuction()` returns null on empty response

---

## Invariants (must not be violated in implementation)

- `starting_price` is NEVER modified by prediction logic
- Model A output (`expected_auction_price`) is NEVER surfaced to Flutter clients in shadow mode
- `ai_prediction_logs` never contains PII (no bidder IDs, no names)
- Comparisons are only computed for `ai_predictions` rows — never created speculatively
- Retrain triggers are advisory only — no code automatically retrains models
- `docs/ai_readiness_audit.md` references `auctions.estimated_market_value` (admin-entered field) — do NOT confuse with `ai_predictions.expected_auction_price`
