"""In-memory job store for retraining background tasks.

Jobs are keyed by a UUID job_id and track status from 'queued' through
'running' to 'completed' or 'failed'. The store is process-local and
non-persistent — jobs are lost on server restart, which is acceptable for
Phase 6 (retraining is idempotent and can simply be re-queued).
"""

from __future__ import annotations

import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Optional


# ---------------------------------------------------------------------------
# Job data model
# ---------------------------------------------------------------------------

@dataclass
class TrainingJob:
    job_id: str
    model_name: str         # "model_a" | "model_b" | "model_c" | "all"
    datasource: str         # "synthetic" | "real"
    data_path: Optional[str]
    status: str             # "queued" | "running" | "completed" | "failed"
    queued_at: float        # monotonic timestamp
    started_at: Optional[float] = None
    completed_at: Optional[float] = None
    result: Optional[dict[str, Any]] = None   # per-model acceptance results
    error: Optional[str] = None

    @property
    def elapsed_seconds(self) -> Optional[float]:
        if self.started_at is None:
            return None
        end = self.completed_at or time.monotonic()
        return round(end - self.started_at, 2)


# ---------------------------------------------------------------------------
# Store
# ---------------------------------------------------------------------------

class JobStore:
    """Thread-safe in-memory job store."""

    _MAX_JOBS = 100  # keep at most this many recent jobs

    def __init__(self) -> None:
        self._jobs: dict[str, TrainingJob] = {}
        self._lock = threading.Lock()

    def create(
        self,
        model_name: str,
        datasource: str,
        data_path: Optional[str] = None,
    ) -> TrainingJob:
        """Create a new job in 'queued' state and return it."""
        job = TrainingJob(
            job_id=str(uuid.uuid4()),
            model_name=model_name,
            datasource=datasource,
            data_path=data_path,
            status="queued",
            queued_at=time.monotonic(),
        )
        with self._lock:
            self._jobs[job.job_id] = job
            self._evict_old_jobs()
        return job

    def get(self, job_id: str) -> Optional[TrainingJob]:
        with self._lock:
            return self._jobs.get(job_id)

    def mark_running(self, job_id: str) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job:
                job.status = "running"
                job.started_at = time.monotonic()

    def mark_completed(self, job_id: str, result: dict[str, Any]) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job:
                job.status = "completed"
                job.completed_at = time.monotonic()
                job.result = result

    def mark_failed(self, job_id: str, error: str) -> None:
        with self._lock:
            job = self._jobs.get(job_id)
            if job:
                job.status = "failed"
                job.completed_at = time.monotonic()
                job.error = error

    def list_recent(self, n: int = 20) -> list[TrainingJob]:
        with self._lock:
            jobs = sorted(self._jobs.values(), key=lambda j: j.queued_at, reverse=True)
            return jobs[:n]

    def _evict_old_jobs(self) -> None:
        """Drop oldest jobs when the store exceeds _MAX_JOBS (called under lock)."""
        if len(self._jobs) > self._MAX_JOBS:
            oldest = sorted(self._jobs.values(), key=lambda j: j.queued_at)
            for job in oldest[: len(self._jobs) - self._MAX_JOBS]:
                del self._jobs[job.job_id]


# ---------------------------------------------------------------------------
# App-level singleton — stored on app.state.job_store at startup
# ---------------------------------------------------------------------------

def get_job_store(request) -> JobStore:  # type: ignore[return]
    """FastAPI dependency: retrieve the JobStore from app.state."""
    return request.app.state.job_store
