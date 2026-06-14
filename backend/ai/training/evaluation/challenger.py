"""Challenger-vs-incumbent model comparison for Phase 5.

For each model type, trains challenger algorithms on the same feature matrix
as the incumbent XGBoost and compares test-set metrics side-by-side.

Challengers
-----------
  Model A (regression):  RandomForestRegressor
  Model B (regression):  RandomForestRegressor
  Model C (classifier):  RandomForestClassifier + LogisticRegression

Promotion verdicts
------------------
  PROMOTE        — challenger beats incumbent on the primary metric by >5%
  DO_NOT_PROMOTE — challenger does not improve over incumbent
  NEEDS_REVIEW   — mixed results (beats on some metrics, not primary)

Usage::

    report = compare_regression(
        X_train, y_train_log, X_test, y_test_rwf, y_test_log,
        incumbent_metrics=registry_entry["metrics"],
        model_name="model_a",
    )
    report.print_report()
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

import numpy as np
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    average_precision_score,
    f1_score,
    mean_absolute_error,
    mean_squared_error,
    precision_score,
    r2_score,
    recall_score,
    roc_auc_score,
)

from training.evaluation.metrics import compute_ece

PromotionVerdict = Literal["PROMOTE", "DO_NOT_PROMOTE", "NEEDS_REVIEW"]

# Challenger beats incumbent if it improves the primary metric by this fraction
_PROMOTE_THRESHOLD = 0.05  # 5% improvement required


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------
@dataclass
class ModelResult:
    """Metrics for a single model (incumbent or one challenger)."""

    label: str
    metrics: dict[str, float]

    def primary(self, key: str) -> float:
        return self.metrics.get(key, float("nan"))


@dataclass
class ChallengerReport:
    """Full comparison between incumbent and all challengers for one model slot."""

    model_name: str
    incumbent: ModelResult
    challengers: list[ModelResult] = field(default_factory=list)
    winner_label: str = ""
    verdict: PromotionVerdict = "DO_NOT_PROMOTE"
    primary_metric: str = ""
    notes: list[str] = field(default_factory=list)

    def print_report(self) -> None:
        width = 60
        print(f"\n{'=' * width}")
        print(f"  Challenger Report — {self.model_name.upper()}")
        print(f"{'=' * width}")
        print(f"  Primary metric : {self.primary_metric}")
        print(f"  Verdict        : {self.verdict}")
        print(f"  Winner         : {self.winner_label}")
        print()

        all_models = [self.incumbent] + self.challengers
        metric_keys = list(self.incumbent.metrics.keys())

        header = f"  {'Metric':<22}" + "".join(f"{m.label:<20}" for m in all_models)
        print(header)
        print("  " + "-" * (len(header) - 2))

        for key in metric_keys:
            row = f"  {key:<22}"
            for m in all_models:
                val = m.metrics.get(key)
                if val is None:
                    row += f"{'N/A':<20}"
                elif abs(val) >= 1_000:
                    row += f"{val:>12,.0f} RWF  "
                else:
                    row += f"{val:>12.4f}        "
            print(row)

        if self.notes:
            print()
            for note in self.notes:
                print(f"  NOTE: {note}")
        print()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
def _regression_metrics(
    y_true_rwf: np.ndarray,
    y_pred_rwf: np.ndarray,
    y_true_log: np.ndarray | None = None,
    y_pred_log: np.ndarray | None = None,
) -> dict[str, float]:
    mae = float(mean_absolute_error(y_true_rwf, y_pred_rwf))
    rmse = float(np.sqrt(mean_squared_error(y_true_rwf, y_pred_rwf)))
    ape = np.abs((y_true_rwf - y_pred_rwf) / np.maximum(y_true_rwf, 1.0))
    mape = float(np.mean(ape))
    r2 = float(r2_score(y_true_rwf, y_pred_rwf))
    result: dict[str, float] = {
        "mae_rwf": mae,
        "rmse_rwf": rmse,
        "mape": mape,
        "r2": r2,
    }
    if y_true_log is not None and y_pred_log is not None:
        result["r2_log"] = float(r2_score(y_true_log, y_pred_log))
    return result


def _classification_metrics(
    y_true: np.ndarray, y_prob: np.ndarray
) -> dict[str, float]:
    y_pred = (y_prob >= 0.5).astype(int)
    return {
        "roc_auc": float(roc_auc_score(y_true, y_prob)),
        "pr_auc": float(average_precision_score(y_true, y_prob)),
        "f1": float(f1_score(y_true, y_pred, zero_division=0)),
        "precision": float(precision_score(y_true, y_pred, zero_division=0)),
        "recall": float(recall_score(y_true, y_pred, zero_division=0)),
        "ece": float(compute_ece(y_true, y_prob)),
    }


def _regression_verdict(
    incumbent: ModelResult,
    challengers: list[ModelResult],
    primary: str,
    lower_is_better: bool,
) -> tuple[str, PromotionVerdict, list[str]]:
    """Return (winner_label, verdict, notes)."""
    notes: list[str] = []
    best_challenger = min(
        challengers,
        key=lambda c: c.primary(primary) if lower_is_better else -c.primary(primary),
    )
    inc_val = incumbent.primary(primary)
    chal_val = best_challenger.primary(primary)

    if lower_is_better:
        improvement = (inc_val - chal_val) / max(abs(inc_val), 1e-9)
    else:
        improvement = (chal_val - inc_val) / max(abs(inc_val), 1e-9)

    if improvement >= _PROMOTE_THRESHOLD:
        verdict: PromotionVerdict = "PROMOTE"
        winner = best_challenger.label
    elif improvement > 0:
        verdict = "NEEDS_REVIEW"
        winner = best_challenger.label
        notes.append(
            f"Challenger improves {primary} by {improvement*100:.1f}% "
            f"— below promotion threshold ({_PROMOTE_THRESHOLD*100:.0f}%)"
        )
    else:
        verdict = "DO_NOT_PROMOTE"
        winner = incumbent.label

    return winner, verdict, notes


# ---------------------------------------------------------------------------
# Public comparison functions
# ---------------------------------------------------------------------------
def compare_regression(
    X_train: np.ndarray,
    y_train_log: np.ndarray,
    X_test: np.ndarray,
    y_test_rwf: np.ndarray,
    y_test_log: np.ndarray,
    incumbent_metrics: dict,
    model_name: str = "model_a",
    n_estimators: int = 200,
    random_state: int = 42,
) -> ChallengerReport:
    """Train a RandomForestRegressor challenger and compare against XGBoost incumbent.

    Parameters
    ----------
    X_train / X_test:
        Pre-processed feature matrices from the same pipeline used for incumbent.
    y_train_log:
        log1p-transformed target for training (same transform as XGBoost).
    y_test_rwf / y_test_log:
        Original-scale and log-scale test targets for metric computation.
    incumbent_metrics:
        Metrics dict from the registry entry (keys: mae_rwf, rmse_rwf, mape, r2, …).
    model_name:
        ``"model_a"`` or ``"model_b"`` — used for labelling only.
    """
    primary_metric = "mape"

    incumbent = ModelResult(
        label=f"XGBoost ({model_name} incumbent)",
        metrics={k: float(v) for k, v in incumbent_metrics.items()},
    )

    print(f"  Training RF challenger for {model_name}...")
    # RF doesn't natively handle NaN — impute before fitting
    imputer = SimpleImputer(strategy="median")
    X_train_imp = imputer.fit_transform(X_train)
    X_test_imp = imputer.transform(X_test)
    rf = RandomForestRegressor(
        n_estimators=n_estimators,
        max_depth=12,
        min_samples_leaf=5,
        n_jobs=-1,
        random_state=random_state,
    )
    rf.fit(X_train_imp, y_train_log)
    rf_pred_log = rf.predict(X_test_imp)
    rf_pred_rwf = np.expm1(rf_pred_log)
    rf_metrics = _regression_metrics(y_test_rwf, rf_pred_rwf, y_test_log, rf_pred_log)

    challengers = [ModelResult(label="RandomForest (challenger)", metrics=rf_metrics)]

    winner, verdict, notes = _regression_verdict(
        incumbent, challengers, primary=primary_metric, lower_is_better=True
    )

    return ChallengerReport(
        model_name=model_name,
        incumbent=incumbent,
        challengers=challengers,
        winner_label=winner,
        verdict=verdict,
        primary_metric=primary_metric,
        notes=notes,
    )


def compare_classification(
    X_train: np.ndarray,
    y_train: np.ndarray,
    X_test: np.ndarray,
    y_test: np.ndarray,
    incumbent_metrics: dict,
    model_name: str = "model_c",
    n_estimators: int = 200,
    random_state: int = 42,
) -> ChallengerReport:
    """Train RF + LogisticRegression challengers and compare against XGBoost incumbent.

    Parameters
    ----------
    X_train / X_test:
        Pre-processed feature matrices.
    y_train / y_test:
        Binary labels (1 = at least one bid placed, 0 = no bids).
    incumbent_metrics:
        Metrics dict from the registry entry (keys: roc_auc, f1, ece, …).
    """
    primary_metric = "roc_auc"

    incumbent = ModelResult(
        label=f"XGBoost+Platt ({model_name} incumbent)",
        metrics={k: float(v) for k, v in incumbent_metrics.items()},
    )

    challengers: list[ModelResult] = []

    # Challenger 1 — Random Forest (impute NaN — RF doesn't handle NaN natively)
    print(f"  Training RF classifier challenger for {model_name}...")
    rf_imputer = SimpleImputer(strategy="median")
    X_train_rf = rf_imputer.fit_transform(X_train)
    X_test_rf = rf_imputer.transform(X_test)
    rf = RandomForestClassifier(
        n_estimators=n_estimators,
        max_depth=10,
        min_samples_leaf=5,
        n_jobs=-1,
        random_state=random_state,
    )
    rf.fit(X_train_rf, y_train)
    rf_prob = rf.predict_proba(X_test_rf)[:, 1]
    challengers.append(
        ModelResult(
            label="RandomForest (challenger A)",
            metrics=_classification_metrics(y_test, rf_prob),
        )
    )

    # Challenger 2 — Logistic Regression (requires finite inputs; impute NaNs)
    print(f"  Training LR challenger for {model_name}...")
    imputer = SimpleImputer(strategy="median")
    X_train_lr = imputer.fit_transform(X_train)
    X_test_lr = imputer.transform(X_test)
    lr = LogisticRegression(max_iter=1_000, C=1.0, random_state=random_state)
    lr.fit(X_train_lr, y_train)
    lr_prob = lr.predict_proba(X_test_lr)[:, 1]
    challengers.append(
        ModelResult(
            label="LogisticRegression (challenger B)",
            metrics=_classification_metrics(y_test, lr_prob),
        )
    )

    # Pick the best challenger by primary metric (higher is better for AUC)
    best = max(challengers, key=lambda c: c.primary(primary_metric))
    inc_val = incumbent.primary(primary_metric)
    chal_val = best.primary(primary_metric)
    improvement = (chal_val - inc_val) / max(abs(inc_val), 1e-9)
    notes: list[str] = []

    if improvement >= _PROMOTE_THRESHOLD:
        verdict: PromotionVerdict = "PROMOTE"
        winner = best.label
    elif improvement > 0:
        verdict = "NEEDS_REVIEW"
        winner = best.label
        notes.append(
            f"Best challenger improves {primary_metric} by {improvement*100:.1f}% "
            f"— below promotion threshold ({_PROMOTE_THRESHOLD*100:.0f}%)"
        )
    else:
        verdict = "DO_NOT_PROMOTE"
        winner = incumbent.label

    return ChallengerReport(
        model_name=model_name,
        incumbent=incumbent,
        challengers=challengers,
        winner_label=winner,
        verdict=verdict,
        primary_metric=primary_metric,
        notes=notes,
    )
