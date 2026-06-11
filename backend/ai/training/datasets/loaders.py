from __future__ import annotations

import pathlib

import numpy as np
import pandas as pd

from ..config import CONFIG

_DATE_COLS = [
    "start_date",
    "end_date",
    "closed_at",
    "time_of_first_bid",
    "time_of_last_bid",
    "created_at",
    "updated_at",
]

_NUMERIC_COLS = [
    "starting_price",
    "mileage",
    "total_bids",
    "views_count",
    "unique_bidder_count",
    "winning_amount",
]


def load_auctions(
    path: pathlib.Path | None = None,
    *,
    parse_dates: bool = True,
) -> pd.DataFrame:
    """Load the synthetic auctions CSV and optionally parse date/numeric columns."""
    csv_path = path if path is not None else CONFIG.paths.synthetic_auctions
    df = pd.read_csv(csv_path)

    if parse_dates:
        for col in _DATE_COLS:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors="coerce")

        if "manufacturing_year" in df.columns:
            df["manufacturing_year"] = pd.to_numeric(
                df["manufacturing_year"], errors="coerce"
            )

        for col in _NUMERIC_COLS:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors="coerce")

    return df


def describe_auctions(df: pd.DataFrame) -> str:
    """Return a short multi-line summary of the auctions DataFrame."""
    rows, cols = df.shape
    lines = [f"Auctions: {rows:,} rows × {cols} columns"]

    if "auction_status" in df.columns:
        lines.append("Status distribution:")
        counts = df["auction_status"].value_counts()
        for status, count in counts.items():
            pct = count / rows * 100
            lines.append(f"  {status:<10}: {count:>10,} ({pct:.1f}%)")

    if "main_category" in df.columns:
        lines.append("Category distribution:")
        counts = df["main_category"].value_counts()
        for cat, count in counts.items():
            pct = count / rows * 100
            lines.append(f"  {cat:<12}: {count:>10,} ({pct:.1f}%)")

    if "winning_amount" in df.columns:
        non_null = int(df["winning_amount"].notna().sum())
        lines.append(f"Winning amount: {non_null:,} non-null / {rows:,} total")

    return "\n".join(lines)
