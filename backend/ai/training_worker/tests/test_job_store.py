"""Tests for training_worker/job_store.py."""

from __future__ import annotations

import json
import pathlib
import time
import uuid

import pytest

from training_worker.job_store import FileJobStore, TrainingJob


# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

def _new_store(tmp_path: pathlib.Path) -> FileJobStore:
    return FileJobStore(jobs_dir=tmp_path / "jobs")


# ---------------------------------------------------------------------------
# create()
# ---------------------------------------------------------------------------

def test_create_returns_training_job(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create(model_name="model_a", datasource="real")
    assert isinstance(job, TrainingJob)
    assert job.model_name == "model_a"
    assert job.datasource == "real"
    assert job.status == "queued"


def test_create_generates_unique_ids(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    j1 = store.create("model_a", "real")
    j2 = store.create("model_b", "real")
    assert j1.job_id != j2.job_id


def test_create_persists_to_disk(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("all", "synthetic")
    json_path = tmp_path / "jobs" / f"{job.job_id}.json"
    assert json_path.exists()
    data = json.loads(json_path.read_text())
    assert data["job_id"] == job.job_id
    assert data["status"] == "queued"


def test_create_stores_dataset_version_and_hash(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("model_a", "real", dataset_version="2026.06.16.0", dataset_hash="abc123")
    assert job.dataset_version == "2026.06.16.0"
    assert job.dataset_hash == "abc123"


def test_create_makes_jobs_dir_if_missing(tmp_path: pathlib.Path) -> None:
    deep = tmp_path / "a" / "b" / "c" / "jobs"
    store = FileJobStore(jobs_dir=deep)
    assert deep.exists()
    job = store.create("model_c", "synthetic")
    assert (deep / f"{job.job_id}.json").exists()


# ---------------------------------------------------------------------------
# get()
# ---------------------------------------------------------------------------

def test_get_returns_job(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    created = store.create("model_b", "real")
    retrieved = store.get(created.job_id)
    assert retrieved is not None
    assert retrieved.job_id == created.job_id


def test_get_returns_none_for_unknown_id(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    assert store.get(str(uuid.uuid4())) is None


# ---------------------------------------------------------------------------
# mark_running()
# ---------------------------------------------------------------------------

def test_mark_running_updates_status(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("model_a", "real")
    store.mark_running(job.job_id)
    updated = store.get(job.job_id)
    assert updated is not None
    assert updated.status == "running"
    assert updated.started_at is not None


def test_mark_running_persists(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("model_a", "real")
    store.mark_running(job.job_id)
    store2 = FileJobStore(jobs_dir=tmp_path / "jobs")
    retrieved = store2.get(job.job_id)
    assert retrieved is not None
    assert retrieved.status == "running"


# ---------------------------------------------------------------------------
# mark_completed()
# ---------------------------------------------------------------------------

def test_mark_completed_updates_status_and_result(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("model_a", "real")
    store.mark_running(job.job_id)
    store.mark_completed(job.job_id, {"model_a": {"passed": True}})
    updated = store.get(job.job_id)
    assert updated is not None
    assert updated.status == "completed"
    assert updated.result == {"model_a": {"passed": True}}
    assert updated.completed_at is not None


# ---------------------------------------------------------------------------
# mark_failed()
# ---------------------------------------------------------------------------

def test_mark_failed_updates_status_and_error(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("model_a", "real")
    store.mark_running(job.job_id)
    store.mark_failed(job.job_id, "data_quality_hard_fail: ['closed_only']")
    updated = store.get(job.job_id)
    assert updated is not None
    assert updated.status == "failed"
    assert "closed_only" in (updated.error or "")
    assert updated.completed_at is not None


# ---------------------------------------------------------------------------
# mark_skipped()
# ---------------------------------------------------------------------------

def test_mark_skipped_updates_status_and_skip_reason(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create("all", "real")
    store.mark_running(job.job_id)
    store.mark_skipped(job.job_id, "insufficient_data:42<100")
    updated = store.get(job.job_id)
    assert updated is not None
    assert updated.status == "skipped"
    assert updated.skip_reason == "insufficient_data:42<100"
    assert updated.completed_at is not None


# ---------------------------------------------------------------------------
# list_recent()
# ---------------------------------------------------------------------------

def test_list_recent_returns_newest_first(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    j1 = store.create("model_a", "real")
    j2 = store.create("model_b", "real")
    j3 = store.create("model_c", "real")
    recent = store.list_recent(n=10)
    ids = [j.job_id for j in recent]
    # j3 was created last, should appear first
    assert ids.index(j3.job_id) < ids.index(j2.job_id) < ids.index(j1.job_id)


def test_list_recent_respects_n_limit(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    for _ in range(5):
        store.create("model_a", "real")
    assert len(store.list_recent(n=3)) == 3


def test_list_recent_empty_store(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    assert store.list_recent() == []


# ---------------------------------------------------------------------------
# Round-trip serialisation
# ---------------------------------------------------------------------------

def test_roundtrip_all_fields(tmp_path: pathlib.Path) -> None:
    store = _new_store(tmp_path)
    job = store.create(
        "model_a", "real",
        dataset_version="2026.06.16.1",
        dataset_hash="deadbeef",
    )
    store.mark_running(job.job_id)
    store.mark_completed(job.job_id, {"model_a": {"passed": False, "error": "too few rows"}})

    # Re-read via a fresh store instance (simulates container restart)
    fresh = FileJobStore(jobs_dir=tmp_path / "jobs")
    loaded = fresh.get(job.job_id)
    assert loaded is not None
    assert loaded.dataset_version == "2026.06.16.1"
    assert loaded.dataset_hash == "deadbeef"
    assert loaded.result == {"model_a": {"passed": False, "error": "too few rows"}}
    assert loaded.status == "completed"
