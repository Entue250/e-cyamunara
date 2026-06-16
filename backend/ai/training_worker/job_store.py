"""
training_worker/job_store.py
==============================
Phase 9C — File-backed job store for the training worker.

Unlike the inference container's in-memory JobStore (inference/job_store.py),
this store writes each job as a JSON file so state survives container restarts.
The training worker runs one job at a time, so concurrent-write safety is not
a concern — a single writer, multiple reader pattern.

Job lifecycle:
    queued → running → completed | failed | skipped

  completed : all requested models trained (acceptance may still have failed)
  failed    : unexpected exception or hard data quality gate failure
  skipped   : not enough data to train (logged with skip_reason)
"""

from __future__ import annotations

import json
import pathlib
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone
from typing import Any

_DEFAULT_JOBS_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "training_jobs"

_VALID_STATUSES = frozenset({"queued", "running", "completed", "failed", "skipped"})


@dataclass
class TrainingJob:
    job_id: str
    model_name: str                   # "model_a" | "model_b" | "model_c" | "all"
    datasource: str                   # "real" | "synthetic"
    status: str                       # see lifecycle above
    queued_at: str                    # UTC ISO timestamp
    started_at: str | None = None
    completed_at: str | None = None
    result: dict[str, Any] | None = None   # {model_name: {passed, error?}}
    error: str | None = None
    skip_reason: str | None = None    # e.g. "insufficient_data:42<100"
    dataset_version: str | None = None
    dataset_hash: str | None = None


class FileJobStore:
    """Persistent file-backed job store.

    Each job is stored as a JSON file named ``{job_id}.json`` inside
    ``jobs_dir``.  The directory is created on first use.
    """

    def __init__(self, jobs_dir: pathlib.Path = _DEFAULT_JOBS_DIR) -> None:
        self._dir = jobs_dir
        self._dir.mkdir(parents=True, exist_ok=True)

    # ── Internal helpers ────────────────────────────────────────────────────

    def _path(self, job_id: str) -> pathlib.Path:
        return self._dir / f"{job_id}.json"

    def _write(self, job: TrainingJob) -> None:
        self._path(job.job_id).write_text(
            json.dumps(asdict(job), indent=2), encoding="utf-8"
        )

    def _read(self, path: pathlib.Path) -> TrainingJob:
        data = json.loads(path.read_text(encoding="utf-8"))
        return TrainingJob(**data)

    # ── Public API ──────────────────────────────────────────────────────────

    def create(
        self,
        model_name: str,
        datasource: str,
        *,
        dataset_version: str | None = None,
        dataset_hash: str | None = None,
    ) -> TrainingJob:
        """Create a new job in 'queued' state and persist it."""
        job = TrainingJob(
            job_id=str(uuid.uuid4()),
            model_name=model_name,
            datasource=datasource,
            status="queued",
            queued_at=datetime.now(timezone.utc).isoformat(),
            dataset_version=dataset_version,
            dataset_hash=dataset_hash,
        )
        self._write(job)
        return job

    def get(self, job_id: str) -> TrainingJob | None:
        """Return the job or None if not found."""
        p = self._path(job_id)
        if not p.exists():
            return None
        return self._read(p)

    def mark_running(self, job_id: str) -> None:
        job = self.get(job_id)
        if job:
            job.status = "running"
            job.started_at = datetime.now(timezone.utc).isoformat()
            self._write(job)

    def mark_completed(self, job_id: str, result: dict[str, Any]) -> None:
        job = self.get(job_id)
        if job:
            job.status = "completed"
            job.completed_at = datetime.now(timezone.utc).isoformat()
            job.result = result
            self._write(job)

    def mark_failed(self, job_id: str, error: str) -> None:
        job = self.get(job_id)
        if job:
            job.status = "failed"
            job.completed_at = datetime.now(timezone.utc).isoformat()
            job.error = error
            self._write(job)

    def mark_skipped(self, job_id: str, skip_reason: str) -> None:
        job = self.get(job_id)
        if job:
            job.status = "skipped"
            job.completed_at = datetime.now(timezone.utc).isoformat()
            job.skip_reason = skip_reason
            self._write(job)

    def list_recent(self, n: int = 20) -> list[TrainingJob]:
        """Return the n most recent jobs, newest first."""
        jobs = [self._read(p) for p in self._dir.glob("*.json")]
        jobs.sort(key=lambda j: j.queued_at, reverse=True)
        return jobs[:n]
