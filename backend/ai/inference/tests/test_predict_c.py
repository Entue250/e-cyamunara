"""Tests for POST /predict/model-c."""

import pytest

from .conftest import FEATURES_BC


def test_predict_c_success(client_c):
    resp = client_c.post(
        "/predict/model-c",
        json={
            "auction_id": "cccccccc-0000-0000-0000-000000000001",
            "store_prediction": True,
            "features": FEATURES_BC,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"
    assert data["model_version"] == "v1.0.0-test"
    assert isinstance(data["predicted_probability"], float)
    assert 0.0 <= data["predicted_probability"] <= 1.0
    assert 0 < data["confidence_score"] <= 1
    assert isinstance(data["inference_ms"], int)


def test_predict_c_probability_value(client_c):
    """Mock returns [[0.27, 0.73]]; response should have 0.73."""
    data = client_c.post(
        "/predict/model-c",
        json={"features": FEATURES_BC},
    ).json()
    assert abs(data["predicted_probability"] - 0.73) < 0.001


def test_predict_c_stores_prediction(client_c, mock_store):
    resp = client_c.post(
        "/predict/model-c",
        json={
            "auction_id": "cccccccc-0000-0000-0000-000000000002",
            "store_prediction": True,
            "features": FEATURES_BC,
        },
    )
    assert resp.status_code == 200
    assert mock_store.store.called
    row = mock_store.store.call_args[0][0]
    assert row["prediction_type"] == "bid_probability"
    assert row["prediction_source"] == "real"
    assert row["model_stage"] == "shadow"
    assert 0.0 <= row["predicted_value"] <= 1.0
    assert row["value_signal"] is None


def test_predict_c_missing_region(client_c):
    bad = {k: v for k, v in FEATURES_BC.items() if k != "region"}
    resp = client_c.post("/predict/model-c", json={"features": bad})
    assert resp.status_code == 422


def test_predict_c_no_store_when_store_false(client_c, mock_store):
    resp = client_c.post(
        "/predict/model-c",
        json={
            "auction_id": "cccccccc-0000-0000-0000-000000000003",
            "store_prediction": False,
            "features": FEATURES_BC,
        },
    )
    assert resp.status_code == 200
    assert not mock_store.store.called
    assert resp.json()["prediction_id"] is None


def test_predict_c_null_engagement_fields(client_c):
    """Model C must accept auctions with no engagement data yet."""
    sparse = {**FEATURES_BC, "total_bids": None, "views_count": None, "time_of_first_bid": None}
    resp = client_c.post("/predict/model-c", json={"features": sparse})
    assert resp.status_code == 200
    assert 0.0 <= resp.json()["predicted_probability"] <= 1.0
