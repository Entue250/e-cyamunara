"""Tests for POST /predict/model-b."""

import numpy as np
import pytest

from .conftest import FEATURES_BC


def test_predict_b_success(client_b):
    resp = client_b.post(
        "/predict/model-b",
        json={
            "auction_id": "bbbbbbbb-0000-0000-0000-000000000001",
            "store_prediction": True,
            "features": FEATURES_BC,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"
    assert data["model_version"] == "v1.0.0-test"
    assert isinstance(data["predicted_winning_bid"], float)
    assert data["predicted_winning_bid"] > 0
    assert 0 < data["confidence_score"] <= 1
    assert isinstance(data["inference_ms"], int)


def test_predict_b_stores_prediction(client_b, mock_store):
    resp = client_b.post(
        "/predict/model-b",
        json={
            "auction_id": "bbbbbbbb-0000-0000-0000-000000000002",
            "store_prediction": True,
            "features": FEATURES_BC,
        },
    )
    assert resp.status_code == 200
    assert mock_store.store.called
    row = mock_store.store.call_args[0][0]
    assert row["prediction_type"] == "winning_bid"
    assert row["prediction_source"] == "real"
    assert row["model_stage"] == "shadow"
    assert "predicted_winning_bid" in row
    assert "value_signal" not in row


def test_predict_b_expm1_transform_applied(client_b):
    """Verify the raw log-scale output is transformed to RWF price."""
    data = client_b.post(
        "/predict/model-b",
        json={"features": FEATURES_BC},
    ).json()
    # Mock returns log output 15.5; expm1(15.5) ≈ 5.3M RWF
    expected = round(float(np.expm1(15.5)), 2)
    assert abs(data["predicted_winning_bid"] - expected) < 1.0  # within 1 RWF


def test_predict_b_missing_main_category(client_b):
    bad = {k: v for k, v in FEATURES_BC.items() if k != "main_category"}
    resp = client_b.post("/predict/model-b", json={"features": bad})
    assert resp.status_code == 422


def test_predict_b_no_store_when_no_auction_id(client_b, mock_store):
    resp = client_b.post(
        "/predict/model-b",
        json={"features": FEATURES_BC},
    )
    assert resp.status_code == 200
    assert not mock_store.store.called


def test_predict_b_zero_bids_accepted(client_b):
    """Cold-start scenario: no bids yet (engagement defaults to 0)."""
    cold_features = {**FEATURES_BC, "total_bids": 0, "views_count": 0, "unique_bidder_count": 0}
    resp = client_b.post("/predict/model-b", json={"features": cold_features})
    assert resp.status_code == 200
