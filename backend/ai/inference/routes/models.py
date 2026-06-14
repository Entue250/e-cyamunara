from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader
from ..schemas import ModelsActiveResponse, VersionInfo

router = APIRouter(tags=["registry"])


@router.get("/models/active", response_model=ModelsActiveResponse)
def models_active(request: Request) -> ModelsActiveResponse:
    loader = get_loader(request)
    registry = loader.get_registry()
    if registry is None:
        raise HTTPException(status_code=503, detail="Registry not loaded")

    def _info(name: str) -> VersionInfo:
        loaded = loader.get_active(name)
        entry = registry.get_active(name)
        return VersionInfo(
            version=loaded.version,
            status=entry.status if entry else "unknown",
            acceptance_grade=entry.acceptance_grade if entry else "unknown",
            training_rows=entry.training_rows if entry else 0,
            metrics=entry.metrics if entry else {},
            feature_count=entry.feature_count if entry else 0,
        )

    return ModelsActiveResponse(
        model_a=_info("model_a"),
        model_b=_info("model_b"),
        model_c=_info("model_c"),
    )
