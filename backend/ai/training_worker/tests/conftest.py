"""Shared fixtures for training_worker tests."""

from __future__ import annotations

import pathlib

import pandas as pd
import pytest

from training_worker.job_store import FileJobStore


@pytest.fixture()
def store(tmp_path: pathlib.Path) -> FileJobStore:
    """FileJobStore backed by a temp directory."""
    return FileJobStore(jobs_dir=tmp_path / "jobs")


@pytest.fixture()
def queued_job(store: FileJobStore):
    """A freshly queued training job."""
    return store.create(model_name="model_a", datasource="real")


def make_closed_df(n: int = 120, *, include_winning: bool = True) -> pd.DataFrame:
    """Minimal closed-auction DataFrame that passes all Phase 9B quality gates."""
    rows = []
    for i in range(n):
        rows.append({
            "auction_id": f"auc-{i:04d}",
            "auction_status": "closed",
            "closed_at": f"2026-0{(i % 6) + 1}-{(i % 28) + 1:02d}T10:00:00+00:00",
            "starting_price": 1_000_000 + i * 100_000,
            "winning_amount": 1_200_000 + i * 100_000 if include_winning else None,
            "region": "Northern",
            "main_category": "vehicle",
            "brand": "Toyota",
        })
    return pd.DataFrame(rows)
