"""Tests for training_worker/trainer.py."""

from __future__ import annotations

import pathlib
from typing import Any
from unittest.mock import patch

import pandas as pd
import pytest

from training_worker.job_store import FileJobStore
from training_worker.trainer import (
    MIN_ROWS_MODEL_AB,
    TrainingResult,
    run_training_job,
)

from .conftest import make_closed_df


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _passing_runner(data_path, datasource) -> bool:
    return True


def _failing_runner(data_path, datasource) -> bool:
    return False


def _raising_runner(data_path, datasource) -> bool:
    raise RuntimeError("training exploded")


def _store_and_job(tmp_path: pathlib.Path, model_name="model_a", datasource="real"):
    store = FileJobStore(jobs_dir=tmp_path / "jobs")
    job = store.create(model_name=model_name, datasource=datasource)
    return store, job


# ---------------------------------------------------------------------------
# No dataset source → fail fast
# ---------------------------------------------------------------------------

def test_no_dataset_source_marks_failed(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path)
    result = run_training_job(
        job, store,
        runners={"model_a": _passing_runner},
    )
    assert result.failed
    assert result.error is not None
    loaded = store.get(job.job_id)
    assert loaded is not None
    assert loaded.status == "failed"


# ---------------------------------------------------------------------------
# Insufficient rows → skip
# ---------------------------------------------------------------------------

def test_too_few_rows_skips_training(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path)
    df = make_closed_df(n=5)  # well below MIN_ROWS_MODEL_AB (100)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert result.skipped
    assert result.skip_reason is not None
    assert "insufficient_data" in result.skip_reason
    loaded = store.get(job.job_id)
    assert loaded is not None
    assert loaded.status == "skipped"


def test_exact_minimum_rows_proceeds(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path)
    df = make_closed_df(n=MIN_ROWS_MODEL_AB)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert not result.skipped
    assert not result.failed


def test_one_below_minimum_skips(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path)
    df = make_closed_df(n=MIN_ROWS_MODEL_AB - 1)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert result.skipped


# ---------------------------------------------------------------------------
# Hard quality gate failure → fail, not skip
# ---------------------------------------------------------------------------

def test_hard_quality_gate_fail_marks_failed(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path)
    df = make_closed_df(n=120)
    # Inject an active row to trip the closed_only hard gate
    df.loc[0, "auction_status"] = "active"
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert result.failed
    assert result.error is not None
    assert "hard_fail" in result.error


# ---------------------------------------------------------------------------
# Successful training — single model
# ---------------------------------------------------------------------------

def test_single_model_success(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_a")
    df = make_closed_df(n=120)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert not result.failed
    assert not result.skipped
    assert result.all_passed
    assert result.model_results == {"model_a": {"passed": True}}
    loaded = store.get(job.job_id)
    assert loaded is not None
    assert loaded.status == "completed"
    assert loaded.result == {"model_a": {"passed": True}}


# ---------------------------------------------------------------------------
# Successful training — all models
# ---------------------------------------------------------------------------

def test_all_models_success(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="all")
    df = make_closed_df(n=200)
    runners = {
        "model_a": _passing_runner,
        "model_b": _passing_runner,
        "model_c": _passing_runner,
    }
    result = run_training_job(job, store, df=df, runners=runners)
    assert result.all_passed
    assert set(result.model_results.keys()) == {"model_a", "model_b", "model_c"}


# ---------------------------------------------------------------------------
# Runner returns False → completed but all_passed=False
# ---------------------------------------------------------------------------

def test_runner_failure_marks_completed_not_passed(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_a")
    df = make_closed_df(n=120)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _failing_runner},
    )
    assert not result.failed     # no exception — it completed
    assert not result.all_passed
    assert result.model_results["model_a"]["passed"] is False
    loaded = store.get(job.job_id)
    assert loaded is not None
    assert loaded.status == "completed"


# ---------------------------------------------------------------------------
# Runner raises exception → captured, stored, job marked completed
# ---------------------------------------------------------------------------

def test_runner_exception_captured_in_model_results(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_a")
    df = make_closed_df(n=120)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _raising_runner},
    )
    assert not result.all_passed
    assert "training exploded" in (result.model_results.get("model_a", {}).get("error", ""))
    loaded = store.get(job.job_id)
    assert loaded is not None
    assert loaded.status == "completed"


# ---------------------------------------------------------------------------
# Missing runner → no_runner error captured
# ---------------------------------------------------------------------------

def test_missing_runner_captured_gracefully(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_b")
    df = make_closed_df(n=120)
    result = run_training_job(
        job, store,
        df=df,
        runners={},  # no runners registered
    )
    assert result.model_results["model_b"]["error"] == "no_runner"
    assert not result.all_passed


# ---------------------------------------------------------------------------
# Dataset path + version/hash flow-through
# ---------------------------------------------------------------------------

def test_dataset_version_and_hash_flow_through(tmp_path: pathlib.Path) -> None:
    store = FileJobStore(jobs_dir=tmp_path / "jobs")
    job = store.create(
        "model_a", "real",
        dataset_version="2026.06.16.0",
        dataset_hash="abc123",
    )
    df = make_closed_df(n=120)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert result.dataset_version == "2026.06.16.0"
    assert result.dataset_hash == "abc123"


# ---------------------------------------------------------------------------
# rows_trained_on is populated
# ---------------------------------------------------------------------------

def test_rows_trained_on_reflects_closed_count(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_a")
    df = make_closed_df(n=150)
    result = run_training_job(
        job, store,
        df=df,
        runners={"model_a": _passing_runner},
    )
    assert result.rows_trained_on == 150


# ---------------------------------------------------------------------------
# min_rows_ab override
# ---------------------------------------------------------------------------

def test_custom_min_rows_override(tmp_path: pathlib.Path) -> None:
    store, job = _store_and_job(tmp_path, model_name="model_a")
    df = make_closed_df(n=10)  # only 10 rows
    # Lower the gate to 5 for this test
    result = run_training_job(
        job, store,
        df=df,
        min_rows_ab=5,
        runners={"model_a": _passing_runner},
    )
    assert not result.skipped
    assert result.all_passed
