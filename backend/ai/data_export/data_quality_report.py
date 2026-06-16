"""
data_export/data_quality_report.py
=====================================
Phase 9B — Data quality gates for the real-data continuous learning pipeline.

Stricter than Phase 5's quality_gates.py, with a hard/soft distinction:

  Gate 1  closed_only           HARD  No active/draft rows (they leak future signal)
  Gate 2  target_present        HARD  winning_amount column must exist
  Gate 3  no_leakage            HARD  FORBIDDEN_FEATURES not in model feature matrices
  Gate 4  no_duplicate_ids      HARD  No duplicate auction_id rows
  Gate 5  target_non_null       soft  At least 1 winning_amount is non-null
  Gate 6  missing_<col>         soft  Each ML feature column <50% null (one gate per column)
  Gate 7  min_row_count         soft  >= 100 rows for model_ab retraining

Hard gates block training.  Soft gates warn but allow training to continue.

Usage:
    from data_export.data_quality_report import run_phase9b_quality_gates
    report = run_phase9b_quality_gates(df)
    report.print_report()
    if report.hard_failed:
        sys.exit(1)
"""

from __future__ import annotations

import sys
from dataclasses import dataclass, field
from typing import Any

import pandas as pd

from training.preprocessing.feature_definitions import (
    FORBIDDEN_FEATURES,
    MODEL_A_FEATURES,
    MODEL_B_FEATURES,
    MODEL_C_FEATURES,
)

# ML feature columns checked for per-column missingness
_ML_FEATURE_COLUMNS: list[str] = [
    "main_category", "sub_category", "brand", "condition", "region",
    "starting_price", "fuel_type", "transmission", "mileage",
    "ownership_history", "accident_history", "insurance_status",
    "manufacturing_year", "asset_age", "auction_duration_hours",
    "has_description", "has_images",
]

_MIN_ROWS_MODEL_AB: int = 100
_MAX_MISSING_PCT: float = 0.50


@dataclass
class GateResult:
    name: str
    passed: bool
    hard: bool      # True = training must not proceed on failure
    message: str
    value: Any = None
    threshold: Any = None

    def __str__(self) -> str:
        if self.passed:
            status = "PASS"
        elif self.hard:
            status = "FAIL[HARD]"
        else:
            status = "WARN"
        suffix = (
            f" (value={self.value}, threshold={self.threshold})"
            if self.value is not None
            else ""
        )
        return f"  [{status}] {self.name}: {self.message}{suffix}"


@dataclass
class DataQualityReport:
    row_count: int
    gates: list[GateResult] = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return all(g.passed for g in self.gates)

    @property
    def hard_failed(self) -> bool:
        return any(not g.passed and g.hard for g in self.gates)

    @property
    def failed_gates(self) -> list[GateResult]:
        return [g for g in self.gates if not g.passed]

    def print_report(self) -> None:
        if self.hard_failed:
            status = "HARD FAIL — training must not proceed"
        elif not self.passed:
            status = "WARN — training may proceed with degraded quality"
        else:
            status = "PASS"
        print(f"\nPhase 9B Data Quality Report — {status}")
        print(f"  Rows evaluated: {self.row_count:,}")
        print("-" * 70)
        for gate in self.gates:
            print(gate)
        if self.hard_failed:
            n = len([g for g in self.gates if not g.passed and g.hard])
            print(f"\n{n} hard gate(s) failed — fix the dataset before retraining.")
        elif self.passed:
            print("\nAll gates passed — dataset is ready for training.")
        else:
            soft_n = len([g for g in self.gates if not g.passed and not g.hard])
            print(f"\n{soft_n} soft gate(s) warned — training can proceed but quality is degraded.")


def run_phase9b_quality_gates(df: pd.DataFrame) -> DataQualityReport:
    """Run Phase 9B data quality gates on a training dataset DataFrame.

    Parameters
    ----------
    df:
        DataFrame loaded from a dataset_builder snapshot (or any CSV of closed auctions).

    Returns
    -------
    DataQualityReport
        Check ``.hard_failed`` to decide whether training must be blocked.
        Call ``.print_report()`` for a human-readable breakdown.
    """
    report = DataQualityReport(row_count=len(df))
    gates: list[GateResult] = []

    # Gate 1 — Closed-only (HARD)
    if "auction_status" in df.columns:
        non_closed = int((df["auction_status"] != "closed").sum())
        gates.append(GateResult(
            name="closed_only",
            passed=non_closed == 0,
            hard=True,
            message=(
                f"{non_closed} non-closed row(s) found — active/draft rows leak future signal"
                if non_closed
                else "All rows are closed auctions"
            ),
            value=non_closed,
            threshold=0,
        ))
    else:
        gates.append(GateResult(
            name="closed_only",
            passed=False,
            hard=True,
            message="Column 'auction_status' not found — cannot verify closed-only invariant",
        ))

    # Gate 2 — Target column present (HARD)
    target_present = "winning_amount" in df.columns
    gates.append(GateResult(
        name="target_present",
        passed=target_present,
        hard=True,
        message=(
            "'winning_amount' column present"
            if target_present
            else "'winning_amount' column missing — Models A/B cannot be trained"
        ),
    ))

    # Gate 3 — No leakage in feature matrices (HARD)
    # Defense-in-depth: feature_definitions already validates this at import time,
    # but we verify it here against the live MODEL_* lists as an explicit gate.
    all_model_features = (
        set(MODEL_A_FEATURES) | set(MODEL_B_FEATURES) | set(MODEL_C_FEATURES)
    )
    leakage = FORBIDDEN_FEATURES & all_model_features
    gates.append(GateResult(
        name="no_leakage",
        passed=len(leakage) == 0,
        hard=True,
        message=(
            f"Forbidden columns found in model feature matrices: {sorted(leakage)}"
            if leakage
            else "No forbidden columns in any model feature matrix"
        ),
        value=sorted(leakage) if leakage else None,
        threshold=0,
    ))

    # Gate 4 — No duplicate auction_id (HARD)
    id_col = next(
        (c for c in ("auction_id", "id") if c in df.columns),
        None,
    )
    if id_col:
        dupes = int(df[id_col].duplicated().sum())
        gates.append(GateResult(
            name="no_duplicate_ids",
            passed=dupes == 0,
            hard=True,
            message=(
                f"{dupes} duplicate auction_id(s) found" if dupes else "No duplicate IDs"
            ),
            value=dupes,
            threshold=0,
        ))
    else:
        gates.append(GateResult(
            name="no_duplicate_ids",
            passed=True,
            hard=True,
            message="No id column found — duplicate check skipped",
        ))

    # Gate 5 — Target non-null (soft)
    if target_present:
        non_null = int(df["winning_amount"].notna().sum())
        pct = non_null / len(df) * 100 if len(df) else 0.0
        gates.append(GateResult(
            name="target_non_null",
            passed=non_null >= 1,
            hard=False,
            message=f"{non_null:,}/{len(df):,} rows have winning_amount ({pct:.1f}%)",
            value=non_null,
            threshold=1,
        ))

    # Gate 6 — Per-column missingness (soft, one gate per failing column)
    for col in _ML_FEATURE_COLUMNS:
        if col not in df.columns:
            continue
        missing_pct = float(df[col].isna().mean())
        if missing_pct > _MAX_MISSING_PCT:
            gates.append(GateResult(
                name=f"missing_{col}",
                passed=False,
                hard=False,
                message=(
                    f"'{col}' is {missing_pct * 100:.1f}% null "
                    f"(>{_MAX_MISSING_PCT * 100:.0f}% threshold)"
                ),
                value=round(missing_pct, 4),
                threshold=_MAX_MISSING_PCT,
            ))

    # Gate 7 — Minimum row count for model_ab retraining (soft)
    gates.append(GateResult(
        name="min_row_count",
        passed=len(df) >= _MIN_ROWS_MODEL_AB,
        hard=False,
        message=(
            f"{len(df):,} rows — below minimum {_MIN_ROWS_MODEL_AB} for retraining"
            if len(df) < _MIN_ROWS_MODEL_AB
            else f"{len(df):,} rows — sufficient for retraining"
        ),
        value=len(df),
        threshold=_MIN_ROWS_MODEL_AB,
    ))

    report.gates = gates
    return report


def main() -> None:
    import argparse
    import pathlib

    parser = argparse.ArgumentParser(
        description="Run Phase 9B data quality gates on a training dataset CSV"
    )
    parser.add_argument("file", type=pathlib.Path, help="CSV file to validate")
    parser.add_argument("--fail-soft", action="store_true",
                        help="Exit 1 on any gate failure, not just hard gates")
    args = parser.parse_args()

    df = pd.read_csv(args.file, low_memory=False)
    report = run_phase9b_quality_gates(df)
    report.print_report()

    if args.fail_soft and not report.passed:
        sys.exit(1)
    if report.hard_failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
