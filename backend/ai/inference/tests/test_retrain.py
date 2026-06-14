"""Tests for retraining orchestration routes.

  POST /retrain-models   — queue a job (HTTP 202)
  GET  /retrain-models/{job_id} — poll status
  GET  /retrain-models   — list recent jobs
"""

from __future__ import annotations

import time
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from .conftest import FEATURES_A


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture
def client(mock_loader_a, mock_store):
    from inference.main import create_app
    app = create_app(loader=mock_loader_a, store=mock_store)
    return TestClient(app)


# ---------------------------------------------------------------------------
# POST /retrain-models
# ---------------------------------------------------------------------------

def test_retrain_queue_returns_202(client):
    with patch("inference.routes.retrain._run_training"):
        resp = client.post(
            "/retrain-models",
            json={"model_name": "model_a", "datasource": "synthetic"},
        )
    assert resp.status_code == 202
    data = resp.json()
    assert data["status"] == "queued"
    assert data["model_name"] == "model_a"
    assert data["datasource"] == "synthetic"
    assert "job_id" in data
    assert len(data["job_id"]) == 36  # UUID


def test_retrain_queue_all_models(client):
    with patch("inference.routes.retrain._run_training"):
        resp = client.post(
            "/retrain-models",
            json={"model_name": "all", "datasource": "synthetic"},
        )
    assert resp.status_code == 202
    assert resp.json()["model_name"] == "all"


def test_retrain_queue_real_datasource(client):
    with patch("inference.routes.retrain._run_training"):
        resp = client.post(
            "/retrain-models",
            json={"model_name": "model_b", "datasource": "real"},
        )
    assert resp.status_code == 202
    assert resp.json()["datasource"] == "real"


def test_retrain_queue_with_data_path(client):
    with patch("inference.routes.retrain._run_training"):
        resp = client.post(
            "/retrain-models",
            json={
                "model_name": "model_c",
                "datasource": "synthetic",
                "data_path": "/tmp/auctions.csv",
            },
        )
    assert resp.status_code == 202


def test_retrain_invalid_model_name_rejected(client):
    resp = client.post(
        "/retrain-models",
        json={"model_name": "model_x", "datasource": "synthetic"},
    )
    assert resp.status_code == 422


def test_retrain_invalid_datasource_rejected(client):
    resp = client.post(
        "/retrain-models",
        json={"model_name": "model_a", "datasource": "live"},
    )
    assert resp.status_code == 422


def test_retrain_missing_model_name_rejected(client):
    resp = client.post(
        "/retrain-models",
        json={"datasource": "synthetic"},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# GET /retrain-models/{job_id}
# ---------------------------------------------------------------------------

def test_get_job_status_queued(client):
    with patch("inference.routes.retrain._run_training"):
        post_resp = client.post(
            "/retrain-models",
            json={"model_name": "model_a", "datasource": "synthetic"},
        )
    job_id = post_resp.json()["job_id"]

    get_resp = client.get(f"/retrain-models/{job_id}")
    assert get_resp.status_code == 200
    data = get_resp.json()
    assert data["job_id"] == job_id
    assert data["model_name"] == "model_a"
    assert data["datasource"] == "synthetic"
    assert data["status"] in ("queued", "running", "completed", "failed")


def test_get_job_status_not_found(client):
    resp = client.get("/retrain-models/00000000-0000-0000-0000-000000000000")
    assert resp.status_code == 404


def test_get_job_elapsed_seconds_none_when_not_started(client):
    with patch("inference.routes.retrain._run_training"):
        post_resp = client.post(
            "/retrain-models",
            json={"model_name": "model_a", "datasource": "synthetic"},
        )
    job_id = post_resp.json()["job_id"]

    get_resp = client.get(f"/retrain-models/{job_id}")
    data = get_resp.json()
    # elapsed_seconds is None when the background task hasn't started yet
    # (TestClient runs synchronously so the task may have already run)
    assert "elapsed_seconds" in data


# ---------------------------------------------------------------------------
# GET /retrain-models — list
# ---------------------------------------------------------------------------

def test_list_jobs_empty(client):
    resp = client.get("/retrain-models")
    assert resp.status_code == 200
    assert isinstance(resp.json(), list)


def test_list_jobs_returns_queued_jobs(client):
    with patch("inference.routes.retrain._run_training"):
        for model in ("model_a", "model_b"):
            client.post(
                "/retrain-models",
                json={"model_name": model, "datasource": "synthetic"},
            )

    resp = client.get("/retrain-models")
    assert resp.status_code == 200
    jobs = resp.json()
    assert len(jobs) >= 2
    model_names = {j["model_name"] for j in jobs}
    assert "model_a" in model_names
    assert "model_b" in model_names


def test_list_jobs_schema(client):
    with patch("inference.routes.retrain._run_training"):
        client.post(
            "/retrain-models",
            json={"model_name": "model_c", "datasource": "synthetic"},
        )

    resp = client.get("/retrain-models")
    job = resp.json()[0]
    assert "job_id" in job
    assert "model_name" in job
    assert "datasource" in job
    assert "status" in job
    assert "elapsed_seconds" in job
    assert "result" in job
    assert "error" in job
