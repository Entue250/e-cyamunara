"""Build a pipeline-ready single-row DataFrame from a raw features dict.

Two invariants the sklearn pipeline requires at inference time that are NOT
obvious from the feature schema alone:

1. CREATION_ZERO_COLUMNS must be present in the DataFrame for ALL models.
   The Log1pTransformer was fitted on training data that always had total_bids,
   views_count, etc. (even for creation-context Model A rows). Its columns_
   attribute includes them, so they must exist at transform time — otherwise
   KeyError inside Log1pTransformer.transform().

2. Numeric columns that arrive as Python None produce object-dtype Series.
   np.log1p cannot operate on object dtype ("loop of ufunc does not support
   argument 0 of type float which has no callable log1p method"). Coercing to
   float64 turns None → NaN, which is valid for log1p and handled by XGBoost.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

# These columns must be present for Log1pTransformer (fitted on data that had them).
# Values default to zero — override with request values where present.
_CREATION_ZERO_DEFAULTS: dict[str, float] = {
    "total_bids": 0.0,
    "views_count": 0.0,
    "unique_bidder_count": 0.0,
    "bid_momentum": 0.0,
    "view_to_bid_ratio": 0.0,
    "bid_acceleration": 0.0,
    "is_first_bid_quick": 0,
}

# Columns that must be float64, not object, before the pipeline runs.
_NUMERIC_COLS: frozenset[str] = frozenset({
    "manufacturing_year",
    "mileage",
    "starting_price",
    "total_bids",
    "unique_bidder_count",
    "views_count",
    "asset_age",
    "auction_duration_hours",
})


def build_inference_df(features_dict: dict) -> pd.DataFrame:
    """Return a single-row DataFrame ready for pipeline.transform().

    Parameters
    ----------
    features_dict:
        Raw Pydantic model_dump() output from the request — raw Supabase fields
        (manufacturing_year, start_date, etc.), NOT pre-computed derived features.
    """
    # Merge creation-zero defaults UNDER request features so the caller's values win
    row = {**_CREATION_ZERO_DEFAULTS, **features_dict}
    df = pd.DataFrame([row])

    # Coerce numeric columns from object dtype (Python None → NaN)
    for col in _NUMERIC_COLS:
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")

    return df
