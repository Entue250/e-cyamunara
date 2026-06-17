"""Tests for training_worker/drift_detector.py — Phase 9G drift detection."""

from __future__ import annotations

import pytest

from training_worker.drift_detector import (
    DriftReport,
    DriftSignal,
    check_high_error_rate,
    check_mape_spike,
    check_residual_bias,
    evaluate_drift,
)


# ===========================================================================
# check_mape_spike
# ===========================================================================

class TestCheckMapeSpike:
    def test_detected_when_7d_exceeds_threshold(self) -> None:
        # 7d MAPE 25% worse than 30d → ratio = 1.25 > 1.20 → detected
        sig = check_mape_spike(mape_7d=0.25, mape_30d=0.20)
        assert sig.detected
        assert sig.name == "mape_spike"
        assert sig.value == pytest.approx(1.25, rel=1e-4)

    def test_not_detected_when_7d_equal_to_threshold(self) -> None:
        # ratio exactly 1.20 is NOT > 1.20 (strict >)
        sig = check_mape_spike(mape_7d=0.24, mape_30d=0.20)
        assert not sig.detected
        assert sig.value == pytest.approx(1.20, rel=1e-4)

    def test_not_detected_when_7d_better_than_30d(self) -> None:
        sig = check_mape_spike(mape_7d=0.10, mape_30d=0.20)
        assert not sig.detected

    def test_not_detected_when_mape_7d_is_none(self) -> None:
        sig = check_mape_spike(mape_7d=None, mape_30d=0.20)
        assert not sig.detected
        assert sig.value is None
        assert "insufficient_data" in sig.description

    def test_not_detected_when_mape_30d_is_none(self) -> None:
        sig = check_mape_spike(mape_7d=0.25, mape_30d=None)
        assert not sig.detected
        assert sig.value is None

    def test_not_detected_when_mape_30d_is_zero(self) -> None:
        sig = check_mape_spike(mape_7d=0.25, mape_30d=0.0)
        assert not sig.detected
        assert "insufficient_data" in sig.description

    def test_custom_threshold(self) -> None:
        # threshold=1.50: ratio must be >1.50 to detect
        sig = check_mape_spike(mape_7d=0.30, mape_30d=0.20, threshold=1.50)
        assert not sig.detected  # 1.50 is not > 1.50
        sig2 = check_mape_spike(mape_7d=0.31, mape_30d=0.20, threshold=1.50)
        assert sig2.detected

    def test_threshold_stored_on_signal(self) -> None:
        sig = check_mape_spike(mape_7d=0.25, mape_30d=0.20, threshold=1.30)
        assert sig.threshold == 1.30


# ===========================================================================
# check_residual_bias
# ===========================================================================

class TestCheckResidualBias:
    def _make(
        self,
        mean_res: float = 0.0,
        mean_act: float = 100.0,
        n: int = 10,
    ) -> tuple[list[float], list[float]]:
        residuals = [mean_res] * n
        actuals = [mean_act] * n
        return residuals, actuals

    def test_detected_when_bias_exceeds_threshold(self) -> None:
        # |mean_residual|=20, mean_actual=100 → ratio=0.20 > 0.15
        r, a = self._make(mean_res=20.0, mean_act=100.0)
        sig = check_residual_bias(r, a)
        assert sig.detected
        assert sig.value == pytest.approx(0.20, rel=1e-4)

    def test_not_detected_when_bias_at_threshold(self) -> None:
        # ratio exactly 0.15 is not > 0.15
        r, a = self._make(mean_res=15.0, mean_act=100.0)
        sig = check_residual_bias(r, a)
        assert not sig.detected
        assert sig.value == pytest.approx(0.15, rel=1e-4)

    def test_detected_for_negative_residual(self) -> None:
        # Under-predicting by 20% — absolute value triggers it
        r, a = self._make(mean_res=-20.0, mean_act=100.0)
        sig = check_residual_bias(r, a)
        assert sig.detected
        assert "under-predicting" in sig.description

    def test_not_detected_when_fewer_than_5_points(self) -> None:
        sig = check_residual_bias([20.0] * 4, [100.0] * 4)
        assert not sig.detected
        assert "insufficient_data" in sig.description

    def test_not_detected_when_mean_actual_zero(self) -> None:
        sig = check_residual_bias([5.0] * 10, [0.0] * 10)
        assert not sig.detected
        assert "mean_actual_not_positive" in sig.description

    def test_not_detected_when_bias_low(self) -> None:
        r, a = self._make(mean_res=5.0, mean_act=100.0)
        sig = check_residual_bias(r, a)
        assert not sig.detected

    def test_custom_threshold(self) -> None:
        r, a = self._make(mean_res=10.0, mean_act=100.0)
        sig = check_residual_bias(r, a, threshold=0.08)
        assert sig.detected  # 0.10 > 0.08

    def test_description_contains_direction(self) -> None:
        r, a = self._make(mean_res=20.0, mean_act=100.0)
        sig = check_residual_bias(r, a)
        assert "over-predicting" in sig.description


# ===========================================================================
# check_high_error_rate
# ===========================================================================

class TestCheckHighErrorRate:
    def test_detected_when_rate_exceeds_threshold(self) -> None:
        # 2 of 10 APEs > 0.50 → rate=0.20 > 0.10
        apes = [0.80, 0.60] + [0.10] * 8
        sig = check_high_error_rate(apes)
        assert sig.detected
        assert sig.value == pytest.approx(0.20, rel=1e-4)

    def test_not_detected_when_exactly_at_rate_threshold(self) -> None:
        # 1 of 10 → rate=0.10, not > 0.10
        apes = [0.80] + [0.10] * 9
        sig = check_high_error_rate(apes)
        assert not sig.detected
        assert sig.value == pytest.approx(0.10, rel=1e-4)

    def test_not_detected_when_no_high_errors(self) -> None:
        apes = [0.05] * 20
        sig = check_high_error_rate(apes)
        assert not sig.detected
        assert sig.value == pytest.approx(0.0)

    def test_not_detected_when_fewer_than_5_points(self) -> None:
        sig = check_high_error_rate([0.80, 0.90, 0.70, 0.60])
        assert not sig.detected
        assert "insufficient_data" in sig.description

    def test_all_high_errors(self) -> None:
        apes = [1.0] * 10
        sig = check_high_error_rate(apes)
        assert sig.detected
        assert sig.value == pytest.approx(1.0)

    def test_custom_ape_threshold(self) -> None:
        # ape_threshold=0.30: APEs of 0.35 now count as high
        apes = [0.35] * 3 + [0.05] * 7  # 30% > 0.30 → rate=0.30 > 0.10
        sig = check_high_error_rate(apes, ape_threshold=0.30)
        assert sig.detected

    def test_custom_rate_threshold(self) -> None:
        # 2 of 10 high → rate=0.20; with rate_threshold=0.25 → not detected
        apes = [0.80, 0.60] + [0.10] * 8
        sig = check_high_error_rate(apes, rate_threshold=0.25)
        assert not sig.detected


# ===========================================================================
# evaluate_drift
# ===========================================================================

def _signal(name: str, detected: bool) -> DriftSignal:
    return DriftSignal(
        name=name,
        detected=detected,
        value=0.5 if detected else 0.1,
        threshold=0.3,
        description="test",
    )


class TestEvaluateDrift:
    def test_severity_none_when_no_signals(self) -> None:
        report = evaluate_drift([
            _signal("mape_spike", False),
            _signal("residual_bias", False),
            _signal("high_error_rate", False),
        ])
        assert report.severity == "none"
        assert not report.drift_detected
        assert report.triggered_names == []
        assert report.reason == "no_drift_signals"

    def test_severity_low_when_one_signal(self) -> None:
        report = evaluate_drift([
            _signal("mape_spike", True),
            _signal("residual_bias", False),
            _signal("high_error_rate", False),
        ])
        assert report.severity == "low"
        assert report.drift_detected
        assert report.triggered_names == ["mape_spike"]
        assert "1_signal" in report.reason

    def test_severity_high_when_two_signals(self) -> None:
        report = evaluate_drift([
            _signal("mape_spike", True),
            _signal("residual_bias", True),
            _signal("high_error_rate", False),
        ])
        assert report.severity == "high"
        assert report.drift_detected
        assert set(report.triggered_names) == {"mape_spike", "residual_bias"}
        assert "2_signals" in report.reason

    def test_severity_high_when_all_three_signals(self) -> None:
        report = evaluate_drift([
            _signal("mape_spike", True),
            _signal("residual_bias", True),
            _signal("high_error_rate", True),
        ])
        assert report.severity == "high"
        assert len(report.triggered_names) == 3

    def test_signals_list_preserved(self) -> None:
        signals = [
            _signal("mape_spike", True),
            _signal("residual_bias", False),
        ]
        report = evaluate_drift(signals)
        assert report.signals is signals

    def test_empty_signal_list(self) -> None:
        report = evaluate_drift([])
        assert report.severity == "none"
        assert not report.drift_detected
