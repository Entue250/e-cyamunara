"""Sklearn-compatible feature transformers for the E-CYAMUNARA ML pipeline."""

from __future__ import annotations

import warnings

import numpy as np
import pandas as pd
from sklearn.base import BaseEstimator, TransformerMixin

from .feature_definitions import (
    BICYCLE_STRUCTURAL_NA_COLUMNS,
    LOG1P_FEATURES,
    MISSINGNESS_FLAG_COLUMNS,
)


class MissingnessFlagger(BaseEstimator, TransformerMixin):
    """Appends binary is_{col}_known flag columns before imputation."""

    def __init__(self, columns: list = None):
        self.columns = columns if columns is not None else MISSINGNESS_FLAG_COLUMNS

    def fit(self, X: pd.DataFrame, y=None):
        """Store columns present in X; warn for absent ones."""
        self.columns_ = list(self.columns)
        for col in self.columns_:
            if col not in X.columns:
                warnings.warn(
                    f"MissingnessFlagger: column '{col}' not found in X; "
                    "flag will be all-zeros at transform time.",
                    UserWarning,
                    stacklevel=2,
                )
        return self

    def transform(self, X: pd.DataFrame, y=None) -> pd.DataFrame:
        """Return copy of X with is_{col}_known columns appended."""
        X = X.copy()
        for col in self.columns_:
            flag_col = f"is_{col}_known"
            if col in X.columns:
                X[flag_col] = (~X[col].isna()).astype(int)
            else:
                X[flag_col] = 0
        return X

    def get_feature_names_out(self, input_features=None):
        """Return input column names plus generated flag column names."""
        flags = [f"is_{col}_known" for col in self.columns_]
        if input_features is not None:
            return np.array(list(input_features) + flags)
        return np.array(flags)


class CategoryAwareImputer(BaseEstimator, TransformerMixin):
    """Handles structural N/A values for bicycles before standard imputation."""

    def __init__(
        self,
        main_category_col: str = "main_category",
        bicycle_structural_na_cols: list = None,
        bicycle_mileage_fill: float = 0.0,
        bicycle_fuel_fill: str = "N/A",
        strategy: str = "median",
    ):
        self.main_category_col = main_category_col
        self.bicycle_structural_na_cols = (
            bicycle_structural_na_cols
            if bicycle_structural_na_cols is not None
            else BICYCLE_STRUCTURAL_NA_COLUMNS
        )
        self.bicycle_mileage_fill = bicycle_mileage_fill
        self.bicycle_fuel_fill = bicycle_fuel_fill
        self.strategy = strategy

    def fit(self, X: pd.DataFrame, y=None):
        """Compute fill values from non-bicycle rows for numeric structural-NA cols."""
        self.numeric_fill_values_: dict = {}
        if self.main_category_col not in X.columns:
            return self
        non_bicycle_mask = X[self.main_category_col] != "bicycle"
        non_bicycle = X.loc[non_bicycle_mask]
        for col in self.bicycle_structural_na_cols:
            if col not in X.columns:
                continue
            if pd.api.types.is_numeric_dtype(X[col]):
                series = non_bicycle[col].dropna()
                if len(series) == 0:
                    self.numeric_fill_values_[col] = 0.0
                elif self.strategy == "mean":
                    self.numeric_fill_values_[col] = float(series.mean())
                else:
                    self.numeric_fill_values_[col] = float(series.median())
        return self

    def transform(self, X: pd.DataFrame, y=None) -> pd.DataFrame:
        """Apply bicycle structural fills and non-bicycle median fills."""
        X = X.copy()
        if self.main_category_col not in X.columns:
            return X
        bicycle_mask = X[self.main_category_col] == "bicycle"
        non_bicycle_mask = ~bicycle_mask
        for col in self.bicycle_structural_na_cols:
            if col not in X.columns:
                continue
            if col == "fuel_type":
                X.loc[bicycle_mask, col] = self.bicycle_fuel_fill
            elif col == "mileage":
                X.loc[bicycle_mask, col] = self.bicycle_mileage_fill
                if col in self.numeric_fill_values_:
                    X.loc[non_bicycle_mask & X[col].isna(), col] = self.numeric_fill_values_[col]
            else:
                if pd.api.types.is_numeric_dtype(X[col]):
                    X.loc[bicycle_mask, col] = self.bicycle_mileage_fill
                    if col in self.numeric_fill_values_:
                        X.loc[non_bicycle_mask & X[col].isna(), col] = self.numeric_fill_values_[col]
        return X

    def get_feature_names_out(self, input_features=None):
        """Return input column names unchanged."""
        if input_features is not None:
            return np.array(list(input_features))
        return np.array([])


class Log1pTransformer(BaseEstimator, TransformerMixin):
    """Applies np.log1p to right-skewed numeric columns after imputation."""

    def __init__(self, columns: list = None):
        self.columns = columns if columns is not None else LOG1P_FEATURES

    def fit(self, X: pd.DataFrame, y=None):
        """Store intersection of requested columns and columns present in X."""
        absent = [c for c in self.columns if c not in X.columns]
        if absent:
            warnings.warn(
                f"Log1pTransformer: column(s) {absent} not found in X and will be skipped.",
                UserWarning,
                stacklevel=2,
            )
        self.columns_ = [c for c in self.columns if c in X.columns]
        return self

    def transform(self, X: pd.DataFrame, y=None) -> pd.DataFrame:
        """Apply log1p to each fitted column; raise ValueError if negatives found."""
        X = X.copy()
        for col in self.columns_:
            if (X[col] < 0).any():
                raise ValueError(
                    f"Log1pTransformer: column '{col}' contains negative values, "
                    "which would produce NaN after log1p. Ensure imputation ran first."
                )
            X[col] = np.log1p(X[col])
        return X

    def get_feature_names_out(self, input_features=None):
        """Return input column names unchanged."""
        if input_features is not None:
            return np.array(list(input_features))
        return np.array([])
