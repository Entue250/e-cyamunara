"""
Unit tests for training/datasets/loaders.py, filters.py, and splitter.py.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from training.datasets.loaders import describe_auctions
from training.datasets.filters import (
    filter_closed,
    filter_has_winning_amount,
    filter_has_target,
    require_min_rows,
)
from training.datasets.splitter import temporal_split, split_summary
from training.config import CONFIG, SplitConfig


# ---------------------------------------------------------------------------
# Helper
# ---------------------------------------------------------------------------

def _make_auctions(n: int = 100) -> pd.DataFrame:
    """Create a minimal auctions DataFrame for testing."""
    rng = np.random.default_rng(42)
    dates = pd.date_range("2025-01-01", periods=n, freq="D")
    return pd.DataFrame(
        {
            "auction_status": rng.choice(
                ["closed", "active", "draft"], size=n, p=[0.6, 0.25, 0.15]
            ),
            "main_category": rng.choice(
                ["vehicle", "motorcycle", "bicycle"], size=n
            ),
            "winning_amount": [
                float(rng.integers(1_000_000, 10_000_000))
                if rng.random() > 0.4
                else None
                for _ in range(n)
            ],
            "starting_price": rng.integers(
                500_000, 15_000_000, size=n
            ).astype(float),
            "total_bids": rng.integers(0, 20, size=n),
            "start_date": dates,
        }
    )


# ---------------------------------------------------------------------------
# describe_auctions — 3 tests
# ---------------------------------------------------------------------------

def test_describe_auctions_includes_row_count():
    """describe_auctions output contains the row count as a string."""
    df = _make_auctions(100)
    result = describe_auctions(df)
    assert "100" in result


def test_describe_auctions_shows_status():
    """describe_auctions output contains at least one known status value."""
    df = _make_auctions(100)
    result = describe_auctions(df)
    assert "closed" in result


def test_describe_auctions_shows_winning_amount():
    """describe_auctions output contains the word 'non-null' for winning_amount."""
    df = _make_auctions(100)
    result = describe_auctions(df)
    assert "non-null" in result


# ---------------------------------------------------------------------------
# filter functions — 7 tests
# ---------------------------------------------------------------------------

def test_filter_closed_keeps_only_closed():
    """filter_closed leaves only rows with auction_status == 'closed'."""
    df = _make_auctions(100)
    result = filter_closed(df)
    unique_statuses = result["auction_status"].unique()
    assert list(unique_statuses) == ["closed"]


def test_filter_closed_resets_index():
    """filter_closed returns a DataFrame with a contiguous RangeIndex starting at 0."""
    df = _make_auctions(100)
    result = filter_closed(df)
    expected_index = pd.RangeIndex(start=0, stop=len(result), step=1)
    pd.testing.assert_index_equal(result.index, expected_index)


def test_filter_has_winning_amount_no_nulls():
    """filter_has_winning_amount leaves no NaN values in winning_amount."""
    df = _make_auctions(100)
    result = filter_has_winning_amount(df)
    assert result["winning_amount"].isna().sum() == 0


def test_filter_has_target_removes_nulls():
    """filter_has_target('winning_amount') removes all rows where winning_amount is NaN."""
    df = _make_auctions(100)
    result = filter_has_target(df, "winning_amount")
    assert result["winning_amount"].isna().sum() == 0


def test_filter_has_target_missing_col_raises():
    """filter_has_target raises KeyError when the requested column does not exist."""
    df = _make_auctions(20)
    with pytest.raises(KeyError):
        filter_has_target(df, "nonexistent_column")


def test_require_min_rows_raises_when_too_few():
    """require_min_rows raises ValueError when the DataFrame has fewer rows than required."""
    df = _make_auctions(100)
    with pytest.raises(ValueError):
        require_min_rows(df.iloc[:5], 10, label="test")


def test_require_min_rows_passes_when_enough():
    """require_min_rows returns the DataFrame unchanged when row count meets the minimum."""
    df = _make_auctions(100)
    result = require_min_rows(df, 10)
    assert result is df


# ---------------------------------------------------------------------------
# temporal_split — 6 tests
# ---------------------------------------------------------------------------

def test_temporal_split_sizes():
    """train + val + test lengths sum to total number of rows (10 000)."""
    df = _make_auctions(10_000)
    train, val, test = temporal_split(df)
    assert len(train) + len(val) + len(test) == 10_000


def test_temporal_split_test_is_most_recent():
    """All dates in test set are >= all dates in train set (temporal ordering)."""
    df = _make_auctions(10_000)
    train, val, test = temporal_split(df)
    max_train_date = train["start_date"].max()
    min_test_date = test["start_date"].min()
    assert min_test_date >= max_train_date


def test_temporal_split_no_overlap():
    """No row appears in more than one split (checked via unique row_id)."""
    df = _make_auctions(10_000)
    df = df.copy()
    df["row_id"] = np.arange(len(df))
    train, val, test = temporal_split(df)
    all_ids = (
        list(train["row_id"])
        + list(val["row_id"])
        + list(test["row_id"])
    )
    assert len(all_ids) == len(set(all_ids))


def test_temporal_split_too_small_raises():
    """temporal_split raises ValueError when the DataFrame is too small for the split config."""
    df = _make_auctions(100)
    # Default config: min_val=5000, min_test=2000 — 100 rows can't satisfy these.
    with pytest.raises(ValueError):
        temporal_split(df)


def test_temporal_split_resets_index():
    """All three split DataFrames have a contiguous RangeIndex starting at 0."""
    df = _make_auctions(10_000)
    train, val, test = temporal_split(df)
    for split_df in (train, val, test):
        expected = pd.RangeIndex(start=0, stop=len(split_df), step=1)
        pd.testing.assert_index_equal(split_df.index, expected)


def test_split_summary_contains_sizes():
    """split_summary output contains 'train=', 'val=', and 'test=' labels."""
    df = _make_auctions(10_000)
    train, val, test = temporal_split(df)
    summary = split_summary(train, val, test, "starting_price")
    assert "train=" in summary
    assert "val=" in summary
    assert "test=" in summary
