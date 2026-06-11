"""
Unit tests for compute_metrics, compute_ece, and check_thresholds in the
three training scripts.  No model training is performed here.
"""

from __future__ import annotations

import numpy as np
import pytest

from training.train_model_a import (
    compute_metrics as metrics_a,
    check_thresholds as thresholds_a,
)
from training.train_model_b import (
    compute_metrics as metrics_b,
    check_thresholds as thresholds_b,
)
from training.train_model_c import (
    compute_ece,
    compute_metrics as metrics_c,
    check_thresholds as thresholds_c,
)
from training.config import CONFIG


# ---------------------------------------------------------------------------
# Shared test arrays (original RWF scale for Models A and C)
# ---------------------------------------------------------------------------

_Y_ORIG = np.array([1_000_000.0, 2_000_000.0, 3_000_000.0, 4_000_000.0])

# For Model B, inputs are in log1p space (it calls np.expm1 internally).
_Y_LOG = np.log1p(_Y_ORIG)


# ---------------------------------------------------------------------------
# compute_metrics — Model A (6 tests)
# ---------------------------------------------------------------------------

def test_model_a_metrics_perfect_prediction():
    """compute_metrics returns 0 MAE/RMSE/MAPE and R²=1 for perfect predictions."""
    m = metrics_a(_Y_ORIG, _Y_ORIG)
    assert m["mae_rwf"] == pytest.approx(0.0, abs=1e-3)
    assert m["rmse_rwf"] == pytest.approx(0.0, abs=1e-3)
    assert m["mape"] == pytest.approx(0.0, abs=1e-6)
    assert m["r2"] == pytest.approx(1.0, abs=1e-6)


def test_model_a_metrics_keys():
    """compute_metrics (Model A) returns the expected keys (without log args)."""
    m = metrics_a(_Y_ORIG, _Y_ORIG)
    assert set(m.keys()) == {"mae_rwf", "rmse_rwf", "mape", "median_ape", "r2"}


def test_model_a_metrics_keys_with_log():
    """compute_metrics (Model A) includes r2_log when log arrays are supplied."""
    y_log = np.log1p(_Y_ORIG)
    m = metrics_a(_Y_ORIG, _Y_ORIG, y_log, y_log)
    assert "r2_log" in m.keys()
    assert m["r2_log"] == pytest.approx(1.0, abs=1e-6)


def test_model_b_metrics_structure():
    """compute_metrics (Model B) returns the standard regression metric keys."""
    m = metrics_b(_Y_LOG, _Y_LOG)
    assert set(m.keys()) == {"mae_rwf", "rmse_rwf", "mape", "r2"}


def test_model_a_mape_correct():
    """MAPE for known inputs is computed correctly."""
    y_true = np.array([1_000_000.0, 2_000_000.0])
    y_pred = np.array([1_100_000.0, 1_900_000.0])
    # MAPE = (100k/1M + 100k/2M) / 2 = (0.10 + 0.05) / 2 = 0.075
    m = metrics_a(y_true, y_pred)
    assert abs(m["mape"] - 0.075) < 0.001


def test_model_a_r2_below_1_for_imperfect():
    """R² is strictly less than 1.0 when predictions are not perfect."""
    y_pred = _Y_ORIG * 1.1   # 10 % over-prediction
    m = metrics_a(_Y_ORIG, y_pred)
    assert m["r2"] < 1.0


def test_model_c_metrics_keys():
    """compute_metrics (Model C) returns exactly the classification metric keys."""
    # Alternating 0/1 labels with matching high-confidence probabilities
    y_true = np.array([0, 0, 1, 1])
    y_prob = np.array([0.1, 0.2, 0.8, 0.9])
    m = metrics_c(y_true, y_prob)
    assert set(m.keys()) == {"auc_roc", "pr_auc", "f1", "precision", "recall", "ece"}


# ---------------------------------------------------------------------------
# compute_ece — 3 tests
# ---------------------------------------------------------------------------

def test_ece_perfect_calibration():
    """ECE is near 0 for well-calibrated probabilities."""
    y_true = np.array([0, 0, 1, 1])
    y_prob = np.array([0.1, 0.1, 0.9, 0.9])
    ece = compute_ece(y_true, y_prob)
    assert ece < 0.1


def test_ece_poor_calibration():
    """ECE is large when all predictions are far from the true positive rate."""
    # All true labels = 1, but model predicts 5% probability for all
    y_true = np.ones(20, dtype=int)
    y_prob = np.full(20, 0.05)
    ece = compute_ece(y_true, y_prob)
    assert ece > 0.5


def test_ece_returns_float():
    """compute_ece always returns a Python float."""
    y_true = np.array([0, 1, 0, 1])
    y_prob = np.array([0.3, 0.7, 0.4, 0.6])
    result = compute_ece(y_true, y_prob)
    assert isinstance(result, float)


# ---------------------------------------------------------------------------
# check_thresholds — Model A (3 tests)
# ---------------------------------------------------------------------------

def test_thresholds_a_all_pass():
    """check_thresholds returns an empty list when r2_log and mape are within limits."""
    # WinningBidThresholds: r2_min=0.60, mape_min=0.30
    good_metrics = {
        "r2_log": 0.85,
        "mape":   0.20,
    }
    warnings = thresholds_a(good_metrics, CONFIG.winning_bid_thresholds)
    assert warnings == []


def test_thresholds_a_mape_fails():
    """check_thresholds includes a 'mape' message when MAPE exceeds the minimum."""
    bad_metrics = {
        "r2_log": 0.80,
        "mape":   0.35,   # > 0.30 threshold
    }
    warnings = thresholds_a(bad_metrics, CONFIG.winning_bid_thresholds)
    assert len(warnings) >= 1
    assert any("mape" in w.lower() for w in warnings)


def test_thresholds_a_r2_fails():
    """check_thresholds includes an 'r2'-related message when r2_log is below the minimum."""
    bad_metrics = {
        "r2_log": 0.55,   # < 0.60 WinningBidThresholds.r2_min
        "mape":   0.20,
    }
    warnings = thresholds_a(bad_metrics, CONFIG.winning_bid_thresholds)
    assert len(warnings) >= 1
    assert any("r2" in w.lower() for w in warnings)


# ---------------------------------------------------------------------------
# check_thresholds — Model B (1 test)
# ---------------------------------------------------------------------------

def test_thresholds_b_all_pass():
    """check_thresholds (Model B) returns an empty list for metrics within WinningBid limits."""
    # WinningBidThresholds: mae_rwf_min=1M, rmse_rwf_min=3M, mape_min=0.30, r2_min=0.60
    good_metrics = {
        "mae_rwf": 100_000.0,
        "rmse_rwf": 200_000.0,
        "mape": 0.05,
        "r2": 0.90,
    }
    failures = thresholds_b(good_metrics)
    assert failures == []


# ---------------------------------------------------------------------------
# check_thresholds — Model C (2 tests)
# ---------------------------------------------------------------------------

def test_thresholds_c_all_pass():
    """check_thresholds (Model C) returns an empty list for metrics within BidProb limits."""
    # BidProbabilityThresholds: auc_roc_min=0.70, pr_auc_min=0.65, f1_min=0.65,
    #   precision_min=0.60, recall_min=0.65, ece_max=0.10
    good_metrics = {
        "auc_roc":   0.85,
        "pr_auc":    0.75,
        "f1":        0.75,
        "precision": 0.70,
        "recall":    0.72,
        "ece":       0.05,
    }
    failures = thresholds_c(good_metrics, CONFIG.bid_prob_thresholds)
    assert failures == []


def test_thresholds_c_ece_fails():
    """check_thresholds (Model C) flags ECE when it exceeds ece_max=0.10."""
    bad_metrics = {
        "auc_roc":   0.85,
        "pr_auc":    0.75,
        "f1":        0.75,
        "precision": 0.70,
        "recall":    0.72,
        "ece":       0.20,   # > 0.10 threshold
    }
    failures = thresholds_c(bad_metrics, CONFIG.bid_prob_thresholds)
    assert len(failures) >= 1
    assert any("ece" in f.lower() for f in failures)
