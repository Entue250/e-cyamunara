"""
training_worker/schedule.py
============================
Phase 9D — Weekly retraining scheduler.

Runs as a daemon background thread inside the training worker container.
After an initial warm-up delay the scheduler fires run_training_job once per
INTERVAL_HOURS (default: 168 = 7 days), then waits again.

The scheduler does NOT use APScheduler or any external library — just
threading.Event so the stop signal is instant and testable without real
wall-clock waits.

Usage (inside app.py lifespan):
    store = FileJobStore()
    scheduler = WeeklyTrainingScheduler(store)
    scheduler.start()
    ...
    scheduler.stop()

For testing, override interval_seconds and initial_delay_seconds:
    scheduler = WeeklyTrainingScheduler(store, interval_seconds=1, initial_delay_seconds=0)
"""

from __future__ import annotations

import logging
import os
import threading
from typing import Any

from training_worker.job_store import FileJobStore
from training_worker.trainer import run_training_job

log = logging.getLogger(__name__)

INTERVAL_HOURS: int = 168          # 7 days
INITIAL_DELAY_SECONDS: int = 300   # 5-minute warm-up before first run


class WeeklyTrainingScheduler:
    """Thread-based weekly scheduler for model retraining.

    Parameters
    ----------
    store:
        FileJobStore used to persist job state.
    model_name:
        Which model(s) to train — "model_a" | "model_b" | "model_c" | "all".
    datasource:
        "real" (fetch from Supabase) or "synthetic" (use pre-built CSV).
    supabase_url / supabase_key:
        Override env vars SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY.
    interval_seconds:
        Override the 7-day interval (useful for testing).
    initial_delay_seconds:
        Delay before the first run (allows container startup to stabilise).
    """

    def __init__(
        self,
        store: FileJobStore,
        *,
        model_name: str = "all",
        datasource: str = "real",
        supabase_url: str | None = None,
        supabase_key: str | None = None,
        interval_seconds: int | None = None,
        initial_delay_seconds: int | None = None,
    ) -> None:
        self._store = store
        self._model_name = model_name
        self._datasource = datasource
        self._supabase_url = supabase_url or os.environ.get("SUPABASE_URL")
        self._supabase_key = supabase_key or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")
        self._interval = interval_seconds if interval_seconds is not None else INTERVAL_HOURS * 3600
        self._initial_delay = initial_delay_seconds if initial_delay_seconds is not None else INITIAL_DELAY_SECONDS
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the background scheduler thread (idempotent)."""
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(
            target=self._loop,
            name="weekly-trainer",
            daemon=True,
        )
        self._thread.start()
        log.info(
            "WeeklyTrainingScheduler started — first run in %ds, then every %ds",
            self._initial_delay,
            self._interval,
        )

    def stop(self) -> None:
        """Signal the background thread to stop and return immediately."""
        self._stop.set()

    def fire_now(self) -> str:
        """Trigger an immediate training job outside the regular schedule.

        Returns the job_id of the newly created job.
        Runs synchronously in the caller's thread — use for on-demand HTTP triggers.
        """
        return self._run_job()

    @property
    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    # ------------------------------------------------------------------
    # Internal loop
    # ------------------------------------------------------------------

    def _loop(self) -> None:
        # Initial warm-up delay — stop event interrupts the sleep immediately.
        if self._stop.wait(self._initial_delay):
            return
        # First run, then repeat every interval.
        while True:
            self._run_job()
            if self._stop.wait(self._interval):
                break

    def _run_job(self) -> str:
        job = self._store.create(
            model_name=self._model_name,
            datasource=self._datasource,
        )
        log.info("WeeklyTrainingScheduler: firing job %s (model=%s)", job.job_id, self._model_name)
        result = None
        try:
            result = run_training_job(
                job,
                self._store,
                supabase_url=self._supabase_url,
                supabase_key=self._supabase_key,
            )
        except Exception:
            log.exception("Unexpected error in scheduled training job %s", job.job_id)

        # Phase 9E — register trained real-data models as shadow candidates
        if result is not None and result.all_passed and self._datasource == "real":
            self._register_candidates(result)

        return job.job_id

    def _register_candidates(self, result: Any) -> None:
        """Call register-candidate-model Edge Function for each passed model."""
        try:
            from training.config import CONFIG
            from training_worker.candidate_registry import register_all_candidates

            model_names = (
                ["model_a", "model_b", "model_c"]
                if self._model_name == "all"
                else [self._model_name]
            )
            passed_names = [
                m for m in model_names
                if result.model_results.get(m, {}).get("passed")
            ]
            if not passed_names:
                return

            reg_results = register_all_candidates(
                model_names=passed_names,
                registry_path=CONFIG.paths.trained_models_registry_file,
                supabase_url=self._supabase_url,
                supabase_key=self._supabase_key,
            )
            for model, status in reg_results.items():
                log.info("Candidate registration %s: %s", model, status)
        except Exception:
            log.exception("Candidate registration failed — training completed successfully")
