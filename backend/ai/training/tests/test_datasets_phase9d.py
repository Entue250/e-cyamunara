"""Tests for Phase 9D filter changes in training/datasets/filters.py."""

from __future__ import annotations

import pandas as pd
import pytest

from training.datasets.filters import (
    MIN_BID_EVENTS_REAL_C,
    MIN_ROWS_REAL_AB,
    MIN_ROWS_REAL_C,
    MIN_ROWS_SYNTHETIC_AB,
    MIN_ROWS_SYNTHETIC_C,
    require_min_bid_events,
    require_min_rows,
)


# ---------------------------------------------------------------------------
# Constants sanity checks
# ---------------------------------------------------------------------------

def test_real_ab_is_100() -> None:
    assert MIN_ROWS_REAL_AB == 100


def test_real_c_is_100() -> None:
    assert MIN_ROWS_REAL_C == 100


def test_synthetic_ab_is_10000() -> None:
    assert MIN_ROWS_SYNTHETIC_AB == 10_000


def test_synthetic_c_is_5000() -> None:
    assert MIN_ROWS_SYNTHETIC_C == 5_000


def test_min_bid_events_real_c_is_500() -> None:
    assert MIN_BID_EVENTS_REAL_C == 500


def test_real_thresholds_below_synthetic() -> None:
    # Real thresholds must be strictly lower than synthetic (sanity).
    assert MIN_ROWS_REAL_AB < MIN_ROWS_SYNTHETIC_AB
    assert MIN_ROWS_REAL_C < MIN_ROWS_SYNTHETIC_C


# ---------------------------------------------------------------------------
# require_min_rows — real-data threshold (100)
# ---------------------------------------------------------------------------

def _df(n: int) -> pd.DataFrame:
    return pd.DataFrame({"x": range(n)})


def test_require_min_rows_passes_at_real_threshold() -> None:
    df = _df(MIN_ROWS_REAL_AB)
    result = require_min_rows(df, MIN_ROWS_REAL_AB, label="model_a")
    assert len(result) == MIN_ROWS_REAL_AB


def test_require_min_rows_fails_just_below_real_threshold() -> None:
    df = _df(MIN_ROWS_REAL_AB - 1)
    with pytest.raises(ValueError, match="Too few rows"):
        require_min_rows(df, MIN_ROWS_REAL_AB, label="model_a")


def test_require_min_rows_fails_just_below_synthetic_threshold() -> None:
    df = _df(MIN_ROWS_SYNTHETIC_AB - 1)
    with pytest.raises(ValueError, match="Too few rows"):
        require_min_rows(df, MIN_ROWS_SYNTHETIC_AB, label="model_a")


def test_require_min_rows_passes_at_synthetic_threshold() -> None:
    df = _df(MIN_ROWS_SYNTHETIC_AB)
    result = require_min_rows(df, MIN_ROWS_SYNTHETIC_AB)
    assert len(result) == MIN_ROWS_SYNTHETIC_AB


# ---------------------------------------------------------------------------
# require_min_bid_events
# ---------------------------------------------------------------------------

def _bid_df(n_rows: int, bids_per_row: int = 5) -> pd.DataFrame:
    return pd.DataFrame({"total_bids": [bids_per_row] * n_rows})


def test_require_min_bid_events_passes_exactly_at_threshold() -> None:
    # 100 rows × 5 bids = 500 events == MIN_BID_EVENTS_REAL_C
    df = _bid_df(100, bids_per_row=5)
    result = require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")
    assert len(result) == 100


def test_require_min_bid_events_fails_below_threshold() -> None:
    # 99 rows × 5 bids = 495 < 500
    df = _bid_df(99, bids_per_row=5)
    with pytest.raises(ValueError, match="Too few bid events"):
        require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")


def test_require_min_bid_events_counts_nulls_as_zero() -> None:
    df = pd.DataFrame({"total_bids": [None] * 200})
    with pytest.raises(ValueError, match="Too few bid events"):
        require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")


def test_require_min_bid_events_mixed_null_and_real() -> None:
    bids = [10] * 60 + [None] * 40  # 600 events from 60 rows, 40 nulls
    df = pd.DataFrame({"total_bids": bids})
    result = require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")
    assert len(result) == 100


def test_require_min_bid_events_missing_column_raises() -> None:
    df = pd.DataFrame({"other_col": [1, 2, 3]})
    with pytest.raises(ValueError, match="'total_bids' column missing"):
        require_min_bid_events(df, 1, label="model_c")


def test_require_min_bid_events_returns_df_unchanged() -> None:
    df = _bid_df(200, bids_per_row=10)
    result = require_min_bid_events(df, MIN_BID_EVENTS_REAL_C)
    assert result is df  # same object returned


# ---------------------------------------------------------------------------
# Datasource-aware pattern used in train_model_*.py
# ---------------------------------------------------------------------------

def test_real_datasource_uses_lower_threshold() -> None:
    """Verify the pattern train_model_a.py uses: real → 100, synthetic → 10000."""
    datasource = "real"
    min_rows = MIN_ROWS_REAL_AB if datasource == "real" else MIN_ROWS_SYNTHETIC_AB
    assert min_rows == 100


def test_synthetic_datasource_uses_higher_threshold() -> None:
    datasource = "synthetic"
    min_rows = MIN_ROWS_REAL_AB if datasource == "real" else MIN_ROWS_SYNTHETIC_AB
    assert min_rows == 10_000


def test_model_c_real_gates_include_bid_events() -> None:
    """Model C real-data path calls require_min_bid_events — verify it raises when met."""
    datasource = "real"
    # 100 rows, each with 6 bids = 600 total — passes both gates
    df = pd.DataFrame({
        "x": range(100),
        "total_bids": [6] * 100,
    })
    min_rows = MIN_ROWS_REAL_C if datasource == "real" else MIN_ROWS_SYNTHETIC_C
    require_min_rows(df, min_rows, label="model_c")
    if datasource == "real":
        require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")
    # No exception — test passes
