from __future__ import annotations

import csv
import json
import pathlib
from datetime import datetime, timezone

import numpy as np
import pandas as pd

from .metrics import (
    regression_metrics,
    regression_metrics_by_group,
    classification_metrics,
    classification_metrics_by_group,
    confusion_matrix_dict,
    calibration_data,
)

_COMPLETENESS_COLS = [
    "brand", "manufacturing_year", "mileage", "fuel_type", "transmission",
    "ownership_history", "accident_history", "insurance_status",
    "condition", "sub_category",
]


def _completeness_tier(df: pd.DataFrame) -> pd.Series:
    """Return per-row completeness tier: high (>=7/10), medium (4-6/10), low (<4/10)."""
    present = [col for col in _COMPLETENESS_COLS if col in df.columns]
    if not present:
        return pd.Series(["unknown"] * len(df), index=df.index)
    score = df[present].notna().sum(axis=1)
    max_possible = len(present)
    ratio = score / max_possible
    return pd.cut(
        ratio,
        bins=[-0.001, 0.4, 0.7, 1.001],
        labels=["low", "medium", "high"],
    ).astype(str)


def _json_default(obj):
    if isinstance(obj, (np.integer,)):
        return int(obj)
    if isinstance(obj, (np.floating,)):
        return float(obj)
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def regression_report(
    y_true: np.ndarray,
    y_pred: np.ndarray,
    df: pd.DataFrame,
    model_name: str,
    feature_names: list[str] | None = None,
) -> dict:
    """Return a regression evaluation report dict."""
    return {
        "model_name": model_name,
        "report_type": "regression",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "n_samples": int(len(y_true)),
        "feature_names": feature_names or [],
        "overall": regression_metrics(y_true, y_pred),
        "by_category": regression_metrics_by_group(y_true, y_pred, df["main_category"]) if "main_category" in df.columns else {},
        "by_region": regression_metrics_by_group(y_true, y_pred, df["region"]) if "region" in df.columns else {},
        "by_completeness": regression_metrics_by_group(y_true, y_pred, _completeness_tier(df)),
    }


def classification_report(
    y_true: np.ndarray,
    y_prob: np.ndarray,
    df: pd.DataFrame,
    model_name: str,
    threshold: float = 0.5,
    feature_names: list[str] | None = None,
) -> dict:
    """Return a classification evaluation report dict."""
    return {
        "model_name": model_name,
        "report_type": "classification",
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "n_samples": int(len(y_true)),
        "positive_rate": float(np.mean(np.asarray(y_true))),
        "feature_names": feature_names or [],
        "threshold": threshold,
        "overall": classification_metrics(y_true, y_prob, threshold),
        "by_category": classification_metrics_by_group(y_true, y_prob, df["main_category"], threshold) if "main_category" in df.columns else {},
        "by_region": classification_metrics_by_group(y_true, y_prob, df["region"], threshold) if "region" in df.columns else {},
        "by_completeness": classification_metrics_by_group(y_true, y_prob, _completeness_tier(df), threshold),
        "calibration": calibration_data(y_true, y_prob),
        "confusion_matrix": confusion_matrix_dict(y_true, (np.asarray(y_prob) >= threshold).astype(int)),
    }


def export_json(report: dict, path: pathlib.Path) -> None:
    """Write report dict to a JSON file (UTF-8, 2-space indent)."""
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, default=_json_default), encoding="utf-8")


def export_csv(report: dict, path: pathlib.Path) -> None:
    """Flatten report to (section, group, metric, value) rows and write CSV."""
    path = pathlib.Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)

    rows = []

    def _add(section: str, group: str, metrics_dict: dict) -> None:
        if not isinstance(metrics_dict, dict):
            return
        for metric, value in metrics_dict.items():
            if isinstance(value, (int, float)):
                rows.append({
                    "section": section,
                    "group": group,
                    "metric": metric,
                    "value": round(float(value), 6),
                })

    _add("overall", "all", report.get("overall", {}))

    for section_key in ("by_category", "by_region", "by_completeness"):
        section = report.get(section_key, {})
        if isinstance(section, dict):
            for group_name, group_metrics in section.items():
                _add(section_key, group_name, group_metrics)

    cm = report.get("confusion_matrix", {})
    if cm:
        _add("confusion_matrix", "all", cm)

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["section", "group", "metric", "value"])
        writer.writeheader()
        writer.writerows(rows)
