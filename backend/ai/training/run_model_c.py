"""
training/run_model_c.py
=======================
Phase 3D orchestrator — train, version, persist, and register Model C.

train_model_c.train(save=False) returns (pipeline, calibrated, metrics).
The raw XGBoost model is extracted from the calibrated wrapper via
PlattScaler.estimator and saved as model.ubj for archival.

Usage:
    python -m training.run_model_c
    python -m training.run_model_c --data /path/to/auctions.csv
"""
from __future__ import annotations

import argparse
import pathlib
import sys
import time
from datetime import datetime, timezone

from training.config import CONFIG
from training.evaluation.acceptance import check_model_c
from training.evaluation.model_registry import ModelRegistry, make_entry
from training.persistence.artifact_io import (
    ensure_artifact_dir,
    save_pipeline,
    save_xgb_model,
    save_calibrated_model,
    save_metrics,
    save_provenance,
)
from training.persistence.version_manager import next_version
from training.persistence.training_history import (
    TrainingRun,
    new_run_id,
    dataset_hash,
    log_run,
)
from training import train_model_c


def run(
    data_path: pathlib.Path | None = None,
    datasource: str = "synthetic",
) -> bool:
    """Orchestrate Model C training → acceptance → persistence → registration."""
    data_path = pathlib.Path(data_path or CONFIG.paths.synthetic_auctions)
    base_dir = CONFIG.paths.trained_models_dir
    registry = ModelRegistry(registry_path=CONFIG.paths.trained_models_registry_file)
    history_path = CONFIG.paths.training_history_file

    t0 = time.monotonic()
    timestamp = datetime.now(timezone.utc).isoformat()
    run_id = new_run_id()

    print(f"[run_model_c] run_id       = {run_id}")
    print(f"[run_model_c] data         = {data_path}")

    version = next_version(registry, "model_c", datasource)
    print(f"[run_model_c] version       = {version}")

    d_hash = dataset_hash(data_path) if data_path.exists() else ""

    print("[run_model_c] Training Model C ...")
    pipeline, calibrated, metrics = train_model_c.train(
        data_path=data_path, save=False, datasource=datasource
    )

    result = check_model_c(metrics)
    print(
        f"[run_model_c] acceptance    = {result.grade.upper()} "
        f"(passed={result.passed})"
    )
    for msg in result.failures:
        print(f"  FAIL: {msg}")
    for msg in result.warnings:
        print(f"  WARN: {msg}")

    out_dir = ensure_artifact_dir("model_c", version, base_dir)
    save_pipeline(pipeline, out_dir)
    save_calibrated_model(calibrated, out_dir)

    # Extract the raw XGBoost classifier from the Platt-calibrated wrapper.
    # PlattScaler stores the raw model directly as .estimator
    raw_xgb = calibrated.estimator
    save_xgb_model(raw_xgb, out_dir)

    save_metrics(metrics, out_dir)
    save_provenance(
        {
            "dataset_source": datasource,
            "data_file": str(data_path),
            "dataset_hash": d_hash,
            "feature_set_version": CONFIG.feature_set_version,
            "training_timestamp": timestamp,
        },
        out_dir,
    )
    print(f"[run_model_c] artifacts     → {out_dir}")

    entry = make_entry(
        "model_c",
        version,
        metrics,
        training_rows=0,
        acceptance_result=result,
        dataset_source=datasource,
    )
    registry.register(entry)
    registry.save_model_card(entry, output_dir=out_dir)
    if result.passed:
        registry.set_active("model_c", version)
        print(f"[run_model_c] active        → {version}")

    duration = time.monotonic() - t0
    log_run(
        TrainingRun(
            run_id=run_id,
            model_name="model_c",
            version=version,
            training_timestamp=timestamp,
            dataset_source=datasource,
            training_rows=0,
            val_rows=0,
            test_rows=0,
            metrics=metrics,
            acceptance_passed=result.passed,
            acceptance_grade=result.grade,
            acceptance_failures=result.failures,
            duration_seconds=round(duration, 2),
            dataset_hash=d_hash,
        ),
        history_path,
    )

    status = "PASSED" if result.passed else "FAILED"
    print(f"\n[run_model_c] {status} — {version}  ({duration:.1f}s)")
    return result.passed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Orchestrate Model C training + registration"
    )
    parser.add_argument("--data", type=pathlib.Path, default=None)
    parser.add_argument("--datasource", default="synthetic")
    args = parser.parse_args()
    passed = run(data_path=args.data, datasource=args.datasource)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
