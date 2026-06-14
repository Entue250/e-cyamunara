# Inference Service — Deployment Guide (Phase 4A)

## Overview

The FastAPI inference service serves real XGBoost predictions via three endpoints. In Phase 4A all predictions are stored with `model_stage='shadow'` and `prediction_source='real'`. They are never returned to Flutter clients until Phase 5 production promotion.

## Prerequisites

- Docker (or Python 3.12 + pip)
- Supabase project with migration `20260614000001_ai_predictions_coexistence.sql` applied
- Trained model artifacts at `backend/ai/trained_models/`

## Local Development

```bash
# From backend/ai/
pip install -r inference/requirements.txt

# Copy and fill in secrets
cp inference/.env.example inference/.env

# Run (training.* must be importable — run from backend/ai/)
PYTHONPATH=. uvicorn inference.main:app --reload --port 8000
```

Test the service:
```bash
curl http://localhost:8000/health
curl http://localhost:8000/models/active
```

## Docker Build

```bash
# From repo root
docker build -f backend/ai/inference/Dockerfile -t ecyamunara-inference:phase4a .
docker run --env-file backend/ai/inference/.env -p 8000:8000 ecyamunara-inference:phase4a
```

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `SUPABASE_URL` | Yes | Your Supabase project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | Yes | Service role key (for ai_predictions insert) |
| `REGISTRY_PATH` | No | Absolute path to registry.json (defaults to ../trained_models/registry.json) |
| `PREDICTION_STORE_ENABLED` | No | Set `false` to disable writing to Supabase (default: `true`) |
| `LOG_LEVEL` | No | `INFO` / `DEBUG` / `WARNING` (default: `INFO`) |

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | Loaded model versions + uptime |
| GET | `/models/active` | Registry metadata for all 3 active models |
| POST | `/predict/model-a` | Market value estimation (RWF price + value signal) |
| POST | `/predict/model-b` | Winning bid prediction (RWF price) |
| POST | `/predict/model-c` | Bid probability classification (0–1) |

## Input Fields

All predict endpoints accept raw auction fields — do **not** pre-compute derived features:

| Raw field | Used to derive |
|---|---|
| `manufacturing_year` | `asset_age` |
| `start_date` + `end_date` | `auction_duration_hours`, `days_until_close` |
| `description` | `has_description` |
| `photo_urls` | `has_images` |
| `total_bids` + `start_date` | `bid_momentum`, `bid_acceleration` |
| `views_count` + `total_bids` | `view_to_bid_ratio` |
| `time_of_first_bid` | `time_to_first_bid_hours`, `is_first_bid_quick` |
| `starting_price` | `price_tier` |

## Shadow Mode Constraints

- `ai.predictions_visible_to_clients` must remain `'false'` — Flutter never sees these predictions
- All real predictions use `model_stage='shadow'` until Phase 5 promotion
- The pg_cron synthetic pipeline continues running in parallel

## Running Tests

```bash
# From backend/ai/
PYTHONPATH=. pytest inference/tests/ -v
```
