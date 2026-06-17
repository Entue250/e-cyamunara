# Phase 9D — Training Worker Container (HTTP server mode)
# =========================================================
# Runs training_worker/app.py as a FastAPI HTTP server on port 8001.
# The WeeklyTrainingScheduler fires inside the container on its own interval;
# pg_cron calls POST /train to trigger additional on-demand runs.
#
# Build (context = backend/ai directory):
#   docker build -t ecyamunara-training-worker -f training_worker/Dockerfile .
#
# Run locally (real data from Supabase):
#   docker run -p 8001:8001 \
#     -e SUPABASE_URL=https://ltpcbsapeshskdnvtlru.supabase.co \
#     -e SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key> \
#     -e TRAINING_DATASOURCE=real \
#     -v $(pwd)/data:/app/data \
#     -v $(pwd)/trained_models:/app/trained_models \
#     ecyamunara-training-worker
#
# Health check:
#   curl http://localhost:8001/health
#
# Manual trigger:
#   curl -X POST http://localhost:8001/train \
#        -H "Content-Type: application/json" \
#        -d '{"model":"all","datasource":"real"}'

FROM python:3.11-slim

WORKDIR /app

# System deps: libgomp1 required by xgboost
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies.
# requirements.txt        — training/data deps (pandas, xgboost, pyarrow, supabase…)
# inference/requirements.txt — adds fastapi, uvicorn, pydantic, httpx (superset)
COPY requirements.txt requirements.txt
COPY inference/requirements.txt requirements_inference.txt
RUN pip install --no-cache-dir -r requirements.txt -r requirements_inference.txt

# Copy only the backend/ai subtree (context is the backend/ai directory)
COPY data_export/    data_export/
COPY training/       training/
COPY training_worker/ training_worker/

# /app/data          — job state + dataset snapshots  (mount via Railway Volume)
# /app/trained_models — model artifacts               (mount via Railway Volume)
# VOLUME is intentionally omitted: Railway does not support Dockerfile VOLUME
# instructions. Attach persistent volumes through the Railway service UI instead.

EXPOSE 8001

# HTTP server — WeeklyTrainingScheduler starts automatically inside app lifespan.
# pg_cron calls POST /train for on-demand triggers; the scheduler handles the
# weekly autonomous runs without any cron dependency.
CMD ["uvicorn", "training_worker.app:app", "--host", "0.0.0.0", "--port", "8001"]
