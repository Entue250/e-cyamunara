"""
Phase 5 — Real-Data Training Pipeline Orchestrator
====================================================

Runs the full Phase 5 workflow:

  Step 1  Export real auction data from Supabase (if --datasource real)
  Step 2  Load dataset (real or synthetic)
  Step 3  Run data quality gates
  Step 4  If gates pass: train challenger models and compare vs incumbent
  Step 5  Generate Phase 5 summary report
  Step 6  STOP — never auto-promote; output promotion candidates only

Usage::

    # Run on synthetic data (default — always available, gates will pass)
    cd backend/ai
    python -m run_phase5

    # Run on real Supabase data
    python -m run_phase5 --datasource real \\
        --supabase-url https://xxx.supabase.co \\
        --supabase-key <service-role-key>

    # Run on a pre-exported CSV
    python -m run_phase5 --data path/to/auctions.csv --datasource real

Environment variables (alternative to CLI flags):
    SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY
"""

from __future__ import annotations

import argparse
import os
import pathlib
import sys
import time

import numpy as np

# Resolve ai root so imports work when running as __main__
_AI_ROOT = pathlib.Path(__file__).resolve().parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))

from training.config import CONFIG
from training.datasets.loaders import load_auctions, describe_auctions
from training.datasets.filters import (
    filter_closed,
    filter_has_winning_amount,
)
from training.datasets.splitter import temporal_split
from training.preprocessing.pipeline_builder import build_pipeline
from training.evaluation.model_registry import ModelRegistry
from training.evaluation.challenger import (
    compare_regression,
    compare_classification,
    ChallengerReport,
)
from data_export.quality_gates import run_quality_gates, DataQualityReport


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _load_real_data(
    supabase_url: str,
    supabase_key: str,
    out_dir: pathlib.Path,
) -> pathlib.Path:
    from data_export.export_supabase import export
    print("[phase5] Exporting real data from Supabase...")
    result = export(url=supabase_url, key=supabase_key, out_dir=out_dir)
    if not result.ok:
        for err in result.errors:
            print(f"  ERROR: {err}", file=sys.stderr)
        sys.exit(1)
    print(f"[phase5] Exported {result.row_count} rows -> {result.out_path}")
    return result.out_path


def _print_section(title: str) -> None:
    bar = "=" * 60
    print(f"\n{bar}")
    print(f"  {title}")
    print(bar)


def _run_regression_challenger(
    df,
    model_name: str,
    registry: ModelRegistry,
    datasource: str,
    n_rf_trees: int,
) -> ChallengerReport | None:
    """Train regression challenger for model_a or model_b."""
    _print_section(f"Challenger Evaluation — {model_name.upper()}")

    entry = registry.get_active(model_name)
    if entry is None:
        print(f"  No active incumbent found for {model_name} — skipping challenger.")
        return None

    incumbent_metrics = entry.metrics
    print(f"  Incumbent: {entry.version} "
          f"(MAPE={incumbent_metrics.get('mape', '?'):.4f})")

    # Filter dataset for regression target
    df_filtered = filter_closed(df)
    df_filtered = filter_has_winning_amount(df_filtered)
    if len(df_filtered) < 10:
        print(f"  Too few rows after filtering ({len(df_filtered)}) — skipping.")
        return None

    train_df, _, test_df = temporal_split(df_filtered)

    y_train_log = np.log1p(train_df["winning_amount"].values.astype(float))
    y_test_rwf = test_df["winning_amount"].values.astype(float)
    y_test_log = np.log1p(y_test_rwf)

    context = "model_a" if model_name == "model_a" else "model_b"
    pipeline = build_pipeline(context)
    X_train = pipeline.fit_transform(train_df, y_train_log)
    X_test = pipeline.transform(test_df)

    return compare_regression(
        X_train, y_train_log, X_test, y_test_rwf, y_test_log,
        incumbent_metrics=incumbent_metrics,
        model_name=model_name,
        n_estimators=n_rf_trees,
    )


def _run_classification_challenger(
    df,
    registry: ModelRegistry,
    n_rf_trees: int,
) -> ChallengerReport | None:
    """Train classification challengers for model_c."""
    _print_section("Challenger Evaluation — MODEL_C")

    entry = registry.get_active("model_c")
    if entry is None:
        print("  No active incumbent found for model_c — skipping challenger.")
        return None

    incumbent_metrics = entry.metrics
    auc_val = incumbent_metrics.get("roc_auc") or incumbent_metrics.get("auc_roc")
    auc_str = f"{auc_val:.4f}" if auc_val is not None else "?"
    print(f"  Incumbent: {entry.version} (AUC={auc_str})")

    df_closed = filter_closed(df)
    if len(df_closed) < 10:
        print(f"  Too few rows after filtering ({len(df_closed)}) — skipping.")
        return None

    train_df, _, test_df = temporal_split(df_closed)

    y_train = (train_df["total_bids"].fillna(0) > 0).astype(int).values
    y_test = (test_df["total_bids"].fillna(0) > 0).astype(int).values

    pipeline = build_pipeline("model_c")
    X_train = pipeline.fit_transform(train_df, y_train)
    X_test = pipeline.transform(test_df)

    return compare_classification(
        X_train, y_train, X_test, y_test,
        incumbent_metrics=incumbent_metrics,
        n_estimators=n_rf_trees,
    )


def _print_phase5_summary(
    datasource: str,
    data_path: pathlib.Path,
    report_ab: DataQualityReport,
    report_c: DataQualityReport,
    challenger_reports: list[ChallengerReport | None],
) -> None:
    _print_section("PHASE 5 SUMMARY REPORT")

    print(f"  Datasource  : {datasource}")
    print(f"  Data file   : {data_path}")
    print(f"  Model AB gate: {'PASS' if report_ab.passed else 'FAIL'}")
    print(f"  Model C gate : {'PASS' if report_c.passed else 'FAIL'}")
    print()

    promote_candidates: list[str] = []
    for cr in challenger_reports:
        if cr is None:
            continue
        status = cr.verdict
        print(f"  {cr.model_name:<10}: verdict={status:<18} winner={cr.winner_label}")
        if cr.verdict == "PROMOTE":
            promote_candidates.append(cr.model_name)

    print()
    if promote_candidates:
        print("  PROMOTION CANDIDATES (require manual review before promoting):")
        for m in promote_candidates:
            print(f"    - {m}")
    else:
        print("  No models are promotion candidates.")

    print()
    print("  IMPORTANT: No automatic promotion performed.")
    print("  To promote a candidate, use Phase 6 /model-promote endpoint.")
    print()


# ---------------------------------------------------------------------------
# Main orchestrator
# ---------------------------------------------------------------------------

def run(
    datasource: str = "synthetic",
    data_path: pathlib.Path | None = None,
    supabase_url: str = "",
    supabase_key: str = "",
    n_rf_trees: int = 200,
) -> None:
    t0 = time.monotonic()
    registry = ModelRegistry(
        registry_path=CONFIG.paths.trained_models_registry_file
    )

    # ------------------------------------------------------------------
    # Step 1: Obtain dataset
    # ------------------------------------------------------------------
    _print_section("Step 1 — Data Acquisition")
    if data_path is not None:
        print(f"  Using provided data file: {data_path}")
    elif datasource == "real":
        url = supabase_url or os.environ.get("SUPABASE_URL", "")
        key = supabase_key or os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
        if not url or not key:
            print(
                "  ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required "
                "for --datasource real",
                file=sys.stderr,
            )
            sys.exit(1)
        out_dir = CONFIG.paths.ai_dir / "data" / "real"
        data_path = _load_real_data(url, key, out_dir)
    else:
        data_path = CONFIG.paths.synthetic_auctions
        print(f"  Using synthetic data: {data_path}")

    # ------------------------------------------------------------------
    # Step 2: Load
    # ------------------------------------------------------------------
    _print_section("Step 2 — Load Dataset")
    df = load_auctions(data_path)
    print(describe_auctions(df))

    # ------------------------------------------------------------------
    # Step 3: Quality gates
    # ------------------------------------------------------------------
    _print_section("Step 3 — Data Quality Gates")
    report_ab = run_quality_gates(df, mode="model_ab")
    report_ab.print_report()

    report_c = run_quality_gates(df, mode="model_c")
    report_c.print_report()

    # ------------------------------------------------------------------
    # Step 4: Challenger evaluation (only if gates pass)
    # ------------------------------------------------------------------
    challenger_reports: list[ChallengerReport | None] = []

    if not report_ab.passed:
        print("\n[phase5] Model A/B gates FAILED — skipping regression challengers.")
    else:
        cr_a = _run_regression_challenger(df, "model_a", registry, datasource, n_rf_trees)
        cr_b = _run_regression_challenger(df, "model_b", registry, datasource, n_rf_trees)
        if cr_a:
            cr_a.print_report()
            challenger_reports.append(cr_a)
        if cr_b:
            cr_b.print_report()
            challenger_reports.append(cr_b)

    if not report_c.passed:
        print("\n[phase5] Model C gates FAILED — skipping classification challengers.")
    else:
        cr_c = _run_classification_challenger(df, registry, n_rf_trees)
        if cr_c:
            cr_c.print_report()
            challenger_reports.append(cr_c)

    # ------------------------------------------------------------------
    # Step 5: Summary
    # ------------------------------------------------------------------
    _print_phase5_summary(
        datasource, data_path, report_ab, report_c, challenger_reports
    )

    elapsed = time.monotonic() - t0
    print(f"  Phase 5 completed in {elapsed:.1f}s")


def main() -> None:
    parser = argparse.ArgumentParser(description="Phase 5 — Real-Data Training Pipeline")
    parser.add_argument(
        "--datasource",
        choices=["synthetic", "real"],
        default="synthetic",
        help="'synthetic' uses the local CSV; 'real' exports from Supabase first",
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        help="Path to a pre-exported CSV (skips Supabase export step)",
    )
    parser.add_argument("--supabase-url", default="")
    parser.add_argument("--supabase-key", default="")
    parser.add_argument(
        "--rf-trees",
        type=int,
        default=200,
        help="Number of trees for RandomForest challengers (default: 200)",
    )
    args = parser.parse_args()

    run(
        datasource=args.datasource,
        data_path=args.data,
        supabase_url=args.supabase_url,
        supabase_key=args.supabase_key,
        n_rf_trees=args.rf_trees,
    )


if __name__ == "__main__":
    main()
