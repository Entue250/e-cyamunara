from __future__ import annotations

import numpy as np
import pandas as pd

from ..preprocessing.feature_definitions import PRICE_TIER_BOUNDARIES, PRICE_TIER_LABELS


def _to_naive(s: pd.Series) -> pd.Series:
    """Convert a datetime Series to timezone-naive UTC."""
    s = pd.to_datetime(s, errors="coerce")
    if s.dt.tz is not None:
        s = s.dt.tz_convert("UTC").dt.tz_localize(None)
    return s


def _has_images(val) -> int:
    """Return 1 if val represents a non-empty image list, else 0."""
    if not isinstance(val, (list, str)):
        try:
            if pd.isna(val):
                return 0
        except (TypeError, ValueError):
            pass
        return 0
    if isinstance(val, list):
        return int(len(val) > 0)
    return int(len(str(val).strip()) > 2)


def add_derived_features(df: pd.DataFrame, ref_year: int = 2026) -> pd.DataFrame:
    """Compute and append all derived feature columns; never mutates the input."""
    df = df.copy()

    # asset_age
    if "manufacturing_year" in df.columns:
        df["asset_age"] = pd.to_numeric(df["manufacturing_year"], errors="coerce").apply(
            lambda y: (ref_year - y) if pd.notna(y) else np.nan
        )
    else:
        df["asset_age"] = np.nan

    # auction_duration_hours
    if "start_date" in df.columns and "end_date" in df.columns:
        start = _to_naive(df["start_date"])
        end = _to_naive(df["end_date"])
        diff = (end - start).dt.total_seconds() / 3600.0
        df["auction_duration_hours"] = diff
    else:
        df["auction_duration_hours"] = np.nan

    # bid_momentum
    if "total_bids" in df.columns:
        duration = df["auction_duration_hours"] if "auction_duration_hours" in df.columns else pd.Series(np.nan, index=df.index)
        total_bids = pd.to_numeric(df["total_bids"], errors="coerce")
        dur_safe = duration.where((duration > 0) & duration.notna(), other=np.nan)
        momentum = total_bids / dur_safe
        df["bid_momentum"] = momentum.fillna(0.0)
    else:
        df["bid_momentum"] = 0.0

    # view_to_bid_ratio
    if "views_count" in df.columns and "total_bids" in df.columns:
        views = pd.to_numeric(df["views_count"], errors="coerce").fillna(0.0)
        bids = pd.to_numeric(df["total_bids"], errors="coerce").fillna(0.0)
        df["view_to_bid_ratio"] = np.where(bids > 0, views / bids, 0.0)
    else:
        df["view_to_bid_ratio"] = 0.0

    # time_to_first_bid_hours
    if "time_of_first_bid" in df.columns and "start_date" in df.columns:
        first_bid = _to_naive(df["time_of_first_bid"])
        start = _to_naive(df["start_date"])
        df["time_to_first_bid_hours"] = (first_bid - start).dt.total_seconds() / 3600.0
    else:
        df["time_to_first_bid_hours"] = np.nan

    # days_until_close
    if "end_date" in df.columns:
        end_naive = _to_naive(df["end_date"])
        now_naive = pd.Timestamp.now()
        df["days_until_close"] = (end_naive - now_naive).dt.total_seconds() / 86400.0
    else:
        df["days_until_close"] = np.nan

    # bid_acceleration
    if "total_bids" in df.columns and "start_date" in df.columns:
        start_naive = _to_naive(df["start_date"])
        now_naive = pd.Timestamp.now()
        days_since_start = (now_naive - start_naive).dt.total_seconds() / 86400.0
        days_clamped = days_since_start.clip(lower=0.5)
        total_bids = pd.to_numeric(df["total_bids"], errors="coerce").fillna(0.0)
        acc = total_bids / days_clamped
        df["bid_acceleration"] = acc.where(start_naive.notna(), other=0.0).fillna(0.0)
    else:
        df["bid_acceleration"] = 0.0

    # is_first_bid_quick
    if "time_to_first_bid_hours" in df.columns:
        ttfb = df["time_to_first_bid_hours"]
        df["is_first_bid_quick"] = np.where(
            ttfb.notna() & (ttfb <= 2.0), 1, 0
        ).astype(int)
    else:
        df["is_first_bid_quick"] = 0

    # has_description
    if "description" in df.columns:
        def _has_desc(val) -> int:
            try:
                if pd.isna(val):
                    return 0
            except (TypeError, ValueError):
                pass
            return int(len(str(val).strip()) > 0)
        df["has_description"] = df["description"].apply(_has_desc)
    else:
        df["has_description"] = 0

    # has_images
    if "photo_urls" in df.columns:
        df["has_images"] = df["photo_urls"].apply(_has_images)
    else:
        df["has_images"] = 0

    # price_tier
    if "starting_price" in df.columns:
        bins = [-np.inf] + PRICE_TIER_BOUNDARIES + [np.inf]
        df["price_tier"] = pd.cut(
            pd.to_numeric(df["starting_price"], errors="coerce"),
            bins=bins,
            labels=PRICE_TIER_LABELS,
        ).astype("object")
    else:
        df["price_tier"] = np.nan

    return df
