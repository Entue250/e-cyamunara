"""training_worker/promotion_gate.py

Phase 9F — Promotion Engine gate logic.

Pure functions with no I/O or Supabase dependency — fully unit-testable.
The Edge Function promote-candidate calls these gates (via its own TypeScript
port) before calling the FastAPI promote endpoint.

Promotion criteria (ALL must pass):
  1. comparisons_count >= min_comparisons  (enough statistical evidence)
  2. candidate_mape IS NOT NULL            (metrics have been collected)
  3. active_mape    IS NOT NULL AND > 0   (baseline is meaningful)
  4. candidate_mape < active_mape * improvement_threshold
     (default 0.97 = 3% better; lower is better for MAPE)

Expiry rule (separate check, not a gate failure):
  registered_at older than expiry_days AND comparisons_count < min_comparisons
  → status becomes 'expired' regardless of metrics

The MAPE improvement threshold is intentionally conservative.  A 3% edge over
100+ real-auction comparisons provides meaningful statistical confidence that
the candidate genuinely outperforms the synthetic-trained active model.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Optional


@dataclass(frozen=True)
class PromotionDecision:
    passed: bool
    reason: str
    candidate_mape: Optional[float]
    active_mape: Optional[float]
    threshold: Optional[float]      # active_mape * improvement_threshold
    comparisons_count: int
    improvement_pct: Optional[float]  # (active - candidate) / active, positive = better


def check_promotion_gate(
    candidate_mape: Optional[float],
    active_mape: Optional[float],
    comparisons_count: int,
    *,
    min_comparisons: int = 100,
    improvement_threshold: float = 0.97,
) -> PromotionDecision:
    """Evaluate whether a candidate model meets the Phase 9F promotion criteria.

    Parameters
    ----------
    candidate_mape:
        Mean Absolute Percentage Error of the candidate model's predictions.
        Lower is better.  None means metrics have not been collected yet.
    active_mape:
        MAPE of the current active (synthetic) model over the same window.
        None means baseline metrics unavailable.
    comparisons_count:
        Number of closed auctions for which candidate comparison rows exist.
    min_comparisons:
        Minimum sample size required (default 100).
    improvement_threshold:
        Gate: candidate_mape < active_mape * improvement_threshold.
        0.97 means the candidate must be at least 3% better (lower MAPE).

    Returns
    -------
    PromotionDecision with passed=True only when all gates pass.
    """
    def _decision(passed: bool, reason: str, threshold: Optional[float] = None) -> PromotionDecision:
        imp = None
        if candidate_mape is not None and active_mape is not None and active_mape > 0:
            imp = round((active_mape - candidate_mape) / active_mape, 6)
        return PromotionDecision(
            passed=passed,
            reason=reason,
            candidate_mape=candidate_mape,
            active_mape=active_mape,
            threshold=threshold,
            comparisons_count=comparisons_count,
            improvement_pct=imp,
        )

    # Gate 1: sample size
    if comparisons_count < min_comparisons:
        return _decision(
            False,
            f"insufficient_comparisons:{comparisons_count}<{min_comparisons}",
        )

    # Gate 2: candidate metrics must be available
    if candidate_mape is None:
        return _decision(False, "candidate_mape_unavailable")

    # Gate 3: active baseline must be available and meaningful
    if active_mape is None:
        return _decision(False, "active_mape_unavailable")
    if active_mape <= 0:
        return _decision(False, f"active_mape_not_positive:{active_mape}")

    # Gate 4: MAPE improvement
    threshold = active_mape * improvement_threshold
    if candidate_mape < threshold:
        return _decision(
            True,
            (
                f"candidate_mape({candidate_mape:.4f})"
                f"<threshold({threshold:.4f})"
                f"=active_mape({active_mape:.4f})*{improvement_threshold}"
            ),
            threshold,
        )

    return _decision(
        False,
        (
            f"candidate_mape({candidate_mape:.4f})"
            f">=threshold({threshold:.4f})"
            f"=active_mape({active_mape:.4f})*{improvement_threshold}"
        ),
        threshold,
    )


def check_expiry(
    registered_at: datetime,
    comparisons_count: int,
    *,
    expiry_days: int = 30,
    min_comparisons: int = 100,
    now: Optional[datetime] = None,
) -> tuple[bool, str]:
    """Return (is_expired, reason).

    A candidate is expired when it has been evaluating for longer than
    expiry_days without accumulating enough comparison rows.
    """
    if now is None:
        now = datetime.now(timezone.utc)

    if registered_at.tzinfo is None:
        registered_at = registered_at.replace(tzinfo=timezone.utc)

    age_days = (now - registered_at).days

    if age_days >= expiry_days and comparisons_count < min_comparisons:
        return True, f"expired_after_{age_days}d_with_{comparisons_count}/{min_comparisons}_comparisons"

    return False, ""
