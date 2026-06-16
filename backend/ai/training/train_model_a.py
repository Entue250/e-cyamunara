"""
training/train_model_a.py
=========================
Train Model A — market value estimation.

Model A estimates the fair market value of a vehicle at auction time.
Target column  : winning_amount (closed auctions with a confirmed sale)
Training rows  : auction_status == 'closed' AND winning_amount IS NOT NULL
Context        : "creation" (forced by build_pipeline — no live engagement signals)
Target transform: np.log1p for training; metrics evaluated on both log and RWF scales.

The output helps clients understand whether a listed auction is undervalued,
fairly priced, or overpriced relative to what similar vehicles have sold for.

Run from backend/ai/:
    python -m training.train_model_a
    python -m training.train_model_a --data path/to/auctions.csv
    python -m training.train_model_a --no-save
"""

from __future__ import annotations

import argparse
import json
import pathlib
from dataclasses import asdict

import joblib
import numpy as np
import xgboost as xgb
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from training.config import CONFIG
from training.datasets.loaders import load_auctions, describe_auctions
from training.datasets.filters import (
    filter_closed,
    filter_has_winning_amount,
    require_min_rows,
    MIN_ROWS_REAL_AB,
    MIN_ROWS_SYNTHETIC_AB,
)
from training.datasets.splitter import temporal_split, split_summary
from training.preprocessing.pipeline_builder import build_pipeline


# ---------------------------------------------------------------------------
# Metric computation
# ---------------------------------------------------------------------------

def compute_metrics(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    y_true_log: np.ndarray | None = None,
    y_pred_log: np.ndarray | None = None,
) -> dict:
    """Return evaluation metrics on the original RWF scale, plus log-scale R².

    Parameters
    ----------
    y_true : np.ndarray
        Ground-truth winning amounts in RWF (original scale).
    y_pred : np.ndarray
        Predicted market values in RWF (original scale, via expm1).
    y_true_log : np.ndarray | None
        Ground-truth in log1p space — if supplied, r2_log is computed.
    y_pred_log : np.ndarray | None
        Predicted values in log1p space — if supplied, r2_log is computed.

    Returns
    -------
    dict with keys:
        mae_rwf    – Mean Absolute Error in RWF
        rmse_rwf   – Root Mean Squared Error in RWF
        mape       – Mean Absolute Percentage Error (fraction, e.g. 0.15 = 15%)
        median_ape – Median APE (robust to outliers)
        r2         – Original-scale R² (informational; not used for gating)
        r2_log     – Log-scale R² (primary acceptance gate metric)
    """
    mae = mean_absolute_error(y_true, y_pred)
    rmse = float(np.sqrt(mean_squared_error(y_true, y_pred)))
    ape = np.abs((y_true - y_pred) / np.maximum(y_true, 1.0))
    mape = float(np.mean(ape))
    median_ape = float(np.median(ape))
    r2 = float(r2_score(y_true, y_pred))

    result = {
        "mae_rwf":    float(mae),
        "rmse_rwf":   rmse,
        "mape":       mape,
        "median_ape": median_ape,
        "r2":         r2,
    }

    if y_true_log is not None and y_pred_log is not None:
        result["r2_log"] = float(r2_score(y_true_log, y_pred_log))

    return result


# ---------------------------------------------------------------------------
# Threshold checks (informational — run_model_a uses acceptance.check_model_a)
# ---------------------------------------------------------------------------

def check_thresholds(metrics: dict, thresholds) -> list[str]:
    """Compare metrics against thresholds; return list of warning strings."""
    warnings: list[str] = []

    r2_log = metrics.get("r2_log", metrics.get("r2", 0.0))
    if r2_log < thresholds.r2_min:
        warnings.append(
            f"FAIL r2_log: {r2_log:.4f} < min {thresholds.r2_min:.4f}"
        )

    mape = metrics.get("mape", 1.0)
    if mape > thresholds.mape_min:
        warnings.append(
            f"FAIL mape: {mape:.4f} > min {thresholds.mape_min:.4f}"
        )

    return warnings


# ---------------------------------------------------------------------------
# Main training routine
# ---------------------------------------------------------------------------

def train(
    data_path: pathlib.Path | None = None,
    save: bool = True,
    datasource: str = "synthetic",
) -> tuple[object, object, dict]:
    """Train Model A (market value estimation) and optionally persist artifacts.

    Parameters
    ----------
    data_path : pathlib.Path | None
        Path to the auctions CSV.  Defaults to CONFIG.paths.synthetic_auctions.
    save : bool
        When True, write pipeline, XGBoost model, and metrics JSON to
        CONFIG.paths.models_dir.

    Returns
    -------
    (pipeline, xgb_model, metrics_dict)
    """
    # ------------------------------------------------------------------
    # 1. Load data
    # ------------------------------------------------------------------
    df = load_auctions(data_path)
    print(describe_auctions(df))

    # ------------------------------------------------------------------
    # 2. Filter to closed auctions with a confirmed sale price
    # ------------------------------------------------------------------
    df = filter_closed(df)
    print(f"Rows after filter_closed: {len(df):,}")

    df = filter_has_winning_amount(df)
    print(f"Rows after filter_has_winning_amount: {len(df):,}")

    # ------------------------------------------------------------------
    # 3. Enforce minimum dataset size (datasource-aware)
    # ------------------------------------------------------------------
    _min_rows = MIN_ROWS_REAL_AB if datasource == "real" else MIN_ROWS_SYNTHETIC_AB
    require_min_rows(df, _min_rows, label="model_a")

    # ------------------------------------------------------------------
    # 4. Temporal split
    # ------------------------------------------------------------------
    train_df, val_df, test_df = temporal_split(df)
    print(split_summary(train_df, val_df, test_df, "winning_amount"))

    # ------------------------------------------------------------------
    # 5. Extract targets; log1p-transform train/val, keep test in RWF
    # ------------------------------------------------------------------
    y_train     = np.log1p(train_df["winning_amount"].values.astype(float))
    y_val       = np.log1p(val_df["winning_amount"].values.astype(float))
    y_test      = test_df["winning_amount"].values.astype(float)   # original RWF scale
    y_test_log  = np.log1p(y_test)                                  # log scale for r2_log

    # ------------------------------------------------------------------
    # 6. Build and fit preprocessing pipeline
    # ------------------------------------------------------------------
    pipeline = build_pipeline("model_a")
    print("Fitting preprocessing pipeline...")
    X_train = pipeline.fit_transform(train_df, y_train)
    X_val   = pipeline.transform(val_df)
    X_test  = pipeline.transform(test_df)
    print(f"  Feature matrix shape: {X_train.shape}")

    # ------------------------------------------------------------------
    # 7. Build and train XGBoost model
    # ------------------------------------------------------------------
    params = asdict(CONFIG.price_hyperparams)
    model = xgb.XGBRegressor(**params)
    print("Training XGBoost (Model A — market value)...")
    model.fit(
        X_train, y_train,
        eval_set=[(X_val, y_val)],
        verbose=False,
    )
    n_trees = (
        model.best_iteration + 1
        if hasattr(model, "best_iteration") and model.best_iteration
        else params["n_estimators"]
    )
    print(
        f"  Stopped at {n_trees} trees "
        f"(early stopping rounds={params['early_stopping_rounds']})"
    )

    # ------------------------------------------------------------------
    # 8. Evaluate on test set — both log and original RWF scale
    # ------------------------------------------------------------------
    y_pred_log = model.predict(X_test)
    y_pred     = np.expm1(y_pred_log)
    metrics    = compute_metrics(y_test, y_pred, y_test_log, y_pred_log)

    # ------------------------------------------------------------------
    # 9. Print metrics report
    # ------------------------------------------------------------------
    t = CONFIG.winning_bid_thresholds
    print()
    print("Model A — Market Value Estimation — Test Set Metrics")
    print("─────────────────────────────────────────────────────")
    print(
        f"R2 (log)  : {metrics['r2_log']:>12.4f}     "
        f"(target >= {t.r2_target:>8.2f}  | min >= {t.r2_min:>8.2f})"
    )
    print(
        f"R2 (orig) : {metrics['r2']:>12.4f}     (informational only)"
    )
    print(
        f"MAE       : {metrics['mae_rwf']:>12,.0f} RWF  "
        f"(target <= {t.mae_rwf_target:>10,.0f})"
    )
    print(
        f"RMSE      : {metrics['rmse_rwf']:>12,.0f} RWF"
    )
    print(
        f"MAPE      : {metrics['mape'] * 100:>11.2f}%      "
        f"(target <= {t.mape_target * 100:>8.2f}% | min <= {t.mape_min * 100:>8.2f}%)"
    )
    print(
        f"Median APE: {metrics['median_ape'] * 100:>11.2f}%"
    )
    print()

    # ------------------------------------------------------------------
    # 10. Threshold checks
    # ------------------------------------------------------------------
    warnings = check_thresholds(metrics, CONFIG.winning_bid_thresholds)
    if warnings:
        print("Threshold warnings:")
        for w in warnings:
            print(f"  {w}")
    else:
        print("All thresholds passed.")

    # ------------------------------------------------------------------
    # 11. Persist artifacts (optional)
    # ------------------------------------------------------------------
    if save:
        models_dir = CONFIG.paths.models_dir
        models_dir.mkdir(parents=True, exist_ok=True)

        pipeline_path = models_dir / "model_a_pipeline.joblib"
        joblib.dump(pipeline, pipeline_path)
        print(f"  Pipeline saved : {pipeline_path}")

        model_path = models_dir / "model_a_xgb.ubj"
        model.save_model(str(model_path))
        print(f"  XGBoost model  : {model_path}")

        metrics_path = models_dir / "model_a_metrics.json"
        metrics_record = {"model": "model_a", **metrics, "n_trees": n_trees}
        metrics_path.write_text(
            json.dumps(metrics_record, indent=2), encoding="utf-8"
        )
        print(f"  Metrics JSON   : {metrics_path}")

    # ------------------------------------------------------------------
    # 12. Return artifacts
    # ------------------------------------------------------------------
    return pipeline, model, metrics


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train Model A — market value estimation"
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        help="Path to auctions CSV",
    )
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="Skip saving artifacts",
    )
    args = parser.parse_args()
    train(data_path=args.data, save=not args.no_save)


if __name__ == "__main__":
    main()
