"""
training_worker/app.py
============================
Phase 9D — Training worker HTTP server.

Exposes a minimal REST API so the Supabase Edge Function
(trigger-weekly-retraining) can fire on-demand training runs in addition
to the built-in weekly schedule.

Endpoints:
    GET  /health          — liveness (returns 200 immediately)
    POST /train           — trigger an immediate training job
    GET  /jobs            — list the 20 most recent jobs (newest first)
    GET  /jobs/{job_id}   — get a specific job by ID

The WeeklyTrainingScheduler starts on app startup and stops on shutdown.

Run (inside the training-worker container):
    uvicorn training_worker.app:app --host 0.0.0.0 --port 8001
"""

from __future__ import annotations

import dataclasses
import logging
import os
import pathlib
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from training_worker.job_store import FileJobStore
from training_worker.schedule import WeeklyTrainingScheduler
from training_worker.trainer import run_training_job

log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Shared singletons (set once during lifespan startup)
# ---------------------------------------------------------------------------

_store: FileJobStore | None = None
_scheduler: WeeklyTrainingScheduler | None = None

_JOBS_DIR = pathlib.Path(
    os.environ.get("TRAINING_JOBS_DIR", "/app/data/training_jobs")
)


# ---------------------------------------------------------------------------
# Lifespan
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    global _store, _scheduler

    _store = FileJobStore(jobs_dir=_JOBS_DIR)

    _scheduler = WeeklyTrainingScheduler(
        _store,
        model_name=os.environ.get("TRAINING_MODEL", "all"),
        datasource=os.environ.get("TRAINING_DATASOURCE", "real"),
        supabase_url=os.environ.get("SUPABASE_URL"),
        supabase_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY"),
    )
    _scheduler.start()
    log.info("Training worker started — weekly scheduler active")

    yield

    if _scheduler:
        _scheduler.stop()
    log.info("Training worker shut down")


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="E-CYAMUNARA Training Worker",
    description="Phase 9D — isolated model retraining service",
    version="9D.0",
    lifespan=lifespan,
)


# ---------------------------------------------------------------------------
# Request / response schemas
# ---------------------------------------------------------------------------

class TrainRequest(BaseModel):
    model: str = "all"
    datasource: str = "real"


class JobResponse(BaseModel):
    job_id: str
    model_name: str
    datasource: str
    status: str
    queued_at: str
    started_at: str | None = None
    completed_at: str | None = None
    result: dict[str, Any] | None = None
    error: str | None = None
    skip_reason: str | None = None
    dataset_version: str | None = None
    dataset_hash: str | None = None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "scheduler_running": _scheduler.is_running if _scheduler else False,
    }


@app.post("/train", response_model=JobResponse, status_code=202)
async def trigger_training(req: TrainRequest):
    """Trigger an immediate training run outside the weekly schedule.

    The job is started synchronously in a background thread — this endpoint
    returns immediately with the job in 'running' or 'queued' state.
    """
    if _scheduler is None or _store is None:
        raise HTTPException(status_code=503, detail="scheduler not initialised")

    _VALID_MODELS = {"model_a", "model_b", "model_c", "all"}
    _VALID_DS = {"real", "synthetic"}
    if req.model not in _VALID_MODELS:
        raise HTTPException(status_code=422, detail=f"model must be one of {sorted(_VALID_MODELS)}")
    if req.datasource not in _VALID_DS:
        raise HTTPException(status_code=422, detail=f"datasource must be one of {sorted(_VALID_DS)}")

    # Create job, then fire asynchronously so the response is immediate.
    import threading
    job = _store.create(model_name=req.model, datasource=req.datasource)

    def _fire():
        run_training_job(
            _store.get(job.job_id),  # type: ignore[arg-type]
            _store,
            supabase_url=os.environ.get("SUPABASE_URL"),
            supabase_key=os.environ.get("SUPABASE_SERVICE_ROLE_KEY"),
        )

    threading.Thread(target=_fire, daemon=True, name=f"train-{job.job_id[:8]}").start()
    return _job_to_response(job)


@app.get("/jobs", response_model=list[JobResponse])
async def list_jobs(n: int = 20):
    if _store is None:
        raise HTTPException(status_code=503, detail="store not initialised")
    return [_job_to_response(j) for j in _store.list_recent(n=n)]


@app.get("/jobs/{job_id}", response_model=JobResponse)
async def get_job(job_id: str):
    if _store is None:
        raise HTTPException(status_code=503, detail="store not initialised")
    job = _store.get(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail=f"job {job_id} not found")
    return _job_to_response(job)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _job_to_response(job) -> JobResponse:
    d = dataclasses.asdict(job)
    return JobResponse(**d)
