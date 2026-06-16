"""Tests for Phase 9E candidate model inference in predict_a/b/c routes.

Verifies that:
  1. When no candidate model is loaded (get_shadow returns None), the response
     contains no candidate_* fields.
  2. When a candidate model is loaded, the response includes candidate_*
     fields populated from the candidate model's prediction.
  3. When candidate inference raises an exception, the active prediction still
     succeeds and candidate fields are absent (silently swallowed).
"""

from __future__ import annotations

from unittest.mock import MagicMock

import numpy as np
import pytest
from fastapi.testclient import TestClient

from .conftest import FEATURES_A, FEATURES_BC, _make_mock_regressor, _make_mock_classifier


# ---------------------------------------------------------------------------
# Helpers — build loaders with active + candidate models
# ---------------------------------------------------------------------------

def _make_candidate_regressor_model(version: str = "v1.0.1-real", log_output: float = 15.5):
    """Build a LoadedModel mock for a candidate regressor (model_a or model_b)."""
    from inference.model_loader import LoadedModel

    pipeline, xgb_model = _make_mock_regressor(log_output)
    cand = MagicMock(spec=LoadedModel)
    cand.model_name = "model_a"
    cand.version = version
    cand.confidence_score = 0.812
    cand.pipeline = pipeline
    cand.xgb_model = xgb_model
    cand.calibrated = None
    return cand


def _make_candidate_classifier_model(version: str = "v1.0.1-real", prob: float = 0.80):
    """Build a LoadedModel mock for a candidate classifier (model_c)."""
    from inference.model_loader import LoadedModel

    pipeline, calibrated = _make_mock_classifier(prob)
    cand = MagicMock(spec=LoadedModel)
    cand.model_name = "model_c"
    cand.version = version
    cand.confidence_score = 0.980
    cand.pipeline = pipeline
    cand.xgb_model = MagicMock()
    cand.calibrated = calibrated
    return cand


def _client_with_candidate(model_name: str, candidate) -> TestClient:
    """Build a TestClient where get_shadow returns the candidate model."""
    from inference.model_loader import LoadedModel
    from inference.main import create_app

    if model_name == "model_a":
        pipeline, xgb_model = _make_mock_regressor(15.0)
        active = MagicMock(spec=LoadedModel)
        active.model_name = "model_a"
        active.version = "v1.0.0-synthetic"
        active.confidence_score = 0.884
        active.pipeline = pipeline
        active.xgb_model = xgb_model
        active.calibrated = None
    elif model_name == "model_b":
        pipeline, xgb_model = _make_mock_regressor(15.5)
        active = MagicMock(spec=LoadedModel)
        active.model_name = "model_b"
        active.version = "v1.0.0-synthetic"
        active.confidence_score = 0.885
        active.pipeline = pipeline
        active.xgb_model = xgb_model
        active.calibrated = None
    else:  # model_c
        pipeline, calibrated = _make_mock_classifier(0.73)
        active = MagicMock(spec=LoadedModel)
        active.model_name = "model_c"
        active.version = "v1.0.0-synthetic"
        active.confidence_score = 0.977
        active.pipeline = pipeline
        active.xgb_model = MagicMock()
        active.calibrated = calibrated

    loader = MagicMock()
    loader.get_active.return_value = active
    loader.get_shadow.return_value = candidate
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = candidate.version if candidate else None
    loader.uptime_seconds.return_value = 42.0
    loader.get_registry.return_value = None

    store = MagicMock()
    store.store.return_value = "pred-id-cand"

    app = create_app(loader=loader, store=store)
    return TestClient(app)


# ---------------------------------------------------------------------------
# Model A — no candidate
# ---------------------------------------------------------------------------

def test_predict_a_no_candidate_fields_when_no_shadow(client_a) -> None:
    resp = client_a.post("/predict/model-a", json={"features": FEATURES_A})
    assert resp.status_code == 200
    data = resp.json()
    assert data["model_version"] == "v1.0.0-test"
    assert data.get("candidate_version") is None
    assert data.get("candidate_expected_auction_price") is None
    assert data.get("candidate_value_signal") is None


def test_predict_a_includes_candidate_fields_when_shadow_loaded() -> None:
    candidate = _make_candidate_regressor_model("v1.0.1-real", log_output=15.5)
    client = _client_with_candidate("model_a", candidate)
    resp = client.post("/predict/model-a", json={"features": FEATURES_A})
    assert resp.status_code == 200
    data = resp.json()

    # Active fields unchanged
    assert data["model_version"] == "v1.0.0-synthetic"
    assert data["model_stage"] == "shadow"
    assert isinstance(data["expected_auction_price"], float)

    # Candidate fields present
    assert data["candidate_version"] == "v1.0.1-real"
    assert isinstance(data["candidate_expected_auction_price"], float)
    assert data["candidate_value_signal"] in {"undervalued", "fairly_priced", "overpriced"}
    assert isinstance(data["candidate_value_ratio"], float)
    assert isinstance(data["candidate_confidence_score"], float)
    assert isinstance(data["candidate_inference_ms"], int)


def test_predict_a_candidate_confidence_from_shadow_model() -> None:
    candidate = _make_candidate_regressor_model("v1.0.1-real")
    candidate.confidence_score = 0.812
    client = _client_with_candidate("model_a", candidate)
    resp = client.post("/predict/model-a", json={"features": FEATURES_A})
    assert resp.json()["candidate_confidence_score"] == pytest.approx(0.812, abs=1e-3)


def test_predict_a_candidate_silently_omitted_when_inference_raises() -> None:
    """Candidate model inference failure must not affect the active prediction."""
    candidate = _make_candidate_regressor_model("v1.0.1-real")
    candidate.pipeline.transform.side_effect = RuntimeError("candidate boom")

    client = _client_with_candidate("model_a", candidate)
    resp = client.post("/predict/model-a", json={"features": FEATURES_A})
    assert resp.status_code == 200
    data = resp.json()
    # Active prediction succeeded
    assert isinstance(data["expected_auction_price"], float)
    # Candidate fields absent — failure was swallowed
    assert data.get("candidate_version") is None
    assert data.get("candidate_expected_auction_price") is None


# ---------------------------------------------------------------------------
# Model B — no candidate
# ---------------------------------------------------------------------------

def test_predict_b_no_candidate_fields_when_no_shadow(client_b) -> None:
    resp = client_b.post("/predict/model-b", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("candidate_version") is None
    assert data.get("candidate_predicted_winning_bid") is None


def test_predict_b_includes_candidate_fields_when_shadow_loaded() -> None:
    candidate = _make_candidate_regressor_model("v1.0.1-real", log_output=15.8)
    candidate.model_name = "model_b"
    client = _client_with_candidate("model_b", candidate)
    resp = client.post("/predict/model-b", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()

    assert data["model_version"] == "v1.0.0-synthetic"
    assert data["candidate_version"] == "v1.0.1-real"
    assert isinstance(data["candidate_predicted_winning_bid"], float)
    assert isinstance(data["candidate_confidence_score"], float)
    assert isinstance(data["candidate_inference_ms"], int)


def test_predict_b_candidate_silently_omitted_when_inference_raises() -> None:
    candidate = _make_candidate_regressor_model("v1.0.1-real")
    candidate.pipeline.transform.side_effect = ValueError("bad features")

    client = _client_with_candidate("model_b", candidate)
    resp = client.post("/predict/model-b", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["predicted_winning_bid"], float)
    assert data.get("candidate_version") is None


# ---------------------------------------------------------------------------
# Model C — no candidate
# ---------------------------------------------------------------------------

def test_predict_c_no_candidate_fields_when_no_shadow(client_c) -> None:
    resp = client_c.post("/predict/model-c", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()
    assert data.get("candidate_version") is None
    assert data.get("candidate_predicted_probability") is None


def test_predict_c_includes_candidate_fields_when_shadow_loaded() -> None:
    candidate = _make_candidate_classifier_model("v1.0.1-real", prob=0.88)
    client = _client_with_candidate("model_c", candidate)
    resp = client.post("/predict/model-c", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()

    assert data["model_version"] == "v1.0.0-synthetic"
    assert data["candidate_version"] == "v1.0.1-real"
    assert isinstance(data["candidate_predicted_probability"], float)
    assert 0.0 <= data["candidate_predicted_probability"] <= 1.0
    assert isinstance(data["candidate_confidence_score"], float)
    assert isinstance(data["candidate_inference_ms"], int)


def test_predict_c_candidate_probability_matches_mock_output() -> None:
    candidate = _make_candidate_classifier_model("v1.0.1-real", prob=0.88)
    client = _client_with_candidate("model_c", candidate)
    resp = client.post("/predict/model-c", json={"features": FEATURES_BC})
    data = resp.json()
    assert data["candidate_predicted_probability"] == pytest.approx(0.88, abs=0.001)


def test_predict_c_candidate_silently_omitted_when_inference_raises() -> None:
    candidate = _make_candidate_classifier_model("v1.0.1-real")
    candidate.calibrated.predict_proba.side_effect = RuntimeError("boom")

    client = _client_with_candidate("model_c", candidate)
    resp = client.post("/predict/model-c", json={"features": FEATURES_BC})
    assert resp.status_code == 200
    data = resp.json()
    assert isinstance(data["predicted_probability"], float)
    assert data.get("candidate_version") is None
