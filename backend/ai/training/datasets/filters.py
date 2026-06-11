from __future__ import annotations

import pathlib

import numpy as np
import pandas as pd

from ..config import CONFIG


def filter_closed(df: pd.DataFrame) -> pd.DataFrame:
    """Return rows where auction_status == 'closed'."""
    return df[df["auction_status"] == "closed"].reset_index(drop=True)


def filter_has_winning_amount(df: pd.DataFrame) -> pd.DataFrame:
    """Return rows where winning_amount is not null."""
    return df[df["winning_amount"].notna()].reset_index(drop=True)


def filter_has_target(df: pd.DataFrame, target_col: str) -> pd.DataFrame:
    """Return rows where target_col is not null."""
    if target_col not in df.columns:
        raise KeyError(target_col)
    return df[df[target_col].notna()].reset_index(drop=True)


def require_min_rows(df: pd.DataFrame, n: int, label: str = "") -> pd.DataFrame:
    """Raise ValueError if df has fewer than n rows, else return df unchanged."""
    if len(df) < n:
        raise ValueError(f"[{label}] Too few rows: {len(df)} < {n}")
    return df
