"""Tests for GET /models/active."""

from unittest.mock import MagicMock

from fastapi.testclient import TestClient

from inference.main import create_app


def _make_registry_entry(name: str):
    entry = MagicMock()
    entry.version = f"v1.0.0-{name}"
    entry.status = "registered"
    entry.acceptance_grade = "excellent"
    entry.training_rows = 10_000
    entry.metrics = {"mape": 0.12, "r2": 0.85}
    entry.feature_count = 20
    return entry


def _make_client():
    loader = MagicMock()
    registry = MagicMock()

    entries = {n: _make_registry_entry(n) for n in ("model_a", "model_b", "model_c")}
    registry.get_active.side_effect = lambda n: entries[n]

    active = {n: MagicMock(version=f"v1.0.0-{n}") for n in ("model_a", "model_b", "model_c")}
    loader.get_active.side_effect = lambda n: active[n]
    loader.get_registry.return_value = registry
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 1.0

    return TestClient(create_app(loader=loader))


def test_models_active_structure():
    client = _make_client()
    resp = client.get("/models/active")
    assert resp.status_code == 200
    data = resp.json()
    for name in ("model_a", "model_b", "model_c"):
        assert name in data
        m = data[name]
        assert m["version"] == f"v1.0.0-{name}"
        assert m["status"] == "registered"
        assert m["acceptance_grade"] == "excellent"
        assert m["training_rows"] == 10_000
        assert "mape" in m["metrics"]
        assert m["feature_count"] == 20


def test_models_active_503_when_registry_missing():
    loader = MagicMock()
    loader.get_registry.return_value = None
    loader.is_loaded.return_value = True
    loader.uptime_seconds.return_value = 1.0
    loader.shadow_version.return_value = None

    client = TestClient(create_app(loader=loader))
    resp = client.get("/models/active")
    assert resp.status_code == 503
