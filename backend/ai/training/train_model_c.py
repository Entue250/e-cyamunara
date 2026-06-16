"""
training/train_model_c.py
=========================
Train Model C — Bid Probability Classification.

Predicts P(auction receives >= 1 bid) as a binary classification task.
Target: (total_bids > 0).astype(int)
Filter: closed auctions only (filter_closed)
Context: "bidding" (engagement features included)
Calibration: Platt scaling via CalibratedClassifierCV(method='sigmoid', cv='prefit')
             fitted on the validation set after XGBoost training.

Usage:
    python -m training.train_model_c
    python -m training.train_model_c --data /path/to/auctions.csv
    python -m training.train_model_c --no-save
"""

from __future__ import annotations

import argparse
import json
import pathlib
from dataclasses import asdict

import joblib
import numpy as np
import xgboost as xgb
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    roc_auc_score,
    average_precision_score,
    f1_score,
    precision_score,
    recall_score,
)

from training.config import CONFIG
from training.datasets.loaders import load_auctions, describe_auctions
from training.datasets.filters import (
    filter_closed,
    require_min_rows,
    require_min_bid_events,
    MIN_ROWS_REAL_C,
    MIN_ROWS_SYNTHETIC_C,
    MIN_BID_EVENTS_REAL_C,
)
from training.datasets.splitter import temporal_split, split_summary
from training.preprocessing.pipeline_builder import build_pipeline


# ---------------------------------------------------------------------------
# Platt scaling (replaces sklearn CalibratedClassifierCV cv="prefit",
# which was removed in sklearn 1.6+)
# ---------------------------------------------------------------------------

class PlattScaler:
    """Sigmoid calibration wrapper for a pre-fitted binary classifier.

    Equivalent to the old ``CalibratedClassifierCV(cv="prefit", method="sigmoid")``:
    fits a logistic regression over the raw probability outputs of *estimator*
    using a held-out calibration set, then rescales predictions at inference time.

    Fully serialisable with joblib.
    """

    def __init__(self, estimator):
        self.estimator = estimator  # pre-fitted XGBClassifier
        self._lr: LogisticRegression | None = None

    def fit(self, X, y) -> "PlattScaler":
        raw = self.estimator.predict_proba(X)[:, 1].reshape(-1, 1)
        self._lr = LogisticRegression(C=1.0, max_iter=1_000)
        self._lr.fit(raw, y)
        return self

    def predict_proba(self, X) -> np.ndarray:
        raw = self.estimator.predict_proba(X)[:, 1].reshape(-1, 1)
        p = self._lr.predict_proba(raw)[:, 1]
        return np.column_stack([1.0 - p, p])

    def predict(self, X) -> np.ndarray:
        return (self.predict_proba(X)[:, 1] >= 0.5).astype(int)


# ---------------------------------------------------------------------------
# Calibration metric helpers
# ---------------------------------------------------------------------------

def compute_ece(y_true: np.ndarray, y_prob: np.ndarray, n_bins: int = 10) -> float:
    """Compute Expected Calibration Error (ECE).

    ECE measures the average gap between predicted confidence and actual
    accuracy across probability bins.  Lower is better; 0.0 is perfect.

    Parameters
    ----------
    y_true : np.ndarray
        Binary ground-truth labels (0 or 1).
    y_prob : np.ndarray
        Predicted probabilities for the positive class.
    n_bins : int
        Number of equal-width probability bins in [0, 1].

    Returns
    -------
    float
        Expected Calibration Error in [0, 1].
    """
    bins = np.linspace(0, 1, n_bins + 1)
    ece = 0.0
    for lo, hi in zip(bins[:-1], bins[1:]):
        mask = (y_prob >= lo) & (y_prob < hi)
        if mask.sum() > 0:
            acc = float(y_true[mask].mean())
            conf = float(y_prob[mask].mean())
            ece += mask.mean() * abs(acc - conf)
    return float(ece)


# ---------------------------------------------------------------------------
# Metrics
# ---------------------------------------------------------------------------

def compute_metrics(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    threshold: float = 0.5,
) -> dict:
    """Compute classification metrics for the bid-probability model.

    Parameters
    ----------
    y_true : np.ndarray
        Binary ground-truth labels (0 or 1).
    y_prob : np.ndarray
        Predicted probabilities for the positive class.
    threshold : float
        Decision threshold for converting probabilities to binary predictions.

    Returns
    -------
    dict
        Dictionary with keys: auc_roc, pr_auc, f1, precision, recall, ece.
    """
    y_pred = (y_prob >= threshold).astype(int)
    return {
        "auc_roc":   float(roc_auc_score(y_true, y_prob)),
        "pr_auc":    float(average_precision_score(y_true, y_prob)),
        "f1":        float(f1_score(y_true, y_pred, zero_division=0)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall":    float(recall_score(y_true, y_pred, zero_division=0)),
        "ece":       compute_ece(y_true, y_prob),
    }


# ---------------------------------------------------------------------------
# Threshold checks
# ---------------------------------------------------------------------------

def check_thresholds(metrics: dict, thresholds) -> list[str]:
    """Check metrics against CONFIG.bid_prob_thresholds.

    Parameters
    ----------
    metrics : dict
        Output of compute_metrics().
    thresholds : BidProbabilityThresholds
        Threshold dataclass from CONFIG.bid_prob_thresholds.

    Returns
    -------
    list[str]
        A list of human-readable failure strings.  Empty list means all checks
        passed.
    """
    failures: list[str] = []

    if metrics["auc_roc"] < thresholds.auc_roc_min:
        failures.append(
            f"FAIL auc_roc: {metrics['auc_roc']:.4f} < min {thresholds.auc_roc_min:.4f}"
        )

    if metrics["pr_auc"] < thresholds.pr_auc_min:
        failures.append(
            f"FAIL pr_auc: {metrics['pr_auc']:.4f} < min {thresholds.pr_auc_min:.4f}"
        )

    if metrics["f1"] < thresholds.f1_min:
        failures.append(
            f"FAIL f1: {metrics['f1']:.4f} < min {thresholds.f1_min:.4f}"
        )

    if metrics["precision"] < thresholds.precision_min:
        failures.append(
            f"FAIL precision: {metrics['precision']:.4f} < min {thresholds.precision_min:.4f}"
        )

    if metrics["recall"] < thresholds.recall_min:
        failures.append(
            f"FAIL recall: {metrics['recall']:.4f} < min {thresholds.recall_min:.4f}"
        )

    if metrics["ece"] > thresholds.ece_max:
        failures.append(
            f"FAIL ece: {metrics['ece']:.4f} > max {thresholds.ece_max:.4f}"
        )

    return failures


# ---------------------------------------------------------------------------
# Training entry point
# ---------------------------------------------------------------------------

def train(
    data_path: pathlib.Path | None = None,
    save: bool = True,
    datasource: str = "synthetic",
) -> tuple:
    """Train Model C end-to-end and optionally persist artefacts.

    Parameters
    ----------
    data_path : pathlib.Path | None
        Path to the auctions CSV.  Defaults to CONFIG.paths.synthetic_auctions.
    save : bool
        If True, serialise the pipeline, calibrated model, native XGBoost model,
        and metrics JSON to CONFIG.paths.models_dir.

    Returns
    -------
    tuple
        (pipeline, calibrated_model, metrics_dict)
    """
    # ------------------------------------------------------------------
    # 1. Load data
    # ------------------------------------------------------------------
    print("Loading auctions data...")
    df = load_auctions(data_path)
    print(describe_auctions(df))

    # ------------------------------------------------------------------
    # 2. Filter to closed auctions only
    # ------------------------------------------------------------------
    df = filter_closed(df)
    print(f"\nAfter filter_closed: {len(df):,} rows")

    # ------------------------------------------------------------------
    # 3. Enforce minimum row count (datasource-aware)
    # ------------------------------------------------------------------
    _min_rows = MIN_ROWS_REAL_C if datasource == "real" else MIN_ROWS_SYNTHETIC_C
    require_min_rows(df, _min_rows, label="model_c")
    if datasource == "real":
        require_min_bid_events(df, MIN_BID_EVENTS_REAL_C, label="model_c")

    # ------------------------------------------------------------------
    # 4. Build binary label BEFORE split
    # ------------------------------------------------------------------
    df["bid_placed"] = (df["total_bids"].fillna(0) > 0).astype(int)
    n_neg = int((df["bid_placed"] == 0).sum())
    n_pos = int((df["bid_placed"] == 1).sum())
    pos_rate = n_pos / len(df)
    print(
        f"Class distribution: 0={n_neg:,}  1={n_pos:,}  "
        f"pos_rate={pos_rate:.1%}"
    )

    # ------------------------------------------------------------------
    # 5. Temporal split
    # ------------------------------------------------------------------
    train_df, val_df, test_df = temporal_split(df)
    print("\n" + split_summary(train_df, val_df, test_df, "bid_placed"))

    # ------------------------------------------------------------------
    # 6. Extract targets
    # ------------------------------------------------------------------
    y_train = train_df["bid_placed"].values.astype(int)
    y_val   = val_df["bid_placed"].values.astype(int)
    y_test  = test_df["bid_placed"].values.astype(int)

    # ------------------------------------------------------------------
    # 7. Build pipeline and transform
    # ------------------------------------------------------------------
    pipeline = build_pipeline("model_c", "bidding")
    print("\nFitting preprocessing pipeline...")
    X_train = pipeline.fit_transform(train_df, y_train)
    X_val   = pipeline.transform(val_df)
    X_test  = pipeline.transform(test_df)
    print(f"  Feature matrix shape: {X_train.shape}")

    # ------------------------------------------------------------------
    # 8. Train XGBoost classifier
    # ------------------------------------------------------------------
    params = asdict(CONFIG.bid_prob_hyperparams)
    # Remove Logistic Regression calibration keys — XGBClassifier doesn't accept them
    params.pop("lr_c", None)
    params.pop("lr_max_iter", None)
    # CONFIG uses lr_C (capital C); pop that variant too in case dataclass serialises it
    params.pop("lr_C", None)

    model = xgb.XGBClassifier(**params, eval_metric="logloss")
    print("\nTraining XGBoost classifier (Model C)...")
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
    print(f"  Stopped at {n_trees} trees")

    # ------------------------------------------------------------------
    # 9. Platt calibration on val set
    # ------------------------------------------------------------------
    print("Calibrating with Platt scaling on val set...")
    calibrated = PlattScaler(model)
    calibrated.fit(X_val, y_val)

    # ------------------------------------------------------------------
    # 10. Evaluate on test set
    # ------------------------------------------------------------------
    y_prob = calibrated.predict_proba(X_test)[:, 1]
    metrics = compute_metrics(y_test, y_prob)

    # ------------------------------------------------------------------
    # 11. Print metrics report
    # ------------------------------------------------------------------
    thresholds = CONFIG.bid_prob_thresholds
    print("\nModel C — Test Set Metrics")
    print("─" * 26)
    print(
        f"AUC-ROC   : {metrics['auc_roc']:>10.4f}  "
        f"(target ≥ {thresholds.auc_roc_target:.2f} | "
        f"min ≥ {thresholds.auc_roc_min:.2f})"
    )
    print(
        f"PR-AUC    : {metrics['pr_auc']:>10.4f}  "
        f"(min ≥ {thresholds.pr_auc_min:.2f})"
    )
    print(
        f"F1        : {metrics['f1']:>10.4f}  "
        f"(min ≥ {thresholds.f1_min:.2f})"
    )
    print(
        f"Precision : {metrics['precision']:>10.4f}  "
        f"(min ≥ {thresholds.precision_min:.2f})"
    )
    print(
        f"Recall    : {metrics['recall']:>10.4f}  "
        f"(min ≥ {thresholds.recall_min:.2f})"
    )
    print(
        f"ECE       : {metrics['ece']:>10.4f}  "
        f"(max ≤ {thresholds.ece_max:.2f})"
    )

    # ------------------------------------------------------------------
    # 12. Threshold warnings
    # ------------------------------------------------------------------
    failures = check_thresholds(metrics, thresholds)
    if failures:
        print("\nThreshold check failures:")
        for msg in failures:
            print(f"  {msg}")
    else:
        print("\nAll threshold checks passed.")

    # ------------------------------------------------------------------
    # 13. Save artefacts
    # ------------------------------------------------------------------
    if save:
        models_dir = CONFIG.paths.models_dir
        models_dir.mkdir(parents=True, exist_ok=True)

        pipeline_path = models_dir / "model_c_pipeline.joblib"
        calibrated_path = models_dir / "model_c_calibrated.joblib"
        xgb_native_path = models_dir / "model_c_xgb.ubj"
        metrics_path = models_dir / "model_c_metrics.json"

        joblib.dump(pipeline, pipeline_path)
        print(f"\nSaved pipeline  -> {pipeline_path}")

        joblib.dump(calibrated, calibrated_path)
        print(f"Saved calibrated model -> {calibrated_path}")

        model.save_model(str(xgb_native_path))
        print(f"Saved XGBoost native   -> {xgb_native_path}")

        with open(metrics_path, "w", encoding="utf-8") as fh:
            json.dump(metrics, fh, indent=2)
        print(f"Saved metrics          -> {metrics_path}")

    # ------------------------------------------------------------------
    # 14. Return artefacts
    # ------------------------------------------------------------------
    return pipeline, calibrated, metrics


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Train Model C — bid probability classification"
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        help="Path to auctions CSV (default: CONFIG.paths.synthetic_auctions)",
    )
    parser.add_argument(
        "--no-save",
        action="store_true",
        help="Skip saving artefacts to disk",
    )
    args = parser.parse_args()
    train(data_path=args.data, save=not args.no_save)


if __name__ == "__main__":
    main()
