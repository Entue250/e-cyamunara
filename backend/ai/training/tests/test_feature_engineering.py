"""
Unit tests for training/feature_engineering/derived_features.py and leakage_guard.py.
"""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from training.feature_engineering.derived_features import add_derived_features
from training.feature_engineering.leakage_guard import (
    DataLeakageError,
    assert_no_leakage,
    get_model_features,
)


# ---------------------------------------------------------------------------
# Minimal helper
# ---------------------------------------------------------------------------

def _minimal_df() -> pd.DataFrame:
    return pd.DataFrame({
        "manufacturing_year": [2020, 2015, None],
        "start_date": pd.to_datetime(["2026-01-01", "2026-01-01", "2026-01-01"]),
        "end_date": pd.to_datetime(["2026-01-08", "2026-01-04", "2026-01-15"]),
        "total_bids": [10, 5, 0],
        "views_count": [100, 50, 0],
        "main_category": ["vehicle", "motorcycle", "bicycle"],
        "time_of_first_bid": pd.to_datetime(["2026-01-01 02:00", "2026-01-01 01:00", None]),
        "starting_price": [5_000_000, 1_500_000, 200_000],
        "description": ["Nice car", None, "Bike"],
        "photo_urls": [["url1", "url2"], [], None],
    })


# ---------------------------------------------------------------------------
# add_derived_features
# ---------------------------------------------------------------------------

def test_add_derived_does_not_mutate_input():
    """add_derived_features must not modify the input DataFrame."""
    df = _minimal_df()
    original_columns = list(df.columns)
    add_derived_features(df)
    assert list(df.columns) == original_columns


def test_asset_age_computed_correctly():
    """asset_age = ref_year - manufacturing_year; NaN for null manufacturing_year."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    assert result.loc[0, "asset_age"] == 6.0
    assert result.loc[1, "asset_age"] == 11.0
    assert pd.isna(result.loc[2, "asset_age"])


def test_auction_duration_hours():
    """7-day auction (2026-01-01 to 2026-01-08) yields 168 hours."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    assert result.loc[0, "auction_duration_hours"] == pytest.approx(168.0)


def test_bid_momentum_zero_when_no_bids():
    """Row with total_bids=0 must have bid_momentum=0.0, not NaN or inf."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    zero_bid_mask = df["total_bids"] == 0
    values = result.loc[zero_bid_mask, "bid_momentum"]
    assert (values == 0.0).all()
    assert not values.isna().any()


def test_view_to_bid_ratio_zero_when_no_bids():
    """Row with total_bids=0 must have view_to_bid_ratio=0.0."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    zero_bid_mask = df["total_bids"] == 0
    values = result.loc[zero_bid_mask, "view_to_bid_ratio"]
    assert (values == 0.0).all()


def test_is_first_bid_quick_true():
    """time_to_first_bid_hours <= 2.0 → is_first_bid_quick = 1."""
    # Row 0: start=2026-01-01 00:00, first_bid=2026-01-01 02:00 → exactly 2h
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    assert result.loc[0, "is_first_bid_quick"] == 1


def test_is_first_bid_quick_false_when_null():
    """time_of_first_bid=NaT → is_first_bid_quick = 0."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 2 has no first bid time
    assert result.loc[2, "is_first_bid_quick"] == 0


def test_has_description_false_for_null():
    """description=None → has_description = 0."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 1 has description=None
    assert result.loc[1, "has_description"] == 0


def test_has_description_true_for_nonempty():
    """Non-empty description string → has_description = 1."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 0 has description="Nice car"
    assert result.loc[0, "has_description"] == 1


def test_has_images_false_for_empty_list():
    """photo_urls=[] → has_images = 0."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 1 has photo_urls=[]
    assert result.loc[1, "has_images"] == 0


def test_has_images_true_for_nonempty_list():
    """photo_urls=['url1', 'url2'] → has_images = 1."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 0 has photo_urls=["url1", "url2"]
    assert result.loc[0, "has_images"] == 1


def test_has_images_false_for_null():
    """photo_urls=None → has_images = 0."""
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 2 has photo_urls=None
    assert result.loc[2, "has_images"] == 0


def test_price_tier_correct_labels():
    """Verify price tier labels against pd.cut bin assignments.

    Bins: (-inf, 500k] -> bicycle_tier
          (500k, 3M]   -> moto_tier
          (3M, 15M]    -> economy_vehicle   <-- 5_000_000 lands here
          (15M, 30M]   -> mid_vehicle
          (30M, inf]   -> luxury
    """
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    # Row 0: starting_price=5_000_000 is in (3M, 15M] → economy_vehicle
    assert result.loc[0, "price_tier"] == "economy_vehicle"
    # Row 1: starting_price=1_500_000 is in (500k, 3M] → moto_tier
    assert result.loc[1, "price_tier"] == "moto_tier"
    # Row 2: starting_price=200_000 is in (-inf, 500k] → bicycle_tier
    assert result.loc[2, "price_tier"] == "bicycle_tier"


def test_all_derived_columns_present():
    """All 11 expected derived columns appear in the output DataFrame."""
    expected_columns = [
        "asset_age",
        "auction_duration_hours",
        "bid_momentum",
        "view_to_bid_ratio",
        "time_to_first_bid_hours",
        "days_until_close",
        "bid_acceleration",
        "is_first_bid_quick",
        "has_description",
        "has_images",
        "price_tier",
    ]
    df = _minimal_df()
    result = add_derived_features(df, ref_year=2026)
    for col in expected_columns:
        assert col in result.columns, f"Missing derived column: {col}"


# ---------------------------------------------------------------------------
# leakage_guard
# ---------------------------------------------------------------------------

def test_assert_no_leakage_passes_clean_df():
    """DataFrame with no forbidden columns returns None without raising."""
    df = pd.DataFrame({
        "asset_age": [6, 11],
        "total_bids": [10, 5],
        "condition": ["Good", "Fair"],
    })
    result = assert_no_leakage(df, "model_a")
    assert result is None


def test_assert_no_leakage_raises_on_forbidden():
    """DataFrame containing a forbidden column raises DataLeakageError."""
    df = pd.DataFrame({
        "asset_age": [6, 11],
        "winning_amount": [1_000_000, 500_000],
    })
    with pytest.raises(DataLeakageError):
        assert_no_leakage(df, "model_b")


def test_data_leakage_error_message():
    """DataLeakageError string representation includes the model name and forbidden column names."""
    err = DataLeakageError("model_a", ["winning_amount", "bid_amount"])
    msg = str(err)
    assert "winning_amount" in msg
    assert "model_a" in msg


def test_get_model_features_model_a():
    """Model A features include 'asset_age', 'condition', and 'starting_price'."""
    features = get_model_features("model_a")
    assert "asset_age" in features
    assert "condition" in features
    # starting_price is now an INPUT for market value estimation (not the target)
    assert "starting_price" in features


def test_get_model_features_model_b_has_engagement():
    """Model B features include 'total_bids' and 'starting_price'."""
    features = get_model_features("model_b")
    assert "total_bids" in features
    assert "starting_price" in features


def test_get_model_features_invalid_raises():
    """get_model_features with an unknown model name raises ValueError."""
    with pytest.raises(ValueError, match="model_x"):
        get_model_features("model_x")
