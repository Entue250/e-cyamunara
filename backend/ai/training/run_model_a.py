"""
training/run_model_a.py
=======================
Phase 3D orchestrator — train, version, persist, and register Model A.

Calls train_model_a.train(save=False), runs the acceptance gate, saves versioned
artifacts to trained_models/model_a/{version}/, and registers the result.

Usage:
    python -m training.run_model_a
    python -m training.run_model_a --data /path/to/auctions.csv
    python -m training.run_model_a --datasource real
"""
from __future__ import annotations

import argparse
import pathlib
import sys
import time
from datetime import datetime, timezone

from training.config import CONFIG
from training.evaluation.acceptance import check_model_a
from training.evaluation.model_registry import ModelRegistry, make_entry
from training.persistence.artifact_io import (
    ensure_artifact_dir,
    save_pipeline,
    save_xgb_model,
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
from training import train_model_a


def run(
    data_path: pathlib.Path | None = None,
    datasource: str = "synthetic",
    promote_to_active: bool = True,
) -> bool:
    """Orchestrate Model A training → acceptance → persistence → registration.

    Returns True if the acceptance gate passed, False otherwise.
    Artifacts are saved regardless of outcome.
    When promote_to_active=False (real-data candidate evaluation), the model is
    saved and registered but NOT set as the active serving version — it enters
    Phase 9E candidate evaluation instead.
    """
    data_path = pathlib.Path(data_path or CONFIG.paths.synthetic_auctions)
    base_dir = CONFIG.paths.trained_models_dir
    registry = ModelRegistry(registry_path=CONFIG.paths.trained_models_registry_file)
    history_path = CONFIG.paths.training_history_file

    t0 = time.monotonic()
    timestamp = datetime.now(timezone.utc).isoformat()
    run_id = new_run_id()

    print(f"[run_model_a] run_id       = {run_id}")
    print(f"[run_model_a] data         = {data_path}")

    # ------------------------------------------------------------------
    # 1. Determine version before training (registry read-only at this point)
    # ------------------------------------------------------------------
    version = next_version(registry, "model_a", datasource)
    print(f"[run_model_a] version       = {version}")

    # ------------------------------------------------------------------
    # 2. Hash dataset for provenance (graceful on missing file)
    # ------------------------------------------------------------------
    d_hash = dataset_hash(data_path) if data_path.exists() else ""

    # ------------------------------------------------------------------
    # 3. Train (save=False so we control artifact placement)
    # ------------------------------------------------------------------
    print("[run_model_a] Training Model A ...")
    pipeline, xgb_model, metrics = train_model_a.train(
        data_path=data_path, save=False, datasource=datasource
    )

    # ------------------------------------------------------------------
    # 4. Acceptance gate
    # ------------------------------------------------------------------
    result = check_model_a(metrics)
    print(
        f"[run_model_a] acceptance    = {result.grade.upper()} "
        f"(passed={result.passed})"
    )
    for msg in result.failures:
        print(f"  FAIL: {msg}")
    for msg in result.warnings:
        print(f"  WARN: {msg}")

    # ------------------------------------------------------------------
    # 5. Save versioned artifacts (always, even on rejection)
    # ------------------------------------------------------------------
    out_dir = ensure_artifact_dir("model_a", version, base_dir)
    save_pipeline(pipeline, out_dir)
    save_xgb_model(xgb_model, out_dir)
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
    print(f"[run_model_a] artifacts     → {out_dir}")

    # ------------------------------------------------------------------
    # 6. Register in trained_models registry
    # ------------------------------------------------------------------
    entry = make_entry(
        "model_a",
        version,
        metrics,
        training_rows=0,
        acceptance_result=result,
        dataset_source=datasource,
    )
    registry.register(entry)
    registry.save_model_card(entry, output_dir=out_dir)
    if result.passed and promote_to_active:
        registry.set_active("model_a", version)
        print(f"[run_model_a] active        → {version}")
    elif result.passed:
        print(f"[run_model_a] candidate     → {version} (promote_to_active=False)")

    # ------------------------------------------------------------------
    # 7. Append to training history
    # ------------------------------------------------------------------
    duration = time.monotonic() - t0
    log_run(
        TrainingRun(
            run_id=run_id,
            model_name="model_a",
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
    print(f"\n[run_model_a] {status} — {version}  ({duration:.1f}s)")
    return result.passed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Orchestrate Model A training + registration"
    )
    parser.add_argument("--data", type=pathlib.Path, default=None)
    parser.add_argument("--datasource", default="synthetic")
    args = parser.parse_args()
    passed = run(data_path=args.data, datasource=args.datasource)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
