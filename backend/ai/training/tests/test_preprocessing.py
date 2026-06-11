"""
Unit tests for training/preprocessing/transformers.py and pipeline_builder.py.
"""

from __future__ import annotations

import warnings

import numpy as np
import pandas as pd
import pytest

from training.preprocessing.transformers import (
    MissingnessFlagger,
    CategoryAwareImputer,
    Log1pTransformer,
)
from training.preprocessing.pipeline_builder import build_pipeline


# ---------------------------------------------------------------------------
# MissingnessFlagger
# ---------------------------------------------------------------------------

def test_missingness_flagger_adds_flag_columns():
    """Flag columns are added; values are 1 for non-null, 0 for null rows."""
    df = pd.DataFrame({
        "mileage": [10_000.0, None, 30_000.0],
        "accident_history": [None, "Yes", "No"],
        "other_col": [1, 2, 3],
    })
    flagger = MissingnessFlagger(columns=["mileage", "accident_history"])
    result = flagger.fit_transform(df)

    assert "is_mileage_known" in result.columns
    assert "is_accident_history_known" in result.columns
    # Original columns still present
    assert "mileage" in result.columns
    assert "accident_history" in result.columns
    # Correct flag values for mileage
    assert list(result["is_mileage_known"]) == [1, 0, 1]
    # Correct flag values for accident_history
    assert list(result["is_accident_history_known"]) == [0, 1, 1]


def test_missingness_flagger_absent_column_fills_zeros():
    """When a requested column is absent from the DataFrame, the flag is all zeros (no exception)."""
    df = pd.DataFrame({"other_col": [1, 2, 3]})
    flagger = MissingnessFlagger(columns=["mileage"])
    with warnings.catch_warnings(record=True):
        warnings.simplefilter("always")
        result = flagger.fit_transform(df)
    assert "is_mileage_known" in result.columns
    assert list(result["is_mileage_known"]) == [0, 0, 0]


def test_missingness_flagger_get_feature_names_out():
    """get_feature_names_out returns input features plus generated flag names."""
    df = pd.DataFrame({
        "mileage": [1.0, None],
        "year": [2020, 2018],
    })
    flagger = MissingnessFlagger(columns=["mileage", "year"])
    flagger.fit(df)
    names = flagger.get_feature_names_out(input_features=["mileage", "year"])
    names_list = list(names)
    assert "mileage" in names_list
    assert "year" in names_list
    assert "is_mileage_known" in names_list
    assert "is_year_known" in names_list


# ---------------------------------------------------------------------------
# CategoryAwareImputer
# ---------------------------------------------------------------------------

def test_category_aware_imputer_bicycle_mileage_zero():
    """Bicycle rows with null mileage are filled with 0.0."""
    df = pd.DataFrame({
        "main_category": ["vehicle", "bicycle", "bicycle", "motorcycle"],
        "mileage": [50_000.0, None, None, 20_000.0],
    })
    imputer = CategoryAwareImputer()
    result = imputer.fit_transform(df)
    bicycle_mask = result["main_category"] == "bicycle"
    assert (result.loc[bicycle_mask, "mileage"] == 0.0).all()


def test_category_aware_imputer_vehicle_mileage_median():
    """Non-bicycle rows with null mileage are filled with the median of non-null non-bicycle mileage."""
    df = pd.DataFrame({
        "main_category": ["vehicle", "vehicle", "vehicle", "motorcycle"],
        "mileage": [10_000.0, 30_000.0, None, None],
    })
    imputer = CategoryAwareImputer()
    result = imputer.fit_transform(df)
    # Median of [10000, 30000] = 20000
    expected_median = 20_000.0
    # The None vehicle row should be filled
    assert result.loc[2, "mileage"] == expected_median
    # The None motorcycle row should also be filled
    assert result.loc[3, "mileage"] == expected_median


def test_category_aware_imputer_absent_main_category_col():
    """DataFrame without main_category column is returned unchanged (no exception)."""
    df = pd.DataFrame({
        "mileage": [10_000.0, None, 30_000.0],
        "condition": ["Good", "Fair", "Excellent"],
    })
    original_columns = list(df.columns)
    imputer = CategoryAwareImputer()
    result = imputer.fit_transform(df)
    assert list(result.columns) == original_columns


# ---------------------------------------------------------------------------
# Log1pTransformer
# ---------------------------------------------------------------------------

def test_log1p_transformer_applies_log1p():
    """Column values are replaced with np.log1p of the original values."""
    values = [0, 1, 9, 99]
    df = pd.DataFrame({"total_bids": values})
    transformer = Log1pTransformer(columns=["total_bids"])
    result = transformer.fit_transform(df)
    expected = np.log1p(values)
    np.testing.assert_allclose(result["total_bids"].values, expected)


def test_log1p_transformer_raises_for_negatives():
    """ValueError is raised when a column contains negative values."""
    df = pd.DataFrame({"total_bids": [-1, 0, 1]})
    transformer = Log1pTransformer(columns=["total_bids"])
    transformer.fit(df)
    with pytest.raises(ValueError, match="negative"):
        transformer.transform(df)


def test_log1p_transformer_skips_absent_columns():
    """Absent columns are skipped with a warning; present columns are still transformed."""
    df = pd.DataFrame({"mileage": [0.0, 1000.0, 5000.0]})
    transformer = Log1pTransformer(columns=["mileage", "nonexistent"])
    with warnings.catch_warnings(record=True) as caught:
        warnings.simplefilter("always")
        result = transformer.fit_transform(df)
    # A warning was issued about the missing column
    warned_messages = [str(w.message) for w in caught]
    assert any("nonexistent" in m for m in warned_messages)
    # The present column was still transformed
    expected = np.log1p([0.0, 1000.0, 5000.0])
    np.testing.assert_allclose(result["mileage"].values, expected)


# ---------------------------------------------------------------------------
# pipeline_builder
# ---------------------------------------------------------------------------

def test_build_pipeline_model_a_returns_pipeline():
    """build_pipeline('model_a') returns a Pipeline with exactly 5 named steps."""
    from sklearn.pipeline import Pipeline
    pipe = build_pipeline("model_a")
    assert isinstance(pipe, Pipeline)
    step_names = [name for name, _ in pipe.steps]
    assert step_names == ["derive", "flag", "impute", "log1p", "encode"]


def test_build_pipeline_model_a_forces_creation_context():
    """Model A pipeline encode step has no 'num_engage' transformer (creation context enforced)."""
    pipe = build_pipeline("model_a")
    encode_step = pipe.named_steps["encode"]
    transformer_names = [name for name, _, _ in encode_step.transformers]
    assert "num_engage" not in transformer_names


def test_build_pipeline_model_b_bidding_has_engagement():
    """build_pipeline('model_b', 'bidding') encode step includes num_engage transformer."""
    pipe = build_pipeline("model_b", "bidding")
    encode_step = pipe.named_steps["encode"]
    transformer_names = [name for name, _, _ in encode_step.transformers]
    assert "num_engage" in transformer_names


def test_build_pipeline_invalid_model_raises():
    """build_pipeline with an unknown model name raises ValueError."""
    with pytest.raises(ValueError, match="model_x"):
        build_pipeline("model_x")


def test_build_pipeline_invalid_context_raises():
    """build_pipeline with an invalid context raises ValueError."""
    with pytest.raises(ValueError, match="online"):
        build_pipeline("model_b", "online")
