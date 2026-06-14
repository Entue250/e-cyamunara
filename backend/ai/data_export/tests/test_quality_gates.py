"""Tests for data_export/quality_gates.py."""

from __future__ import annotations

import numpy as np
import pandas as pd
import pytest

from data_export.quality_gates import (
    MIN_ROWS_MODEL_AB,
    MIN_ROWS_MODEL_C,
    DataQualityReport,
    GateResult,
    run_quality_gates,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _make_df(
    n: int = 200,
    has_winning_amount: bool = True,
    bid_rate: float = 0.6,
    main_category_missing_pct: float = 0.0,
    duplicate_ids: bool = False,
) -> pd.DataFrame:
    rng = np.random.default_rng(42)
    ids = [f"id-{i}" for i in range(n)]
    if duplicate_ids:
        ids[-1] = ids[-2]  # inject one duplicate

    return pd.DataFrame(
        {
            "id": ids,
            "main_category": [
                None if rng.random() < main_category_missing_pct else "vehicle"
                for _ in range(n)
            ],
            "region": ["Central"] * n,
            "starting_price": rng.uniform(500_000, 10_000_000, n),
            "winning_amount": (
                rng.uniform(600_000, 12_000_000, n) if has_winning_amount
                else [None] * n
            ),
            "total_bids": [
                int(rng.integers(1, 20)) if rng.random() < bid_rate else 0
                for _ in range(n)
            ],
            "auction_status": ["closed"] * n,
        }
    )


# ---------------------------------------------------------------------------
# GateResult
# ---------------------------------------------------------------------------

class TestGateResult:
    def test_str_pass(self):
        g = GateResult(name="test_gate", passed=True, message="All good")
        assert "[PASS]" in str(g)

    def test_str_fail(self):
        g = GateResult(name="test_gate", passed=False, message="Too few rows")
        assert "[FAIL]" in str(g)

    def test_str_includes_value(self):
        g = GateResult(name="g", passed=True, message="ok", value=42, threshold=10)
        assert "42" in str(g) and "10" in str(g)


# ---------------------------------------------------------------------------
# DataQualityReport
# ---------------------------------------------------------------------------

class TestDataQualityReport:
    def test_passed_all_pass(self):
        report = DataQualityReport(
            mode="model_ab",
            row_count=200,
            gates=[GateResult("a", True, "ok"), GateResult("b", True, "ok")],
        )
        assert report.passed is True

    def test_failed_any_fail(self):
        report = DataQualityReport(
            mode="model_ab",
            row_count=200,
            gates=[GateResult("a", True, "ok"), GateResult("b", False, "bad")],
        )
        assert report.passed is False
        assert len(report.failed_gates) == 1

    def test_print_report_runs(self, capsys):
        report = DataQualityReport(
            mode="model_ab",
            row_count=5,
            gates=[GateResult("g", False, "too few")],
        )
        report.print_report()
        out = capsys.readouterr().out
        assert "FAIL" in out


# ---------------------------------------------------------------------------
# run_quality_gates — model_ab
# ---------------------------------------------------------------------------

class TestQualityGatesModelAB:
    def test_all_pass_with_good_data(self):
        df = _make_df(n=MIN_ROWS_MODEL_AB + 50)
        report = run_quality_gates(df, mode="model_ab")
        assert report.passed

    def test_fail_min_row_count(self):
        df = _make_df(n=MIN_ROWS_MODEL_AB - 1)
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "min_row_count")
        assert gate.passed is False
        assert report.passed is False

    def test_fail_target_not_present(self):
        df = _make_df(n=200)
        df = df.drop(columns=["winning_amount"])
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "target_column_present")
        assert gate.passed is False

    def test_fail_target_all_null(self):
        df = _make_df(n=200, has_winning_amount=False)
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "target_not_all_null")
        assert gate.passed is False

    def test_fail_high_feature_missingness(self):
        # main_category 90% missing
        df = _make_df(n=200, main_category_missing_pct=0.90)
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "feature_coverage")
        assert gate.passed is False

    def test_fail_duplicate_ids(self):
        df = _make_df(n=200, duplicate_ids=True)
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "no_duplicate_ids")
        assert gate.passed is False

    def test_no_id_column_skips_duplicate_check(self):
        df = _make_df(n=200).drop(columns=["id"])
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "no_duplicate_ids")
        assert gate.passed is True

    def test_invalid_mode_raises(self):
        df = _make_df(n=200)
        with pytest.raises(ValueError, match="mode must be"):
            run_quality_gates(df, mode="bad_mode")


# ---------------------------------------------------------------------------
# run_quality_gates — model_c
# ---------------------------------------------------------------------------

class TestQualityGatesModelC:
    def test_all_pass_with_good_data(self):
        df = _make_df(n=100, bid_rate=0.6)
        report = run_quality_gates(df, mode="model_c")
        assert report.passed

    def test_fail_min_row_count(self):
        df = _make_df(n=MIN_ROWS_MODEL_C - 1)
        report = run_quality_gates(df, mode="model_c")
        gate = next(g for g in report.gates if g.name == "min_row_count")
        assert gate.passed is False

    def test_fail_class_balance_too_low(self):
        # 0% positive class
        df = _make_df(n=100, bid_rate=0.0)
        report = run_quality_gates(df, mode="model_c")
        gate = next(g for g in report.gates if g.name == "class_balance")
        assert gate.passed is False

    def test_pass_class_balance_just_above_threshold(self):
        # 6% positive class — above the 5% minimum
        n = 200
        df = _make_df(n=n, bid_rate=0.0)
        # Set 12 rows to have bids (6%)
        df.loc[:11, "total_bids"] = 3
        report = run_quality_gates(df, mode="model_c")
        gate = next(g for g in report.gates if g.name == "class_balance")
        assert gate.passed is True

    def test_model_c_has_class_balance_gate(self):
        df = _make_df(n=100)
        report = run_quality_gates(df, mode="model_c")
        gate_names = [g.name for g in report.gates]
        assert "class_balance" in gate_names

    def test_model_ab_has_no_class_balance_gate(self):
        df = _make_df(n=200)
        report = run_quality_gates(df, mode="model_ab")
        gate_names = [g.name for g in report.gates]
        assert "class_balance" not in gate_names

    def test_report_row_count_matches(self):
        df = _make_df(n=150)
        report = run_quality_gates(df, mode="model_c")
        assert report.row_count == 150


# ---------------------------------------------------------------------------
# Real-data scenario: 10 auctions (current production state)
# ---------------------------------------------------------------------------

class TestRealDataScenario:
    def test_10_auctions_fails_model_ab_gate(self):
        """Simulate the current production state: only 10 auctions."""
        df = _make_df(n=10)
        report = run_quality_gates(df, mode="model_ab")
        gate = next(g for g in report.gates if g.name == "min_row_count")
        assert gate.passed is False
        assert report.passed is False

    def test_10_auctions_fails_model_c_gate(self):
        df = _make_df(n=10)
        report = run_quality_gates(df, mode="model_c")
        gate = next(g for g in report.gates if g.name == "min_row_count")
        assert gate.passed is False
