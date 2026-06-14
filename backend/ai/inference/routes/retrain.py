"""Retraining orchestration routes.

  POST /retrain-models
      Queue a retraining job for one or all models. Runs the existing
      run_model_x.run() orchestrators as a FastAPI BackgroundTask
      (non-blocking — returns immediately with a job_id).

  GET  /retrain-models/{job_id}
      Poll the status of a queued or running retraining job.

  GET  /retrain-models
      List the 20 most recent jobs (newest first).
"""

from __future__ import annotations

import logging
import pathlib
import sys

from fastapi import APIRouter, BackgroundTasks, HTTPException, Request

from ..deps import get_loader
from ..job_store import JobStore, TrainingJob, get_job_store
from ..schemas import RetrainRequest, RetrainResponse, TrainingJobStatus

log = logging.getLogger(__name__)
router = APIRouter(tags=["retrain"])

_VALID_MODELS = frozenset({"model_a", "model_b", "model_c", "all"})

# Resolve backend/ai so training imports work regardless of cwd
_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))


# ---------------------------------------------------------------------------
# Background task
# ---------------------------------------------------------------------------

def _run_training(
    job: TrainingJob,
    store: JobStore,
    registry_path: pathlib.Path,
    loader,
) -> None:
    """Run model training in a background thread and update the job store."""
    store.mark_running(job.job_id)
    log.info("[retrain] job=%s model=%s datasource=%s — started",
             job.job_id, job.model_name, job.datasource)

    data_path = pathlib.Path(job.data_path) if job.data_path else None

    try:
        from training.run_model_a import run as run_a
        from training.run_model_b import run as run_b
        from training.run_model_c import run as run_c

        results: dict[str, bool] = {}

        targets = (
            ["model_a", "model_b", "model_c"]
            if job.model_name == "all"
            else [job.model_name]
        )

        for name in targets:
            runner = {"model_a": run_a, "model_b": run_b, "model_c": run_c}[name]
            passed = runner(data_path=data_path, datasource=job.datasource)
            results[name] = passed
            log.info("[retrain] job=%s %s acceptance=%s", job.job_id, name, passed)

        # Reload active models so the server starts serving the new version
        shadow_flags: dict = {}
        loader.load_all(registry_path, shadow_flags=shadow_flags)
        log.info("[retrain] job=%s — models reloaded after training", job.job_id)

        store.mark_completed(job.job_id, result=results)
        log.info("[retrain] job=%s — completed results=%s", job.job_id, results)

    except Exception as exc:
        log.exception("[retrain] job=%s — failed: %s", job.job_id, exc)
        store.mark_failed(job.job_id, error=str(exc))


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post("/retrain-models", response_model=RetrainResponse, status_code=202)
def queue_retrain(
    body: RetrainRequest,
    background_tasks: BackgroundTasks,
    request: Request,
) -> RetrainResponse:
    """Queue a retraining job. Returns immediately with a job_id (HTTP 202)."""
    store: JobStore = get_job_store(request)
    loader = get_loader(request)
    registry = loader.get_registry()
    registry_path = registry._path if registry else _AI_ROOT / "trained_models" / "registry.json"

    job = store.create(
        model_name=body.model_name,
        datasource=body.datasource,
        data_path=body.data_path,
    )

    background_tasks.add_task(
        _run_training, job, store, registry_path, loader
    )

    log.info("[retrain] queued job=%s model=%s", job.job_id, body.model_name)
    return RetrainResponse(
        job_id=job.job_id,
        status="queued",
        model_name=body.model_name,
        datasource=body.datasource,
        message=(
            f"Retraining queued for {body.model_name} "
            f"(datasource={body.datasource}). Poll /retrain-models/{job.job_id} for status."
        ),
    )


@router.get("/retrain-models/{job_id}", response_model=TrainingJobStatus)
def get_retrain_status(job_id: str, request: Request) -> TrainingJobStatus:
    """Return the current status of a retraining job."""
    store: JobStore = get_job_store(request)
    job = store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"Job '{job_id}' not found")
    return TrainingJobStatus(
        job_id=job.job_id,
        model_name=job.model_name,
        datasource=job.datasource,
        status=job.status,
        elapsed_seconds=job.elapsed_seconds,
        result=job.result,
        error=job.error,
    )


@router.get("/retrain-models", response_model=list[TrainingJobStatus])
def list_retrain_jobs(request: Request) -> list[TrainingJobStatus]:
    """List the 20 most recent retraining jobs (newest first)."""
    store: JobStore = get_job_store(request)
    return [
        TrainingJobStatus(
            job_id=j.job_id,
            model_name=j.model_name,
            datasource=j.datasource,
            status=j.status,
            elapsed_seconds=j.elapsed_seconds,
            result=j.result,
            error=j.error,
        )
        for j in store.list_recent(20)
    ]
