"""Tests for GET /health."""

from fastapi.testclient import TestClient
from unittest.mock import MagicMock

from inference.main import create_app


def _make_client(is_loaded: bool = True):
    loader = MagicMock()
    loader.is_loaded.return_value = is_loaded
    loader.get_active.return_value = MagicMock(version="v1.0.0-test")
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 99.5
    loader.get_registry.return_value = None
    return TestClient(create_app(loader=loader))


def test_health_ok():
    client = _make_client(is_loaded=True)
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    assert data["uptime_seconds"] == 99.5
    for name in ("model_a", "model_b", "model_c"):
        assert data["models"][name]["loaded"] is True
        assert data["models"][name]["version"] == "v1.0.0-test"
        assert data["models"][name]["shadow_version"] is None


def test_health_model_not_loaded():
    client = _make_client(is_loaded=False)
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "ok"
    for name in ("model_a", "model_b", "model_c"):
        assert data["models"][name]["loaded"] is False
        assert data["models"][name]["version"] is None


def test_health_with_shadow_version():
    loader = MagicMock()
    loader.is_loaded.return_value = True
    loader.get_active.return_value = MagicMock(version="v1.0.4-synthetic")
    loader.shadow_version.side_effect = lambda n: "v2.0.0-real" if n == "model_a" else None
    loader.uptime_seconds.return_value = 5.0
    loader.get_registry.return_value = None

    client = TestClient(create_app(loader=loader))
    resp = client.get("/health")
    assert resp.status_code == 200
    data = resp.json()
    assert data["models"]["model_a"]["shadow_version"] == "v2.0.0-real"
    assert data["models"]["model_b"]["shadow_version"] is None
