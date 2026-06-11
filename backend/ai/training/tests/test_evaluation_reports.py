"""Phase 3C — Unit tests for training.evaluation.reports."""
from __future__ import annotations

import json
import pathlib
import tempfile

import numpy as np
import pandas as pd
import pytest

from training.evaluation.reports import (
    regression_report,
    classification_report,
    export_json,
    export_csv,
    _completeness_tier,
)


# ---------------------------------------------------------------------------
# Shared helper
# ---------------------------------------------------------------------------

def _make_df(n: int = 100) -> pd.DataFrame:
    rng = np.random.default_rng(1)
    return pd.DataFrame({
        "main_category": rng.choice(["vehicle", "motorcycle", "bicycle"], size=n),
        "region": rng.choice(["Central", "Eastern", "Western"], size=n),
        "brand": rng.choice(["Toyota", None], size=n),
        "manufacturing_year": rng.choice([2018, 2019, None], size=n),
        "condition": rng.choice(["Good", "Fair"], size=n),
        "mileage": rng.integers(0, 200_000, size=n).astype(float),
    })


def _reg_targets(n: int = 100):
    rng = np.random.default_rng(2)
    y_true = rng.uniform(1_000_000, 8_000_000, size=n)
    y_pred = y_true + rng.normal(0, 150_000, size=n)
    return y_true, y_pred


def _cls_targets(n: int = 100):
    rng = np.random.default_rng(3)
    y_true = rng.integers(0, 2, size=n)
    # Make sure both classes are present
    y_true[0] = 0
    y_true[1] = 1
    y_prob = np.clip(y_true * 0.7 + rng.uniform(0, 0.3, size=n), 0, 1)
    return y_true, y_prob


# ---------------------------------------------------------------------------
# _completeness_tier tests
# ---------------------------------------------------------------------------

def test_completeness_tier_returns_series():
    df = _make_df(50)
    result = _completeness_tier(df)
    assert isinstance(result, pd.Series)
    assert len(result) == len(df)


def test_completeness_tier_labels():
    df = _make_df(100)
    result = _completeness_tier(df)
    assert set(result.unique()).issubset({"low", "medium", "high"})


def test_completeness_tier_no_known_cols():
    df = pd.DataFrame({"unrelated_col": [1, 2, 3]})
    result = _completeness_tier(df)
    assert (result == "unknown").all()


# ---------------------------------------------------------------------------
# regression_report tests
# ---------------------------------------------------------------------------

def test_regression_report_keys():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    result = regression_report(y_true, y_pred, df, model_name="model_a")
    assert set(result.keys()) >= {
        "model_name", "report_type", "generated_at", "n_samples",
        "feature_names", "overall", "by_category", "by_region", "by_completeness",
    }


def test_regression_report_overall_has_metrics():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    result = regression_report(y_true, y_pred, df, model_name="model_a")
    assert set(result["overall"].keys()) == {"mae", "rmse", "r2", "mape"}


def test_regression_report_by_category_nonempty():
    df = _make_df(150)
    y_true, y_pred = _reg_targets(150)
    result = regression_report(y_true, y_pred, df, model_name="model_a")
    assert len(result["by_category"]) > 0


def test_regression_report_n_samples():
    df = _make_df(80)
    y_true, y_pred = _reg_targets(80)
    result = regression_report(y_true, y_pred, df, model_name="model_a")
    assert result["n_samples"] == len(y_true)


def test_regression_report_no_category_col():
    df = _make_df().drop(columns=["main_category"])
    y_true, y_pred = _reg_targets()
    result = regression_report(y_true, y_pred, df, model_name="model_a")
    assert result["by_category"] == {}


# ---------------------------------------------------------------------------
# classification_report tests
# ---------------------------------------------------------------------------

def test_classification_report_keys():
    df = _make_df()
    y_true, y_prob = _cls_targets()
    result = classification_report(y_true, y_prob, df, model_name="model_c")
    assert set(result.keys()) >= {
        "overall", "calibration", "confusion_matrix", "positive_rate", "threshold",
    }


def test_classification_report_calibration_has_ece():
    df = _make_df()
    y_true, y_prob = _cls_targets()
    result = classification_report(y_true, y_prob, df, model_name="model_c")
    assert isinstance(result["calibration"]["ece"], float)


def test_classification_report_confusion_matrix_keys():
    df = _make_df()
    y_true, y_prob = _cls_targets()
    result = classification_report(y_true, y_prob, df, model_name="model_c")
    assert set(result["confusion_matrix"].keys()) == {"TP", "FP", "TN", "FN"}


def test_classification_report_positive_rate():
    df = _make_df()
    y_true, y_prob = _cls_targets()
    result = classification_report(y_true, y_prob, df, model_name="model_c")
    assert result["positive_rate"] == pytest.approx(float(np.mean(y_true)))


# ---------------------------------------------------------------------------
# export_json tests
# ---------------------------------------------------------------------------

def test_export_json_creates_file():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "report.json"
        export_json(report, path)
        assert path.exists()


def test_export_json_parseable():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "report.json"
        export_json(report, path)
        loaded = json.loads(path.read_text(encoding="utf-8"))
        assert "model_name" in loaded
        assert loaded["model_name"] == "model_a"


def test_export_json_creates_parent_dirs():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "nested" / "dir" / "report.json"
        export_json(report, path)
        assert path.exists()


# ---------------------------------------------------------------------------
# export_csv tests
# ---------------------------------------------------------------------------

def test_export_csv_creates_file():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "report.csv"
        export_csv(report, path)
        assert path.exists()


def test_export_csv_has_header():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "report.csv"
        export_csv(report, path)
        first_line = path.read_text(encoding="utf-8").splitlines()[0]
        assert first_line == "section,group,metric,value"


def test_export_csv_overall_row():
    df = _make_df()
    y_true, y_pred = _reg_targets()
    report = regression_report(y_true, y_pred, df, model_name="model_a")
    with tempfile.TemporaryDirectory() as tmp:
        path = pathlib.Path(tmp) / "report.csv"
        export_csv(report, path)
        content = path.read_text(encoding="utf-8")
        assert "overall" in content
