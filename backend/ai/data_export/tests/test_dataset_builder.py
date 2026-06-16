"""Tests for data_export/dataset_builder.py."""

from __future__ import annotations

import json
import pathlib

import pandas as pd
import pytest

from data_export.dataset_builder import DatasetManifest, build_dataset


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_closed_df(n: int = 10, include_winning_amount: bool = True) -> pd.DataFrame:
    rows = []
    for i in range(n):
        rows.append({
            "auction_id": f"auc-{i:04d}",
            "auction_status": "closed",
            "closed_at": f"2026-0{(i % 6) + 1}-{(i % 28) + 1:02d}T10:00:00+00:00",
            "starting_price": 1_000_000 + i * 100_000,
            "winning_amount": 1_200_000 + i * 100_000 if include_winning_amount else None,
            "region": "Northern",
            "main_category": "Vehicles",
            "brand": "Toyota",
        })
    return pd.DataFrame(rows)


# ---------------------------------------------------------------------------
# Closed-only invariant
# ---------------------------------------------------------------------------

def test_non_closed_rows_dropped(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(10)
    df.loc[0, "auction_status"] = "active"
    df.loc[1, "auction_status"] = "draft"
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.row_count == 8  # 10 - 2 non-closed


def test_all_non_closed_returns_none(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5)
    df["auction_status"] = "active"
    result = build_dataset(df, tmp_path)
    assert result is None


def test_missing_auction_status_column_passes_through(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5).drop(columns=["auction_status"])
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.row_count == 5


# ---------------------------------------------------------------------------
# Null closed_at handling
# ---------------------------------------------------------------------------

def test_null_closed_at_dropped(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(6)
    df.loc[0, "closed_at"] = None
    df.loc[1, "closed_at"] = None
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.row_count == 4


def test_all_null_closed_at_returns_none(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(4)
    df["closed_at"] = None
    result = build_dataset(df, tmp_path)
    assert result is None


# ---------------------------------------------------------------------------
# Training window
# ---------------------------------------------------------------------------

def test_training_window_start_end(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(6)
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.training_window_start is not None
    assert manifest.training_window_end is not None
    # window_end must be >= window_start
    assert manifest.training_window_end >= manifest.training_window_start


def test_date_filter_from_date(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(6)
    # 3 rows in Jan, 3 in Feb+
    df.loc[0, "closed_at"] = "2026-01-10T00:00:00+00:00"
    df.loc[1, "closed_at"] = "2026-01-15T00:00:00+00:00"
    df.loc[2, "closed_at"] = "2026-01-20T00:00:00+00:00"
    df.loc[3, "closed_at"] = "2026-03-01T00:00:00+00:00"
    df.loc[4, "closed_at"] = "2026-04-01T00:00:00+00:00"
    df.loc[5, "closed_at"] = "2026-05-01T00:00:00+00:00"
    manifest = build_dataset(df, tmp_path, from_date="2026-02-01")
    assert manifest is not None
    assert manifest.row_count == 3


def test_date_filter_to_date(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(4)
    df.loc[0, "closed_at"] = "2026-01-01T00:00:00+00:00"
    df.loc[1, "closed_at"] = "2026-02-01T00:00:00+00:00"
    df.loc[2, "closed_at"] = "2026-03-01T00:00:00+00:00"
    df.loc[3, "closed_at"] = "2026-04-01T00:00:00+00:00"
    manifest = build_dataset(df, tmp_path, to_date="2026-02-28")
    assert manifest is not None
    assert manifest.row_count == 2


# ---------------------------------------------------------------------------
# Manifest fields
# ---------------------------------------------------------------------------

def test_manifest_all_required_fields_present(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5)
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.dataset_version
    assert manifest.dataset_hash
    assert manifest.dataset_created_at
    assert manifest.row_count == 5
    assert manifest.out_path
    assert manifest.manifest_path


def test_manifest_written_to_disk(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5)
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    manifest_file = pathlib.Path(manifest.manifest_path)
    assert manifest_file.exists()
    data = json.loads(manifest_file.read_text())
    assert data["dataset_version"] == manifest.dataset_version
    assert data["dataset_hash"] == manifest.dataset_hash
    assert data["row_count"] == 5


def test_csv_written_to_disk(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5)
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    csv_file = pathlib.Path(manifest.out_path)
    assert csv_file.exists()
    loaded = pd.read_csv(csv_file)
    assert len(loaded) == 5


# ---------------------------------------------------------------------------
# Hash stability
# ---------------------------------------------------------------------------

def test_dataset_hash_stable_same_data(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5)
    m1 = build_dataset(df, tmp_path / "run1")
    m2 = build_dataset(df, tmp_path / "run2")
    assert m1 is not None and m2 is not None
    assert m1.dataset_hash == m2.dataset_hash


def test_dataset_hash_changes_on_different_data(tmp_path: pathlib.Path) -> None:
    df1 = _make_closed_df(5)
    df2 = _make_closed_df(6)
    m1 = build_dataset(df1, tmp_path / "run1")
    m2 = build_dataset(df2, tmp_path / "run2")
    assert m1 is not None and m2 is not None
    assert m1.dataset_hash != m2.dataset_hash


# ---------------------------------------------------------------------------
# row_count_with_target
# ---------------------------------------------------------------------------

def test_row_count_with_target(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(6)
    df.loc[0, "winning_amount"] = None
    df.loc[1, "winning_amount"] = None
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.row_count == 6
    assert manifest.row_count_with_target == 4


def test_row_count_with_target_no_column(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(5).drop(columns=["winning_amount"])
    manifest = build_dataset(df, tmp_path)
    assert manifest is not None
    assert manifest.row_count_with_target == 0


# ---------------------------------------------------------------------------
# Version incrementing
# ---------------------------------------------------------------------------

def test_version_increments_on_same_day(tmp_path: pathlib.Path) -> None:
    df = _make_closed_df(3)
    m1 = build_dataset(df, tmp_path)
    m2 = build_dataset(df, tmp_path)
    assert m1 is not None and m2 is not None
    assert m1.dataset_version != m2.dataset_version
    v1_n = int(m1.dataset_version.rsplit(".", 1)[-1])
    v2_n = int(m2.dataset_version.rsplit(".", 1)[-1])
    assert v2_n == v1_n + 1
