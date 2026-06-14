"""FastAPI inference service — Phase 6 MLOps inference + lifecycle service."""

from __future__ import annotations

import logging
import logging.config
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI

from .config import settings
from .job_store import JobStore
from .model_loader import ModelLoader
from .prediction_store import NullPredictionStore, PredictionStore

log = logging.getLogger(__name__)


def _configure_logging() -> None:
    logging.basicConfig(
        level=getattr(logging, settings.log_level.upper(), logging.INFO),
        format="%(asctime)s %(levelname)s %(name)s — %(message)s",
    )


def _build_store() -> Any:
    if settings.prediction_store_enabled and settings.store_configured:
        log.info("Prediction store: ENABLED (Supabase %s)", settings.supabase_url)
        return PredictionStore(settings.supabase_url, settings.supabase_service_role_key)
    log.warning("Prediction store: DISABLED (SUPABASE_URL or key not set, or disabled via env)")
    return NullPredictionStore()


def _fetch_shadow_flags(store: Any) -> dict[str, str]:
    """Read ai_feature_flags shadow version entries from Supabase.

    Returns an empty dict if Supabase is unreachable — shadow models are
    optional and their absence must not prevent startup.
    """
    if isinstance(store, NullPredictionStore):
        return {}
    try:
        result = (
            store._client  # noqa: SLF001
            .table("ai_feature_flags")
            .select("key,value")
            .in_("key", [
                "ai.model_a_shadow_version",
                "ai.model_b_shadow_version",
                "ai.model_c_shadow_version",
            ])
            .execute()
        )
        return {row["key"]: row["value"] for row in (result.data or [])}
    except Exception as exc:
        log.warning("Could not fetch shadow flags from Supabase (%s); no shadow models loaded", exc)
        return {}


@asynccontextmanager
async def _lifespan(app: FastAPI):
    _configure_logging()

    store = _build_store()
    shadow_flags = _fetch_shadow_flags(store)

    loader = ModelLoader.get_instance()
    loader.load_all(settings.registry_path, shadow_flags=shadow_flags)

    app.state.loader = loader
    app.state.store = store
    app.state.job_store = JobStore()
    log.info("Inference service ready — all models loaded")
    yield
    log.info("Inference service shutting down")


def create_app(
    *,
    loader: Any = None,
    store: Any = None,
) -> FastAPI:
    """Create the FastAPI application.

    Parameters
    ----------
    loader:
        Inject a ModelLoader (or mock). If None, startup loads real models.
    store:
        Inject a PredictionStore (or mock). If None, startup creates the real store.
    """
    lifespan_fn = _lifespan

    application = FastAPI(
        title="E-CYAMUNARA AI Inference",
        version="6.0.0",
        description=(
            "Phase 6 MLOps inference service. "
            "Provides real XGBoost predictions (prediction_source='real', model_stage='shadow'), "
            "business-friendly URL aliases, retraining orchestration, and model lifecycle management. "
            "Predictions are NOT visible to clients until production promotion."
        ),
        lifespan=lifespan_fn,
    )

    # Inject state directly for test / programmatic use (bypasses lifespan)
    if loader is not None:
        application.state.loader = loader
        application.state.store = store if store is not None else NullPredictionStore()
        application.state.job_store = JobStore()

    from .routes import (  # noqa: PLC0415
        health, models,
        predict_a, predict_b, predict_c,
        predict_aliases, retrain, lifecycle,
    )

    application.include_router(health.router)
    application.include_router(models.router)
    application.include_router(predict_a.router)
    application.include_router(predict_b.router)
    application.include_router(predict_c.router)
    application.include_router(predict_aliases.router)
    application.include_router(retrain.router)
    application.include_router(lifecycle.router)

    return application


# Module-level app instance for uvicorn (must be last — routes are imported inside create_app)
app = create_app()
