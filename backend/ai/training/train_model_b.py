"""
training/train_model_b.py
=========================
Train Model B — winning bid prediction.

Loads the synthetic auctions dataset, filters to closed auctions that have a
recorded winning amount, applies a log1p target transform, trains an XGBoost
regressor inside a sklearn Pipeline, evaluates against acceptance thresholds,
and serialises the pipeline + booster + metrics to disk.

Usage::

    python -m training.train_model_b
    python -m training.train_model_b --data path/to/auctions.csv
    python -m training.train_model_b --out-dir path/to/models/
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
from training.datasets.filters import filter_closed, filter_has_winning_amount, require_min_rows
from training.datasets.splitter import temporal_split, split_summary
from training.preprocessing.pipeline_builder import build_pipeline

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
TARGET_COL = "winning_amount"
MODEL_NAME = "model_b"
CONTEXT = "bidding"

PIPELINE_FILENAME = "model_b_pipeline.joblib"
BOOSTER_FILENAME = "model_b_xgb.ubj"
METRICS_FILENAME = "model_b_metrics.json"


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------
def compute_metrics(y_true_log: np.ndarray, y_pred_log: np.ndarray) -> dict[str, float]:
    """Compute MAE, RMSE, MAPE, and R² on the original (RWF) scale.

    Parameters
    ----------
    y_true_log:
        True target values in log1p space.
    y_pred_log:
        Predicted target values in log1p space.

    Returns
    -------
    dict with keys: mae_rwf, rmse_rwf, mape, r2
    """
    y_true = np.expm1(y_true_log)
    y_pred = np.expm1(y_pred_log)

    mae = float(mean_absolute_error(y_true, y_pred))
    rmse = float(np.sqrt(mean_squared_error(y_true, y_pred)))

    # MAPE — guard against zero targets to avoid division by zero
    nonzero_mask = y_true != 0.0
    if nonzero_mask.sum() == 0:
        mape = float("nan")
    else:
        mape = float(np.mean(np.abs((y_true[nonzero_mask] - y_pred[nonzero_mask]) / y_true[nonzero_mask])))

    r2 = float(r2_score(y_true, y_pred))

    return {"mae_rwf": mae, "rmse_rwf": rmse, "mape": mape, "r2": r2}


# ---------------------------------------------------------------------------
# Threshold checks
# ---------------------------------------------------------------------------
def check_thresholds(metrics: dict[str, float]) -> list[str]:
    """Return a list of failure messages (empty list = all thresholds passed).

    Uses ``CONFIG.winning_bid_thresholds`` as the acceptance criteria.
    """
    thresholds = CONFIG.winning_bid_thresholds
    failures: list[str] = []

    if metrics["mae_rwf"] > thresholds.mae_rwf_min:
        failures.append(
            f"MAE {metrics['mae_rwf']:,.0f} RWF exceeds minimum {thresholds.mae_rwf_min:,.0f} RWF"
        )

    if metrics["rmse_rwf"] > thresholds.rmse_rwf_min:
        failures.append(
            f"RMSE {metrics['rmse_rwf']:,.0f} RWF exceeds minimum {thresholds.rmse_rwf_min:,.0f} RWF"
        )

    if metrics["mape"] > thresholds.mape_min:
        failures.append(
            f"MAPE {metrics['mape'] * 100:.2f}% exceeds minimum {thresholds.mape_min * 100:.2f}%"
        )

    if metrics["r2"] < thresholds.r2_min:
        failures.append(
            f"R² {metrics['r2']:.4f} is below minimum {thresholds.r2_min:.4f}"
        )

    return failures


# ---------------------------------------------------------------------------
# Metrics report
# ---------------------------------------------------------------------------
def print_metrics_report(metrics: dict[str, float]) -> None:
    """Print a formatted metrics report to stdout."""
    thresholds = CONFIG.winning_bid_thresholds

    header = "Model B — Test Set Metrics"
    separator = "─" * len(header)

    print(header)
    print(separator)
    print(
        f"MAE       : {metrics['mae_rwf']:>12,.0f} RWF  "
        f"(target ≤ {thresholds.mae_rwf_target:>10,.0f} | "
        f"min ≤ {thresholds.mae_rwf_min:>10,.0f})"
    )
    print(
        f"RMSE      : {metrics['rmse_rwf']:>12,.0f} RWF  "
        f"(target ≤ {thresholds.rmse_rwf_target:>10,.0f} | "
        f"min ≤ {thresholds.rmse_rwf_min:>10,.0f})"
    )
    print(
        f"MAPE      : {metrics['mape'] * 100:>11.2f}%      "
        f"(target ≤ {thresholds.mape_target * 100:>9.2f}% | "
        f"min ≤ {thresholds.mape_min * 100:>9.2f}%)"
    )
    print(
        f"R²        : {metrics['r2']:>12.4f}     "
        f"(target ≥ {thresholds.r2_target:>9.2f}  | "
        f"min ≥ {thresholds.r2_min:>9.2f})"
    )


# ---------------------------------------------------------------------------
# Main training routine
# ---------------------------------------------------------------------------
def train(
    data_path: pathlib.Path | None = None,
    out_dir: pathlib.Path | None = None,
) -> dict[str, float]:
    """Run the full Model B training pipeline.

    Parameters
    ----------
    data_path:
        Optional override for the CSV path.  Defaults to
        ``CONFIG.paths.synthetic_auctions``.
    out_dir:
        Optional override for the output directory.  Defaults to
        ``CONFIG.paths.models_dir``.

    Returns
    -------
    dict of test-set metrics (original scale).
    """
    out_dir = out_dir if out_dir is not None else CONFIG.paths.models_dir
    out_dir = pathlib.Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # 1. Load
    # ------------------------------------------------------------------
    print("Loading auctions ...")
    df = load_auctions(data_path)
    print(describe_auctions(df))
    print()

    # ------------------------------------------------------------------
    # 2. Filter
    # ------------------------------------------------------------------
    df = filter_closed(df)
    df = filter_has_winning_amount(df)
    require_min_rows(df, 5_000, label="model_b")

    print(f"After filtering: {len(df):,} rows")
    print()

    # ------------------------------------------------------------------
    # 3. Split
    # ------------------------------------------------------------------
    train_df, val_df, test_df = temporal_split(df)
    print(split_summary(train_df, val_df, test_df, TARGET_COL))
    print()

    # ------------------------------------------------------------------
    # 4. Prepare features / targets
    # ------------------------------------------------------------------
    X_train = train_df.drop(columns=[TARGET_COL])
    y_train_raw = train_df[TARGET_COL].values.astype(float)
    y_train = np.log1p(y_train_raw)

    X_val = val_df.drop(columns=[TARGET_COL])
    y_val_raw = val_df[TARGET_COL].values.astype(float)
    y_val = np.log1p(y_val_raw)

    X_test = test_df.drop(columns=[TARGET_COL])
    y_test_raw = test_df[TARGET_COL].values.astype(float)
    y_test = np.log1p(y_test_raw)

    # ------------------------------------------------------------------
    # 5. Build preprocessing pipeline and transform
    # ------------------------------------------------------------------
    print("Building preprocessing pipeline ...")
    pipeline = build_pipeline(MODEL_NAME, CONTEXT)

    print("Fitting preprocessing pipeline on training data ...")
    X_train_t = pipeline.fit_transform(X_train, y_train)
    X_val_t = pipeline.transform(X_val)
    X_test_t = pipeline.transform(X_test)

    # ------------------------------------------------------------------
    # 6. Build XGBoost DMatrix objects
    # ------------------------------------------------------------------
    dtrain = xgb.DMatrix(X_train_t, label=y_train)
    dval = xgb.DMatrix(X_val_t, label=y_val)
    dtest = xgb.DMatrix(X_test_t, label=y_test)

    # ------------------------------------------------------------------
    # 7. Train XGBoost
    # ------------------------------------------------------------------
    hp = CONFIG.winning_bid_hyperparams

    xgb_params = {
        "objective": "reg:squarederror",
        "max_depth": hp.max_depth,
        "learning_rate": hp.learning_rate,
        "subsample": hp.subsample,
        "colsample_bytree": hp.colsample_bytree,
        "reg_alpha": hp.reg_alpha,
        "reg_lambda": hp.reg_lambda,
        "min_child_weight": hp.min_child_weight,
        "seed": hp.random_state,
        "tree_method": "hist",
    }

    print("Training XGBoost model ...")
    booster = xgb.train(
        params=xgb_params,
        dtrain=dtrain,
        num_boost_round=hp.n_estimators,
        evals=[(dtrain, "train"), (dval, "val")],
        early_stopping_rounds=hp.early_stopping_rounds,
        verbose_eval=50,
    )

    print(f"Best iteration: {booster.best_iteration}")
    print()

    # ------------------------------------------------------------------
    # 8. Evaluate on test set
    # ------------------------------------------------------------------
    y_pred_log = booster.predict(dtest, iteration_range=(0, booster.best_iteration + 1))
    metrics = compute_metrics(y_test, y_pred_log)

    print_metrics_report(metrics)
    print()

    # ------------------------------------------------------------------
    # 9. Threshold check
    # ------------------------------------------------------------------
    failures = check_thresholds(metrics)
    if failures:
        print("THRESHOLD FAILURES:")
        for msg in failures:
            print(f"  - {msg}")
        print()
    else:
        print("All thresholds passed.")
        print()

    # ------------------------------------------------------------------
    # 10. Serialise artifacts
    # ------------------------------------------------------------------
    pipeline_path = out_dir / PIPELINE_FILENAME
    booster_path = out_dir / BOOSTER_FILENAME
    metrics_path = out_dir / METRICS_FILENAME

    joblib.dump(pipeline, pipeline_path)
    print(f"Pipeline saved  : {pipeline_path}")

    booster.save_model(str(booster_path))
    print(f"Booster saved   : {booster_path}")

    thresholds = CONFIG.winning_bid_thresholds
    metrics_payload = {
        "model": MODEL_NAME,
        "metrics": metrics,
        "thresholds": asdict(thresholds),
        "passed": len(failures) == 0,
        "failures": failures,
        "best_iteration": int(booster.best_iteration),
        "train_rows": len(train_df),
        "val_rows": len(val_df),
        "test_rows": len(test_df),
    }
    with metrics_path.open("w", encoding="utf-8") as fh:
        json.dump(metrics_payload, fh, indent=2)
    print(f"Metrics saved   : {metrics_path}")

    if failures:
        raise SystemExit(
            f"Model B did not meet acceptance thresholds ({len(failures)} failure(s)). "
            "See output above for details."
        )

    return metrics


# ---------------------------------------------------------------------------
# CLI entry-point
# ---------------------------------------------------------------------------
def main() -> None:
    """Train Model B — winning bid prediction."""
    parser = argparse.ArgumentParser(
        description="Train Model B — winning bid prediction"
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        metavar="PATH",
        help="Path to the auctions CSV (default: CONFIG.paths.synthetic_auctions)",
    )
    parser.add_argument(
        "--out-dir",
        type=pathlib.Path,
        default=None,
        metavar="DIR",
        help="Directory to write model artifacts (default: CONFIG.paths.models_dir)",
    )
    args = parser.parse_args()

    train(data_path=args.data, out_dir=args.out_dir)


if __name__ == "__main__":
    main()
