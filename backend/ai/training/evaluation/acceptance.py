from __future__ import annotations

from dataclasses import dataclass, field

from training.config import CONFIG, BidProbabilityThresholds, PriceModelThresholds, WinningBidThresholds


@dataclass
class AcceptanceResult:
    """Outcome of running a model through the production acceptance gate."""

    model_name: str
    passed: bool
    failures: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    grade: str = "unknown"
    metrics: dict = field(default_factory=dict)


def check_model_a(
    metrics: dict,
    thresholds: WinningBidThresholds | None = None,
) -> AcceptanceResult:
    """Production acceptance gate for Model A (market value estimation).

    Gates on log-scale R² (r2_log) rather than original-scale R² because
    Model A trains on log1p(winning_amount) and original-scale R² is penalised
    by the heavy right tail of the auction price distribution.  Falls back to
    the plain 'r2' key so legacy metrics dicts without r2_log still route
    through the gate without errors.
    """
    t = thresholds or CONFIG.winning_bid_thresholds
    failures, warnings = [], []

    # Prefer the log-scale metric; fall back to original-scale for compat
    r2_log = float(metrics.get("r2_log", metrics.get("r2", -999)))
    mape   = float(metrics.get("mape", 999))
    mae    = float(metrics.get("mae", metrics.get("mae_rwf", 0)))

    if r2_log < t.r2_min:
        failures.append(f"FAIL r2_log: {r2_log:.4f} < min {t.r2_min:.4f}")
    elif r2_log < t.r2_target:
        warnings.append(f"WARN r2_log: {r2_log:.4f} below target {t.r2_target:.4f}")

    if mape > t.mape_min:
        failures.append(f"FAIL mape: {mape:.4f} > min {t.mape_min:.4f}")
    elif mape > t.mape_target:
        warnings.append(f"WARN mape: {mape:.4f} above target {t.mape_target:.4f}")

    if mae > 0 and mae > t.mae_rwf_target:
        warnings.append(f"WARN mae: {mae:,.0f} above target {t.mae_rwf_target:,.0f}")

    passed = len(failures) == 0

    if not passed:
        grade = "fail"
    elif r2_log >= t.r2_excellent and mape <= t.mape_excellent:
        grade = "excellent"
    elif r2_log >= t.r2_target and mape <= t.mape_target:
        grade = "target"
    else:
        grade = "minimum"

    return AcceptanceResult(
        model_name="model_a",
        passed=passed,
        failures=failures,
        warnings=warnings,
        grade=grade,
        metrics=dict(metrics),
    )


def check_model_b(
    metrics: dict,
    thresholds: WinningBidThresholds | None = None,
) -> AcceptanceResult:
    """Production acceptance gate for Model B (winning bid regression)."""
    t = thresholds or CONFIG.winning_bid_thresholds
    failures, warnings = [], []

    r2  = float(metrics.get("r2", -999))
    mae = float(metrics.get("mae", metrics.get("mae_rwf", 999_999_999)))

    if r2 < t.r2_min:
        failures.append(f"FAIL r2: {r2:.4f} < min {t.r2_min:.4f}")
    elif r2 < t.r2_target:
        warnings.append(f"WARN r2: {r2:.4f} below target {t.r2_target:.4f}")

    if mae > t.mae_rwf_min:
        failures.append(f"FAIL mae: {mae:,.0f} > min {t.mae_rwf_min:,.0f}")
    elif mae > t.mae_rwf_target:
        warnings.append(f"WARN mae: {mae:,.0f} above target {t.mae_rwf_target:,.0f}")

    passed = len(failures) == 0

    if not passed:
        grade = "fail"
    elif r2 >= t.r2_excellent and mae <= t.mae_rwf_excellent:
        grade = "excellent"
    elif r2 >= t.r2_target and mae <= t.mae_rwf_target:
        grade = "target"
    else:
        grade = "minimum"

    return AcceptanceResult(
        model_name="model_b",
        passed=passed,
        failures=failures,
        warnings=warnings,
        grade=grade,
        metrics=dict(metrics),
    )


def check_model_c(
    metrics: dict,
    thresholds: BidProbabilityThresholds | None = None,
) -> AcceptanceResult:
    """Production acceptance gate for Model C (bid probability classification)."""
    t = thresholds or CONFIG.bid_prob_thresholds
    failures, warnings = [], []

    roc_auc = float(metrics.get("roc_auc", metrics.get("auc_roc", -1)))
    ece     = float(metrics.get("ece", 999))
    f1      = float(metrics.get("f1", 0))
    pr_auc  = float(metrics.get("pr_auc", 0))

    if roc_auc < t.auc_roc_min:
        failures.append(f"FAIL roc_auc: {roc_auc:.4f} < min {t.auc_roc_min:.4f}")
    elif roc_auc < t.auc_roc_target:
        warnings.append(f"WARN roc_auc: {roc_auc:.4f} below target {t.auc_roc_target:.4f}")

    if ece > t.ece_max:
        failures.append(f"FAIL ece: {ece:.4f} > max {t.ece_max:.4f}")

    if f1 > 0 and f1 < t.f1_min:
        warnings.append(f"WARN f1: {f1:.4f} < min {t.f1_min:.4f}")

    if pr_auc > 0 and pr_auc < t.pr_auc_min:
        warnings.append(f"WARN pr_auc: {pr_auc:.4f} < min {t.pr_auc_min:.4f}")

    passed = len(failures) == 0

    if not passed:
        grade = "fail"
    elif roc_auc >= t.auc_roc_excellent and ece <= t.ece_max * 0.5:
        grade = "excellent"
    elif roc_auc >= t.auc_roc_target:
        grade = "target"
    else:
        grade = "minimum"

    return AcceptanceResult(
        model_name="model_c",
        passed=passed,
        failures=failures,
        warnings=warnings,
        grade=grade,
        metrics=dict(metrics),
    )


def check_model(model_name: str, metrics: dict) -> AcceptanceResult:
    """Route metrics to the correct acceptance gate by model name."""
    _dispatch = {
        "model_a": check_model_a,
        "model_b": check_model_b,
        "model_c": check_model_c,
    }
    if model_name not in _dispatch:
        raise ValueError(f"Unknown model_name {model_name!r}. Expected one of {sorted(_dispatch)}.")
    return _dispatch[model_name](metrics)
