from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, OrdinalEncoder
from sklearn.base import BaseEstimator, TransformerMixin
import category_encoders as ce

from .feature_definitions import (
    ONE_HOT_FEATURES,
    TARGET_ENCODED_FEATURES,
    ORDINAL_FEATURES,
    STATIC_CONTINUOUS_FEATURES,
    STATIC_BINARY_FEATURES,
    ENGAGEMENT_CONTINUOUS_FEATURES,
    ENGAGEMENT_BINARY_FEATURES,
    ENGAGEMENT_CATEGORICAL_FEATURES,
    CONDITION_ORDINAL_MAP,
)
from .transformers import MissingnessFlagger, CategoryAwareImputer, Log1pTransformer
from ..feature_engineering.derived_features import add_derived_features

_VALID_MODELS = {"model_a", "model_b", "model_c"}
_VALID_CONTEXTS = {"creation", "bidding"}


class DerivedFeatureAdder(BaseEstimator, TransformerMixin):
    """Wraps add_derived_features as a sklearn transformer."""

    def __init__(self, ref_year: int = 2026):
        self.ref_year = ref_year

    def fit(self, X: pd.DataFrame, y=None):
        self.ref_year_ = self.ref_year
        return self

    def transform(self, X: pd.DataFrame, y=None) -> pd.DataFrame:
        return add_derived_features(X, ref_year=self.ref_year_)


def _build_encoder(model_name: str, context: str) -> ColumnTransformer:
    """Build the ColumnTransformer encoding step."""
    condition_categories = [list(CONDITION_ORDINAL_MAP.keys())]

    # starting_price is an input for all models:
    #   model_a: floor price anchors market value estimation
    #   model_b/c: bidding context (already always included)
    static_num = STATIC_CONTINUOUS_FEATURES + STATIC_BINARY_FEATURES + ["starting_price"]

    transformers = [
        (
            "ohe",
            OneHotEncoder(handle_unknown="ignore", sparse_output=False),
            ONE_HOT_FEATURES,
        ),
        (
            "target",
            ce.LeaveOneOutEncoder(sigma=0.05, random_state=42),
            TARGET_ENCODED_FEATURES,
        ),
        (
            "ordinal",
            OrdinalEncoder(
                categories=condition_categories,
                handle_unknown="use_encoded_value",
                unknown_value=-1,
                encoded_missing_value=-1,
            ),
            ["condition"],
        ),
        (
            "num_static",
            "passthrough",
            static_num,
        ),
    ]

    if context == "bidding":
        transformers.append(
            (
                "num_engage",
                "passthrough",
                ENGAGEMENT_CONTINUOUS_FEATURES + ENGAGEMENT_BINARY_FEATURES,
            )
        )
        transformers.append(
            (
                "cat_engage",
                OneHotEncoder(handle_unknown="ignore", sparse_output=False),
                ENGAGEMENT_CATEGORICAL_FEATURES,
            )
        )

    return ColumnTransformer(transformers=transformers, remainder="drop")


def build_pipeline(model_name: str, context: str = "bidding") -> Pipeline:
    """Return an unfitted sklearn Pipeline for the given model and context."""
    if model_name not in _VALID_MODELS:
        raise ValueError(
            f"Invalid model_name {model_name!r}. Expected one of {sorted(_VALID_MODELS)}."
        )
    if context not in _VALID_CONTEXTS:
        raise ValueError(
            f"Invalid context {context!r}. Expected one of {sorted(_VALID_CONTEXTS)}."
        )

    if model_name == "model_a":
        context = "creation"

    return Pipeline(
        steps=[
            ("derive", DerivedFeatureAdder()),
            ("flag", MissingnessFlagger()),
            ("impute", CategoryAwareImputer()),
            ("log1p", Log1pTransformer()),
            ("encode", _build_encoder(model_name, context)),
        ]
    )
