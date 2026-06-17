"""training_worker/drift_detector.py

Phase 9G — Model Drift Detection.

Pure functions with no I/O or Supabase dependency — fully unit-testable.
The Edge Function check-model-drift calls these checks after reading
ai_prediction_comparisons rows, then stores results in ai_drift_metrics.

Three drift signals (all derived from ai_prediction_comparisons data):

  mape_spike
    7-day rolling MAPE has risen more than 20% above 30-day baseline.
    Threshold: mape_7d > mape_30d * mape_spike_threshold (default 1.20).
    Indicates recent prediction quality degradation.

  residual_bias
    Predictions are systematically over- or under-estimating.
    |mean_residual| / mean_actual > bias_threshold (default 0.15).
    A 15%+ systematic bias means the model's calibration has drifted.

  high_error_rate
    More than 10% of recent predictions have APE > 50%.
    These are "catastrophic" errors unacceptable for client-facing insights.

Severity:
  none  — 0 signals triggered
  low   — 1 signal triggered (logged only)
  high  — 2+ signals triggered (logged + early retraining triggered)
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional, Sequence


# ---------------------------------------------------------------------------
# Signal dataclass
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DriftSignal:
    name: str
    detected: bool
    value: Optional[float]       # measured value (e.g. mape_7d/mape_30d ratio)
    threshold: float             # the threshold that was applied
    description: str             # human-readable explanation


# ---------------------------------------------------------------------------
# Report dataclass
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class DriftReport:
    signals: list[DriftSignal]
    drift_detected: bool
    severity: str                # 'none' | 'low' | 'high'
    triggered_names: list[str]   # names of signals where detected=True
    reason: str                  # human-readable summary


# ---------------------------------------------------------------------------
# Individual signal checks
# ---------------------------------------------------------------------------

def check_mape_spike(
    mape_7d: Optional[float],
    mape_30d: Optional[float],
    *,
    threshold: float = 1.20,
) -> DriftSignal:
    """Detect if recent MAPE (7-day) is significantly worse than 30-day baseline.

    Returns detected=True when mape_7d > mape_30d * threshold.
    Returns detected=False (with value=None) when either input is unavailable.
    """
    if mape_7d is None or mape_30d is None or mape_30d <= 0:
        return DriftSignal(
            name="mape_spike",
            detected=False,
            value=None,
            threshold=threshold,
            description="insufficient_data",
        )

    ratio = mape_7d / mape_30d
    detected = ratio > threshold
    return DriftSignal(
        name="mape_spike",
        detected=detected,
        value=round(ratio, 4),
        threshold=threshold,
        description=(
            f"mape_7d({mape_7d:.4f})/mape_30d({mape_30d:.4f})={ratio:.4f}"
            f"{'>' if detected else '<='}{threshold}"
        ),
    )


def check_residual_bias(
    residuals: Sequence[float],
    actuals: Sequence[float],
    *,
    threshold: float = 0.15,
) -> DriftSignal:
    """Detect systematic over- or under-prediction bias.

    residuals: list of (predicted - actual) values
    actuals:   list of actual winning_amount values (must match length)

    Returns detected=True when |mean_residual| / mean_actual > threshold.
    Returns detected=False when there are fewer than 5 data points or
    mean_actual <= 0.
    """
    if len(residuals) < 5 or len(actuals) < 5:
        return DriftSignal(
            name="residual_bias",
            detected=False,
            value=None,
            threshold=threshold,
            description="insufficient_data",
        )

    mean_residual = sum(residuals) / len(residuals)
    mean_actual = sum(actuals) / len(actuals)

    if mean_actual <= 0:
        return DriftSignal(
            name="residual_bias",
            detected=False,
            value=None,
            threshold=threshold,
            description="mean_actual_not_positive",
        )

    ratio = abs(mean_residual) / mean_actual
    detected = ratio > threshold
    direction = "over" if mean_residual > 0 else "under"
    return DriftSignal(
        name="residual_bias",
        detected=detected,
        value=round(ratio, 4),
        threshold=threshold,
        description=(
            f"|mean_residual({mean_residual:.2f})|/mean_actual({mean_actual:.2f})"
            f"={ratio:.4f}{'>' if detected else '<='}{threshold}"
            f" ({direction}-predicting)"
        ),
    )


def check_high_error_rate(
    apes: Sequence[float],
    *,
    ape_threshold: float = 0.50,
    rate_threshold: float = 0.10,
) -> DriftSignal:
    """Detect if too many predictions have catastrophically high error.

    apes: list of absolute_percentage_error values (0.0 to ∞, lower is better)

    Returns detected=True when fraction(ape > ape_threshold) > rate_threshold.
    Returns detected=False when fewer than 5 data points.
    """
    if len(apes) < 5:
        return DriftSignal(
            name="high_error_rate",
            detected=False,
            value=None,
            threshold=rate_threshold,
            description="insufficient_data",
        )

    high_count = sum(1 for a in apes if a > ape_threshold)
    rate = high_count / len(apes)
    detected = rate > rate_threshold
    return DriftSignal(
        name="high_error_rate",
        detected=detected,
        value=round(rate, 4),
        threshold=rate_threshold,
        description=(
            f"{high_count}/{len(apes)} predictions have APE>{ape_threshold}"
            f" → rate={rate:.4f}{'>' if detected else '<='}{rate_threshold}"
        ),
    )


# ---------------------------------------------------------------------------
# Aggregate evaluation
# ---------------------------------------------------------------------------

def evaluate_drift(signals: list[DriftSignal]) -> DriftReport:
    """Aggregate individual signals into an overall DriftReport.

    Severity mapping:
      0 triggered → 'none'
      1 triggered → 'low'
      2+ triggered → 'high'
    """
    triggered = [s for s in signals if s.detected]
    triggered_names = [s.name for s in triggered]
    count = len(triggered)

    if count == 0:
        severity = "none"
        drift_detected = False
        reason = "no_drift_signals"
    elif count == 1:
        severity = "low"
        drift_detected = True
        reason = f"1_signal:{triggered_names[0]}"
    else:
        severity = "high"
        drift_detected = True
        reason = f"{count}_signals:{','.join(triggered_names)}"

    return DriftReport(
        signals=signals,
        drift_detected=drift_detected,
        severity=severity,
        triggered_names=triggered_names,
        reason=reason,
    )
