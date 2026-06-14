"""Business-friendly URL aliases for the three prediction endpoints.

These routes are intended for consumption by Phase 7 Edge Functions and
external integrations. They delegate entirely to the same handlers as
/predict/model-a, /predict/model-b, and /predict/model-c.

  POST /predict-price              → same as POST /predict/model-a
  POST /predict-winning-bid        → same as POST /predict/model-b
  POST /predict-winning-probability → same as POST /predict/model-c
"""

from __future__ import annotations

from fastapi import APIRouter, Request

from ..schemas import (
    ModelARequest, ModelAResponse,
    ModelBRequest, ModelBResponse,
    ModelCRequest, ModelCResponse,
)
from .predict_a import predict_model_a
from .predict_b import predict_model_b
from .predict_c import predict_model_c

router = APIRouter(tags=["predict"])


@router.post(
    "/predict-price",
    response_model=ModelAResponse,
    summary="Estimate fair market value (alias for /predict/model-a)",
)
def predict_price(body: ModelARequest, request: Request) -> ModelAResponse:
    return predict_model_a(body, request)


@router.post(
    "/predict-winning-bid",
    response_model=ModelBResponse,
    summary="Predict expected winning bid (alias for /predict/model-b)",
)
def predict_winning_bid(body: ModelBRequest, request: Request) -> ModelBResponse:
    return predict_model_b(body, request)


@router.post(
    "/predict-winning-probability",
    response_model=ModelCResponse,
    summary="Predict bid probability (alias for /predict/model-c)",
)
def predict_winning_probability(body: ModelCRequest, request: Request) -> ModelCResponse:
    return predict_model_c(body, request)
