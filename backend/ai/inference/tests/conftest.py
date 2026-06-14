"""Shared fixtures for inference unit tests.

All tests here use mock model loaders so they run without real artifact files.
Tests that require real artifacts are marked @pytest.mark.integration and skipped
when backend/ai/trained_models/registry.json is absent.
"""

from __future__ import annotations

import pathlib
import sys
from unittest.mock import MagicMock

import numpy as np
import pytest
from fastapi.testclient import TestClient

# Make training.* importable
_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))

REGISTRY_PATH = _AI_ROOT / "trained_models" / "registry.json"
ARTIFACTS_AVAILABLE = REGISTRY_PATH.exists()

# ---------------------------------------------------------------------------
# Mock LoadedModel helpers
# ---------------------------------------------------------------------------

def _make_mock_regressor(log_output: float = 15.0):
    """Pipeline + XGBRegressor that returns np.expm1(log_output) as price."""
    pipeline = MagicMock()
    pipeline.transform.return_value = np.zeros((1, 30))
    xgb_model = MagicMock()
    xgb_model.predict.return_value = np.array([log_output])
    return pipeline, xgb_model


def _make_mock_classifier(prob: float = 0.73):
    """Pipeline + calibrated model that returns bid probability."""
    pipeline = MagicMock()
    pipeline.transform.return_value = np.zeros((1, 40))
    calibrated = MagicMock()
    calibrated.predict_proba.return_value = np.array([[1 - prob, prob]])
    return pipeline, calibrated


@pytest.fixture
def mock_loader_a():
    from inference.model_loader import LoadedModel

    pipeline, xgb_model = _make_mock_regressor(15.0)
    loaded = MagicMock(spec=LoadedModel)
    loaded.model_name = "model_a"
    loaded.version = "v1.0.0-test"
    loaded.confidence_score = 0.884
    loaded.pipeline = pipeline
    loaded.xgb_model = xgb_model
    loaded.calibrated = None

    loader = MagicMock()
    loader.get_active.return_value = loaded
    loader.get_shadow.return_value = None
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 42.0
    loader.get_registry.return_value = None
    return loader


@pytest.fixture
def mock_loader_b():
    from inference.model_loader import LoadedModel

    pipeline, xgb_model = _make_mock_regressor(15.5)
    loaded = MagicMock(spec=LoadedModel)
    loaded.model_name = "model_b"
    loaded.version = "v1.0.0-test"
    loaded.confidence_score = 0.885
    loaded.pipeline = pipeline
    loaded.xgb_model = xgb_model
    loaded.calibrated = None

    loader = MagicMock()
    loader.get_active.return_value = loaded
    loader.get_shadow.return_value = None
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 42.0
    loader.get_registry.return_value = None
    return loader


@pytest.fixture
def mock_loader_c():
    from inference.model_loader import LoadedModel

    pipeline, calibrated = _make_mock_classifier(0.73)
    loaded = MagicMock(spec=LoadedModel)
    loaded.model_name = "model_c"
    loaded.version = "v1.0.0-test"
    loaded.confidence_score = 0.977
    loaded.pipeline = pipeline
    loaded.xgb_model = MagicMock()
    loaded.calibrated = calibrated

    loader = MagicMock()
    loader.get_active.return_value = loaded
    loader.get_shadow.return_value = None
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 42.0
    loader.get_registry.return_value = None
    return loader


@pytest.fixture
def mock_store():
    store = MagicMock()
    store.store.return_value = "test-prediction-id-123"
    return store


# ---------------------------------------------------------------------------
# TestClient fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client_a(mock_loader_a, mock_store):
    from inference.main import create_app
    app = create_app(loader=mock_loader_a, store=mock_store)
    return TestClient(app)


@pytest.fixture
def client_b(mock_loader_b, mock_store):
    from inference.main import create_app
    app = create_app(loader=mock_loader_b, store=mock_store)
    return TestClient(app)


@pytest.fixture
def client_c(mock_loader_c, mock_store):
    from inference.main import create_app
    app = create_app(loader=mock_loader_c, store=mock_store)
    return TestClient(app)


# ---------------------------------------------------------------------------
# Sample feature payloads
# ---------------------------------------------------------------------------

FEATURES_A = {
    "main_category": "vehicle",
    "region": "Central",
    "starting_price": 5_000_000.0,
    "fuel_type": "petrol",
    "transmission": "automatic",
    "ownership_history": "first_owner",
    "accident_history": None,
    "insurance_status": None,
    "brand": "Toyota",
    "sub_category": "sedan",
    "condition": "Good",
    "manufacturing_year": 2018,
    "mileage": 80_000,
    "start_date": "2026-06-01T08:00:00Z",
    "end_date": "2026-06-04T08:00:00Z",
    "description": "Clean Toyota Corolla",
    "photo_urls": ["url1", "url2"],
}

FEATURES_BC = {
    **FEATURES_A,
    "total_bids": 5,
    "unique_bidder_count": 3,
    "views_count": 120,
    "time_of_first_bid": "2026-06-01T10:30:00Z",
}
