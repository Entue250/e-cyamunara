# Phase 9C — Training Worker Container
# ======================================
# Isolated from the FastAPI inference service. Shares only the
# trained_models/ volume. Training NEVER runs in the inference container.
#
# Build:
#   docker build -t ecyamunara-training-worker -f training_worker/Dockerfile .
#
# Run (real data from Supabase):
#   docker run --rm \
#     -e SUPABASE_URL=... \
#     -e SUPABASE_SERVICE_ROLE_KEY=... \
#     -v $(pwd)/data:/app/data \
#     -v $(pwd)/trained_models:/app/trained_models \
#     ecyamunara-training-worker \
#     python -m training_worker.trainer --model all --datasource real
#
# Run (from pre-built CSV):
#   docker run --rm \
#     -v $(pwd)/data:/app/data \
#     -v $(pwd)/trained_models:/app/trained_models \
#     ecyamunara-training-worker \
#     python -m training_worker.trainer --model all --datasource synthetic \
#       --data /app/data/synthetic/dataset.csv

FROM python:3.11-slim

WORKDIR /app

# System deps: only what xgboost + scikit-learn need
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies (reuse inference requirements where possible)
COPY inference/requirements.txt requirements_inference.txt
COPY requirements.txt requirements.txt 2>/dev/null || true
RUN pip install --no-cache-dir -r requirements_inference.txt

# Copy only the backend/ai subtree (context is the backend/ai directory)
COPY data_export/    data_export/
COPY training/       training/
COPY training_worker/ training_worker/

# Persistent volume for job state and dataset snapshots (mounted at runtime)
VOLUME ["/app/data"]

# Persistent volume for model artifacts shared with inference container
VOLUME ["/app/trained_models"]

# Default: train all models from real Supabase data
CMD ["python", "-m", "training_worker.trainer", "--model", "all", "--datasource", "real"]
