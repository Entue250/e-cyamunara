from __future__ import annotations

import pandas as pd

from ..preprocessing.feature_definitions import (
    FORBIDDEN_FEATURES,
    MODEL_A_FEATURES,
    MODEL_B_FEATURES,
    MODEL_C_FEATURES,
)


class DataLeakageError(ValueError):
    """Raised when forbidden columns are found in a training feature matrix."""

    def __init__(self, model_name: str, forbidden_columns: list[str]) -> None:
        self.model_name = model_name
        self.forbidden_columns = forbidden_columns
        super().__init__(
            f"DataLeakageError: forbidden column(s) {sorted(forbidden_columns)} "
            f"found in feature matrix for {model_name}. "
            f"Remove them from the DataFrame before training."
        )


def assert_no_leakage(df: pd.DataFrame, model_name: str) -> None:
    """Raise DataLeakageError if df contains any forbidden column."""
    found = set(df.columns) & FORBIDDEN_FEATURES
    if found:
        raise DataLeakageError(model_name, list(found))


def get_model_features(model_name: str) -> list[str]:
    """Return the canonical feature list for the given model name."""
    _map: dict[str, list[str]] = {
        "model_a": MODEL_A_FEATURES,
        "model_b": MODEL_B_FEATURES,
        "model_c": MODEL_C_FEATURES,
    }
    if model_name not in _map:
        raise ValueError(
            f"Unknown model_name {model_name!r}. Expected one of {sorted(_map.keys())}."
        )
    return _map[model_name]
