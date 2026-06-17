"""Tests for training_worker/promotion_gate.py — Phase 9F promotion engine."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest

from training_worker.promotion_gate import (
    PromotionDecision,
    check_expiry,
    check_promotion_gate,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _gate(
    candidate_mape: float | None = 0.10,
    active_mape: float | None = 0.15,
    comparisons: int = 100,
    min_comparisons: int = 100,
    threshold: float = 0.97,
) -> PromotionDecision:
    return check_promotion_gate(
        candidate_mape,
        active_mape,
        comparisons,
        min_comparisons=min_comparisons,
        improvement_threshold=threshold,
    )


# ---------------------------------------------------------------------------
# Gate 1: minimum comparisons
# ---------------------------------------------------------------------------

def test_gate_fails_with_zero_comparisons() -> None:
    d = _gate(comparisons=0)
    assert not d.passed
    assert "insufficient_comparisons" in d.reason


def test_gate_fails_with_99_comparisons_when_min_is_100() -> None:
    d = _gate(comparisons=99, min_comparisons=100)
    assert not d.passed
    assert "99<100" in d.reason


def test_gate_proceeds_with_exactly_100_comparisons() -> None:
    d = _gate(comparisons=100, min_comparisons=100)
    # May pass or fail on other gates, but not on the count gate
    assert "insufficient_comparisons" not in d.reason


def test_gate_passes_with_custom_lower_min_comparisons() -> None:
    d = _gate(comparisons=10, min_comparisons=5)
    # Should proceed past Gate 1
    assert "insufficient_comparisons" not in d.reason


# ---------------------------------------------------------------------------
# Gate 2: candidate_mape availability
# ---------------------------------------------------------------------------

def test_gate_fails_when_candidate_mape_is_none() -> None:
    d = _gate(candidate_mape=None, comparisons=100)
    assert not d.passed
    assert "candidate_mape_unavailable" in d.reason


# ---------------------------------------------------------------------------
# Gate 3: active_mape availability
# ---------------------------------------------------------------------------

def test_gate_fails_when_active_mape_is_none() -> None:
    d = _gate(active_mape=None, comparisons=100)
    assert not d.passed
    assert "active_mape_unavailable" in d.reason


def test_gate_fails_when_active_mape_is_zero() -> None:
    d = _gate(active_mape=0.0, comparisons=100)
    assert not d.passed
    assert "active_mape_not_positive" in d.reason


def test_gate_fails_when_active_mape_is_negative() -> None:
    d = _gate(active_mape=-0.01, comparisons=100)
    assert not d.passed
    assert "active_mape_not_positive" in d.reason


# ---------------------------------------------------------------------------
# Gate 4: MAPE improvement
# ---------------------------------------------------------------------------

def test_gate_passes_when_candidate_3_percent_better() -> None:
    # active=0.15, threshold=0.15*0.97=0.1455, candidate=0.14 < 0.1455 → pass
    d = _gate(candidate_mape=0.14, active_mape=0.15, comparisons=100)
    assert d.passed
    assert "candidate_mape" in d.reason


def test_gate_fails_when_candidate_equal_to_active() -> None:
    d = _gate(candidate_mape=0.15, active_mape=0.15, comparisons=100)
    assert not d.passed


def test_gate_fails_when_candidate_worse_than_active() -> None:
    d = _gate(candidate_mape=0.20, active_mape=0.15, comparisons=100)
    assert not d.passed


def test_gate_fails_when_exactly_at_threshold() -> None:
    # threshold = 0.15 * 0.97 = 0.1455; candidate = 0.1455 is NOT < threshold
    active = 0.15
    threshold = active * 0.97  # 0.1455
    d = _gate(candidate_mape=threshold, active_mape=active, comparisons=100)
    assert not d.passed


def test_gate_passes_just_below_threshold() -> None:
    active = 0.15
    threshold = active * 0.97  # 0.1455
    d = _gate(candidate_mape=threshold - 0.0001, active_mape=active, comparisons=100)
    assert d.passed


def test_custom_improvement_threshold_0_99_requires_1_percent() -> None:
    # 0.99 threshold: candidate must be 1% better (lower)
    # active=0.15, threshold=0.1485; candidate=0.148 → pass
    d = _gate(candidate_mape=0.148, active_mape=0.15, comparisons=100, threshold=0.99)
    assert d.passed


def test_custom_improvement_threshold_0_90_requires_10_percent() -> None:
    # 0.90 threshold: candidate must be 10% better
    # active=0.15, threshold=0.135; candidate=0.14 is NOT < 0.135 → fail
    d = _gate(candidate_mape=0.14, active_mape=0.15, comparisons=100, threshold=0.90)
    assert not d.passed


# ---------------------------------------------------------------------------
# PromotionDecision fields
# ---------------------------------------------------------------------------

def test_decision_carries_threshold_on_pass() -> None:
    d = _gate(candidate_mape=0.10, active_mape=0.15, comparisons=100)
    assert d.passed
    assert d.threshold is not None
    assert d.threshold == pytest.approx(0.15 * 0.97, rel=1e-6)


def test_decision_carries_improvement_pct() -> None:
    # improvement = (0.15 - 0.10) / 0.15 = 0.3333
    d = _gate(candidate_mape=0.10, active_mape=0.15, comparisons=100)
    assert d.improvement_pct is not None
    assert d.improvement_pct == pytest.approx(1/3, rel=1e-3)


def test_decision_improvement_pct_is_none_when_active_unavailable() -> None:
    d = _gate(candidate_mape=0.10, active_mape=None, comparisons=100)
    assert d.improvement_pct is None


def test_decision_improvement_pct_negative_when_candidate_worse() -> None:
    # active=0.10, candidate=0.20 → improvement = (0.10-0.20)/0.10 = -1.0
    d = _gate(candidate_mape=0.20, active_mape=0.10, comparisons=100)
    assert d.improvement_pct is not None
    assert d.improvement_pct < 0


def test_decision_comparisons_count_preserved() -> None:
    d = _gate(comparisons=247)
    assert d.comparisons_count == 247


# ---------------------------------------------------------------------------
# check_expiry
# ---------------------------------------------------------------------------

_NOW = datetime(2026, 6, 16, 12, 0, 0, tzinfo=timezone.utc)


def test_expiry_false_when_young_and_insufficient_comparisons() -> None:
    registered = _NOW - timedelta(days=10)
    expired, reason = check_expiry(registered, 5, expiry_days=30, min_comparisons=100, now=_NOW)
    assert not expired
    assert reason == ""


def test_expiry_true_when_old_and_insufficient_comparisons() -> None:
    registered = _NOW - timedelta(days=31)
    expired, reason = check_expiry(registered, 50, expiry_days=30, min_comparisons=100, now=_NOW)
    assert expired
    assert "expired_after_31d" in reason
    assert "50/100" in reason


def test_expiry_false_when_old_but_sufficient_comparisons() -> None:
    registered = _NOW - timedelta(days=35)
    expired, _ = check_expiry(registered, 120, expiry_days=30, min_comparisons=100, now=_NOW)
    assert not expired


def test_expiry_exactly_at_expiry_boundary() -> None:
    # 30 days old, 99 comparisons (< 100) → expired
    registered = _NOW - timedelta(days=30)
    expired, _ = check_expiry(registered, 99, expiry_days=30, min_comparisons=100, now=_NOW)
    assert expired


def test_expiry_handles_naive_datetime() -> None:
    # registered_at without timezone info → treated as UTC
    registered = datetime(2026, 5, 15, 0, 0, 0)  # naive, 32 days ago
    expired, _ = check_expiry(registered, 0, expiry_days=30, min_comparisons=100, now=_NOW)
    assert expired
