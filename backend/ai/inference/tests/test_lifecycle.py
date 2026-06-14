"""Tests for model lifecycle management routes.

  GET  /models/candidates              — list promotion-eligible versions
  GET  /models/{model_name}/history    — version history for one model
  POST /models/{model_name}/promote    — promote a version to active
  POST /models/{model_name}/rollback   — revert to last deprecated version
"""

from __future__ import annotations

import pathlib
from types import SimpleNamespace
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient


# ---------------------------------------------------------------------------
# Helpers — build mock registry entries
# ---------------------------------------------------------------------------

def _entry(
    model_name: str,
    version: str,
    status: str = "registered",
    acceptance_passed: bool = True,
    acceptance_grade: str = "EXCELLENT",
    training_rows: int = 1000,
    metrics: dict | None = None,
    training_timestamp: str = "2026-06-10T12:00:00",
    dataset_source: str = "synthetic",
) -> SimpleNamespace:
    return SimpleNamespace(
        model_name=model_name,
        version=version,
        status=status,
        acceptance_passed=acceptance_passed,
        acceptance_grade=acceptance_grade,
        training_rows=training_rows,
        metrics=metrics or {"mape": 0.12},
        training_timestamp=training_timestamp,
        dataset_source=dataset_source,
    )


def _make_registry(
    *,
    a_active=None,
    a_versions=None,
    b_active=None,
    b_versions=None,
    c_active=None,
    c_versions=None,
) -> MagicMock:
    registry = MagicMock()
    registry._path = pathlib.Path("/fake/registry.json")

    _versions = {
        "model_a": a_versions or [],
        "model_b": b_versions or [],
        "model_c": c_versions or [],
    }
    _actives = {
        "model_a": a_active,
        "model_b": b_active,
        "model_c": c_active,
    }

    registry.list_versions.side_effect = lambda name: _versions.get(name, [])
    registry.get_active.side_effect = lambda name: _actives.get(name)
    registry.set_active = MagicMock()
    return registry


def _make_loader_with_registry(registry) -> MagicMock:
    loader = MagicMock()
    loader.get_registry.return_value = registry
    loader.load_all.return_value = None
    loader.get_active.return_value = None
    loader.is_loaded.return_value = True
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 42.0
    return loader


@pytest.fixture
def client_lifecycle(mock_store):
    """Client with a registry containing a candidate version for each model."""
    a_active = _entry("model_a", "v1.0.0-synthetic", status="active")
    a_candidate = _entry("model_a", "v1.1.0-synthetic", status="registered")

    b_active = _entry("model_b", "v1.0.0-synthetic", status="active")

    c_active = _entry("model_c", "v1.0.0-synthetic", status="active")

    registry = _make_registry(
        a_active=a_active,
        a_versions=[a_active, a_candidate],
        b_active=b_active,
        b_versions=[b_active],
        c_active=c_active,
        c_versions=[c_active],
    )
    loader = _make_loader_with_registry(registry)

    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    app = create_app(loader=loader, store=NullPredictionStore())
    return TestClient(app), registry


@pytest.fixture
def client_no_registry(mock_store):
    """Client with no registry loaded — all lifecycle routes return 503."""
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    loader = MagicMock()
    loader.get_registry.return_value = None
    loader.is_loaded.return_value = False
    loader.shadow_version.return_value = None
    loader.uptime_seconds.return_value = 1.0

    app = create_app(loader=loader, store=NullPredictionStore())
    return TestClient(app)


# ---------------------------------------------------------------------------
# GET /models/candidates
# ---------------------------------------------------------------------------

def test_candidates_returns_registered_versions(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/candidates")
    assert resp.status_code == 200
    candidates = resp.json()["candidates"]
    assert len(candidates) == 1
    c = candidates[0]
    assert c["model_name"] == "model_a"
    assert c["version"] == "v1.1.0-synthetic"
    assert c["acceptance_grade"] == "EXCELLENT"
    assert "metrics" in c
    assert "training_timestamp" in c


def test_candidates_excludes_active_versions(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/candidates")
    versions_in_response = {c["version"] for c in resp.json()["candidates"]}
    assert "v1.0.0-synthetic" not in versions_in_response


def test_candidates_empty_when_no_registered_versions():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    registry = _make_registry(
        a_active=_entry("model_a", "v1.0.0-synthetic", status="active"),
        a_versions=[_entry("model_a", "v1.0.0-synthetic", status="active")],
    )
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.get("/models/candidates")
    assert resp.status_code == 200
    assert resp.json()["candidates"] == []


def test_candidates_503_when_no_registry(client_no_registry):
    resp = client_no_registry.get("/models/candidates")
    assert resp.status_code == 503


def test_candidates_excludes_failed_acceptance():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    failed = _entry("model_a", "v1.1.0-synthetic", status="registered", acceptance_passed=False)
    registry = _make_registry(a_versions=[failed])
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.get("/models/candidates")
    assert resp.json()["candidates"] == []


# ---------------------------------------------------------------------------
# GET /models/{model_name}/history
# ---------------------------------------------------------------------------

def test_history_returns_all_versions(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/model_a/history")
    assert resp.status_code == 200
    data = resp.json()
    assert data["model_name"] == "model_a"
    assert data["active_version"] == "v1.0.0-synthetic"
    assert len(data["versions"]) == 2


def test_history_version_schema(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/model_a/history")
    v = resp.json()["versions"][0]
    assert "version" in v
    assert "status" in v
    assert "acceptance_grade" in v
    assert "training_rows" in v
    assert "metrics" in v
    assert "training_timestamp" in v
    assert "dataset_source" in v


def test_history_unknown_model_returns_404(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/model_x/history")
    assert resp.status_code == 404


def test_history_empty_model(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.get("/models/model_b/history")
    assert resp.status_code == 200
    assert resp.json()["active_version"] == "v1.0.0-synthetic"


def test_history_503_when_no_registry(client_no_registry):
    resp = client_no_registry.get("/models/model_a/history")
    assert resp.status_code == 503


# ---------------------------------------------------------------------------
# POST /models/{model_name}/promote
# ---------------------------------------------------------------------------

def test_promote_success(client_lifecycle):
    client, registry = client_lifecycle
    resp = client.post(
        "/models/model_a/promote",
        json={"version": "v1.1.0-synthetic"},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["model_name"] == "model_a"
    assert data["promoted_version"] == "v1.1.0-synthetic"
    assert data["previous_version"] == "v1.0.0-synthetic"
    registry.set_active.assert_called_once_with("model_a", "v1.1.0-synthetic")


def test_promote_unknown_model_returns_404(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.post("/models/model_x/promote", json={"version": "v1.1.0"})
    assert resp.status_code == 404


def test_promote_unknown_version_returns_404(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.post("/models/model_a/promote", json={"version": "v9.9.9-unknown"})
    assert resp.status_code == 404


def test_promote_already_active_returns_409(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.post(
        "/models/model_a/promote",
        json={"version": "v1.0.0-synthetic"},  # already active
    )
    assert resp.status_code == 409


def test_promote_failed_acceptance_returns_422():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    active = _entry("model_a", "v1.0.0-synthetic", status="active")
    failed = _entry("model_a", "v1.1.0-synthetic", status="registered", acceptance_passed=False, acceptance_grade="FAIL")
    registry = _make_registry(
        a_active=active,
        a_versions=[active, failed],
    )
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.post("/models/model_a/promote", json={"version": "v1.1.0-synthetic"})
    assert resp.status_code == 422


def test_promote_503_when_no_registry(client_no_registry):
    resp = client_no_registry.post("/models/model_a/promote", json={"version": "v1.0.0"})
    assert resp.status_code == 503


# ---------------------------------------------------------------------------
# POST /models/{model_name}/rollback
# ---------------------------------------------------------------------------

def test_rollback_success():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    active = _entry("model_a", "v1.1.0-synthetic", status="active", training_timestamp="2026-06-10T13:00:00")
    deprecated = _entry("model_a", "v1.0.0-synthetic", status="deprecated", training_timestamp="2026-06-09T12:00:00")
    registry = _make_registry(
        a_active=active,
        a_versions=[deprecated, active],
    )
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.post("/models/model_a/rollback")
    assert resp.status_code == 200
    data = resp.json()
    assert data["model_name"] == "model_a"
    assert data["rolled_back_from"] == "v1.1.0-synthetic"
    assert data["rolled_back_to"] == "v1.0.0-synthetic"
    registry.set_active.assert_called_once_with("model_a", "v1.0.0-synthetic")


def test_rollback_no_active_version_returns_409():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    registry = _make_registry(a_active=None, a_versions=[])
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.post("/models/model_a/rollback")
    assert resp.status_code == 409


def test_rollback_no_deprecated_versions_returns_409():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    active = _entry("model_a", "v1.0.0-synthetic", status="active")
    registry = _make_registry(
        a_active=active,
        a_versions=[active],
    )
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.post("/models/model_a/rollback")
    assert resp.status_code == 409


def test_rollback_picks_most_recent_deprecated():
    from inference.main import create_app
    from inference.prediction_store import NullPredictionStore

    active = _entry("model_a", "v1.2.0-synthetic", status="active", training_timestamp="2026-06-11T10:00:00")
    old = _entry("model_a", "v1.0.0-synthetic", status="deprecated", training_timestamp="2026-06-08T10:00:00")
    recent = _entry("model_a", "v1.1.0-synthetic", status="deprecated", training_timestamp="2026-06-10T10:00:00")
    registry = _make_registry(
        a_active=active,
        a_versions=[old, recent, active],
    )
    loader = _make_loader_with_registry(registry)
    app = create_app(loader=loader, store=NullPredictionStore())
    client = TestClient(app)

    resp = client.post("/models/model_a/rollback")
    assert resp.status_code == 200
    # Must pick v1.1.0 (more recent than v1.0.0)
    assert resp.json()["rolled_back_to"] == "v1.1.0-synthetic"


def test_rollback_unknown_model_returns_404(client_lifecycle):
    client, _ = client_lifecycle
    resp = client.post("/models/model_z/rollback")
    assert resp.status_code == 404


def test_rollback_503_when_no_registry(client_no_registry):
    resp = client_no_registry.post("/models/model_a/rollback")
    assert resp.status_code == 503
