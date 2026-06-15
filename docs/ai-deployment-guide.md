# E-CYAMUNARA AI System — Deployment Guide

**Date:** 2026-06-15  
**Phase coverage:** Phase 4A (training) → Phase 6 (MLOps inference) → Phase 7 (Edge Functions)

---

## 1. Deployment Audit Table

| Component | Implemented | Committed to Git | Deployed | Production Ready |
|-----------|-------------|-----------------|----------|-----------------|
| FastAPI inference service (`backend/ai/inference/`) | ✅ Yes | ✅ Yes | ❌ No — needs hosting | ❌ Blocked on hosting |
| Dockerfile (`backend/ai/Dockerfile`) | ✅ Yes | ✅ Yes | N/A | ✅ Ready to build |
| Trained models (model_a v1.0.4, model_b v1.0.1, model_c v1.0.1) | ✅ Yes | ✅ Yes | ❌ Local only | ❌ Must be on server |
| `ai-predict-price` Edge Function | ✅ Yes | ✅ Yes | ✅ **DEPLOYED** | ⚠️ Needs FastAPI URL |
| `ai-bid-forecast` Edge Function | ✅ Yes | ✅ Yes | ✅ **DEPLOYED** | ⚠️ Needs FastAPI URL |
| `ai-retrain-trigger` Edge Function | ✅ Yes | ✅ Yes | ✅ **DEPLOYED** | ⚠️ Needs FastAPI URL |
| `ai-model-promote` Edge Function | ✅ Yes | ✅ Yes | ✅ **DEPLOYED** | ⚠️ Needs FastAPI URL |
| `ai-model-rollback` Edge Function | ✅ Yes | ✅ Yes | ✅ **DEPLOYED** | ⚠️ Needs FastAPI URL |
| `AI_INFERENCE_URL` secret in Supabase | ✅ In `.env` | N/A (secret) | ❌ Not set in Supabase | ❌ Blocked on hosting |
| `ai_feature_flags` DB table | Unknown | Unknown | Unknown | Must verify exists |
| `ai_predictions` DB table | Unknown | Unknown | Unknown | Must verify exists |

---

## 2. What Was Done in This Session

### 2.1 Edge Functions — All 5 Deployed

All five Phase 7 Edge Functions are now live on Supabase project `ecyamunara-rnp` (`ltpcbsapeshskdnvtlru`):

| Function | Endpoint | Auth Required |
|----------|----------|--------------|
| `ai-predict-price` | `POST /functions/v1/ai-predict-price` | Any authenticated user |
| `ai-bid-forecast` | `POST /functions/v1/ai-bid-forecast` | Any authenticated user |
| `ai-retrain-trigger` | `POST /functions/v1/ai-retrain-trigger` | `region_admin` or `super_admin` |
| `ai-model-promote` | `POST /functions/v1/ai-model-promote` | `super_admin` only |
| `ai-model-rollback` | `POST /functions/v1/ai-model-rollback` | `super_admin` only |

Deployed with:
```
supabase functions deploy ai-predict-price
supabase functions deploy ai-bid-forecast
supabase functions deploy ai-retrain-trigger
supabase functions deploy ai-model-promote
supabase functions deploy ai-model-rollback
```

### 2.2 Dockerfile Created

`backend/ai/Dockerfile` is ready to build and run the FastAPI service. It:
- Uses `python:3.11-slim`
- Copies `backend/ai/inference/` and `backend/ai/trained_models/`
- Exposes port 8000
- Runs `uvicorn inference.main:app --host 0.0.0.0 --port 8000`

### 2.3 Environment Files

- `supabase/.env` — contains real OneSignal keys and `AI_INFERENCE_URL=http://localhost:8000` (placeholder)
- `supabase/.env.example` — committed to git with full documentation
- `.gitignore` — updated to allow `**/.env.example` while keeping `.env` ignored
- `backend/ai/inference/.env.example` — template for FastAPI service environment

---

## 3. What You Must Do Manually (Blockers Before Phase 8)

### 3.1 Host the FastAPI Service

The five deployed Edge Functions call your FastAPI service. Until it has a **public URL**, all AI features return `503 AI inference service not configured`.

#### Option A — Railway (Recommended — free tier available)

1. Go to [railway.app](https://railway.app) → New Project → Deploy from GitHub repo
2. Set root directory: `backend/ai`
3. Railway auto-detects the Dockerfile
4. Set these environment variables in Railway dashboard:
   - `SUPABASE_URL=https://ltpcbsapeshskdnvtlru.supabase.co`
   - `SUPABASE_SERVICE_ROLE_KEY=<your service role key>`
   - `PREDICTION_STORE_ENABLED=true`
   - `REGISTRY_PATH=/app/trained_models/registry.json`
5. Railway gives you a public URL like `https://ecyamunara-ai.up.railway.app`

#### Option B — Render (free tier)

1. Go to [render.com](https://render.com) → New → Web Service → GitHub
2. Root Directory: `backend/ai`
3. Dockerfile detected automatically
4. Add environment variables (same as above)
5. You get a URL like `https://ecyamunara-ai.onrender.com`

#### Option C — VPS (DigitalOcean, AWS EC2, Hetzner)

```bash
# On your VPS
git clone https://github.com/Entue250/e-cyamunara.git
cd e-cyamunara/backend/ai

# Create .env for inference service
cp inference/.env.example inference/.env
# Edit inference/.env with your real Supabase keys

# Build and run
docker build -t ecyamunara-ai .
docker run -d -p 8000:8000 --env-file inference/.env --name ecyamunara-ai ecyamunara-ai
```

### 3.2 Set AI_INFERENCE_URL in Supabase

Once FastAPI is hosted, run this **one command**:

```bash
supabase secrets set AI_INFERENCE_URL=https://your-fastapi-url-here
```

Example with Railway URL:
```bash
supabase secrets set AI_INFERENCE_URL=https://ecyamunara-ai.up.railway.app
```

This must be run from the project directory (where `supabase` CLI is linked).

### 3.3 Verify the DB Tables Exist

The Edge Functions read/write two tables that must exist in your Supabase database:

**`ai_feature_flags`** — controls shadow mode and client visibility:
```sql
CREATE TABLE IF NOT EXISTS ai_feature_flags (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Required seed rows
INSERT INTO ai_feature_flags (key, value) VALUES
  ('ai.shadow_mode_enabled',         'true'),
  ('ai.predictions_visible_to_clients', 'false'),
  ('ai.model_a_shadow_version',      ''),
  ('ai.model_b_shadow_version',      ''),
  ('ai.model_c_shadow_version',      '');
```

**`ai_predictions`** — stores every prediction:
```sql
CREATE TABLE IF NOT EXISTS ai_predictions (
  id                     UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  auction_id             UUID NOT NULL,
  prediction_type        TEXT NOT NULL,  -- 'auction_price_estimate' | 'winning_bid' | 'bid_probability'
  prediction_source      TEXT NOT NULL,  -- 'real' | 'shadow'
  model_version          TEXT NOT NULL,
  expected_auction_price NUMERIC,
  value_signal           TEXT,
  value_ratio            NUMERIC,
  predicted_winning_bid  NUMERIC,
  predicted_probability  NUMERIC,
  confidence_score       NUMERIC,
  inference_ms           INTEGER,
  created_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_type
  ON ai_predictions (auction_id, prediction_type, prediction_source, created_at DESC);
```

Run these in **Supabase Dashboard → SQL Editor**.

---

## 4. End-to-End Verification Commands

Run these after FastAPI is hosted and `AI_INFERENCE_URL` is set.

### 4.1 FastAPI Health Check

```bash
curl https://your-fastapi-url/health
```

Expected response:
```json
{
  "status": "ok",
  "models": {
    "model_a": {"status": "loaded", "version": "v1.0.4-synthetic"},
    "model_b": {"status": "loaded", "version": "v1.0.1-synthetic"},
    "model_c": {"status": "loaded", "version": "v1.0.1-synthetic"}
  }
}
```

### 4.2 FastAPI Direct Prediction Tests

```bash
# Model A — predict auction price
curl -X POST https://your-fastapi-url/predict-price \
  -H "Content-Type: application/json" \
  -d '{
    "auction_id": "test-001",
    "store_prediction": false,
    "features": {
      "main_category": "Vehicle",
      "fuel_type": "Petrol",
      "transmission": "Automatic",
      "ownership_history": "one_owner",
      "accident_history": "none",
      "insurance_status": "valid",
      "brand": "Toyota",
      "sub_category": "Sedan",
      "region": "Kigali",
      "condition": "good",
      "asset_age": 5,
      "auction_duration_hours": 72,
      "mileage": 80000,
      "starting_price": 8000000,
      "has_description": true,
      "has_images": true,
      "is_accident_history_known": true,
      "is_insurance_status_known": true,
      "is_mileage_known": true,
      "is_manufacturing_year_known": true
    }
  }'
```

Expected: `{"model_version": "v1.0.4-synthetic", "expected_auction_price": <number>, "value_signal": "...", ...}`

```bash
# Model B — predict winning bid
curl -X POST https://your-fastapi-url/predict-winning-bid \
  -H "Content-Type: application/json" \
  -d '{
    "auction_id": "test-001",
    "store_prediction": false,
    "features": {
      "main_category": "Vehicle",
      "fuel_type": "Petrol",
      "transmission": "Automatic",
      "ownership_history": "one_owner",
      "accident_history": "none",
      "insurance_status": "valid",
      "brand": "Toyota",
      "sub_category": "Sedan",
      "region": "Kigali",
      "condition": "good",
      "asset_age": 5,
      "auction_duration_hours": 72,
      "mileage": 80000,
      "starting_price": 8000000,
      "has_description": true,
      "has_images": true,
      "is_accident_history_known": true,
      "is_insurance_status_known": true,
      "is_mileage_known": true,
      "is_manufacturing_year_known": true,
      "total_bids": 5,
      "unique_bidder_count": 3,
      "views_count": 50,
      "bid_momentum": 1.5,
      "view_to_bid_ratio": 10.0,
      "time_to_first_bid_hours": 2.0,
      "days_until_close": 1.0,
      "bid_acceleration": 0.5,
      "is_first_bid_quick": true,
      "price_tier": "medium"
    }
  }'
```

```bash
# Model C — predict winning probability
curl -X POST https://your-fastapi-url/predict-winning-probability \
  -H "Content-Type: application/json" \
  -d '{ ... same body as Model B above ... }'
```

### 4.3 Edge Function Tests (via Supabase)

Replace `<JWT>` with a valid user JWT token from your app.

```bash
# ai-predict-price
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-predict-price \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"auction_id": "your-auction-uuid", "features": { ... }}'

# ai-bid-forecast
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-bid-forecast \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"auction_id": "your-auction-uuid", "features": { ... }}'

# ai-retrain-trigger (admin JWT required)
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-retrain-trigger \
  -H "Authorization: Bearer <ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "all", "datasource": "synthetic"}'

# ai-model-promote (super_admin JWT required)
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-model-promote \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "model_a", "version": "v1.0.4-synthetic"}'

# ai-model-rollback (super_admin JWT required)
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-model-rollback \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "model_a"}'
```

### 4.4 Shadow Mode Behavior

Until you run the SQL seed above and set `ai.shadow_mode_enabled = 'true'`, Edge Functions return:
```json
{"error": "AI predictions not available (shadow mode disabled)"}
```

Until you set `ai.predictions_visible_to_clients = 'true'`, Edge Functions return:
```json
{"stored": true, "auction_id": "...", "shadow_mode": true}
```
(Predictions are stored in `ai_predictions` but not shown to users — this is by design.)

---

## 5. FastAPI Rollback Steps

If FastAPI crashes or models behave unexpectedly after deployment:

```bash
# Check container logs
docker logs ecyamunara-ai --tail 50

# Restart container
docker restart ecyamunara-ai

# Roll back model_a to previous version via Edge Function
curl -X POST https://ltpcbsapeshskdnvtlru.supabase.co/functions/v1/ai-model-rollback \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"model_name": "model_a"}'

# Disable all AI predictions immediately (no restart needed)
# Run in Supabase SQL Editor:
UPDATE ai_feature_flags SET value = 'false' WHERE key = 'ai.shadow_mode_enabled';
```

---

## 6. Phase 8 Readiness Checklist

**Phase 8 (Flutter AI integration) MUST NOT begin until all of these are checked:**

- [ ] FastAPI hosted on public URL (Railway / Render / VPS)
- [ ] `GET /health` returns 200 with all 3 models loaded
- [ ] `supabase secrets set AI_INFERENCE_URL=https://your-url` completed
- [ ] `ai_feature_flags` table created and seeded
- [ ] `ai_predictions` table created with index
- [ ] `POST /predict-price` returns valid prediction (curl test)
- [ ] `POST /predict-winning-bid` returns valid prediction (curl test)
- [ ] `POST /predict-winning-probability` returns valid prediction (curl test)
- [ ] Edge Function `ai-predict-price` returns `{"stored": true, ...}` (shadow mode on, clients off)
- [ ] Edge Function `ai-bid-forecast` returns `{"stored": true, ...}`

Once all boxes above are checked: **GO for Phase 8.**

---

## 7. Active Model Versions (as of 2026-06-15)

| Model | Active Version | Acceptance | R² | Notes |
|-------|---------------|------------|-----|-------|
| model_a | v1.0.4-synthetic | EXCELLENT | 0.9535 | Predicts `winning_amount`; `starting_price` is input |
| model_b | v1.0.1-synthetic | EXCELLENT | 0.9566 | Predicts `predicted_winning_bid` |
| model_c | v1.0.1-synthetic | EXCELLENT | AUC=1.0 | Predicts `bid_probability` |

All models trained on synthetic data. When real auction data accumulates, retrain via `ai-retrain-trigger`.
