"""Phase 3C — Unit tests for training.evaluation.acceptance."""
from __future__ import annotations

import pytest

from training.evaluation.acceptance import (
    AcceptanceResult,
    check_model_a,
    check_model_b,
    check_model_c,
    check_model,
)
from training.config import CONFIG


# ---------------------------------------------------------------------------
# AcceptanceResult tests
# ---------------------------------------------------------------------------

def test_acceptance_result_defaults():
    result = AcceptanceResult("model_a", True)
    assert result.failures == []
    assert result.warnings == []
    assert result.grade == "unknown"


def test_acceptance_result_fields():
    result = AcceptanceResult("model_a", True)
    assert hasattr(result, "model_name")
    assert hasattr(result, "passed")
    assert hasattr(result, "failures")
    assert hasattr(result, "warnings")
    assert hasattr(result, "grade")
    assert hasattr(result, "metrics")


# ---------------------------------------------------------------------------
# check_model_a tests
# ---------------------------------------------------------------------------

def test_model_a_passes_excellent():
    result = check_model_a({"r2": 0.93, "mape": 0.08})
    assert result.passed is True
    assert result.grade == "excellent"


def test_model_a_passes_target():
    result = check_model_a({"r2": 0.87, "mape": 0.13})
    assert result.passed is True
    assert result.grade == "target"


def test_model_a_passes_minimum():
    result = check_model_a({"r2": 0.72, "mape": 0.22})
    assert result.passed is True
    assert result.grade == "minimum"


def test_model_a_fails_r2():
    # r2_log=0.55 < WinningBidThresholds.r2_min=0.60 → FAIL
    result = check_model_a({"r2_log": 0.55, "mape": 0.10})
    assert result.passed is False
    assert any("FAIL r2" in f for f in result.failures)


def test_model_a_fails_mape():
    # mape=0.35 > WinningBidThresholds.mape_min=0.30 → FAIL
    result = check_model_a({"r2_log": 0.80, "mape": 0.35})
    assert result.passed is False
    assert any("FAIL mape" in f for f in result.failures)


# ---------------------------------------------------------------------------
# check_model_b tests
# ---------------------------------------------------------------------------

def test_model_b_passes():
    # r2=0.75 >= r2_min=0.60; mae=800_000 <= mae_rwf_min=1_000_000
    result = check_model_b({"r2": 0.75, "mae": 800_000})
    assert result.passed is True


def test_model_b_fails_r2():
    result = check_model_b({"r2": 0.50, "mae": 500_000})
    assert result.passed is False


def test_model_b_fails_mae():
    # mae=1_500_000 > mae_rwf_min=1_000_000
    result = check_model_b({"r2": 0.75, "mae": 1_500_000})
    assert result.passed is False


def test_model_b_grade_excellent():
    # r2=0.90 >= r2_excellent=0.88; mae=200_000 <= mae_rwf_excellent=300_000
    result = check_model_b({"r2": 0.90, "mae": 200_000})
    assert result.grade == "excellent"


# ---------------------------------------------------------------------------
# check_model_c tests
# ---------------------------------------------------------------------------

def test_model_c_passes():
    result = check_model_c({"roc_auc": 0.80, "ece": 0.05})
    assert result.passed is True


def test_model_c_fails_roc():
    result = check_model_c({"roc_auc": 0.60, "ece": 0.05})
    assert result.passed is False


def test_model_c_fails_ece():
    result = check_model_c({"roc_auc": 0.80, "ece": 0.15})
    assert result.passed is False


def test_model_c_advisory_warnings():
    # f1=0.50 < f1_min=0.65 → advisory WARN; roc/ece still pass
    result = check_model_c({"roc_auc": 0.80, "ece": 0.05, "f1": 0.50})
    assert result.passed is True
    assert any("WARN f1" in w for w in result.warnings)


# ---------------------------------------------------------------------------
# dispatcher tests
# ---------------------------------------------------------------------------

def test_check_model_dispatcher_model_a():
    result = check_model("model_a", {"r2": 0.80, "mape": 0.20})
    assert isinstance(result, AcceptanceResult)
    assert result.model_name == "model_a"


def test_check_model_dispatcher_invalid():
    with pytest.raises(ValueError):
        check_model("model_x", {})
