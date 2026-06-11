# Shadow-Mode AI Prediction Rollout — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run AI predictions silently on every auction activation, store results in `ai_predictions`, never expose to clients. Gate everything behind `app_settings` feature flags.

**Architecture:** Edge Function webhook triggers FastAPI inference server on every new active auction. FastAPI runs all three models, writes `ai_predictions` + `ai_prediction_logs`. Comparisons computed on auction close. Daily cron aggregates health metrics. No Flutter UI changes — shadow mode is enforced at the DB RLS layer.

**Tech Stack:** Deno Edge Functions (TypeScript), FastAPI + uvicorn (Python 3.11), XGBoost + joblib, Supabase Python client, Dart (Flutter), PostgreSQL migrations.

**Spec:** `docs/superpowers/specs/2026-06-11-shadow-mode-rollout-design.md`

---

### Task 1: SQL Migration — Shadow Mode Infrastructure

**Files:**
- Create: `supabase/migrations/20260611000011_shadow_mode_infrastructure.sql` ✓ (already written)

- [ ] **Step 1: Push migration**

```bash
supabase db push
```
Expected output:
```
Applying migration 20260611000011_shadow_mode_infrastructure.sql...
Finished supabase db push.
```

- [ ] **Step 2: Verify all 13 flags seeded**

Run in Supabase SQL editor (or `supabase db remote changes`):
```sql
SELECT key, value FROM public.app_settings WHERE key LIKE 'ai.%' ORDER BY key;
```
Expected: 13 rows. `ai.shadow_mode_enabled = 'true'`, `ai.predictions_visible_to_clients = 'false'`.

- [ ] **Step 3: Verify client RLS blocks reads**

```sql
-- Run this as the anon role or a client JWT to simulate a client query:
SELECT COUNT(*) FROM public.ai_predictions WHERE prediction_type = 'auction_price_estimate';
```
Expected: `0` even if rows exist (blocked by feature flag subquery in policy).

- [ ] **Step 4: Verify new tables and view exist**

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('app_settings','ai_prediction_logs','ai_prediction_comparisons','ai_shadow_metrics')
ORDER BY table_name;
```
Expected: 4 rows.

```sql
SELECT shadow_mode_enabled, predictions_visible, retrain_pending
FROM public.v_ai_shadow_dashboard;
```
Expected: `true`, `false`, `false`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260611000011_shadow_mode_infrastructure.sql
git commit -m "feat(db): shadow mode infrastructure — flags, logs, comparisons, metrics, policy gate"
```

---

### Task 2: FastAPI Project Scaffold

**Files:**
- Create: `backend/ai/inference/__init__.py`
- Create: `backend/ai/inference/main.py`
- Create: `backend/ai/inference/dependencies.py`
- Create: `backend/ai/inference/requirements.txt`
- Create: `backend/ai/inference/Dockerfile`
- Create: `backend/ai/inference/routers/__init__.py`
- Create: `backend/ai/inference/services/__init__.py`
- Create: `backend/ai/inference/models/__init__.py`
- Create: `backend/ai/inference/tests/__init__.py`
- Create: `backend/ai/inference/tests/conftest.py`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p backend/ai/inference/routers backend/ai/inference/services \
          backend/ai/inference/models backend/ai/inference/tests
touch backend/ai/inference/__init__.py \
      backend/ai/inference/routers/__init__.py \
      backend/ai/inference/services/__init__.py \
      backend/ai/inference/models/__init__.py \
      backend/ai/inference/tests/__init__.py
```

- [ ] **Step 2: Write `requirements.txt`**

```
fastapi==0.115.0
uvicorn[standard]==0.30.6
pydantic==2.9.2
supabase==2.9.1
httpx==0.27.2
joblib==1.4.2
xgboost==2.1.1
scikit-learn==1.5.2
numpy==1.26.4
pytest==8.3.3
pytest-asyncio==0.24.0
httpx==0.27.2
```

- [ ] **Step 3: Write `dependencies.py`**

```python
# backend/ai/inference/dependencies.py
import os
from fastapi import HTTPException, Security
from fastapi.security import APIKeyHeader

_api_key_header = APIKeyHeader(name="X-API-Key", auto_error=False)

def require_api_key(api_key: str | None = Security(_api_key_header)) -> str:
    expected = os.environ.get("INFERENCE_API_KEY", "")
    if not expected or api_key != expected:
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
    return api_key
```

- [ ] **Step 4: Write `main.py`**

```python
# backend/ai/inference/main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from inference.services.model_loader import ModelLoader
from inference.routers import health, predict, shadow

_loader: ModelLoader | None = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _loader
    _loader = ModelLoader()
    _loader.load_all()
    app.state.models = _loader
    yield
    _loader = None

app = FastAPI(title="E-CYAMUNARA Inference", lifespan=lifespan)
app.include_router(health.router)
app.include_router(predict.router)
app.include_router(shadow.router)
```

- [ ] **Step 5: Write `tests/conftest.py`**

```python
# backend/ai/inference/tests/conftest.py
import os
import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("INFERENCE_API_KEY", "test-key")
os.environ.setdefault("SUPABASE_URL", "http://localhost:54321")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-key")

# Import app AFTER env vars are set
from inference.main import app

@pytest.fixture
def client():
    with TestClient(app) as c:
        yield c

@pytest.fixture
def auth_headers():
    return {"X-API-Key": "test-key"}
```

- [ ] **Step 6: Verify scaffold imports**

```bash
cd backend/ai
pip install -r inference/requirements.txt
python -c "from inference.main import app; print('OK')"
```
Expected: `OK`

- [ ] **Step 7: Commit**

```bash
git add backend/ai/inference/
git commit -m "feat(inference): FastAPI project scaffold — dependencies, app, auth"
```

---

### Task 3: Model Loader Service

**Files:**
- Create: `backend/ai/inference/services/model_loader.py`
- Create: `backend/ai/inference/tests/test_model_loader.py`

- [ ] **Step 1: Write failing test**

```python
# backend/ai/inference/tests/test_model_loader.py
import os, pathlib, pytest
from unittest.mock import patch, MagicMock

MODEL_ROOT = pathlib.Path(__file__).parents[3] / "trained_models"

class TestModelLoader:
    def test_load_all_finds_three_models(self, tmp_path, monkeypatch):
        # Build a minimal fake model directory
        for name, ver in [("model_a", "v1.0.4-synthetic"),
                          ("model_b", "v1.0.0-synthetic"),
                          ("model_c", "v1.0.0-synthetic")]:
            d = tmp_path / name / ver
            d.mkdir(parents=True)
            import joblib, sklearn.pipeline
            joblib.dump(MagicMock(), d / f"{name}_{ver}_pipeline.pkl")

        monkeypatch.setenv("MODEL_ROOT", str(tmp_path))
        monkeypatch.setenv("MODEL_A_VERSION", "v1.0.4-synthetic")
        monkeypatch.setenv("MODEL_B_VERSION", "v1.0.0-synthetic")
        monkeypatch.setenv("MODEL_C_VERSION", "v1.0.0-synthetic")

        from inference.services.model_loader import ModelLoader
        loader = ModelLoader()
        loader.load_all()

        assert loader.model_a is not None
        assert loader.model_b is not None
        assert loader.model_c is not None

    def test_load_all_raises_on_missing_file(self, tmp_path, monkeypatch):
        monkeypatch.setenv("MODEL_ROOT", str(tmp_path))
        monkeypatch.setenv("MODEL_A_VERSION", "v999-missing")
        monkeypatch.setenv("MODEL_B_VERSION", "v999-missing")
        monkeypatch.setenv("MODEL_C_VERSION", "v999-missing")

        from inference.services.model_loader import ModelLoader
        loader = ModelLoader()
        with pytest.raises(FileNotFoundError):
            loader.load_all()
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
cd backend/ai
python -m pytest inference/tests/test_model_loader.py -v
```
Expected: `ImportError` or `ModuleNotFoundError` (service doesn't exist yet).

- [ ] **Step 3: Write `model_loader.py`**

```python
# backend/ai/inference/services/model_loader.py
import os
import pathlib
import joblib

_ROOT_DEFAULT = pathlib.Path(__file__).parents[3] / "trained_models"

class ModelLoader:
    def __init__(self):
        root = os.environ.get("MODEL_ROOT")
        self._root = pathlib.Path(root) if root else _ROOT_DEFAULT
        self.model_a = None
        self.model_b = None
        self.model_c = None
        self.versions: dict[str, str] = {}

    def load_all(self) -> None:
        self.model_a, self.versions["model_a"] = self._load("model_a", "MODEL_A_VERSION", "v1.0.4-synthetic")
        self.model_b, self.versions["model_b"] = self._load("model_b", "MODEL_B_VERSION", "v1.0.0-synthetic")
        self.model_c, self.versions["model_c"] = self._load("model_c", "MODEL_C_VERSION", "v1.0.0-synthetic")

    def _load(self, name: str, env_key: str, default: str):
        version = os.environ.get(env_key, default)
        path = self._root / name / version / f"{name}_{version}_pipeline.pkl"
        if not path.exists():
            raise FileNotFoundError(f"Model not found: {path}")
        return joblib.load(path), version
```

- [ ] **Step 4: Run test — expect PASS**

```bash
python -m pytest inference/tests/test_model_loader.py -v
```
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/ai/inference/services/model_loader.py backend/ai/inference/tests/test_model_loader.py
git commit -m "feat(inference): model loader service — loads all 3 XGBoost pipelines"
```

---

### Task 4: Pydantic Models (Request / Response)

**Files:**
- Create: `backend/ai/inference/models/request.py`
- Create: `backend/ai/inference/models/response.py`
- Create: `backend/ai/inference/tests/test_models.py`

- [ ] **Step 1: Write failing test**

```python
# backend/ai/inference/tests/test_models.py
from inference.models.response import PredictionResponse, ValueSignal

def test_prediction_response_value_signal_enum():
    assert ValueSignal.UNDERVALUED == "undervalued"
    assert ValueSignal.FAIRLY_PRICED == "fairly_priced"
    assert ValueSignal.OVERPRICED == "overpriced"

def test_prediction_response_serialises():
    resp = PredictionResponse(
        auction_id="abc-123",
        status="generated",
        model_a={"expected_auction_price": 5_000_000, "value_signal": "fairly_priced",
                 "value_ratio": 0.95, "confidence_score": 0.82},
        model_b={"predicted_winning_bid": 5_200_000},
        model_c={"predicted_probability": 0.87},
        model_versions={"model_a": "v1.0.4-synthetic"},
        duration_ms=312,
    )
    data = resp.model_dump()
    assert data["auction_id"] == "abc-123"
    assert data["model_a"]["value_signal"] == "fairly_priced"
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
python -m pytest inference/tests/test_models.py -v
```

- [ ] **Step 3: Write `models/request.py`**

```python
# backend/ai/inference/models/request.py
from pydantic import BaseModel

class BatchPredictRequest(BaseModel):
    auction_ids: list[str]

    model_config = {"json_schema_extra": {"example": {"auction_ids": ["uuid1", "uuid2"]}}}
```

- [ ] **Step 4: Write `models/response.py`**

```python
# backend/ai/inference/models/response.py
from enum import Enum
from pydantic import BaseModel

class ValueSignal(str, Enum):
    UNDERVALUED  = "undervalued"
    FAIRLY_PRICED = "fairly_priced"
    OVERPRICED   = "overpriced"

class SkipResponse(BaseModel):
    auction_id: str
    status: str       # "skipped"
    reason: str       # skip_reason value

class PredictionResponse(BaseModel):
    auction_id:     str
    status:         str           # "generated"
    model_a:        dict          # expected_auction_price, value_signal, value_ratio, confidence_score
    model_b:        dict          # predicted_winning_bid
    model_c:        dict          # predicted_probability
    model_versions: dict[str, str]
    duration_ms:    int

class BatchPredictionResponse(BaseModel):
    generated: int
    skipped:   int
    errored:   int
    results:   list[PredictionResponse | SkipResponse]

class HealthResponse(BaseModel):
    status:         str           # "ok"
    model_versions: dict[str, str]
    db_connected:   bool
```

- [ ] **Step 5: Run test — expect PASS**

```bash
python -m pytest inference/tests/test_models.py -v
```
Expected: 2 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add backend/ai/inference/models/ backend/ai/inference/tests/test_models.py
git commit -m "feat(inference): Pydantic request/response models"
```

---

### Task 5: Prediction Service (Inference Logic)

**Files:**
- Create: `backend/ai/inference/services/prediction_service.py`
- Create: `backend/ai/inference/tests/test_prediction_service.py`

- [ ] **Step 1: Write failing tests**

```python
# backend/ai/inference/tests/test_prediction_service.py
import pytest
from inference.services.prediction_service import compute_value_signal, compute_confidence

class TestValueSignal:
    def test_undervalued(self):
        # starting_price / expected < 0.75
        assert compute_value_signal(starting_price=1_000_000, expected_price=2_000_000) == "undervalued"

    def test_fairly_priced_low_end(self):
        assert compute_value_signal(starting_price=750_000, expected_price=1_000_000) == "fairly_priced"

    def test_fairly_priced_high_end(self):
        assert compute_value_signal(starting_price=1_250_000, expected_price=1_000_000) == "fairly_priced"

    def test_overpriced(self):
        # starting_price / expected > 1.25
        assert compute_value_signal(starting_price=2_000_000, expected_price=1_000_000) == "overpriced"

    def test_zero_expected_returns_overpriced(self):
        # Guard against divide-by-zero
        assert compute_value_signal(starting_price=1_000_000, expected_price=0) == "overpriced"

class TestConfidence:
    def test_full_completeness_and_engagement(self):
        score = compute_confidence(completeness=1.0, engagement_boost=0.5)
        assert 0.0 <= score <= 1.0

    def test_low_completeness_is_penalised(self):
        low  = compute_confidence(completeness=0.3, engagement_boost=0.0)
        high = compute_confidence(completeness=1.0, engagement_boost=0.0)
        assert low < high

    def test_score_clipped_to_unit_interval(self):
        score = compute_confidence(completeness=2.0, engagement_boost=2.0)
        assert 0.0 <= score <= 1.0
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
python -m pytest inference/tests/test_prediction_service.py -v
```

- [ ] **Step 3: Write `prediction_service.py`**

```python
# backend/ai/inference/services/prediction_service.py
from __future__ import annotations
import time
import numpy as np
from training.config import CONFIG

_INF = CONFIG.inference

def compute_value_signal(starting_price: float, expected_price: float) -> str:
    if expected_price <= 0:
        return "overpriced"
    ratio = starting_price / expected_price
    if ratio < 0.75:
        return "undervalued"
    if ratio > 1.25:
        return "overpriced"
    return "fairly_priced"

def compute_confidence(completeness: float, engagement_boost: float) -> float:
    base = max(0.0, completeness) * _INF.confidence_min_completeness_factor
    boosted = base + engagement_boost * _INF.confidence_engagement_boost
    return float(np.clip(boosted, 0.0, 1.0))

def run_inference(
    models,               # app.state.models (ModelLoader)
    feature_row: dict,
) -> dict:
    """
    Runs all three models on a single feature row dict.
    Returns a dict with model_a, model_b, model_c sub-dicts.
    feature_row must match the v_auction_ml_features column names.
    """
    t0 = time.perf_counter()

    from training.preprocessing.pipeline_builder import build_feature_matrix
    X = build_feature_matrix([feature_row])  # shape (1, n_features)

    # Model A — expected auction price
    expected_price = float(models.model_a.predict(X)[0])
    starting_price = float(feature_row.get("starting_price", 0))
    value_ratio    = starting_price / expected_price if expected_price > 0 else 999.0
    value_signal   = compute_value_signal(starting_price, expected_price)
    completeness   = float(feature_row.get("metadata_completeness_score", 0))
    engagement     = min(1.0, float(feature_row.get("bids_per_view_ratio", 0)))
    confidence     = compute_confidence(completeness, engagement)

    # Model B — predicted winning bid
    predicted_winning_bid = float(models.model_b.predict(X)[0])

    # Model C — bid probability
    predicted_probability = float(models.model_c.predict_proba(X)[0, 1])

    duration_ms = int((time.perf_counter() - t0) * 1000)

    return {
        "model_a": {
            "expected_auction_price": round(expected_price, 2),
            "value_signal":           value_signal,
            "value_ratio":            round(value_ratio, 4),
            "confidence_score":       round(confidence, 4),
        },
        "model_b": {
            "predicted_winning_bid": round(predicted_winning_bid, 2),
        },
        "model_c": {
            "predicted_probability": round(predicted_probability, 4),
        },
        "duration_ms": duration_ms,
    }
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
python -m pytest inference/tests/test_prediction_service.py -v
```
Expected: 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/ai/inference/services/prediction_service.py \
        backend/ai/inference/tests/test_prediction_service.py
git commit -m "feat(inference): prediction service — value_signal, confidence, run_inference"
```

---

### Task 6: Supabase Writer Service

**Files:**
- Create: `backend/ai/inference/services/supabase_writer.py`
- Create: `backend/ai/inference/tests/test_supabase_writer.py`

- [ ] **Step 1: Write failing test**

```python
# backend/ai/inference/tests/test_supabase_writer.py
import pytest
from unittest.mock import MagicMock, patch

class TestSupabaseWriter:
    def _make_writer(self):
        from inference.services.supabase_writer import SupabaseWriter
        mock_client = MagicMock()
        # Chain: .from_().insert().execute()
        mock_client.from_.return_value.insert.return_value.execute.return_value = \
            MagicMock(data=[{"id": "new-id"}], error=None)
        return SupabaseWriter(mock_client), mock_client

    def test_write_predictions_calls_insert_three_times(self):
        writer, mock_client = self._make_writer()
        writer.write_predictions(
            auction_id="auction-uuid",
            starting_price_at_prediction=1_000_000,
            inference_result={
                "model_a": {"expected_auction_price": 2_000_000, "value_signal": "undervalued",
                            "value_ratio": 0.5, "confidence_score": 0.8},
                "model_b": {"predicted_winning_bid": 2_100_000},
                "model_c": {"predicted_probability": 0.9},
                "duration_ms": 200,
            },
            model_versions={"model_a": "v1.0.4-synthetic", "model_b": "v1.0.0-synthetic",
                            "model_c": "v1.0.0-synthetic"},
        )
        # 3 inserts: one per model
        assert mock_client.from_.call_count == 3

    def test_write_log_calls_insert_once(self):
        writer, mock_client = self._make_writer()
        writer.write_log(
            auction_id="auction-uuid",
            event_type="prediction_generated",
            models_run=["model_a", "model_b", "model_c"],
            model_versions={"model_a": "v1.0.4-synthetic"},
            duration_ms=200,
            feature_completeness_score=0.9,
        )
        mock_client.from_.assert_called_once()
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
python -m pytest inference/tests/test_supabase_writer.py -v
```

- [ ] **Step 3: Write `supabase_writer.py`**

```python
# backend/ai/inference/services/supabase_writer.py
from __future__ import annotations
import os
from datetime import datetime, timezone
from supabase import create_client, Client

def _get_client() -> Client:
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"],
    )

class SupabaseWriter:
    def __init__(self, client: Client | None = None):
        self._client = client or _get_client()

    def write_predictions(
        self,
        auction_id: str,
        starting_price_at_prediction: float,
        inference_result: dict,
        model_versions: dict[str, str],
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        a = inference_result["model_a"]
        b = inference_result["model_b"]
        c = inference_result["model_c"]

        rows = [
            {
                "auction_id":                  auction_id,
                "model_version":               model_versions.get("model_a", ""),
                "prediction_type":             "auction_price_estimate",
                "expected_auction_price":      a["expected_auction_price"],
                "value_signal":                a["value_signal"],
                "value_ratio":                 a["value_ratio"],
                "starting_price_at_prediction": starting_price_at_prediction,
                "confidence_score":            a["confidence_score"],
                "created_at":                  now,
            },
            {
                "auction_id":       auction_id,
                "model_version":    model_versions.get("model_b", ""),
                "prediction_type":  "winning_bid",
                "predicted_winning_bid": b["predicted_winning_bid"],
                "created_at":       now,
            },
            {
                "auction_id":         auction_id,
                "model_version":      model_versions.get("model_c", ""),
                "prediction_type":    "bid_probability",
                "predicted_probability": c["predicted_probability"],
                "created_at":         now,
            },
        ]
        for row in rows:
            self._client.from_("ai_predictions").insert(row).execute()

    def write_log(
        self,
        auction_id: str,
        event_type: str,
        models_run: list[str] | None = None,
        model_versions: dict | None = None,
        duration_ms: int | None = None,
        error_code: str | None = None,
        error_message: str | None = None,
        skip_reason: str | None = None,
        feature_completeness_score: float | None = None,
        metadata: dict | None = None,
    ) -> None:
        self._client.from_("ai_prediction_logs").insert({
            "auction_id":                  auction_id,
            "event_type":                  event_type,
            "models_run":                  models_run,
            "model_versions":              model_versions,
            "duration_ms":                 duration_ms,
            "error_code":                  error_code,
            "error_message":               error_message,
            "skip_reason":                 skip_reason,
            "feature_completeness_score":  feature_completeness_score,
            "metadata":                    metadata,
        }).execute()
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
python -m pytest inference/tests/test_supabase_writer.py -v
```
Expected: 2 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/ai/inference/services/supabase_writer.py \
        backend/ai/inference/tests/test_supabase_writer.py
git commit -m "feat(inference): Supabase writer service — ai_predictions + ai_prediction_logs"
```

---

### Task 7: Feature Client (Query v_auction_ml_features)

**Files:**
- Create: `backend/ai/inference/services/feature_client.py`
- Create: `backend/ai/inference/tests/test_feature_client.py`

- [ ] **Step 1: Write failing test**

```python
# backend/ai/inference/tests/test_feature_client.py
from unittest.mock import MagicMock, patch
import pytest

MOCK_ROW = {
    "auction_id": "test-uuid", "region": "Central", "main_category": "vehicle",
    "starting_price": 5_000_000, "metadata_completeness_score": 0.9,
    "bids_per_view_ratio": 0.05, "asset_age": 5,
}

class TestFeatureClient:
    def _make_client(self, row_data):
        from inference.services.feature_client import FeatureClient
        mock_sb = MagicMock()
        mock_sb.from_.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = \
            MagicMock(data=row_data, error=None)
        return FeatureClient(mock_sb), mock_sb

    def test_get_features_returns_dict(self):
        client, _ = self._make_client(MOCK_ROW)
        result = client.get_features("test-uuid")
        assert result is not None
        assert result["region"] == "Central"
        assert result["starting_price"] == 5_000_000

    def test_get_features_returns_none_when_not_found(self):
        client, mock_sb = self._make_client(None)
        mock_sb.from_.return_value.select.return_value.eq.return_value.single.return_value.execute.return_value = \
            MagicMock(data=None, error={"code": "PGRST116"})
        result = client.get_features("nonexistent")
        assert result is None

    def test_get_features_low_completeness_detected(self):
        low_row = {**MOCK_ROW, "metadata_completeness_score": 0.3}
        client, _ = self._make_client(low_row)
        result = client.get_features("test-uuid")
        assert result["metadata_completeness_score"] == 0.3
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
python -m pytest inference/tests/test_feature_client.py -v
```

- [ ] **Step 3: Write `feature_client.py`**

```python
# backend/ai/inference/services/feature_client.py
from __future__ import annotations
import os
from supabase import create_client, Client

def _get_client() -> Client:
    return create_client(
        os.environ["SUPABASE_URL"],
        os.environ["SUPABASE_SERVICE_ROLE_KEY"],
    )

class FeatureClient:
    def __init__(self, client: Client | None = None):
        self._client = client or _get_client()

    def get_features(self, auction_id: str) -> dict | None:
        try:
            resp = (
                self._client
                .from_("v_auction_ml_features")
                .select("*")
                .eq("auction_id", auction_id)
                .single()
                .execute()
            )
            if resp.error or not resp.data:
                return None
            return dict(resp.data)
        except Exception:
            return None
```

- [ ] **Step 4: Run tests — expect PASS**

```bash
python -m pytest inference/tests/test_feature_client.py -v
```
Expected: 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add backend/ai/inference/services/feature_client.py \
        backend/ai/inference/tests/test_feature_client.py
git commit -m "feat(inference): feature client — queries v_auction_ml_features"
```

---

### Task 8: Health + Predict + Shadow Routers

**Files:**
- Create: `backend/ai/inference/routers/health.py`
- Create: `backend/ai/inference/routers/predict.py`
- Create: `backend/ai/inference/routers/shadow.py`
- Create: `backend/ai/inference/tests/test_routers.py`

- [ ] **Step 1: Write failing tests**

```python
# backend/ai/inference/tests/test_routers.py
from unittest.mock import MagicMock, patch
import pytest

AUTH = {"X-API-Key": "test-key"}

class TestHealthRouter:
    def test_health_returns_ok(self, client):
        resp = client.get("/health")
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

class TestPredictRouter:
    def test_predict_requires_api_key(self, client):
        resp = client.post("/predict/auction/some-id")
        assert resp.status_code == 401

    def test_predict_returns_skip_when_shadow_disabled(self, client):
        with patch("inference.routers.predict.shadow_mode_enabled", return_value=False):
            resp = client.post("/predict/auction/some-id", headers=AUTH)
        assert resp.status_code == 200
        assert resp.json()["status"] == "skipped"
        assert resp.json()["reason"] == "shadow_mode_disabled"

    def test_predict_returns_skip_when_already_predicted(self, client):
        with patch("inference.routers.predict.shadow_mode_enabled", return_value=True), \
             patch("inference.routers.predict.already_predicted", return_value=True):
            resp = client.post("/predict/auction/some-id", headers=AUTH)
        assert resp.json()["reason"] == "already_predicted"

    def test_predict_returns_skip_on_low_completeness(self, client):
        low_features = {"metadata_completeness_score": 0.2, "starting_price": 1_000_000}
        with patch("inference.routers.predict.shadow_mode_enabled", return_value=True), \
             patch("inference.routers.predict.already_predicted", return_value=False), \
             patch("inference.routers.predict._feature_client") as mock_fc:
            mock_fc.get_features.return_value = low_features
            resp = client.post("/predict/auction/some-id", headers=AUTH)
        assert resp.json()["reason"] == "feature_completeness_low"
```

- [ ] **Step 2: Run tests — expect FAIL**

```bash
python -m pytest inference/tests/test_routers.py -v
```

- [ ] **Step 3: Write `routers/health.py`**

```python
# backend/ai/inference/routers/health.py
from fastapi import APIRouter, Request
from inference.models.response import HealthResponse

router = APIRouter()

@router.get("/health", response_model=HealthResponse)
async def health(request: Request):
    loader = getattr(request.app.state, "models", None)
    versions = loader.versions if loader else {}
    return HealthResponse(status="ok", model_versions=versions, db_connected=True)
```

- [ ] **Step 4: Write `routers/predict.py`**

```python
# backend/ai/inference/routers/predict.py
from __future__ import annotations
import os
from fastapi import APIRouter, Depends, Request
from inference.dependencies import require_api_key
from inference.models.response import PredictionResponse, SkipResponse, BatchPredictionResponse
from inference.models.request import BatchPredictRequest
from inference.services.feature_client import FeatureClient
from inference.services.prediction_service import run_inference
from inference.services.supabase_writer import SupabaseWriter

router = APIRouter()

_min_completeness = float(os.environ.get("MIN_FEATURE_COMPLETENESS", "0.5"))

# Module-level clients (replaced in tests via patch)
_feature_client = FeatureClient()
_writer = SupabaseWriter()

def shadow_mode_enabled() -> bool:
    from supabase import create_client
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    resp = client.from_("app_settings").select("value").eq("key", "ai.shadow_mode_enabled").single().execute()
    return resp.data and resp.data.get("value") == "true"

def already_predicted(auction_id: str) -> bool:
    from supabase import create_client
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    resp = client.from_("ai_predictions").select("id").eq("auction_id", auction_id).limit(1).execute()
    return bool(resp.data)

@router.post("/predict/auction/{auction_id}")
async def predict_auction(
    auction_id: str,
    request: Request,
    _: str = Depends(require_api_key),
):
    if not shadow_mode_enabled():
        _writer.write_log(auction_id, "prediction_skipped", skip_reason="shadow_mode_disabled")
        return SkipResponse(auction_id=auction_id, status="skipped", reason="shadow_mode_disabled")

    if already_predicted(auction_id):
        return SkipResponse(auction_id=auction_id, status="skipped", reason="already_predicted")

    features = _feature_client.get_features(auction_id)
    if features is None:
        _writer.write_log(auction_id, "prediction_error", error_code="feature_fetch_failed")
        return SkipResponse(auction_id=auction_id, status="skipped", reason="auction_not_active")

    completeness = float(features.get("metadata_completeness_score", 0))
    if completeness < _min_completeness:
        _writer.write_log(auction_id, "prediction_skipped",
                          skip_reason="feature_completeness_low",
                          feature_completeness_score=completeness)
        return SkipResponse(auction_id=auction_id, status="skipped", reason="feature_completeness_low")

    loader = request.app.state.models
    result = run_inference(loader, features)

    _writer.write_predictions(
        auction_id=auction_id,
        starting_price_at_prediction=float(features.get("starting_price", 0)),
        inference_result=result,
        model_versions=loader.versions,
    )
    _writer.write_log(
        auction_id=auction_id,
        event_type="prediction_generated",
        models_run=["model_a", "model_b", "model_c"],
        model_versions=loader.versions,
        duration_ms=result["duration_ms"],
        feature_completeness_score=completeness,
    )

    return PredictionResponse(
        auction_id=auction_id,
        status="generated",
        model_a=result["model_a"],
        model_b=result["model_b"],
        model_c=result["model_c"],
        model_versions=loader.versions,
        duration_ms=result["duration_ms"],
    )

@router.post("/predict/batch", response_model=BatchPredictionResponse)
async def predict_batch(
    body: BatchPredictRequest,
    request: Request,
    _: str = Depends(require_api_key),
):
    results, generated, skipped, errored = [], 0, 0, 0
    for auction_id in body.auction_ids[:100]:  # cap at 100
        try:
            resp = await predict_auction(auction_id, request, _)
            results.append(resp)
            if isinstance(resp, PredictionResponse):
                generated += 1
            else:
                skipped += 1
        except Exception:
            errored += 1
    return BatchPredictionResponse(generated=generated, skipped=skipped,
                                   errored=errored, results=results)
```

- [ ] **Step 5: Write `routers/shadow.py`**

```python
# backend/ai/inference/routers/shadow.py
import os
from fastapi import APIRouter, Depends
from inference.dependencies import require_api_key

router = APIRouter()

@router.get("/shadow/metrics")
async def shadow_metrics(days: int = 30, _: str = Depends(require_api_key)):
    from supabase import create_client
    client = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_SERVICE_ROLE_KEY"])
    resp = (
        client.from_("ai_shadow_metrics")
        .select("*")
        .order("metric_date", desc=True)
        .limit(days)
        .execute()
    )
    return {"days": days, "metrics": resp.data or []}
```

- [ ] **Step 6: Run tests — expect PASS**

```bash
python -m pytest inference/tests/test_routers.py -v
```
Expected: 5 tests PASS.

- [ ] **Step 7: Run full test suite**

```bash
python -m pytest inference/tests/ -v
```
Expected: all tests PASS (no regressions).

- [ ] **Step 8: Commit**

```bash
git add backend/ai/inference/routers/ backend/ai/inference/tests/test_routers.py
git commit -m "feat(inference): health, predict, shadow routers — complete FastAPI inference server"
```

---

### Task 9: Dockerfile

**Files:**
- Create: `backend/ai/inference/Dockerfile`

- [ ] **Step 1: Write Dockerfile**

```dockerfile
# backend/ai/inference/Dockerfile
FROM python:3.11-slim

WORKDIR /app

# Copy training package (needed by prediction_service.py for pipeline_builder + config)
COPY backend/ai/training/ /app/training/
COPY backend/ai/trained_models/ /app/trained_models/
COPY backend/ai/inference/requirements.txt /app/requirements.txt

RUN pip install --no-cache-dir -r requirements.txt

COPY backend/ai/inference/ /app/inference/

ENV PYTHONPATH=/app
ENV MODEL_ROOT=/app/trained_models

EXPOSE 8000

CMD ["uvicorn", "inference.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 2: Test Docker build (optional — requires Docker)**

```bash
docker build -f backend/ai/inference/Dockerfile -t ecyamunara-inference .
docker run --rm -e INFERENCE_API_KEY=test -e SUPABASE_URL=http://localhost -e SUPABASE_SERVICE_ROLE_KEY=x \
  ecyamunara-inference
```
Expected: uvicorn starts on port 8000.

- [ ] **Step 3: Commit**

```bash
git add backend/ai/inference/Dockerfile
git commit -m "feat(inference): Dockerfile for containerized FastAPI deployment"
```

---

### Task 10: Edge Function — generate-ai-predictions

**Files:**
- Create: `supabase/functions/generate-ai-predictions/index.ts`

- [ ] **Step 1: Write Edge Function**

```typescript
// supabase/functions/generate-ai-predictions/index.ts
//
// Triggered by Database Webhook: auctions INSERT + UPDATE (auction_status = 'active')
// Calls FastAPI inference server to generate predictions for the activated auction.
// Shadow mode: predictions stored in ai_predictions, NOT visible to clients.
//
// Setup:
//   Dashboard → Database → Webhooks → Create webhook
//   Table: auctions | Events: INSERT, UPDATE | URL: .../generate-ai-predictions
//   HTTP Headers: Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
//
//   Add secret: supabase secrets set INFERENCE_API_KEY=<key> INFERENCE_API_URL=<url>

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  try {
    const payload = await req.json();
    const auction = payload.record ?? payload;

    if (!auction?.id || auction.auction_status !== 'active') {
      return new Response(JSON.stringify({ status: 'skipped', reason: 'auction_not_active' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Check master shadow mode flag
    const { data: flagRow } = await supabase
      .from('app_settings')
      .select('value')
      .eq('key', 'ai.shadow_mode_enabled')
      .single();
    if (flagRow?.value !== 'true') {
      return new Response(JSON.stringify({ status: 'skipped', reason: 'shadow_mode_disabled' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    // Idempotency: skip if predictions already exist for this auction
    const { data: existing } = await supabase
      .from('ai_predictions')
      .select('id')
      .eq('auction_id', auction.id)
      .limit(1);
    if (existing && existing.length > 0) {
      return new Response(JSON.stringify({ status: 'skipped', reason: 'already_predicted' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    // Call FastAPI inference server
    const inferenceUrl = Deno.env.get('INFERENCE_API_URL')!;
    const apiKey      = Deno.env.get('INFERENCE_API_KEY')!;

    const resp = await fetch(`${inferenceUrl}/predict/auction/${auction.id}`, {
      method:  'POST',
      headers: { 'X-API-Key': apiKey, 'Content-Type': 'application/json' },
      signal:  AbortSignal.timeout(10_000),
    });

    const body = await resp.json();
    return new Response(JSON.stringify({ status: resp.ok ? 'ok' : 'error', inference: body }),
      { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (e) {
    console.error('generate-ai-predictions error:', e);
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
```

- [ ] **Step 2: Deploy Edge Function**

```bash
supabase functions deploy generate-ai-predictions
supabase secrets set INFERENCE_API_KEY=<your-key> INFERENCE_API_URL=<your-fastapi-url>
```

- [ ] **Step 3: Set up Database Webhook**

In Supabase Dashboard → Database → Webhooks:
- Name: `on-auction-activate`
- Table: `auctions`
- Events: INSERT, UPDATE
- URL: `https://<project-ref>.supabase.co/functions/v1/generate-ai-predictions`
- HTTP Method: POST
- HTTP Headers: `Authorization: Bearer <SERVICE_ROLE_KEY>`

- [ ] **Step 4: Test manually**

In Supabase SQL editor, simulate an activation:
```sql
UPDATE public.auctions
SET auction_status = 'active'
WHERE id = '<any-draft-auction-id>';
```
Then check:
```sql
SELECT event_type, duration_ms, error_code FROM public.ai_prediction_logs
WHERE auction_id = '<that-auction-id>' ORDER BY created_at DESC LIMIT 5;
```
Expected: one row with `event_type = 'prediction_generated'` (or `prediction_skipped` if features incomplete).

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/generate-ai-predictions/
git commit -m "feat(edge): generate-ai-predictions — webhook triggers FastAPI on auction activation"
```

---

### Task 11: Edge Function — compute-prediction-comparison

**Files:**
- Create: `supabase/functions/compute-prediction-comparison/index.ts`

- [ ] **Step 1: Write Edge Function**

```typescript
// supabase/functions/compute-prediction-comparison/index.ts
//
// Triggered by Database Webhook: auctions UPDATE where auction_status = 'closed'
// Also called from auto-close-auctions (belt-and-suspenders).
// Computes ground-truth error metrics and inserts into ai_prediction_comparisons.

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

function computeValueSignal(startingPrice: number, referencePrice: number): string {
  if (referencePrice <= 0) return 'overpriced';
  const ratio = startingPrice / referencePrice;
  if (ratio < 0.75)  return 'undervalued';
  if (ratio > 1.25)  return 'overpriced';
  return 'fairly_priced';
}

serve(async (req) => {
  try {
    const payload = await req.json();
    const auction = payload.record ?? payload;

    if (!auction?.id || auction.auction_status !== 'closed') {
      return new Response(JSON.stringify({ status: 'skipped' }),
        { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    );

    // Find Model A prediction for this auction
    const { data: prediction } = await supabase
      .from('ai_predictions')
      .select('id, model_version, expected_auction_price, value_signal, created_at')
      .eq('auction_id', auction.id)
      .eq('prediction_type', 'auction_price_estimate')
      .single();

    const winningAmount: number | null = auction.winning_amount ?? null;
    const hadBids = typeof winningAmount === 'number' && winningAmount > 0;

    let compRow: Record<string, unknown> = {
      auction_id:              auction.id,
      prediction_id:           prediction?.id ?? null,
      model_version:           prediction?.model_version ?? 'unknown',
      predicted_value:         prediction?.expected_auction_price ?? null,
      predicted_value_signal:  prediction?.value_signal ?? null,
      actual_value:            winningAmount,
      had_bids:                hadBids,
      prediction_created_at:   prediction?.created_at ?? null,
      auction_closed_at:       auction.closed_at ?? new Date().toISOString(),
    };

    if (hadBids && prediction?.expected_auction_price) {
      const predicted = Number(prediction.expected_auction_price);
      const actual    = Number(winningAmount);
      const absErr    = Math.abs(predicted - actual);
      const ape       = actual > 0 ? absErr / actual : null;
      const actualSig = computeValueSignal(Number(auction.starting_price ?? 0), actual);
      compRow = {
        ...compRow,
        absolute_error_rwf:        Math.round(absErr),
        absolute_percentage_error: ape,
        residual:                  Math.round(predicted - actual),
        actual_signal:             actualSig,
        signal_correct:            actualSig === prediction.value_signal,
      };
    }

    // INSERT ON CONFLICT DO NOTHING (UNIQUE on auction_id)
    await supabase.from('ai_prediction_comparisons').upsert(compRow, {
      onConflict: 'auction_id',
      ignoreDuplicates: true,
    });

    await supabase.from('ai_prediction_logs').insert({
      auction_id:    auction.id,
      event_type:    'comparison_computed',
      model_versions: prediction ? { model_a: prediction.model_version } : null,
      metadata:      { had_bids: hadBids, ape: compRow.absolute_percentage_error },
    });

    return new Response(JSON.stringify({ status: 'ok', had_bids: hadBids }),
      { status: 200, headers: { 'Content-Type': 'application/json' } });

  } catch (e) {
    console.error('compute-prediction-comparison error:', e);
    return new Response(JSON.stringify({ error: String(e) }),
      { status: 500, headers: { 'Content-Type': 'application/json' } });
  }
});
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy compute-prediction-comparison
```

- [ ] **Step 3: Set up webhook**

Dashboard → Database → Webhooks:
- Name: `on-auction-close-compare`
- Table: `auctions` | Events: UPDATE
- URL: `.../functions/v1/compute-prediction-comparison`
- Headers: `Authorization: Bearer <SERVICE_ROLE_KEY>`

- [ ] **Step 4: Commit**

```bash
git add supabase/functions/compute-prediction-comparison/
git commit -m "feat(edge): compute-prediction-comparison — ground-truth APE on auction close"
```

---

### Task 12: Edge Function — collect-ai-shadow-metrics

**Files:**
- Create: `supabase/functions/collect-ai-shadow-metrics/index.ts`

- [ ] **Step 1: Write Edge Function**

```typescript
// supabase/functions/collect-ai-shadow-metrics/index.ts
//
// Scheduled daily at 02:00 UTC by pg_cron.
// Aggregates yesterday's logs, coverage, and rolling MAPE.
// Checks retrain triggers and updates app_settings flags.
//
// pg_cron setup (run once in SQL editor):
//   SELECT cron.schedule('collect-shadow-metrics', '0 2 * * *',
//     $$SELECT net.http_post(
//       url := 'https://<ref>.supabase.co/functions/v1/collect-ai-shadow-metrics',
//       headers := '{"Authorization":"Bearer <SERVICE_ROLE_KEY>","Content-Type":"application/json"}'::jsonb,
//       body := '{}'::jsonb)$$);

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

serve(async (req) => {
  const expectedKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const incoming    = req.headers.get('Authorization') ?? '';
  if (!expectedKey || incoming !== `Bearer ${expectedKey}`) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const supabase  = createClient(Deno.env.get('SUPABASE_URL')!, expectedKey);
  const yesterday = new Date();
  yesterday.setUTCDate(yesterday.getUTCDate() - 1);
  const metricDate = yesterday.toISOString().split('T')[0];

  // ── 1. Aggregate yesterday's logs ────────────────────────────────────────
  const { data: logs } = await supabase
    .from('ai_prediction_logs')
    .select('event_type, duration_ms')
    .gte('created_at', `${metricDate}T00:00:00Z`)
    .lt('created_at',  `${metricDate}T23:59:59Z`);

  const generated = (logs ?? []).filter(l => l.event_type === 'prediction_generated').length;
  const skipped   = (logs ?? []).filter(l => l.event_type === 'prediction_skipped').length;
  const errored   = (logs ?? []).filter(l => l.event_type === 'prediction_error').length;
  const durations = (logs ?? [])
    .filter(l => l.event_type === 'prediction_generated' && l.duration_ms)
    .map(l => l.duration_ms as number)
    .sort((a, b) => a - b);
  const avgMs = durations.length ? Math.round(durations.reduce((s, v) => s + v, 0) / durations.length) : null;
  const p95Ms = durations.length ? durations[Math.floor(durations.length * 0.95)] : null;

  // ── 2. Coverage ───────────────────────────────────────────────────────────
  const { count: eligibleCount } = await supabase
    .from('auctions')
    .select('id', { count: 'exact', head: true })
    .in('auction_status', ['active', 'closed']);

  const { count: coveredCount } = await supabase
    .from('ai_predictions')
    .select('auction_id', { count: 'exact', head: true })
    .eq('prediction_type', 'auction_price_estimate');

  const eligible  = eligibleCount ?? 0;
  const covered   = coveredCount  ?? 0;
  const coverage  = eligible > 0 ? Math.round((covered / eligible) * 10000) / 10000 : null;

  // ── 3. Rolling MAPE (last 100 closed auctions with bids) ─────────────────
  const { data: comps } = await supabase
    .from('ai_prediction_comparisons')
    .select('absolute_percentage_error, absolute_error_rwf, signal_correct')
    .eq('had_bids', true)
    .not('absolute_percentage_error', 'is', null)
    .order('created_at', { ascending: false })
    .limit(100);

  const mapeValues = (comps ?? []).map(c => c.absolute_percentage_error as number);
  const maeValues  = (comps ?? []).map(c => c.absolute_error_rwf as number);
  const sigCorrect = (comps ?? []).filter(c => c.signal_correct === true).length;

  const rollingMape     = mapeValues.length ? mapeValues.reduce((s, v) => s + v, 0) / mapeValues.length : null;
  const rollingMae      = maeValues.length  ? maeValues.reduce((s, v) => s + v, 0) / maeValues.length   : null;
  const signalAccuracy  = comps?.length     ? sigCorrect / comps.length : null;
  const comparisonsComputed = comps?.length ?? 0;

  // ── 4. Check retrain triggers ─────────────────────────────────────────────
  const { data: flags } = await supabase
    .from('app_settings')
    .select('key, value')
    .in('key', ['ai.retrain_mape_trigger_threshold', 'ai.retrain_pending',
                 'ai.last_retrain_date', 'ai.retrain_min_new_closed_auctions']);

  const flagMap = Object.fromEntries((flags ?? []).map(f => [f.key, f.value]));
  const mapeThreshold    = parseFloat(flagMap['ai.retrain_mape_trigger_threshold'] ?? '0.25');
  const alreadyPending   = flagMap['ai.retrain_pending'] === 'true';
  const minNewAuctions   = parseInt(flagMap['ai.retrain_min_new_closed_auctions'] ?? '100');
  const lastRetrainDate  = flagMap['ai.last_retrain_date'] || '1970-01-01';

  let retrainTriggered = false;
  let retrainReason    = '';

  if (!alreadyPending) {
    // Check MAPE threshold
    if (rollingMape !== null && rollingMape > mapeThreshold) {
      retrainTriggered = true;
      retrainReason    = 'mape_degraded';
    }
    // Check data volume threshold
    if (!retrainTriggered) {
      const { count: newClosed } = await supabase
        .from('auctions')
        .select('id', { count: 'exact', head: true })
        .eq('auction_status', 'closed')
        .gte('closed_at', `${lastRetrainDate}T00:00:00Z`);
      if ((newClosed ?? 0) >= minNewAuctions) {
        retrainTriggered = true;
        retrainReason    = 'data_volume';
      }
    }

    if (retrainTriggered) {
      await supabase.from('app_settings').upsert([
        { key: 'ai.retrain_pending',        value: 'true',        updated_at: new Date().toISOString() },
        { key: 'ai.retrain_trigger_reason', value: retrainReason, updated_at: new Date().toISOString() },
      ]);
      await supabase.from('ai_prediction_logs').insert({
        event_type: 'retrain_trigger',
        metadata:   { reason: retrainReason, rolling_mape: rollingMape },
      });
    }
  }

  // ── 5. Write daily metrics row ────────────────────────────────────────────
  await supabase.from('ai_shadow_metrics').upsert({
    metric_date:             metricDate,
    predictions_generated:   generated,
    predictions_skipped:     skipped,
    predictions_error:       errored,
    eligible_auctions:       eligible,
    covered_auctions:        covered,
    coverage_rate:           coverage,
    avg_inference_ms:        avgMs,
    p95_inference_ms:        p95Ms,
    comparisons_computed:    comparisonsComputed,
    rolling_mape_model_a:    rollingMape,
    rolling_mae_rwf_model_a: rollingMae,
    signal_accuracy_rate:    signalAccuracy,
    retrain_triggered:       retrainTriggered,
    retrain_trigger_reason:  retrainReason || null,
  }, { onConflict: 'metric_date' });

  return new Response(JSON.stringify({
    status: 'ok', metric_date: metricDate,
    generated, skipped, errored, coverage, rolling_mape: rollingMape,
    retrain_triggered: retrainTriggered,
  }), { status: 200, headers: { 'Content-Type': 'application/json' } });
});
```

- [ ] **Step 2: Deploy**

```bash
supabase functions deploy collect-ai-shadow-metrics
```

- [ ] **Step 3: Set up pg_cron (run once in Supabase SQL editor)**

```sql
SELECT cron.schedule(
  'collect-shadow-metrics',
  '0 2 * * *',
  $$SELECT net.http_post(
    url     := 'https://<your-ref>.supabase.co/functions/v1/collect-ai-shadow-metrics',
    headers := ('{"Authorization":"Bearer ' || current_setting('app.service_role_key') || '","Content-Type":"application/json"}')::jsonb,
    body    := '{}'::jsonb
  )$$
);
```

- [ ] **Step 4: Test manually (run once)**

```bash
curl -X POST https://<ref>.supabase.co/functions/v1/collect-ai-shadow-metrics \
  -H "Authorization: Bearer <SERVICE_ROLE_KEY>"
```
Expected: `{"status":"ok","metric_date":"2026-06-10",...}`

Then verify:
```sql
SELECT metric_date, predictions_generated, coverage_rate, rolling_mape_model_a
FROM public.ai_shadow_metrics ORDER BY metric_date DESC LIMIT 5;
```

- [ ] **Step 5: Commit**

```bash
git add supabase/functions/collect-ai-shadow-metrics/
git commit -m "feat(edge): collect-ai-shadow-metrics — daily cron aggregates coverage, MAPE, retrain triggers"
```

---

### Task 13: Flutter — SupabaseConstants + Model

**Files:**
- Modify: `lib/core/constants/supabase_constants.dart`
- Create: `lib/data/models/ai_prediction_model.dart`
- Create: `test/data/models/ai_prediction_model_test.dart`

- [ ] **Step 1: Add constants to `supabase_constants.dart`**

Add after `auctionAutoCloseLogsTable`:
```dart
static const String aiPredictionsTable          = 'ai_predictions';
static const String aiPredictionLogsTable       = 'ai_prediction_logs';
static const String aiPredictionComparisonsTable = 'ai_prediction_comparisons';
static const String aiShadowMetricsTable        = 'ai_shadow_metrics';
static const String appSettingsTable2           = 'app_settings'; // alias — already: appSettingsTable
```

Add after existing Edge Function constants:
```dart
static const String fnGenerateAiPredictions     = 'generate-ai-predictions';
static const String fnComputePredictionComparison = 'compute-prediction-comparison';
static const String fnCollectAiShadowMetrics    = 'collect-ai-shadow-metrics';
```

Note: `appSettingsTable` already exists at line 27. Do NOT add a duplicate.

- [ ] **Step 2: Write failing model test**

```dart
// test/data/models/ai_prediction_model_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ecyamunara/data/models/ai_prediction_model.dart';

void main() {
  group('AIPredictionModel', () {
    const json = {
      'id': 'pred-uuid',
      'auction_id': 'auction-uuid',
      'model_version': 'v1.0.4-synthetic',
      'prediction_type': 'auction_price_estimate',
      'expected_auction_price': 5000000.0,
      'value_signal': 'fairly_priced',
      'value_ratio': 0.95,
      'starting_price_at_prediction': 4750000.0,
      'confidence_score': 0.82,
      'created_at': '2026-06-11T10:00:00.000Z',
    };

    test('fromJson parses all fields', () {
      final model = AIPredictionModel.fromJson(json);
      expect(model.id, 'pred-uuid');
      expect(model.auctionId, 'auction-uuid');
      expect(model.predictionType, 'auction_price_estimate');
      expect(model.expectedAuctionPrice, 5000000.0);
      expect(model.valueSignal, 'fairly_priced');
      expect(model.confidenceScore, 0.82);
    });

    test('fromJson handles null optional fields', () {
      final sparse = {'id': 'x', 'auction_id': 'y', 'model_version': 'v1',
                      'prediction_type': 'winning_bid', 'created_at': '2026-01-01T00:00:00Z'};
      final model = AIPredictionModel.fromJson(sparse);
      expect(model.expectedAuctionPrice, isNull);
      expect(model.valueSignal, isNull);
    });
  });
}
```

- [ ] **Step 3: Run test — expect FAIL**

```bash
flutter test test/data/models/ai_prediction_model_test.dart
```

- [ ] **Step 4: Write `AIPredictionModel`**

```dart
// lib/data/models/ai_prediction_model.dart
class AIPredictionModel {
  final String  id;
  final String  auctionId;
  final String  modelVersion;
  final String  predictionType;
  final double? expectedAuctionPrice;
  final String? valueSignal;
  final double? valueRatio;
  final double? startingPriceAtPrediction;
  final double? predictedWinningBid;
  final double? predictedProbability;
  final double? confidenceScore;
  final DateTime createdAt;

  const AIPredictionModel({
    required this.id,
    required this.auctionId,
    required this.modelVersion,
    required this.predictionType,
    required this.createdAt,
    this.expectedAuctionPrice,
    this.valueSignal,
    this.valueRatio,
    this.startingPriceAtPrediction,
    this.predictedWinningBid,
    this.predictedProbability,
    this.confidenceScore,
  });

  factory AIPredictionModel.fromJson(Map<String, dynamic> json) {
    return AIPredictionModel(
      id:                        json['id']           as String,
      auctionId:                 json['auction_id']   as String,
      modelVersion:              json['model_version'] as String,
      predictionType:            json['prediction_type'] as String,
      createdAt:                 DateTime.parse(json['created_at'] as String),
      expectedAuctionPrice:      (json['expected_auction_price'] as num?)?.toDouble(),
      valueSignal:               json['value_signal']   as String?,
      valueRatio:                (json['value_ratio']   as num?)?.toDouble(),
      startingPriceAtPrediction: (json['starting_price_at_prediction'] as num?)?.toDouble(),
      predictedWinningBid:       (json['predicted_winning_bid'] as num?)?.toDouble(),
      predictedProbability:      (json['predicted_probability'] as num?)?.toDouble(),
      confidenceScore:           (json['confidence_score'] as num?)?.toDouble(),
    );
  }
}
```

- [ ] **Step 5: Run test — expect PASS**

```bash
flutter test test/data/models/ai_prediction_model_test.dart
```
Expected: 2 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/core/constants/supabase_constants.dart \
        lib/data/models/ai_prediction_model.dart \
        test/data/models/ai_prediction_model_test.dart
git commit -m "feat(flutter): AIPredictionModel + new SupabaseConstants for AI tables/functions"
```

---

### Task 14: Flutter — AIPredictionRepository (hidden)

**Files:**
- Create: `lib/data/repositories/ai_prediction_repository.dart`
- Create: `test/data/repositories/ai_prediction_repository_test.dart`

- [ ] **Step 1: Write failing test**

```dart
// test/data/repositories/ai_prediction_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ecyamunara/data/repositories/ai_prediction_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockQueryBuilder extends Mock implements SupabaseQueryBuilder {}

void main() {
  group('AIPredictionRepository', () {
    late AIPredictionRepository repo;
    late MockSupabaseClient mockClient;

    setUp(() {
      mockClient = MockSupabaseClient();
      repo = AIPredictionRepository(mockClient);
    });

    test('getPredictionForAuction returns null when blocked by shadow mode', () async {
      // Shadow mode blocks reads → Supabase returns empty list
      when(() => mockClient.from(any())).thenReturn(MockQueryBuilder());
      // ... configure mock chain to return []
      final result = await repo.getPredictionForAuction('auction-uuid');
      expect(result, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test — expect FAIL**

```bash
flutter test test/data/repositories/ai_prediction_repository_test.dart
```

- [ ] **Step 3: Write `AIPredictionRepository`**

```dart
// lib/data/repositories/ai_prediction_repository.dart
//
// Shadow mode: reads return null while ai.predictions_visible_to_clients = 'false'.
// The RLS policy enforces this at the DB level — this repository does not
// need to check the flag in application code.
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/ai_prediction_model.dart';
import '../../core/constants/supabase_constants.dart';

class AIPredictionRepository {
  final SupabaseClient _client;
  const AIPredictionRepository(this._client);

  Future<AIPredictionModel?> getPredictionForAuction(String auctionId) async {
    final resp = await _client
        .from(SupabaseConstants.aiPredictionsTable)
        .select()
        .eq('auction_id', auctionId)
        .eq('prediction_type', 'auction_price_estimate')
        .maybeSingle();
    if (resp == null) return null;
    return AIPredictionModel.fromJson(resp);
  }

  Future<List<AIPredictionModel>> getPredictionsForAuction(String auctionId) async {
    final resp = await _client
        .from(SupabaseConstants.aiPredictionsTable)
        .select()
        .eq('auction_id', auctionId);
    return (resp as List).map((e) => AIPredictionModel.fromJson(e)).toList();
  }
}
```

- [ ] **Step 4: Run test + full test suite**

```bash
flutter test test/data/repositories/ai_prediction_repository_test.dart
flutter test
```
Expected: repository tests PASS, no regressions.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/ai_prediction_repository.dart \
        test/data/repositories/ai_prediction_repository_test.dart
git commit -m "feat(flutter): AIPredictionRepository — shadow mode, not wired to any UI"
```

---

### Task 15: Flutter — Provider (hidden)

**Files:**
- Modify: `lib/presentation/providers/providers.dart`

- [ ] **Step 1: Add provider (do NOT wire to any screen)**

Locate the existing provider exports in `providers.dart`. Add:

```dart
// AI Prediction repository — shadow mode only, no UI consumer yet
import '../../data/repositories/ai_prediction_repository.dart';
export '../../data/repositories/ai_prediction_repository.dart';

final aiPredictionRepositoryProvider = Provider<AIPredictionRepository>(
  (ref) => AIPredictionRepository(Supabase.instance.client),
);
```

- [ ] **Step 2: Verify flutter analyze passes**

```bash
flutter analyze
```
Expected: no new errors or warnings.

- [ ] **Step 3: Run full test suite**

```bash
flutter test
```
Expected: all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/presentation/providers/providers.dart
git commit -m "feat(flutter): aiPredictionRepositoryProvider — shadow mode, no UI binding"
```

---

### Task 16: Push All + Final Validation

- [ ] **Step 1: Push all commits**

```bash
git push
```

- [ ] **Step 2: Deploy remaining Edge Functions**

```bash
supabase functions deploy generate-ai-predictions
supabase functions deploy compute-prediction-comparison
supabase functions deploy collect-ai-shadow-metrics
```

- [ ] **Step 3: Run full SQL validation**

```sql
-- V1: All 13 flags present
SELECT COUNT(*) FROM public.app_settings WHERE key LIKE 'ai.%';
-- Expected: 13

-- V2: Shadow mode is ON, clients cannot see predictions
SELECT key, value FROM public.app_settings
WHERE key IN ('ai.shadow_mode_enabled','ai.predictions_visible_to_clients');
-- Expected: shadow_mode_enabled=true, predictions_visible_to_clients=false

-- V3: Policy qual contains feature flag subquery
SELECT policyname, LEFT(qual, 200) AS qual_snippet
FROM pg_policies
WHERE tablename = 'ai_predictions' AND policyname = 'client_read_auction_price_estimates';
-- Expected: qual contains 'predictions_visible_to_clients'

-- V4: All 4 new tables exist
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('app_settings','ai_prediction_logs','ai_prediction_comparisons','ai_shadow_metrics')
ORDER BY table_name;
-- Expected: 4 rows

-- V5: Dashboard view returns current state
SELECT shadow_mode_enabled, predictions_visible, model_a_version, retrain_pending
FROM public.v_ai_shadow_dashboard;
-- Expected: true, false, v1.0.4-synthetic, false

-- V6: New migration recorded
SELECT version, name FROM supabase_migrations.schema_migrations
WHERE version = '20260611000011';
-- Expected: 1 row
```

- [ ] **Step 4: Run Python inference tests**

```bash
cd backend/ai
python -m pytest inference/tests/ -v --tb=short
```
Expected: all tests PASS.

- [ ] **Step 5: Run Flutter tests**

```bash
flutter test
```
Expected: all tests PASS.

- [ ] **Step 6: End-to-end smoke test**

```sql
-- Manually insert a test prediction as service_role (simulates FastAPI output)
INSERT INTO public.ai_predictions
  (auction_id, model_version, prediction_type, expected_auction_price,
   value_signal, value_ratio, starting_price_at_prediction, confidence_score)
VALUES
  ((SELECT id FROM public.auctions WHERE auction_status = 'active' LIMIT 1),
   'v1.0.4-synthetic', 'auction_price_estimate', 5000000,
   'fairly_priced', 0.95, 4750000, 0.82);

-- Verify: super_admin can read it
SET ROLE authenticated;  -- simulate super_admin (adjust for your setup)
SELECT COUNT(*) FROM public.ai_predictions;
-- Expected: 1 row (as super_admin)

-- Verify: client CANNOT read it (shadow mode gate)
-- Expected: 0 rows when predictions_visible_to_clients = 'false'

-- Clean up test row
DELETE FROM public.ai_predictions WHERE model_version = 'v1.0.4-synthetic'
  AND confidence_score = 0.82;
```

- [ ] **Step 7: Final commit (if any cleanup)**

```bash
git add -A
git status  # verify nothing sensitive or unintended
git commit -m "chore: shadow mode rollout complete — all validation passing"
git push
```
