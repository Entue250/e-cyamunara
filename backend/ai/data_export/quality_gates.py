"""Data quality gates for the Phase 5 real-data training pipeline.

Gates are intentionally conservative for early production data:

  Gate 1 — Minimum row count          (model_ab: >=100, model_c: >=50)
  Gate 2 — Target column present       (winning_amount for A/B; any row for C)
  Gate 3 — Target not all-null         (at least 1 valid target value)
  Gate 4 — Required feature coverage   (<50% missing for each required column)
  Gate 5 — Class balance (model_c)     (positive class >=5% of total rows)
  Gate 6 — No duplicate auction IDs

All thresholds are intentionally lower than the synthetic-data split config
(which assumed 200 K rows) so real data is evaluated fairly at early scale.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import pandas as pd

# ---------------------------------------------------------------------------
# Required columns per mode — must be <50% missing to pass Gate 4
# ---------------------------------------------------------------------------
_REQUIRED_FEATURES_AB = [
    "main_category",
    "region",
    "starting_price",
]

_REQUIRED_FEATURES_C = [
    "main_category",
    "region",
    "starting_price",
    "total_bids",
]

# ---------------------------------------------------------------------------
# Thresholds
# ---------------------------------------------------------------------------
MIN_ROWS_MODEL_AB: int = 100
MIN_ROWS_MODEL_C: int = 50
MAX_MISSING_PCT: float = 0.50
MIN_CLASS_BALANCE_C: float = 0.05  # positive class must be >=5% of total


# ---------------------------------------------------------------------------
# Result types
# ---------------------------------------------------------------------------
@dataclass
class GateResult:
    name: str
    passed: bool
    message: str
    value: Any = None
    threshold: Any = None

    def __str__(self) -> str:
        status = "PASS" if self.passed else "FAIL"
        suffix = f" (value={self.value}, threshold={self.threshold})" if self.value is not None else ""
        return f"  [{status}] {self.name}: {self.message}{suffix}"


@dataclass
class DataQualityReport:
    mode: str
    row_count: int
    gates: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gates)

    @property
    def failed_gates(self) -> list[GateResult]:
        return [g for g in self.gates if not g.passed]

    def print_report(self) -> None:
        status = "PASS" if self.passed else "FAIL"
        print(f"\nData Quality Report [{self.mode.upper()}] — {status}")
        print(f"  Rows evaluated: {self.row_count:,}")
        print("-" * 60)
        for gate in self.gates:
            print(gate)
        if self.passed:
            print("\nAll gates PASSED — dataset is ready for training.")
        else:
            n = len(self.failed_gates)
            print(f"\n{n} gate(s) FAILED — training cannot proceed on this dataset.")
            print("Recommendation: collect more production data or use synthetic data.")


# ---------------------------------------------------------------------------
# Individual gate checks
# ---------------------------------------------------------------------------
def _gate_min_rows(df: pd.DataFrame, min_rows: int) -> GateResult:
    n = len(df)
    passed = n >= min_rows
    return GateResult(
        name="min_row_count",
        passed=passed,
        message=(
            f"{n:,} rows available, need {min_rows:,}"
            if not passed
            else f"{n:,} rows — sufficient"
        ),
        value=n,
        threshold=min_rows,
    )


def _gate_target_present(df: pd.DataFrame, target_col: str) -> GateResult:
    if target_col not in df.columns:
        return GateResult(
            name="target_column_present",
            passed=False,
            message=f"Column '{target_col}' not found in dataset",
        )
    return GateResult(
        name="target_column_present",
        passed=True,
        message=f"Column '{target_col}' present",
    )


def _gate_target_not_all_null(df: pd.DataFrame, target_col: str) -> GateResult:
    if target_col not in df.columns:
        return GateResult(
            name="target_not_all_null",
            passed=False,
            message=f"Column '{target_col}' missing — cannot evaluate nulls",
        )
    non_null = int(df[target_col].notna().sum())
    total = len(df)
    passed = non_null > 0
    pct = non_null / total * 100 if total > 0 else 0
    return GateResult(
        name="target_not_all_null",
        passed=passed,
        message=(
            f"{non_null:,}/{total:,} non-null ({pct:.1f}%) for '{target_col}'"
        ),
        value=non_null,
        threshold=1,
    )


def _gate_feature_coverage(df: pd.DataFrame, required: list[str]) -> GateResult:
    n = len(df)
    failing: list[str] = []
    details: list[str] = []

    for col in required:
        if col not in df.columns:
            failing.append(col)
            details.append(f"{col}: MISSING")
            continue
        missing_pct = df[col].isna().mean()
        if missing_pct > MAX_MISSING_PCT:
            failing.append(col)
        details.append(f"{col}: {missing_pct*100:.1f}% missing")

    passed = len(failing) == 0
    msg = "All required features within missingness limit"
    if not passed:
        msg = f"High missingness in: {', '.join(failing)}"
    return GateResult(
        name="feature_coverage",
        passed=passed,
        message=msg,
        value="; ".join(details),
        threshold=f"<={MAX_MISSING_PCT*100:.0f}% missing",
    )


def _gate_class_balance(df: pd.DataFrame) -> GateResult:
    # Positive class: auction has at least one bid (total_bids > 0)
    if "total_bids" not in df.columns:
        return GateResult(
            name="class_balance",
            passed=False,
            message="'total_bids' column missing — cannot compute class balance",
        )
    positive = int((df["total_bids"].fillna(0) > 0).sum())
    total = len(df)
    balance = positive / total if total > 0 else 0
    passed = balance >= MIN_CLASS_BALANCE_C
    return GateResult(
        name="class_balance",
        passed=passed,
        message=(
            f"{positive:,}/{total:,} auctions have bids ({balance*100:.1f}%) "
            f"— need >={MIN_CLASS_BALANCE_C*100:.0f}%"
        ),
        value=round(balance, 4),
        threshold=MIN_CLASS_BALANCE_C,
    )


def _gate_no_duplicate_ids(df: pd.DataFrame) -> GateResult:
    if "id" not in df.columns:
        return GateResult(
            name="no_duplicate_ids",
            passed=True,
            message="No 'id' column — skipping duplicate check",
        )
    dupes = int(df["id"].duplicated().sum())
    passed = dupes == 0
    return GateResult(
        name="no_duplicate_ids",
        passed=passed,
        message=(
            f"{dupes} duplicate auction IDs found" if dupes else "No duplicate IDs"
        ),
        value=dupes,
        threshold=0,
    )


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
def run_quality_gates(df: pd.DataFrame, mode: str = "model_ab") -> DataQualityReport:
    """Run all data quality gates for the given training mode.

    Parameters
    ----------
    df:
        DataFrame loaded from CSV (synthetic or real export).
    mode:
        ``"model_ab"`` for regression models (A/B) or ``"model_c"`` for the
        bid-probability classifier.

    Returns
    -------
    DataQualityReport
        Call ``.passed`` for a boolean summary or ``.print_report()`` for a
        human-readable breakdown.
    """
    if mode not in ("model_ab", "model_c"):
        raise ValueError(f"mode must be 'model_ab' or 'model_c', got {mode!r}")

    report = DataQualityReport(mode=mode, row_count=len(df))

    if mode == "model_ab":
        min_rows = MIN_ROWS_MODEL_AB
        required_features = _REQUIRED_FEATURES_AB
        target_col = "winning_amount"
    else:
        min_rows = MIN_ROWS_MODEL_C
        required_features = _REQUIRED_FEATURES_C
        target_col = "total_bids"

    report.gates = [
        _gate_min_rows(df, min_rows),
        _gate_target_present(df, target_col),
        _gate_target_not_all_null(df, target_col),
        _gate_feature_coverage(df, required_features),
        _gate_no_duplicate_ids(df),
    ]

    if mode == "model_c":
        report.gates.append(_gate_class_balance(df))

    return report
