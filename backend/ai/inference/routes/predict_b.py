"""POST /predict/model-b — winning bid prediction."""

from __future__ import annotations

import time
from typing import Any, Optional

import numpy as np
from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader, get_store
from ..df_utils import build_inference_df
from ..error_codes import ErrorCode
from ..feature_validator import validate_model_bc
from ..schemas import ModelBRequest, ModelBResponse

router = APIRouter(tags=["predict"])


def _run_inference(loaded, features_dict: dict) -> float:
    """Return predicted winning bid in RWF."""
    df = build_inference_df(features_dict)
    X = loaded.pipeline.transform(df)
    raw_log = loaded.xgb_model.predict(X)
    return float(np.expm1(raw_log[0]))


def _build_store_row(
    auction_id: Optional[str],
    loaded,
    features_dict: dict,
    winning_bid: float,
    confidence: float,
    inference_ms: int,
) -> dict[str, Any]:
    return {
        "auction_id": auction_id,
        "model_version": loaded.version,
        "prediction_type": "winning_bid_prediction",
        "predicted_value": winning_bid,
        "confidence_score": confidence,
        "feature_snapshot": features_dict,
        "value_signal": None,
        "value_ratio": None,
        "metadata": {"inference_ms": inference_ms},
        "prediction_source": "real",
        "model_stage": "shadow",
    }


@router.post("/predict/model-b", response_model=ModelBResponse)
def predict_model_b(body: ModelBRequest, request: Request) -> ModelBResponse:
    loader = get_loader(request)
    store = get_store(request)

    features_dict = body.features.model_dump()
    errors = validate_model_bc(features_dict)
    if errors:
        raise HTTPException(
            status_code=422,
            detail={"code": ErrorCode.FEATURE_MISSING, "errors": errors},
        )

    try:
        loaded = loader.get_active("model_b")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    t0 = time.perf_counter()
    try:
        winning_bid = _run_inference(loaded, features_dict)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail={"code": ErrorCode.INTERNAL_ERROR, "detail": str(exc)},
        ) from exc
    inference_ms = int((time.perf_counter() - t0) * 1000)

    prediction_id: Optional[str] = None
    if body.store_prediction and body.auction_id:
        row = _build_store_row(
            body.auction_id, loaded, features_dict,
            winning_bid, loaded.confidence_score, inference_ms,
        )
        prediction_id = store.store(row)

    return ModelBResponse(
        prediction_id=prediction_id,
        model_version=loaded.version,
        model_stage="shadow",
        predicted_winning_bid=round(winning_bid, 2),
        confidence_score=loaded.confidence_score,
        inference_ms=inference_ms,
    )
