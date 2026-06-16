from __future__ import annotations

import pathlib

import numpy as np
import pandas as pd

from ..config import CONFIG

# ---------------------------------------------------------------------------
# Minimum row thresholds — Phase 9D
# ---------------------------------------------------------------------------

# Synthetic thresholds match the original hardcoded values in each train_model_*.py.
MIN_ROWS_SYNTHETIC_AB: int = 10_000
MIN_ROWS_SYNTHETIC_C: int = 5_000

# Real-data thresholds are much lower — early real datasets will be small.
MIN_ROWS_REAL_AB: int = 100
MIN_ROWS_REAL_C: int = 100

# Model C additionally gates on total bid event volume (sum of total_bids).
# Ensures the classifier has seen enough bidding examples, not just auction rows.
MIN_BID_EVENTS_REAL_C: int = 500


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


def require_min_bid_events(df: pd.DataFrame, n: int, label: str = "") -> pd.DataFrame:
    """Raise ValueError if sum(total_bids) < n.

    Used as the Phase 9D gate for Model C on real data: the classifier must
    have seen at least MIN_BID_EVENTS_REAL_C bid events across all training
    rows, not just MIN_ROWS_REAL_C closed-auction rows.
    """
    if "total_bids" not in df.columns:
        raise ValueError(
            f"[{label}] 'total_bids' column missing — cannot verify bid event count"
        )
    total = int(df["total_bids"].fillna(0).sum())
    if total < n:
        raise ValueError(f"[{label}] Too few bid events: {total} < {n}")
    return df
