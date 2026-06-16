"""
training/run_model_b.py
=======================
Phase 3D orchestrator — train, version, persist, and register Model B.

train_model_b.train() always saves artifacts to out_dir and raises SystemExit
if its internal threshold check fails.  This orchestrator:
  - Directs the output to the versioned artifact directory
  - Catches SystemExit (raised on internal threshold failure) and extracts
    metrics from the saved metrics file so the acceptance gate can run
  - Adds SHA-256 checksums to the saved files
  - Registers the result (pass or fail) in the trained_models registry

Usage:
    python -m training.run_model_b
    python -m training.run_model_b --data /path/to/auctions.csv
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys
import time
from datetime import datetime, timezone

from training.config import CONFIG
from training.evaluation.acceptance import check_model_b
from training.evaluation.model_registry import ModelRegistry, make_entry
from training.persistence.artifact_io import (
    ensure_artifact_dir,
    compute_and_write_checksum,
    save_provenance,
)
from training.persistence.version_manager import next_version
from training.persistence.training_history import (
    TrainingRun,
    new_run_id,
    dataset_hash,
    log_run,
)
from training import train_model_b

# File names written by train_model_b.train()
_PIPELINE_FILE = "model_b_pipeline.joblib"
_BOOSTER_FILE  = "model_b_xgb.ubj"
_METRICS_FILE  = "model_b_metrics.json"


def _read_saved_metrics(out_dir: pathlib.Path) -> tuple[dict, int, int, int]:
    """Extract metrics and row counts from the JSON file train_model_b saved."""
    mf = out_dir / _METRICS_FILE
    if not mf.exists():
        return {}, 0, 0, 0
    payload = json.loads(mf.read_text(encoding="utf-8"))
    # train_model_b nests metrics under a "metrics" key alongside row counts
    metrics = payload.get("metrics", payload)
    return (
        metrics,
        int(payload.get("train_rows", 0)),
        int(payload.get("val_rows", 0)),
        int(payload.get("test_rows", 0)),
    )


def run(
    data_path: pathlib.Path | None = None,
    datasource: str = "synthetic",
) -> bool:
    """Orchestrate Model B training → acceptance → persistence → registration."""
    data_path = pathlib.Path(data_path or CONFIG.paths.synthetic_auctions)
    base_dir = CONFIG.paths.trained_models_dir
    registry = ModelRegistry(registry_path=CONFIG.paths.trained_models_registry_file)
    history_path = CONFIG.paths.training_history_file

    t0 = time.monotonic()
    timestamp = datetime.now(timezone.utc).isoformat()
    run_id = new_run_id()

    print(f"[run_model_b] run_id       = {run_id}")
    print(f"[run_model_b] data         = {data_path}")

    version = next_version(registry, "model_b", datasource)
    print(f"[run_model_b] version       = {version}")

    d_hash = dataset_hash(data_path) if data_path.exists() else ""

    # train_model_b always saves to out_dir — direct it to the versioned dir
    out_dir = ensure_artifact_dir("model_b", version, base_dir)

    print("[run_model_b] Training Model B ...")
    train_rows = val_rows = test_rows = 0
    try:
        metrics = train_model_b.train(data_path=data_path, out_dir=out_dir, datasource=datasource)
        _, train_rows, val_rows, test_rows = _read_saved_metrics(out_dir)
    except SystemExit:
        # train_model_b raises SystemExit when its internal gates fail.
        # Artifacts are already saved; read metrics from the saved file.
        metrics, train_rows, val_rows, test_rows = _read_saved_metrics(out_dir)

    # Add checksums to the files train_model_b saved, then rename to the
    # standard convention used by all other models so artifact_io.load_pipeline
    # and load_xgb_model can find them without caller-supplied filenames.
    _RENAME_MAP = {
        _PIPELINE_FILE: "pipeline.joblib",
        _BOOSTER_FILE:  "model.ubj",
    }
    for orig_name, std_name in _RENAME_MAP.items():
        orig_path = out_dir / orig_name
        if orig_path.exists():
            compute_and_write_checksum(orig_path)
            std_path = out_dir / std_name
            orig_path.rename(std_path)
            sha_orig = out_dir / (orig_name + ".sha256")
            sha_std  = out_dir / (std_name  + ".sha256")
            if sha_orig.exists():
                sha_orig.rename(sha_std)

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
    print(f"[run_model_b] artifacts     → {out_dir}")

    # Acceptance gate (handles both "mae" and "mae_rwf" key names)
    result = check_model_b(metrics)
    print(
        f"[run_model_b] acceptance    = {result.grade.upper()} "
        f"(passed={result.passed})"
    )
    for msg in result.failures:
        print(f"  FAIL: {msg}")
    for msg in result.warnings:
        print(f"  WARN: {msg}")

    entry = make_entry(
        "model_b",
        version,
        metrics,
        training_rows=train_rows,
        acceptance_result=result,
        dataset_source=datasource,
    )
    registry.register(entry)
    registry.save_model_card(entry, output_dir=out_dir)
    if result.passed:
        registry.set_active("model_b", version)
        print(f"[run_model_b] active        → {version}")

    duration = time.monotonic() - t0
    log_run(
        TrainingRun(
            run_id=run_id,
            model_name="model_b",
            version=version,
            training_timestamp=timestamp,
            dataset_source=datasource,
            training_rows=train_rows,
            val_rows=val_rows,
            test_rows=test_rows,
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
    print(f"\n[run_model_b] {status} — {version}  ({duration:.1f}s)")
    return result.passed


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Orchestrate Model B training + registration"
    )
    parser.add_argument("--data", type=pathlib.Path, default=None)
    parser.add_argument("--datasource", default="synthetic")
    args = parser.parse_args()
    passed = run(data_path=args.data, datasource=args.datasource)
    sys.exit(0 if passed else 1)


if __name__ == "__main__":
    main()
