"""Model lifecycle management routes.

  GET  /models/candidates
      List all registered versions that passed acceptance but are not yet
      active — i.e., promotion candidates.

  GET  /models/{model_name}/history
      Full version history for one model (all statuses, sorted newest-first).

  POST /models/{model_name}/promote
      Promote a registered/candidate version to active. The current active
      version is automatically deprecated. Reloads the ModelLoader so
      predictions switch to the new version immediately.

  POST /models/{model_name}/rollback
      Revert to the most recent deprecated version for a model. The current
      active is deprecated. Reloads the ModelLoader immediately.
"""

from __future__ import annotations

import logging
import pathlib
import sys

from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader, get_store
from ..schemas import (
    ModelHistoryResponse,
    ModelVersionInfo,
    PromoteRequest,
    PromoteResponse,
    PromotionCandidate,
    PromotionCandidatesResponse,
    RollbackResponse,
)

# Shadow flags are stored as PostgreSQL session parameters in ai_feature_flags
_SHADOW_FLAG_KEYS = (
    "ai.model_a_shadow_version",
    "ai.model_b_shadow_version",
    "ai.model_c_shadow_version",
)

log = logging.getLogger(__name__)
router = APIRouter(tags=["lifecycle"])

_KNOWN_MODELS = frozenset({"model_a", "model_b", "model_c"})

_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent.parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_registry_or_503(request: Request):
    loader = get_loader(request)
    registry = loader.get_registry()
    if registry is None:
        raise HTTPException(status_code=503, detail="Registry not loaded")
    return loader, registry


def _reload_loader(loader, registry_path: pathlib.Path) -> None:
    """Reload all active models so the running server serves the new version."""
    try:
        loader.load_all(registry_path, shadow_flags={})
        log.info("ModelLoader reloaded after lifecycle change")
    except Exception as exc:
        log.warning("ModelLoader reload failed after lifecycle change: %s", exc)


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.get("/models/candidates", response_model=PromotionCandidatesResponse)
def list_candidates(request: Request) -> PromotionCandidatesResponse:
    """List all registered (non-active) versions that passed acceptance."""
    _, registry = _get_registry_or_503(request)

    candidates: list[PromotionCandidate] = []
    for model_name in _KNOWN_MODELS:
        for entry in registry.list_versions(model_name):
            if entry.status == "registered" and entry.acceptance_passed:
                candidates.append(
                    PromotionCandidate(
                        model_name=entry.model_name,
                        version=entry.version,
                        acceptance_grade=entry.acceptance_grade,
                        metrics=entry.metrics,
                        training_timestamp=entry.training_timestamp,
                    )
                )

    # Sort by training_timestamp descending (newest first)
    candidates.sort(key=lambda c: c.training_timestamp, reverse=True)
    return PromotionCandidatesResponse(candidates=candidates)


@router.get("/models/{model_name}/history", response_model=ModelHistoryResponse)
def model_history(model_name: str, request: Request) -> ModelHistoryResponse:
    """Return all registered versions for a model, newest first."""
    if model_name not in _KNOWN_MODELS:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown model '{model_name}'. Valid: {sorted(_KNOWN_MODELS)}",
        )
    loader, registry = _get_registry_or_503(request)

    active_entry = registry.get_active(model_name)
    active_version = active_entry.version if active_entry else None

    versions = [
        ModelVersionInfo(
            version=e.version,
            status=e.status,
            acceptance_grade=e.acceptance_grade,
            training_rows=e.training_rows,
            metrics=e.metrics,
            training_timestamp=e.training_timestamp,
            dataset_source=e.dataset_source,
        )
        for e in reversed(registry.list_versions(model_name))  # newest first
    ]
    return ModelHistoryResponse(
        model_name=model_name,
        active_version=active_version,
        versions=versions,
    )


@router.post("/models/{model_name}/promote", response_model=PromoteResponse)
def promote_model(
    model_name: str,
    body: PromoteRequest,
    request: Request,
) -> PromoteResponse:
    """Promote a version to active. Current active becomes deprecated."""
    if model_name not in _KNOWN_MODELS:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown model '{model_name}'. Valid: {sorted(_KNOWN_MODELS)}",
        )
    loader, registry = _get_registry_or_503(request)

    # Verify the requested version exists and is eligible
    versions = {e.version: e for e in registry.list_versions(model_name)}
    if body.version not in versions:
        raise HTTPException(
            status_code=404,
            detail=f"Version '{body.version}' not found for {model_name}",
        )

    entry = versions[body.version]
    if not entry.acceptance_passed:
        raise HTTPException(
            status_code=422,
            detail=(
                f"Version '{body.version}' failed the acceptance gate "
                f"(grade={entry.acceptance_grade}) and cannot be promoted."
            ),
        )

    active_entry = registry.get_active(model_name)
    previous_version = active_entry.version if active_entry else None

    if previous_version == body.version:
        raise HTTPException(
            status_code=409,
            detail=f"Version '{body.version}' is already active for {model_name}.",
        )

    try:
        registry.set_active(model_name, body.version)
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    _reload_loader(loader, registry._path)  # noqa: SLF001

    log.info("[lifecycle] promoted %s %s (was %s)", model_name, body.version, previous_version)
    return PromoteResponse(
        model_name=model_name,
        promoted_version=body.version,
        previous_version=previous_version,
        message=(
            f"{model_name} promoted to {body.version}. "
            f"Previous active ({previous_version}) deprecated. "
            "ModelLoader reloaded — new version serves predictions immediately."
        ),
    )


@router.post("/models/{model_name}/rollback", response_model=RollbackResponse)
def rollback_model(model_name: str, request: Request) -> RollbackResponse:
    """Rollback to the most recent deprecated version."""
    if model_name not in _KNOWN_MODELS:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown model '{model_name}'. Valid: {sorted(_KNOWN_MODELS)}",
        )
    loader, registry = _get_registry_or_503(request)

    active_entry = registry.get_active(model_name)
    if not active_entry:
        raise HTTPException(
            status_code=409,
            detail=f"No active version for {model_name} — nothing to roll back from.",
        )

    # Find the most recent deprecated version (previous active)
    deprecated = [
        e for e in registry.list_versions(model_name)
        if e.status == "deprecated" and e.acceptance_passed
    ]
    if not deprecated:
        raise HTTPException(
            status_code=409,
            detail=(
                f"No deprecated versions found for {model_name}. "
                "Rollback requires at least one prior active version."
            ),
        )

    # Pick the most recently trained deprecated version
    target = max(deprecated, key=lambda e: e.training_timestamp)

    try:
        registry.set_active(model_name, target.version)
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc

    _reload_loader(loader, registry._path)  # noqa: SLF001

    log.info(
        "[lifecycle] rolled back %s from %s to %s",
        model_name, active_entry.version, target.version,
    )
    return RollbackResponse(
        model_name=model_name,
        rolled_back_from=active_entry.version,
        rolled_back_to=target.version,
        message=(
            f"{model_name} rolled back from {active_entry.version} to {target.version}. "
            "ModelLoader reloaded — previous version serves predictions immediately."
        ),
    )


@router.post("/models/reload-shadow")
def reload_shadow_models(request: Request) -> dict:
    """Re-read ai_feature_flags and hot-reload shadow/candidate models.

    Called by the register-candidate-model Edge Function after updating the
    ai.model_*_shadow_version flags so the inference service starts serving
    candidate predictions without a process restart.
    """
    loader, registry = _get_registry_or_503(request)
    store = get_store(request)
    base_dir: pathlib.Path = registry._path.parent  # noqa: SLF001

    # Re-fetch shadow version flags from Supabase ai_feature_flags
    shadow_flags: dict[str, str] = {}
    try:
        rows = (
            store._client  # noqa: SLF001
            .table("ai_feature_flags")
            .select("flag_key,flag_value")
            .in_("flag_key", list(_SHADOW_FLAG_KEYS))
            .execute()
        )
        for row in (rows.data or []):
            shadow_flags[row["flag_key"]] = row.get("flag_value") or ""
    except Exception as exc:
        log.warning("Could not fetch shadow flags from Supabase: %s", exc)

    loaded_models = loader.reload_shadow(shadow_flags, base_dir)
    log.info("[lifecycle] reload-shadow complete: %s", loaded_models)
    return {
        "status": "ok",
        "shadow_flags": shadow_flags,
        "loaded_models": loaded_models,
    }
