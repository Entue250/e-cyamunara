"""
training/persistence/training_history.py
==========================================
Append-only JSONL log of every training run, regardless of acceptance outcome.

One JSON line is written per run via log_run().  The file grows monotonically —
entries are never modified or deleted, giving a complete audit trail.
"""
from __future__ import annotations

import hashlib
import json
import pathlib
import uuid
from dataclasses import asdict, dataclass, field
from datetime import datetime, timezone


@dataclass
class TrainingRun:
    """One entry in the training history log."""

    run_id: str
    model_name: str
    version: str
    training_timestamp: str
    dataset_source: str
    training_rows: int
    val_rows: int
    test_rows: int
    metrics: dict
    acceptance_passed: bool
    acceptance_grade: str
    acceptance_failures: list[str] = field(default_factory=list)
    duration_seconds: float = 0.0
    dataset_hash: str = ""
    notes: str = ""


def new_run_id() -> str:
    """Return a new UUID4 string for a training run."""
    return str(uuid.uuid4())


def now_utc() -> str:
    """Return the current UTC time as an ISO-8601 string."""
    return datetime.now(timezone.utc).isoformat()


def dataset_hash(csv_path: pathlib.Path) -> str:
    """Return the SHA-256 hex digest of a CSV file (for provenance tracking)."""
    sha = hashlib.sha256()
    with open(csv_path, "rb") as f:
        for chunk in iter(lambda: f.read(65_536), b""):
            sha.update(chunk)
    return sha.hexdigest()


def log_run(run: TrainingRun, path: pathlib.Path) -> None:
    """Append *run* as a single JSON line to the history file at *path*."""
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(asdict(run), ensure_ascii=False) + "\n")


def load_history(
    path: pathlib.Path,
    model_name: str | None = None,
) -> list[TrainingRun]:
    """Load all TrainingRun records from the history file.

    Parameters
    ----------
    path:
        Path to training_history.jsonl.
    model_name:
        If given, only records for this model are returned.
    """
    path = pathlib.Path(path)
    if not path.exists():
        return []

    known_fields = set(TrainingRun.__dataclass_fields__)
    runs: list[TrainingRun] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        raw = raw.strip()
        if not raw:
            continue
        data = json.loads(raw)
        # Forward-compat: ignore unknown keys, use defaults for missing optional fields
        kwargs = {k: data[k] for k in known_fields if k in data}
        run = TrainingRun(**kwargs)
        if model_name is None or run.model_name == model_name:
            runs.append(run)
    return runs


def last_run(path: pathlib.Path, model_name: str) -> TrainingRun | None:
    """Return the most recent TrainingRun for *model_name*, or None."""
    runs = load_history(path, model_name=model_name)
    return runs[-1] if runs else None
