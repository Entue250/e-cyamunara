"""Tests for data_export/data_quality_report.py."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from data_export.data_quality_report import (
    DataQualityReport,
    GateResult,
    _MAX_MISSING_PCT,
    _MIN_ROWS_MODEL_AB,
    run_phase9b_quality_gates,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_clean_df(n: int = 150) -> pd.DataFrame:
    """Return a minimal valid closed-auction DataFrame that passes all gates."""
    rng = np.random.default_rng(0)
    return pd.DataFrame({
        "auction_id": [f"auc-{i:04d}" for i in range(n)],
        "auction_status": ["closed"] * n,
        "winning_amount": rng.integers(1_000_000, 5_000_000, size=n).astype(float),
        "main_category": ["Vehicles"] * n,
        "region": ["Northern"] * n,
        "starting_price": rng.integers(500_000, 4_000_000, size=n).astype(float),
        "brand": ["Toyota"] * n,
        "condition": ["Good"] * n,
        "fuel_type": ["petrol"] * n,
        "transmission": ["automatic"] * n,
        "mileage": rng.integers(10_000, 200_000, size=n).astype(float),
        "ownership_history": ["one_owner"] * n,
        "accident_history": ["none"] * n,
        "insurance_status": ["valid"] * n,
        "manufacturing_year": rng.integers(2010, 2024, size=n).astype(float),
        "asset_age": rng.integers(1, 14, size=n).astype(float),
        "auction_duration_hours": [72.0] * n,
        "has_description": [True] * n,
        "has_images": [True] * n,
    })


# ---------------------------------------------------------------------------
# Gate 1 — Closed-only (HARD)
# ---------------------------------------------------------------------------

def test_all_closed_passes_gate1() -> None:
    df = _make_clean_df()
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "closed_only")
    assert gate.passed


def test_active_row_fails_gate1_hard() -> None:
    df = _make_clean_df(150)
    df.loc[0, "auction_status"] = "active"
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "closed_only")
    assert not gate.passed
    assert gate.hard
    assert report.hard_failed


def test_draft_row_fails_gate1() -> None:
    df = _make_clean_df(150)
    df.loc[5, "auction_status"] = "draft"
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "closed_only")
    assert not gate.passed


def test_missing_auction_status_column_fails_gate1_hard() -> None:
    df = _make_clean_df().drop(columns=["auction_status"])
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "closed_only")
    assert not gate.passed
    assert gate.hard


# ---------------------------------------------------------------------------
# Gate 2 — Target present (HARD)
# ---------------------------------------------------------------------------

def test_winning_amount_present_passes_gate2() -> None:
    report = run_phase9b_quality_gates(_make_clean_df())
    gate = next(g for g in report.gates if g.name == "target_present")
    assert gate.passed


def test_missing_winning_amount_column_fails_gate2_hard() -> None:
    df = _make_clean_df().drop(columns=["winning_amount"])
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "target_present")
    assert not gate.passed
    assert gate.hard
    assert report.hard_failed


# ---------------------------------------------------------------------------
# Gate 3 — No leakage (HARD)
# ---------------------------------------------------------------------------

def test_no_leakage_passes_gate3() -> None:
    report = run_phase9b_quality_gates(_make_clean_df())
    gate = next(g for g in report.gates if g.name == "no_leakage")
    assert gate.passed


def test_no_leakage_is_hard_gate() -> None:
    report = run_phase9b_quality_gates(_make_clean_df())
    gate = next(g for g in report.gates if g.name == "no_leakage")
    assert gate.hard


# ---------------------------------------------------------------------------
# Gate 4 — No duplicate auction_id (HARD)
# ---------------------------------------------------------------------------

def test_unique_ids_pass_gate4() -> None:
    report = run_phase9b_quality_gates(_make_clean_df())
    gate = next(g for g in report.gates if g.name == "no_duplicate_ids")
    assert gate.passed


def test_duplicate_id_fails_gate4_hard() -> None:
    df = _make_clean_df(10)
    df.loc[0, "auction_id"] = df.loc[1, "auction_id"]  # introduce duplicate
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "no_duplicate_ids")
    assert not gate.passed
    assert gate.hard
    assert report.hard_failed


def test_no_id_column_gate4_passes_with_skip() -> None:
    df = _make_clean_df().drop(columns=["auction_id"])
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "no_duplicate_ids")
    assert gate.passed  # skipped = effectively passes


# ---------------------------------------------------------------------------
# Gate 5 — Target non-null (soft)
# ---------------------------------------------------------------------------

def test_some_null_winning_amount_is_soft_warn() -> None:
    df = _make_clean_df(150)
    df["winning_amount"] = None
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "target_non_null")
    assert not gate.passed
    assert not gate.hard
    assert not report.hard_failed  # only soft failure


def test_partial_null_winning_amount_passes_gate5() -> None:
    df = _make_clean_df(150)
    df.loc[:50, "winning_amount"] = None
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "target_non_null")
    assert gate.passed  # at least 1 non-null


# ---------------------------------------------------------------------------
# Gate 6 — Per-column missingness (soft)
# ---------------------------------------------------------------------------

def test_high_missing_column_produces_soft_warn() -> None:
    df = _make_clean_df(150)
    # Make mileage 80% null — exceeds the 50% threshold
    df.loc[:119, "mileage"] = None
    report = run_phase9b_quality_gates(df)
    missing_gate = next(
        (g for g in report.gates if g.name == "missing_mileage"), None
    )
    assert missing_gate is not None
    assert not missing_gate.passed
    assert not missing_gate.hard


def test_low_missing_column_no_extra_gate() -> None:
    df = _make_clean_df(150)
    df.loc[:10, "mileage"] = None  # only 7% null — within threshold
    report = run_phase9b_quality_gates(df)
    gates_names = [g.name for g in report.gates]
    assert "missing_mileage" not in gates_names


# ---------------------------------------------------------------------------
# Gate 7 — Minimum row count (soft)
# ---------------------------------------------------------------------------

def test_min_row_count_passes_with_sufficient_rows() -> None:
    report = run_phase9b_quality_gates(_make_clean_df(_MIN_ROWS_MODEL_AB))
    gate = next(g for g in report.gates if g.name == "min_row_count")
    assert gate.passed


def test_min_row_count_fails_soft_with_few_rows() -> None:
    df = _make_clean_df(10)  # way below threshold
    report = run_phase9b_quality_gates(df)
    gate = next(g for g in report.gates if g.name == "min_row_count")
    assert not gate.passed
    assert not gate.hard  # soft only


# ---------------------------------------------------------------------------
# Overall report state
# ---------------------------------------------------------------------------

def test_clean_df_report_fully_passes() -> None:
    report = run_phase9b_quality_gates(_make_clean_df(150))
    assert report.passed
    assert not report.hard_failed
    assert report.failed_gates == []


def test_hard_fail_sets_hard_failed_flag() -> None:
    df = _make_clean_df(150)
    df.loc[0, "auction_status"] = "active"
    report = run_phase9b_quality_gates(df)
    assert report.hard_failed
    assert not report.passed


def test_soft_only_fail_not_hard_failed() -> None:
    # only 10 rows → below min_row_count (soft gate)
    df = _make_clean_df(10)
    report = run_phase9b_quality_gates(df)
    assert not report.hard_failed


def test_print_report_runs_without_error(capsys) -> None:
    report = run_phase9b_quality_gates(_make_clean_df(150))
    report.print_report()
    captured = capsys.readouterr()
    assert "Phase 9B Data Quality Report" in captured.out
