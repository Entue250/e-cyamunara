"""Tests for training/evaluation/challenger.py.

Uses small synthetic fixtures — no real model artifacts required.
"""

from __future__ import annotations

import numpy as np
import pytest
from sklearn.datasets import make_classification, make_regression

from training.evaluation.challenger import (
    ChallengerReport,
    ModelResult,
    compare_classification,
    compare_regression,
)


# ---------------------------------------------------------------------------
# Fixtures — tiny datasets for fast tests
# ---------------------------------------------------------------------------

@pytest.fixture(scope="module")
def regression_data():
    X, y_rwf = make_regression(n_samples=400, n_features=10, noise=0.5, random_state=42)
    y_log = np.log1p(np.abs(y_rwf) + 1_000_000)
    y_rwf_pos = np.abs(y_rwf) + 1_000_000
    split = 320
    return (
        X[:split], y_log[:split],          # X_train, y_train_log
        X[split:], y_rwf_pos[split:],      # X_test, y_test_rwf
        np.log1p(y_rwf_pos[split:]),       # y_test_log
    )


@pytest.fixture(scope="module")
def classification_data():
    X, y = make_classification(
        n_samples=400, n_features=10, n_informative=5,
        n_redundant=2, random_state=42
    )
    split = 320
    return X[:split], y[:split], X[split:], y[split:]


_INCUMBENT_REGRESSION = {
    "mae_rwf": 300_000.0,
    "rmse_rwf": 600_000.0,
    "mape": 0.20,
    "r2": 0.88,
    "r2_log": 0.91,
}

_INCUMBENT_CLASSIFICATION = {
    "roc_auc": 0.75,
    "pr_auc": 0.72,
    "f1": 0.70,
    "precision": 0.68,
    "recall": 0.72,
    "ece": 0.06,
}


# ---------------------------------------------------------------------------
# ModelResult
# ---------------------------------------------------------------------------

class TestModelResult:
    def test_primary_returns_metric(self):
        m = ModelResult(label="test", metrics={"mape": 0.15, "r2": 0.90})
        assert m.primary("mape") == pytest.approx(0.15)

    def test_primary_missing_returns_nan(self):
        m = ModelResult(label="test", metrics={})
        assert np.isnan(m.primary("mape"))


# ---------------------------------------------------------------------------
# ChallengerReport
# ---------------------------------------------------------------------------

class TestChallengerReport:
    def _make_report(self, verdict: str = "DO_NOT_PROMOTE") -> ChallengerReport:
        return ChallengerReport(
            model_name="model_a",
            incumbent=ModelResult("XGBoost", {"mape": 0.20}),
            challengers=[ModelResult("RF", {"mape": 0.18})],
            winner_label="XGBoost" if verdict == "DO_NOT_PROMOTE" else "RF",
            verdict=verdict,
            primary_metric="mape",
        )

    def test_print_report_runs_without_error(self, capsys):
        self._make_report().print_report()
        out = capsys.readouterr().out
        assert "model_a" in out.lower() or "MODEL_A" in out

    def test_verdict_in_report(self, capsys):
        self._make_report(verdict="NEEDS_REVIEW").print_report()
        out = capsys.readouterr().out
        assert "NEEDS_REVIEW" in out

    def test_notes_printed(self, capsys):
        report = self._make_report()
        report.notes = ["This is a test note"]
        report.print_report()
        out = capsys.readouterr().out
        assert "test note" in out


# ---------------------------------------------------------------------------
# compare_regression
# ---------------------------------------------------------------------------

class TestCompareRegression:
    def test_returns_challenger_report(self, regression_data):
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=_INCUMBENT_REGRESSION,
            model_name="model_a",
            n_estimators=20,
        )
        assert isinstance(report, ChallengerReport)
        assert report.model_name == "model_a"

    def test_has_one_challenger(self, regression_data):
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=_INCUMBENT_REGRESSION,
            n_estimators=20,
        )
        assert len(report.challengers) == 1
        assert "RandomForest" in report.challengers[0].label

    def test_challenger_metrics_computed(self, regression_data):
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=_INCUMBENT_REGRESSION,
            n_estimators=20,
        )
        rf_metrics = report.challengers[0].metrics
        assert "mae_rwf" in rf_metrics
        assert "mape" in rf_metrics
        assert "r2" in rf_metrics
        assert rf_metrics["mae_rwf"] > 0

    def test_verdict_is_valid(self, regression_data):
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=_INCUMBENT_REGRESSION,
            n_estimators=20,
        )
        assert report.verdict in ("PROMOTE", "DO_NOT_PROMOTE", "NEEDS_REVIEW")

    def test_winner_label_non_empty(self, regression_data):
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=_INCUMBENT_REGRESSION,
            n_estimators=20,
        )
        assert report.winner_label

    def test_very_bad_incumbent_leads_to_promote(self, regression_data):
        """If incumbent MAPE is 0.99, RF should beat it by >5% -> PROMOTE."""
        X_train, y_log, X_test, y_rwf, y_log_test = regression_data
        bad_incumbent = {**_INCUMBENT_REGRESSION, "mape": 0.99}
        report = compare_regression(
            X_train, y_log, X_test, y_rwf, y_log_test,
            incumbent_metrics=bad_incumbent,
            n_estimators=20,
        )
        assert report.verdict == "PROMOTE"


# ---------------------------------------------------------------------------
# compare_classification
# ---------------------------------------------------------------------------

class TestCompareClassification:
    def test_returns_challenger_report(self, classification_data):
        X_train, y_train, X_test, y_test = classification_data
        report = compare_classification(
            X_train, y_train, X_test, y_test,
            incumbent_metrics=_INCUMBENT_CLASSIFICATION,
            model_name="model_c",
            n_estimators=20,
        )
        assert isinstance(report, ChallengerReport)
        assert report.model_name == "model_c"

    def test_has_two_challengers(self, classification_data):
        X_train, y_train, X_test, y_test = classification_data
        report = compare_classification(
            X_train, y_train, X_test, y_test,
            incumbent_metrics=_INCUMBENT_CLASSIFICATION,
            n_estimators=20,
        )
        assert len(report.challengers) == 2
        labels = [c.label for c in report.challengers]
        assert any("RandomForest" in l for l in labels)
        assert any("LogisticRegression" in l for l in labels)

    def test_challenger_metrics_in_valid_range(self, classification_data):
        X_train, y_train, X_test, y_test = classification_data
        report = compare_classification(
            X_train, y_train, X_test, y_test,
            incumbent_metrics=_INCUMBENT_CLASSIFICATION,
            n_estimators=20,
        )
        for c in report.challengers:
            auc = c.metrics.get("roc_auc", 0)
            assert 0.0 <= auc <= 1.0
            ece = c.metrics.get("ece", 0)
            assert 0.0 <= ece <= 1.0

    def test_verdict_valid(self, classification_data):
        X_train, y_train, X_test, y_test = classification_data
        report = compare_classification(
            X_train, y_train, X_test, y_test,
            incumbent_metrics=_INCUMBENT_CLASSIFICATION,
            n_estimators=20,
        )
        assert report.verdict in ("PROMOTE", "DO_NOT_PROMOTE", "NEEDS_REVIEW")

    def test_very_bad_incumbent_leads_to_promote(self, classification_data):
        """Incumbent AUC=0.50 (random); both challengers should easily beat it."""
        X_train, y_train, X_test, y_test = classification_data
        terrible_incumbent = {**_INCUMBENT_CLASSIFICATION, "roc_auc": 0.50}
        report = compare_classification(
            X_train, y_train, X_test, y_test,
            incumbent_metrics=terrible_incumbent,
            n_estimators=20,
        )
        assert report.verdict == "PROMOTE"
