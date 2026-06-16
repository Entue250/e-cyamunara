"""
training_worker/trainer.py
============================
Phase 9C — Isolated training worker.

Orchestrates the full training pipeline in a container that is completely
separate from the FastAPI inference service:

  1. Build a closed-only dataset snapshot (via dataset_builder)
  2. Run Phase 9B data quality gates (HARD failures abort training)
  3. Check minimum row count gate (too few rows → skip, logged)
  4. Train each requested model via the existing run_model_* orchestrators
  5. Persist job state at every step via FileJobStore

Training NEVER runs inside the inference container. The only shared
resource is the trained_models/ directory written by run_model_*.

Minimum row gates (Phase 9D will make these configurable via DB flags):
  Model A / B : MIN_ROWS_MODEL_AB  = 100 closed auctions
  Model C     : MIN_ROWS_MODEL_C   = 100 closed auctions (bids gate is Phase 9D)

Usage (CLI):
    python -m training_worker.trainer --model all --datasource real
    python -m training_worker.trainer --model model_a --data /path/to/dataset.csv

Environment variables (required when fetching from Supabase):
    SUPABASE_URL
    SUPABASE_SERVICE_ROLE_KEY
"""

from __future__ import annotations

import argparse
import logging
import os
import pathlib
import sys
import traceback
from dataclasses import dataclass, field
from typing import Any, Callable

import pandas as pd

from training_worker.job_store import FileJobStore, TrainingJob

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Minimum row gates — Phase 9D will lower or configurer these via DB flags
# ---------------------------------------------------------------------------
MIN_ROWS_MODEL_AB: int = 100
MIN_ROWS_MODEL_C: int = 100

_VALID_MODELS = frozenset({"model_a", "model_b", "model_c", "all"})
_VALID_DATASOURCES = frozenset({"real", "synthetic"})


# ---------------------------------------------------------------------------
# Result type
# ---------------------------------------------------------------------------

@dataclass
class TrainingResult:
    skipped: bool = False
    skip_reason: str | None = None
    failed: bool = False
    error: str | None = None
    model_results: dict[str, Any] = field(default_factory=dict)
    all_passed: bool = False
    dataset_version: str | None = None
    dataset_hash: str | None = None
    rows_trained_on: int = 0


# ---------------------------------------------------------------------------
# Runner type alias
# ---------------------------------------------------------------------------

RunnerFn = Callable[[pathlib.Path | None, str], bool]


def _default_runners(datasource: str = "synthetic") -> dict[str, RunnerFn]:
    """Import the run_model_* orchestrators lazily to avoid import at module level.

    Real-data runs set promote_to_active=False so newly trained models enter
    Phase 9E candidate evaluation instead of immediately replacing active models.
    """
    from training import run_model_a, run_model_b, run_model_c
    promote = datasource == "synthetic"
    return {
        "model_a": lambda data_path, ds: run_model_a.run(
            data_path=data_path, datasource=ds, promote_to_active=promote
        ),
        "model_b": lambda data_path, ds: run_model_b.run(
            data_path=data_path, datasource=ds, promote_to_active=promote
        ),
        "model_c": lambda data_path, ds: run_model_c.run(
            data_path=data_path, datasource=ds, promote_to_active=promote
        ),
    }


# ---------------------------------------------------------------------------
# Core orchestration
# ---------------------------------------------------------------------------

def run_training_job(
    job: TrainingJob,
    store: FileJobStore,
    *,
    df: pd.DataFrame | None = None,
    dataset_path: pathlib.Path | None = None,
    supabase_url: str | None = None,
    supabase_key: str | None = None,
    out_dir: pathlib.Path | None = None,
    min_rows_ab: int = MIN_ROWS_MODEL_AB,
    min_rows_c: int = MIN_ROWS_MODEL_C,
    runners: dict[str, RunnerFn] | None = None,
) -> TrainingResult:
    """Orchestrate a single training job end-to-end.

    Parameters
    ----------
    job:
        A TrainingJob in 'queued' state, created by the caller via FileJobStore.
    store:
        FileJobStore to update job state at each lifecycle transition.
    df:
        Pre-loaded DataFrame (used in tests to bypass Supabase fetch).
    dataset_path:
        Path to an existing CSV snapshot.  Mutually exclusive with ``df``.
    supabase_url / supabase_key:
        Credentials for fetching a live snapshot when neither ``df`` nor
        ``dataset_path`` is supplied.
    out_dir:
        Directory where dataset_builder writes the snapshot CSV.
    min_rows_ab:
        Minimum closed auctions required for Model A / B training.
    min_rows_c:
        Minimum closed auctions required for Model C training.
    runners:
        Injectable dict of {model_name: callable(data_path, datasource) -> bool}.
        Defaults to the real run_model_* orchestrators.  Pass mocks in tests.

    Returns
    -------
    TrainingResult
    """
    store.mark_running(job.job_id)

    dataset_version: str | None = job.dataset_version
    dataset_hash: str | None = job.dataset_hash
    active_path: pathlib.Path | None = dataset_path

    try:
        # ── Step 1: Obtain dataset ──────────────────────────────────────────
        if df is None and active_path is None:
            if not supabase_url or not supabase_key:
                msg = "No dataset source: provide df, dataset_path, or Supabase credentials"
                store.mark_failed(job.job_id, msg)
                return TrainingResult(failed=True, error=msg)

            from data_export.dataset_builder import fetch_and_build
            manifest = fetch_and_build(
                supabase_url,
                supabase_key,
                out_dir or (pathlib.Path(__file__).resolve().parent.parent / "data" / "real"),
            )
            if manifest is None:
                reason = "no_closed_auctions_in_supabase"
                store.mark_skipped(job.job_id, reason)
                return TrainingResult(skipped=True, skip_reason=reason)

            active_path = pathlib.Path(manifest.out_path)
            dataset_version = manifest.dataset_version
            dataset_hash = manifest.dataset_hash
            log.info("Dataset snapshot: v%s (%d rows)", dataset_version, manifest.row_count)

        # ── Step 2: Load DataFrame (if not pre-supplied) ────────────────────
        if df is None:
            df = pd.read_csv(active_path, low_memory=False)  # type: ignore[arg-type]

        # ── Step 3: Phase 9B data quality gates ─────────────────────────────
        from data_export.data_quality_report import run_phase9b_quality_gates
        report = run_phase9b_quality_gates(df)

        if report.hard_failed:
            failed_names = [g.name for g in report.failed_gates if g.hard]
            msg = f"data_quality_hard_fail: {failed_names}"
            store.mark_failed(job.job_id, msg)
            return TrainingResult(failed=True, error=msg)

        # ── Step 4: Minimum row count gate ──────────────────────────────────
        # Use closed-only rows for the count (quality gates may have warned but
        # not hard-failed, so we still check here for the training minimum).
        n_rows = (
            int((df["auction_status"] == "closed").sum())
            if "auction_status" in df.columns
            else len(df)
        )

        models_requested = (
            ["model_a", "model_b", "model_c"]
            if job.model_name == "all"
            else [job.model_name]
        )

        # Determine the relevant minimum for the requested models
        min_needed = min_rows_c if models_requested == ["model_c"] else min_rows_ab
        if n_rows < min_needed:
            reason = f"insufficient_data:{n_rows}<{min_needed}"
            log.warning("Skipping training — %s", reason)
            store.mark_skipped(job.job_id, reason)
            return TrainingResult(
                skipped=True,
                skip_reason=reason,
                dataset_version=dataset_version,
                dataset_hash=dataset_hash,
                rows_trained_on=n_rows,
            )

        # ── Step 5: Train each model ─────────────────────────────────────────
        _runners = runners if runners is not None else _default_runners(job.datasource)
        model_results: dict[str, Any] = {}

        for model_name in models_requested:
            runner = _runners.get(model_name)
            if runner is None:
                model_results[model_name] = {"passed": False, "error": "no_runner"}
                continue
            try:
                passed = runner(active_path, job.datasource)
                model_results[model_name] = {"passed": passed}
                log.info("%s: %s", model_name, "PASSED" if passed else "FAILED acceptance")
            except Exception as exc:
                log.exception("Exception training %s", model_name)
                model_results[model_name] = {"passed": False, "error": str(exc)}

        all_passed = all(v.get("passed", False) for v in model_results.values())

        store.mark_completed(job.job_id, model_results)
        return TrainingResult(
            model_results=model_results,
            all_passed=all_passed,
            dataset_version=dataset_version,
            dataset_hash=dataset_hash,
            rows_trained_on=n_rows,
        )

    except Exception as exc:
        error_msg = f"{type(exc).__name__}: {exc}\n{traceback.format_exc()}"
        log.exception("Unexpected error in training job %s", job.job_id)
        store.mark_failed(job.job_id, error_msg[:2000])
        return TrainingResult(failed=True, error=str(exc))


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    parser = argparse.ArgumentParser(description="E-CYAMUNARA training worker")
    parser.add_argument(
        "--model",
        choices=sorted(_VALID_MODELS),
        default="all",
        help="Which model(s) to train (default: all)",
    )
    parser.add_argument(
        "--datasource",
        choices=sorted(_VALID_DATASOURCES),
        default="real",
    )
    parser.add_argument(
        "--data",
        type=pathlib.Path,
        default=None,
        help="Path to a pre-built dataset CSV (skips Supabase fetch)",
    )
    parser.add_argument(
        "--jobs-dir",
        type=pathlib.Path,
        default=None,
        help="Directory for job state JSON files",
    )
    args = parser.parse_args()

    store_kwargs = {}
    if args.jobs_dir:
        store_kwargs["jobs_dir"] = args.jobs_dir
    store = FileJobStore(**store_kwargs)

    job = store.create(model_name=args.model, datasource=args.datasource)
    log.info("Created training job %s (model=%s datasource=%s)", job.job_id, args.model, args.datasource)

    result = run_training_job(
        job,
        store,
        dataset_path=args.data,
        supabase_url=os.environ.get("SUPABASE_URL"),
        supabase_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY"),
    )

    if result.skipped:
        log.info("Training skipped: %s", result.skip_reason)
        sys.exit(0)
    if result.failed:
        log.error("Training failed: %s", result.error)
        sys.exit(1)

    log.info(
        "Training complete — all_passed=%s rows=%d",
        result.all_passed,
        result.rows_trained_on,
    )
    for model_name, res in result.model_results.items():
        status = "PASSED" if res.get("passed") else "FAILED"
        log.info("  %s: %s", model_name, status)

    sys.exit(0 if result.all_passed else 1)


if __name__ == "__main__":
    main()
