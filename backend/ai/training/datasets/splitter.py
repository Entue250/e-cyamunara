from __future__ import annotations

import numpy as np
import pandas as pd

from ..config import CONFIG, SplitConfig


def temporal_split(
    df: pd.DataFrame,
    config: SplitConfig | None = None,
) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame]:
    """Split df into (train, val, test) by temporal order."""
    cfg = config if config is not None else CONFIG.split

    sort_key = pd.to_datetime(df[cfg.temporal_col], errors="coerce")
    sorted_df = df.iloc[sort_key.argsort(kind="mergesort")]

    n_total = len(sorted_df)
    n_test = max(cfg.min_test_rows, int(n_total * cfg.test_pct))
    n_val = max(cfg.min_val_rows, int((n_total - n_test) * cfg.val_pct))
    n_train = n_total - n_test - n_val

    if n_train <= 0:
        raise ValueError(
            f"Dataset too small to split: {n_total} rows. "
            f"Need at least {n_test + n_val + 1} rows."
        )

    train_df = sorted_df.iloc[:n_train].reset_index(drop=True)
    val_df = sorted_df.iloc[n_train:n_train + n_val].reset_index(drop=True)
    test_df = sorted_df.iloc[n_train + n_val:].reset_index(drop=True)

    return train_df, val_df, test_df


def split_summary(
    train: pd.DataFrame,
    val: pd.DataFrame,
    test: pd.DataFrame,
    target_col: str,
) -> str:
    """Return a formatted summary string of split sizes and target statistics."""
    total = len(train) + len(val) + len(test)
    lines = [
        f"Split sizes: train={len(train):<8} val={len(val):<8} "
        f"test={len(test):<8} total={total}"
    ]

    if target_col in train.columns:
        lines.append(f"Target statistics ({target_col}):")
        for name, frame in (("train", train), ("val", val), ("test", test)):
            col = frame[target_col]
            mean = int(round(col.mean()))
            median = int(round(col.median()))
            mn = int(col.min())
            mx = int(col.max())
            lines.append(
                f"  {name:<6} mean={mean:,}  median={median:,}  "
                f"min={mn:,}  max={mx:,}"
            )

    return "\n".join(lines)
