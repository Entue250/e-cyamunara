"""Tests for POST /predict/model-a."""

import math

import pytest

from .conftest import FEATURES_A


def test_predict_a_success(client_a):
    resp = client_a.post(
        "/predict/model-a",
        json={
            "auction_id": "aaaaaaaa-0000-0000-0000-000000000001",
            "store_prediction": True,
            "features": FEATURES_A,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"
    assert data["model_version"] == "v1.0.0-test"
    assert isinstance(data["expected_auction_price"], float)
    assert data["expected_auction_price"] > 0
    assert data["value_signal"] in ("undervalued", "fairly_priced", "overpriced")
    assert isinstance(data["value_ratio"], float)
    assert 0 < data["confidence_score"] <= 1
    assert isinstance(data["inference_ms"], int)


def test_predict_a_stores_prediction(client_a, mock_store):
    resp = client_a.post(
        "/predict/model-a",
        json={
            "auction_id": "aaaaaaaa-0000-0000-0000-000000000002",
            "store_prediction": True,
            "features": FEATURES_A,
        },
    )
    assert resp.status_code == 200
    assert mock_store.store.called
    row = mock_store.store.call_args[0][0]
    assert row["prediction_source"] == "real"
    assert row["model_stage"] == "shadow"
    assert row["prediction_type"] == "auction_price_estimate"
    assert row["model_version"] == "v1.0.0-test"
    assert "value_signal" in row
    assert "value_ratio" in row


def test_predict_a_no_store_when_store_false(client_a, mock_store):
    resp = client_a.post(
        "/predict/model-a",
        json={
            "auction_id": "aaaaaaaa-0000-0000-0000-000000000003",
            "store_prediction": False,
            "features": FEATURES_A,
        },
    )
    assert resp.status_code == 200
    assert not mock_store.store.called
    assert resp.json()["prediction_id"] is None


def test_predict_a_no_store_when_no_auction_id(client_a, mock_store):
    resp = client_a.post(
        "/predict/model-a",
        json={"store_prediction": True, "features": FEATURES_A},
    )
    assert resp.status_code == 200
    assert not mock_store.store.called
    assert resp.json()["prediction_id"] is None


def test_predict_a_missing_required_field(client_a):
    bad = {k: v for k, v in FEATURES_A.items() if k != "starting_price"}
    resp = client_a.post("/predict/model-a", json={"features": bad})
    assert resp.status_code == 422


def test_predict_a_value_signal_undervalued():
    """Verify value_ratio > 1.30 → undervalued signal."""
    import numpy as np
    from unittest.mock import MagicMock
    from inference.main import create_app
    from fastapi.testclient import TestClient

    pipeline = MagicMock()
    pipeline.transform.return_value = np.zeros((1, 30))
    xgb_model = MagicMock()
    # log1p(10_000_000) ~ 16.1; expm1(16.1) ~ 9.9M
    # starting_price=5M → ratio=9.9/5=1.98 → undervalued
    xgb_model.predict.return_value = np.array([math.log1p(10_000_000)])

    loaded = MagicMock()
    loaded.version = "v1.0.0-test"
    loaded.confidence_score = 0.88
    loaded.pipeline = pipeline
    loaded.xgb_model = xgb_model
    loaded.calibrated = None

    loader = MagicMock()
    loader.get_active.return_value = loaded
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 1.0
    loader.get_registry.return_value = None

    client = TestClient(create_app(loader=loader))
    resp = client.post(
        "/predict/model-a",
        json={"features": {**FEATURES_A, "starting_price": 5_000_000}},
    )
    assert resp.status_code == 200
    assert resp.json()["value_signal"] == "undervalued"


def test_predict_a_value_signal_overpriced():
    """Verify value_ratio < 1.10 → overpriced signal."""
    import numpy as np
    from unittest.mock import MagicMock
    from inference.main import create_app
    from fastapi.testclient import TestClient

    pipeline = MagicMock()
    pipeline.transform.return_value = np.zeros((1, 30))
    xgb_model = MagicMock()
    # returning expm1 = 4.9M; starting=5M → ratio=0.98 → overpriced
    xgb_model.predict.return_value = np.array([math.log1p(4_900_000)])

    loaded = MagicMock()
    loaded.version = "v1.0.0-test"
    loaded.confidence_score = 0.88
    loaded.pipeline = pipeline
    loaded.xgb_model = xgb_model
    loaded.calibrated = None

    loader = MagicMock()
    loader.get_active.return_value = loaded
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 1.0
    loader.get_registry.return_value = None

    client = TestClient(create_app(loader=loader))
    resp = client.post(
        "/predict/model-a",
        json={"features": {**FEATURES_A, "starting_price": 5_000_000}},
    )
    assert resp.status_code == 200
    assert resp.json()["value_signal"] == "overpriced"
