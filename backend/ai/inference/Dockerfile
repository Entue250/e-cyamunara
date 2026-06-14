FROM python:3.12-slim

WORKDIR /app

# System dependencies for XGBoost and scientific stack
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgomp1 \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies from the inference requirements file
COPY backend/ai/inference/requirements.txt /tmp/inference-requirements.txt
RUN pip install --no-cache-dir -r /tmp/inference-requirements.txt

# Copy the full AI backend so training.* imports work
COPY backend/ai/ /app/

# Trained model artifacts (built separately, copied here at deploy time)
# COPY backend/ai/trained_models/ /app/trained_models/

# /app is the PYTHONPATH root — training.* and inference.* are importable from here
ENV PYTHONPATH=/app

# Override registry path to match container layout
ENV REGISTRY_PATH=/app/trained_models/registry.json

EXPOSE 8000

CMD ["uvicorn", "inference.main:app", "--host", "0.0.0.0", "--port", "8000"]
