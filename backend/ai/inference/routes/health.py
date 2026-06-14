from fastapi import APIRouter, Request

from ..deps import get_loader
from ..schemas import HealthResponse, ModelStatus

router = APIRouter(tags=["ops"])


@router.get("/health", response_model=HealthResponse)
def health(request: Request) -> HealthResponse:
    loader = get_loader(request)
    return HealthResponse(
        status="ok",
        models={
            name: ModelStatus(
                loaded=loader.is_loaded(name),
                version=loader.get_active(name).version if loader.is_loaded(name) else None,
                shadow_version=loader.shadow_version(name),
            )
            for name in ("model_a", "model_b", "model_c")
        },
        uptime_seconds=round(loader.uptime_seconds(), 1),
    )
