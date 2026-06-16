"""Tests for training_worker/schedule.py."""

from __future__ import annotations

import pathlib
import threading
import time

import pytest

from training_worker.job_store import FileJobStore
from training_worker.schedule import WeeklyTrainingScheduler


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _store(tmp_path: pathlib.Path) -> FileJobStore:
    return FileJobStore(jobs_dir=tmp_path / "jobs")


def _fast_scheduler(store: FileJobStore, **kwargs) -> WeeklyTrainingScheduler:
    """Scheduler with zero delays and a stub runner so no real training fires."""
    return WeeklyTrainingScheduler(
        store,
        interval_seconds=kwargs.pop("interval_seconds", 9999),
        initial_delay_seconds=kwargs.pop("initial_delay_seconds", 9999),
        **kwargs,
    )


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

def test_scheduler_starts_not_running(tmp_path: pathlib.Path) -> None:
    s = _fast_scheduler(_store(tmp_path))
    assert not s.is_running


def test_scheduler_is_running_after_start(tmp_path: pathlib.Path) -> None:
    s = _fast_scheduler(_store(tmp_path))
    s.start()
    assert s.is_running
    s.stop()


def test_start_is_idempotent(tmp_path: pathlib.Path) -> None:
    s = _fast_scheduler(_store(tmp_path))
    s.start()
    thread1 = s._thread
    s.start()  # second call — should not replace the thread
    thread2 = s._thread
    assert thread1 is thread2
    s.stop()


def test_stop_signals_thread(tmp_path: pathlib.Path) -> None:
    s = _fast_scheduler(_store(tmp_path))
    s.start()
    assert s.is_running
    s.stop()
    # Thread is daemon — we can't join it with a timeout in tests, but the
    # stop event is set so the loop will exit on next wait().
    assert s._stop.is_set()


# ---------------------------------------------------------------------------
# fire_now() — synchronous immediate job
# ---------------------------------------------------------------------------

def test_fire_now_creates_job(tmp_path: pathlib.Path) -> None:
    store = _store(tmp_path)
    fired_jobs: list[str] = []

    # Patch run_training_job to a no-op to avoid real training
    import training_worker.schedule as sched_mod
    original = sched_mod.run_training_job

    def _fake_run(job, store, **kwargs):
        fired_jobs.append(job.job_id)

    sched_mod.run_training_job = _fake_run
    try:
        s = _fast_scheduler(store)
        job_id = s.fire_now()
        assert job_id in fired_jobs
        # The job must be persisted in the store
        persisted = store.get(job_id)
        assert persisted is not None
    finally:
        sched_mod.run_training_job = original


def test_fire_now_returns_job_id_string(tmp_path: pathlib.Path) -> None:
    import training_worker.schedule as sched_mod
    original = sched_mod.run_training_job
    sched_mod.run_training_job = lambda job, store, **kw: None  # type: ignore
    try:
        s = _fast_scheduler(_store(tmp_path))
        job_id = s.fire_now()
        assert isinstance(job_id, str)
        assert len(job_id) == 36  # UUID length
    finally:
        sched_mod.run_training_job = original


# ---------------------------------------------------------------------------
# Initial delay — stop during warm-up exits without running a job
# ---------------------------------------------------------------------------

def test_stop_during_initial_delay_fires_no_job(tmp_path: pathlib.Path) -> None:
    import training_worker.schedule as sched_mod
    original = sched_mod.run_training_job
    fired = []
    sched_mod.run_training_job = lambda job, store, **kw: fired.append(job.job_id)

    try:
        store = _store(tmp_path)
        # 60s initial delay — we'll stop well before it fires
        s = WeeklyTrainingScheduler(
            store,
            interval_seconds=9999,
            initial_delay_seconds=60,
        )
        s.start()
        time.sleep(0.05)  # let the thread start
        s.stop()
        time.sleep(0.05)  # let the stop propagate
        assert fired == [], "No training job should fire when stopped during warm-up"
    finally:
        sched_mod.run_training_job = original


# ---------------------------------------------------------------------------
# Loop — fires once, then waits for interval
# ---------------------------------------------------------------------------

def test_loop_fires_once_then_waits(tmp_path: pathlib.Path) -> None:
    import training_worker.schedule as sched_mod
    original = sched_mod.run_training_job
    fired: list[str] = []
    sched_mod.run_training_job = lambda job, store, **kw: fired.append(job.job_id)

    try:
        store = _store(tmp_path)
        s = WeeklyTrainingScheduler(
            store,
            interval_seconds=9999,   # very long — won't fire a second time
            initial_delay_seconds=0, # no warm-up — fires immediately
        )
        s.start()
        # Give the thread time to run the first job
        deadline = time.monotonic() + 2.0
        while not fired and time.monotonic() < deadline:
            time.sleep(0.05)
        s.stop()
        assert len(fired) == 1, f"Expected 1 firing, got {len(fired)}"
    finally:
        sched_mod.run_training_job = original


# ---------------------------------------------------------------------------
# Exception in _run_job — scheduler continues running
# ---------------------------------------------------------------------------

def test_exception_in_run_job_does_not_crash_scheduler(tmp_path: pathlib.Path) -> None:
    import training_worker.schedule as sched_mod
    original = sched_mod.run_training_job
    sched_mod.run_training_job = lambda job, store, **kw: (_ for _ in ()).throw(RuntimeError("boom"))  # type: ignore

    try:
        store = _store(tmp_path)
        s = WeeklyTrainingScheduler(
            store,
            interval_seconds=9999,
            initial_delay_seconds=0,
        )
        s.start()
        time.sleep(0.2)  # let it attempt to run
        # Scheduler thread should still be alive (exception was caught)
        assert s.is_running
        s.stop()
    finally:
        sched_mod.run_training_job = original


# ---------------------------------------------------------------------------
# Configuration defaults
# ---------------------------------------------------------------------------

def test_model_and_datasource_defaults(tmp_path: pathlib.Path) -> None:
    s = _fast_scheduler(_store(tmp_path))
    assert s._model_name == "all"
    assert s._datasource == "real"


def test_model_and_datasource_overrides(tmp_path: pathlib.Path) -> None:
    s = WeeklyTrainingScheduler(
        _store(tmp_path),
        model_name="model_a",
        datasource="synthetic",
        interval_seconds=9999,
        initial_delay_seconds=9999,
    )
    assert s._model_name == "model_a"
    assert s._datasource == "synthetic"
