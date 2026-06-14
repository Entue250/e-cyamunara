"""Integration tests — load real trained artifacts and run end-to-end inference.

These tests skip automatically when trained_models/registry.json is absent.
Run from backend/ai/:  PYTHONPATH=. pytest inference/tests/test_integration.py -v
"""

from __future__ import annotations

import pathlib
import sys

import pytest
from fastapi.testclient import TestClient

_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))

REGISTRY_PATH = _AI_ROOT / "trained_models" / "registry.json"
ARTIFACTS_AVAILABLE = REGISTRY_PATH.exists()

pytestmark = pytest.mark.skipif(
    not ARTIFACTS_AVAILABLE,
    reason="trained_models/registry.json not found — skipping integration tests",
)

# ---------------------------------------------------------------------------
# Real loader fixture
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def real_loader():
    from inference.model_loader import ModelLoader
    # Use a fresh instance (not the process singleton) to avoid polluting other tests
    loader = ModelLoader()
    loader.load_all(REGISTRY_PATH, shadow_flags=None)
    return loader


@pytest.fixture(scope="module")
def real_client(real_loader):
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore
    app = create_app(loader=real_loader, store=NullPredictionStore())
    return TestClient(app)


# ---------------------------------------------------------------------------
# Sample payloads — realistic Supabase auction fields
# ---------------------------------------------------------------------------

FEATURES_A = {
    "main_category": "vehicle",
    "region": "Central",
    "starting_price": 5_000_000.0,
    "fuel_type": "petrol",
    "transmission": "automatic",
    "ownership_history": "first_owner",
    "accident_history": None,        # unknown → is_accident_history_known=0
    "insurance_status": "active",
    "brand": "Toyota",
    "sub_category": "sedan",
    "condition": "Good",
    "manufacturing_year": 2018,      # → asset_age = 2026-2018 = 8
    "mileage": 80_000.0,
    "start_date": "2026-06-01T08:00:00Z",
    "end_date": "2026-06-04T08:00:00Z",  # → auction_duration_hours = 72
    "description": "Clean Toyota Corolla, well maintained",  # → has_description=1
    "photo_urls": ["url1.jpg", "url2.jpg"],                  # → has_images=1
}

FEATURES_A_BICYCLE = {
    "main_category": "bicycle",
    "region": "Southern",
    "starting_price": 200_000.0,
    "fuel_type": None,           # structural NA for bicycles
    "transmission": None,
    "brand": "Phoenix",
    "sub_category": "mountain_bike",
    "condition": "Fair",
    "manufacturing_year": 2020,
    "mileage": None,             # structural NA for bicycles
    "start_date": "2026-06-01T08:00:00Z",
    "end_date": "2026-06-03T08:00:00Z",
}

FEATURES_BC = {
    **FEATURES_A,
    "total_bids": 5.0,
    "unique_bidder_count": 3.0,
    "views_count": 120.0,
    "time_of_first_bid": "2026-06-01T10:30:00Z",   # → time_to_first_bid_hours ≈ 2.5
}

FEATURES_BC_COLD = {
    **FEATURES_A,
    "total_bids": 0.0,
    "unique_bidder_count": 0.0,
    "views_count": 0.0,
    "time_of_first_bid": None,
}


# ---------------------------------------------------------------------------
# Health + registry
# ---------------------------------------------------------------------------

def test_health_with_real_loader(real_client):
    resp = real_client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    for name in ("model_a", "model_b", "model_c"):
        assert data["models"][name]["loaded"] is True
        version = data["models"][name]["version"]
        assert version and version.startswith("v")
    assert data["uptime_seconds"] >= 0


def test_models_active_real_registry(real_client):
    resp = real_client.get("/models/active")
    assert resp.status_code == 200
    data = resp.json()
    assert data["model_a"]["version"] == "v1.0.4-synthetic"
    assert data["model_b"]["version"] == "v1.0.1-synthetic"
    assert data["model_c"]["version"] == "v1.0.1-synthetic"
    for name in ("model_a", "model_b", "model_c"):
        m = data[name]
        assert m["acceptance_grade"] in ("excellent", "good", "acceptable", "poor")
        assert m["training_rows"] >= 0  # model_a/c registry entry has 0 (known data gap)
        assert m["feature_count"] > 0
        assert "mape" in m["metrics"] or "roc_auc" in m["metrics"] or "ece" in m["metrics"]


# ---------------------------------------------------------------------------
# Model A — market value estimation
# ---------------------------------------------------------------------------

def test_predict_a_returns_rwf_price(real_client):
    resp = real_client.post("/predict/model-a", json={"features": FEATURES_A})
    assert resp.status_code == 200, resp.text
    data = resp.json()

    price = data["expected_auction_price"]
    assert isinstance(price, float)
    assert 100_000 < price < 500_000_000, f"Price {price:,.0f} RWF outside plausible range"

    signal = data["value_signal"]
    assert signal in ("undervalued", "fairly_priced", "overpriced")

    ratio = data["value_ratio"]
    assert isinstance(ratio, float)
    assert ratio > 0

    assert 0.5 < data["confidence_score"] <= 0.99
    assert data["model_version"] == "v1.0.4-synthetic"
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"
    assert data["inference_ms"] >= 0


def test_predict_a_value_ratio_consistent(real_client):
    """value_ratio = expected_price / starting_price, consistent with value_signal."""
    resp = real_client.post("/predict/model-a", json={"features": FEATURES_A})
    data = resp.json()
    price = data["expected_auction_price"]
    ratio = data["value_ratio"]
    starting = FEATURES_A["starting_price"]

    assert abs(ratio - price / starting) < 0.01, (
        f"value_ratio {ratio} inconsistent with price/starting = {price/starting:.4f}"
    )

    if ratio > 1.30:
        assert data["value_signal"] == "undervalued"
    elif ratio < 1.10:
        assert data["value_signal"] == "overpriced"
    else:
        assert data["value_signal"] == "fairly_priced"


def test_predict_a_bicycle(real_client):
    """Bicycle category is handled by the pipeline's structural NA logic."""
    resp = real_client.post("/predict/model-a", json={"features": FEATURES_A_BICYCLE})
    assert resp.status_code == 200, resp.text
    data = resp.json()
    assert data["expected_auction_price"] > 0
    assert data["value_signal"] in ("undervalued", "fairly_priced", "overpriced")


def test_predict_a_unknown_fields_are_none_safe(real_client):
    """All optional fields absent — pipeline uses imputed values."""
    minimal = {
        "main_category": "motorcycle",
        "region": "Eastern",
        "starting_price": 1_500_000.0,
    }
    resp = real_client.post("/predict/model-a", json={"features": minimal})
    assert resp.status_code == 200, resp.text
    assert resp.json()["expected_auction_price"] > 0


def test_predict_a_deterministic(real_client):
    """Same input twice returns same prediction."""
    r1 = real_client.post("/predict/model-a", json={"features": FEATURES_A}).json()
    r2 = real_client.post("/predict/model-a", json={"features": FEATURES_A}).json()
    assert r1["expected_auction_price"] == r2["expected_auction_price"]
    assert r1["value_signal"] == r2["value_signal"]


# ---------------------------------------------------------------------------
# Model B — winning bid prediction
# ---------------------------------------------------------------------------

def test_predict_b_returns_rwf_bid(real_client):
    resp = real_client.post("/predict/model-b", json={"features": FEATURES_BC})
    assert resp.status_code == 200, resp.text
    data = resp.json()

    bid = data["predicted_winning_bid"]
    assert isinstance(bid, float)
    assert 100_000 < bid < 500_000_000, f"Winning bid {bid:,.0f} RWF outside plausible range"

    assert 0.5 < data["confidence_score"] <= 0.99
    assert data["model_version"] == "v1.0.1-synthetic"
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"
    assert data["inference_ms"] >= 0


def test_predict_b_cold_start(real_client):
    """Zero engagement signals (auction just posted) must produce a valid bid."""
    resp = real_client.post("/predict/model-b", json={"features": FEATURES_BC_COLD})
    assert resp.status_code == 200, resp.text
    assert resp.json()["predicted_winning_bid"] > 0


def test_predict_b_deterministic(real_client):
    r1 = real_client.post("/predict/model-b", json={"features": FEATURES_BC}).json()
    r2 = real_client.post("/predict/model-b", json={"features": FEATURES_BC}).json()
    assert r1["predicted_winning_bid"] == r2["predicted_winning_bid"]


def test_predict_b_engagement_shifts_prediction(real_client):
    """Adding bidding activity should produce a different (typically higher) estimate."""
    cold = real_client.post("/predict/model-b", json={"features": FEATURES_BC_COLD}).json()
    warm = real_client.post("/predict/model-b", json={"features": FEATURES_BC}).json()
    # They should differ — we don't assert direction (model determines that)
    assert cold["predicted_winning_bid"] != warm["predicted_winning_bid"]


# ---------------------------------------------------------------------------
# Model C — bid probability classification
# ---------------------------------------------------------------------------

def test_predict_c_returns_probability(real_client):
    resp = real_client.post("/predict/model-c", json={"features": FEATURES_BC})
    assert resp.status_code == 200, resp.text
    data = resp.json()

    prob = data["predicted_probability"]
    assert isinstance(prob, float)
    assert 0.0 <= prob <= 1.0, f"Probability {prob} outside [0, 1]"

    assert 0.5 < data["confidence_score"] <= 0.99
    assert data["model_version"] == "v1.0.1-synthetic"
    assert data["prediction_source"] == "real"
    assert data["model_stage"] == "shadow"


def test_predict_c_probability_bounded(real_client):
    """Both cold and warm cases must produce valid probabilities."""
    for payload in (FEATURES_BC, FEATURES_BC_COLD):
        resp = real_client.post("/predict/model-c", json={"features": payload})
        assert resp.status_code == 200
        prob = resp.json()["predicted_probability"]
        assert 0.0 <= prob <= 1.0


def test_predict_c_deterministic(real_client):
    r1 = real_client.post("/predict/model-c", json={"features": FEATURES_BC}).json()
    r2 = real_client.post("/predict/model-c", json={"features": FEATURES_BC}).json()
    assert r1["predicted_probability"] == r2["predicted_probability"]


def test_predict_c_high_engagement_higher_probability(real_client):
    """Auction with many bids/views should have higher bid probability than no engagement."""
    cold_prob = real_client.post(
        "/predict/model-c", json={"features": FEATURES_BC_COLD}
    ).json()["predicted_probability"]

    high_engage = {
        **FEATURES_BC,
        "total_bids": 25.0,
        "unique_bidder_count": 12.0,
        "views_count": 500.0,
    }
    hot_prob = real_client.post(
        "/predict/model-c", json={"features": high_engage}
    ).json()["predicted_probability"]

    assert hot_prob > cold_prob, (
        f"Expected high-engagement prob ({hot_prob:.4f}) > cold prob ({cold_prob:.4f})"
    )


# ---------------------------------------------------------------------------
# Cross-model consistency sanity checks
# ---------------------------------------------------------------------------

def test_model_b_price_in_plausible_range_relative_to_model_a(real_client):
    """Model B winning bid and Model A market value should be in a similar ballpark."""
    price_a = real_client.post(
        "/predict/model-a", json={"features": FEATURES_A}
    ).json()["expected_auction_price"]

    bid_b = real_client.post(
        "/predict/model-b", json={"features": FEATURES_BC}
    ).json()["predicted_winning_bid"]

    ratio = bid_b / price_a
    # Reasonable range: Model B bid should be within 0.2x–5x of Model A market value
    assert 0.2 < ratio < 5.0, (
        f"Model B bid ({bid_b:,.0f}) unreasonably far from Model A value ({price_a:,.0f}), ratio={ratio:.2f}"
    )
