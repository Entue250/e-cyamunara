"""Phase 3C — Unit tests for training.evaluation.metrics."""
from __future__ import annotations

import numpy as np
import pytest

from training.evaluation.metrics import (
    compute_ece,
    calibration_data,
    regression_metrics,
    regression_metrics_by_group,
    classification_metrics,
    classification_metrics_by_group,
    confusion_matrix_dict,
)


# ---------------------------------------------------------------------------
# Shared helper fixtures
# ---------------------------------------------------------------------------

def _reg_data():
    """Return (y_true, y_pred) for regression tests."""
    rng = np.random.default_rng(0)
    y_true = rng.uniform(1_000_000, 10_000_000, size=200)
    noise = rng.normal(0, 200_000, size=200)
    return y_true, y_true + noise


def _cls_data():
    """Return (y_true, y_prob) for classification tests."""
    rng = np.random.default_rng(0)
    y_true = rng.integers(0, 2, size=200)
    y_prob = np.clip(y_true * 0.7 + rng.uniform(0, 0.3, size=200), 0, 1)
    return y_true, y_prob


# ---------------------------------------------------------------------------
# compute_ece tests
# ---------------------------------------------------------------------------

def test_ece_returns_float():
    y_true, y_prob = _cls_data()
    result = compute_ece(y_true, y_prob)
    assert isinstance(result, float)


def test_ece_perfect_calibration():
    y_true = np.ones(20)
    y_prob = np.ones(20)
    result = compute_ece(y_true, y_prob)
    assert result < 0.05


def test_ece_poor_calibration():
    y_true = np.ones(20)
    y_prob = np.full(20, 0.05)
    result = compute_ece(y_true, y_prob)
    assert result > 0.8


def test_ece_range():
    y_true, y_prob = _cls_data()
    result = compute_ece(y_true, y_prob)
    assert 0.0 <= result <= 1.0


# ---------------------------------------------------------------------------
# calibration_data tests
# ---------------------------------------------------------------------------

def test_calibration_data_keys():
    y_true, y_prob = _cls_data()
    cd = calibration_data(y_true, y_prob)
    assert set(cd.keys()) == {"bin_edges", "bin_accuracy", "bin_confidence", "bin_count", "ece"}


def test_calibration_data_bin_count():
    y_true, y_prob = _cls_data()
    cd = calibration_data(y_true, y_prob, n_bins=5)
    assert len(cd["bin_edges"]) == 5
    assert len(cd["bin_count"]) == 5


def test_calibration_data_ece_matches():
    y_true, y_prob = _cls_data()
    cd = calibration_data(y_true, y_prob)
    assert cd["ece"] == compute_ece(y_true, y_prob)


# ---------------------------------------------------------------------------
# regression_metrics tests
# ---------------------------------------------------------------------------

def test_regression_metrics_keys():
    y_true, y_pred = _reg_data()
    m = regression_metrics(y_true, y_pred)
    assert set(m.keys()) == {"mae", "rmse", "r2", "mape"}


def test_regression_metrics_perfect():
    y = np.array([1_000_000.0, 2_000_000.0, 3_000_000.0])
    m = regression_metrics(y, y)
    assert m["mae"] == 0.0
    assert m["rmse"] == 0.0
    assert m["r2"] == pytest.approx(1.0)
    assert m["mape"] == pytest.approx(0.0)


def test_regression_metrics_mae_positive():
    y_true, y_pred = _reg_data()
    m = regression_metrics(y_true, y_pred)
    assert m["mae"] >= 0


def test_regression_metrics_mape_formula():
    y_true = np.array([2.0, 4.0])
    y_pred = np.array([3.0, 3.0])
    m = regression_metrics(y_true, y_pred)
    expected_mape = (abs(2 - 3) / 2 + abs(4 - 3) / 4) / 2  # = 0.375
    assert abs(m["mape"] - expected_mape) < 0.001


def test_regression_by_group_skips_small():
    rng = np.random.default_rng(0)
    y_true = rng.uniform(1_000_000, 5_000_000, size=10)
    y_pred = y_true + rng.normal(0, 50_000, size=10)
    # group "lone" has only 1 sample — should be skipped
    groups = np.array(["big"] * 9 + ["lone"])
    result = regression_metrics_by_group(y_true, y_pred, groups)
    assert "lone" not in result
    assert "big" in result


# ---------------------------------------------------------------------------
# classification_metrics tests
# ---------------------------------------------------------------------------

def test_classification_metrics_keys():
    y_true, y_prob = _cls_data()
    m = classification_metrics(y_true, y_prob)
    assert set(m.keys()) == {
        "accuracy", "precision", "recall", "f1",
        "roc_auc", "pr_auc", "brier_score", "ece",
    }


def test_classification_metrics_range():
    y_true, y_prob = _cls_data()
    m = classification_metrics(y_true, y_prob)
    for v in m.values():
        assert 0.0 <= v <= 1.0, f"value out of range: {v}"


def test_classification_metrics_perfect_auc():
    y_true = np.array([0, 1])
    y_prob = np.array([0.0, 1.0])
    m = classification_metrics(y_true, y_prob)
    assert m["roc_auc"] == pytest.approx(1.0)


def test_classification_by_group_skips_single_class():
    """Groups where all y_true values are the same class should be excluded."""
    rng = np.random.default_rng(1)
    # 50 samples: group "A" has only class 0, group "B" has both classes
    y_true = np.array([0] * 15 + [0] * 10 + [1] * 25)
    y_prob = np.clip(rng.uniform(0, 1, size=50), 0, 1)
    groups = np.array(["A"] * 25 + ["B"] * 25)
    result = classification_metrics_by_group(y_true, y_prob, groups)
    # Group A: all zeros → single class → excluded
    assert "A" not in result


def test_classification_by_group_skips_small():
    """Groups with < 10 samples should be excluded."""
    rng = np.random.default_rng(2)
    y_true = np.array([0, 1, 0, 1, 0, 1, 0, 1, 0])  # 9 samples
    y_prob = rng.uniform(0, 1, size=9)
    groups = np.array(["small"] * 9)
    result = classification_metrics_by_group(y_true, y_prob, groups)
    assert "small" not in result


def test_confusion_matrix_dict_keys():
    y_true, y_prob = _cls_data()
    y_pred = (y_prob >= 0.5).astype(int)
    cm = confusion_matrix_dict(y_true, y_pred)
    assert set(cm.keys()) == {"TP", "FP", "TN", "FN"}


# ---------------------------------------------------------------------------
# confusion_matrix_dict tests
# ---------------------------------------------------------------------------

def test_confusion_matrix_all_correct():
    y_true = np.array([0, 0, 1, 1])
    y_pred = np.array([0, 0, 1, 1])
    cm = confusion_matrix_dict(y_true, y_pred)
    assert cm["FP"] == 0
    assert cm["FN"] == 0


def test_confusion_matrix_all_wrong():
    y_true = np.array([0, 1])
    y_pred = np.array([1, 0])
    cm = confusion_matrix_dict(y_true, y_pred)
    assert cm["TP"] == 0
    assert cm["TN"] == 0
