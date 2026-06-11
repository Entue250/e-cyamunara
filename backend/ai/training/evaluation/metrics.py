from __future__ import annotations
import numpy as np
from sklearn.metrics import (
    mean_absolute_error,
    mean_squared_error,
    r2_score,
    roc_auc_score,
    average_precision_score,
    f1_score,
    precision_score,
    recall_score,
    accuracy_score,
    brier_score_loss,
    confusion_matrix,
)


def compute_ece(y_true: np.ndarray, y_prob: np.ndarray, n_bins: int = 10) -> float:
    """Expected Calibration Error — mean weighted gap between confidence and accuracy."""
    y_true = np.asarray(y_true)
    y_prob = np.asarray(y_prob)
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    ece = 0.0
    for lo, hi in zip(bins[:-1], bins[1:]):
        mask = (y_prob >= lo) & (y_prob < hi)
        if mask.sum() > 0:
            acc = float(y_true[mask].mean())
            conf = float(y_prob[mask].mean())
            ece += (mask.sum() / len(y_true)) * abs(acc - conf)
    return float(ece)


def calibration_data(y_true: np.ndarray, y_prob: np.ndarray, n_bins: int = 10) -> dict:
    """Return per-bin calibration statistics."""
    y_true = np.asarray(y_true)
    y_prob = np.asarray(y_prob)
    bins = np.linspace(0.0, 1.0, n_bins + 1)
    bin_edges, bin_accuracy, bin_confidence, bin_count = [], [], [], []
    for lo, hi in zip(bins[:-1], bins[1:]):
        mask = (y_prob >= lo) & (y_prob < hi)
        n = int(mask.sum())
        bin_edges.append((float(lo), float(hi)))
        bin_count.append(n)
        if n > 0:
            bin_accuracy.append(float(y_true[mask].mean()))
            bin_confidence.append(float(y_prob[mask].mean()))
        else:
            bin_accuracy.append(None)
            bin_confidence.append(None)
    return {
        "bin_edges": bin_edges,
        "bin_accuracy": bin_accuracy,
        "bin_confidence": bin_confidence,
        "bin_count": bin_count,
        "ece": compute_ece(y_true, y_prob, n_bins=n_bins),
    }


def regression_metrics(y_true: np.ndarray, y_pred: np.ndarray) -> dict:
    """Compute MAE, RMSE, R², MAPE for a regression model."""
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    mae  = float(mean_absolute_error(y_true, y_pred))
    rmse = float(np.sqrt(mean_squared_error(y_true, y_pred)))
    r2   = float(r2_score(y_true, y_pred))
    denom = np.where(np.abs(y_true) < 1.0, 1.0, np.abs(y_true))
    mape  = float(np.mean(np.abs((y_true - y_pred) / denom)))
    return {"mae": mae, "rmse": rmse, "r2": r2, "mape": mape}


def regression_metrics_by_group(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    groups: np.ndarray,
) -> dict:
    """Return {group_label: regression_metrics(...)} for each unique group."""
    y_true  = np.asarray(y_true, dtype=float)
    y_pred  = np.asarray(y_pred, dtype=float)
    groups  = np.asarray(groups)
    result  = {}
    for label in np.unique(groups):
        mask = groups == label
        if mask.sum() < 2:
            continue
        result[str(label)] = regression_metrics(y_true[mask], y_pred[mask])
    return result


def classification_metrics(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    threshold: float = 0.5,
) -> dict:
    """Compute Accuracy, Precision, Recall, F1, ROC-AUC, PR-AUC, Brier, ECE."""
    y_true = np.asarray(y_true)
    y_prob = np.asarray(y_prob)
    y_pred = (y_prob >= threshold).astype(int)
    return {
        "accuracy":    float(accuracy_score(y_true, y_pred)),
        "precision":   float(precision_score(y_true, y_pred, zero_division=0)),
        "recall":      float(recall_score(y_true, y_pred, zero_division=0)),
        "f1":          float(f1_score(y_true, y_pred, zero_division=0)),
        "roc_auc":     float(roc_auc_score(y_true, y_prob)),
        "pr_auc":      float(average_precision_score(y_true, y_prob)),
        "brier_score": float(brier_score_loss(y_true, y_prob)),
        "ece":         compute_ece(y_true, y_prob),
    }


def classification_metrics_by_group(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    groups: np.ndarray,
    threshold: float = 0.5,
) -> dict:
    """Return {group_label: classification_metrics(...)} for each unique group."""
    y_true  = np.asarray(y_true)
    y_prob  = np.asarray(y_prob)
    groups  = np.asarray(groups)
    result  = {}
    for label in np.unique(groups):
        mask = groups == label
        if mask.sum() < 10:
            continue
        sub_true = y_true[mask]
        if len(np.unique(sub_true)) < 2:
            continue
        result[str(label)] = classification_metrics(sub_true, y_prob[mask], threshold)
    return result


def confusion_matrix_dict(y_true: np.ndarray, y_pred: np.ndarray) -> dict:
    """Return TP, FP, TN, FN counts as a dict."""
    y_true = np.asarray(y_true)
    y_pred = np.asarray(y_pred)
    tn, fp, fn, tp = confusion_matrix(y_true, y_pred, labels=[0, 1]).ravel()
    return {"TP": int(tp), "FP": int(fp), "TN": int(tn), "FN": int(fn)}
