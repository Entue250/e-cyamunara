FROM python:3.11-slim

WORKDIR /app

# Install dependencies first (layer cache)
COPY inference/requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt

# Copy inference service source
COPY inference/ ./inference/
COPY trained_models/ ./trained_models/

# training/ must be present: model_loader.py imports ModelRegistry, artifact_io,
# and PlattScaler (which is baked into calibrated_model.joblib's pickle path).
# All Python deps training needs are already in inference/requirements.txt.
COPY training/ ./training/

# Copy package init so `backend.ai` imports resolve (not strictly needed in container)
COPY __init__.py ./__init__.py

ENV HOST=0.0.0.0
ENV PORT=8000
ENV REGISTRY_PATH=/app/trained_models/registry.json

EXPOSE 8000

CMD ["uvicorn", "inference.main:app", "--host", "0.0.0.0", "--port", "8000"]
