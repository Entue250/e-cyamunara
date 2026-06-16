"""POST /predict/model-b — winning bid prediction."""

from __future__ import annotations

import logging
import time
from typing import Any, Optional

import numpy as np
from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader, get_store
from ..df_utils import build_inference_df
from ..error_codes import ErrorCode
from ..feature_validator import validate_model_bc
from ..schemas import ModelBRequest, ModelBResponse

log = logging.getLogger(__name__)

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
        "prediction_type": "winning_bid",
        "predicted_winning_bid": winning_bid,
        "confidence_score": confidence,
        "feature_snapshot": features_dict,
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

    # Phase 9E — candidate model inference (non-blocking; failure silently omitted)
    candidate_fields: dict[str, Any] = {}
    shadow = loader.get_shadow("model_b")
    if shadow is not None:
        try:
            c_t0 = time.perf_counter()
            c_bid = _run_inference(shadow, features_dict)
            c_ms = int((time.perf_counter() - c_t0) * 1000)
            candidate_fields = {
                "candidate_version": shadow.version,
                "candidate_predicted_winning_bid": round(c_bid, 2),
                "candidate_confidence_score": shadow.confidence_score,
                "candidate_inference_ms": c_ms,
            }
        except Exception as exc:
            log.warning("Candidate model_b inference failed (skipped): %s", exc)

    return ModelBResponse(
        prediction_id=prediction_id,
        model_version=loaded.version,
        model_stage="shadow",
        predicted_winning_bid=round(winning_bid, 2),
        confidence_score=loaded.confidence_score,
        inference_ms=inference_ms,
        **candidate_fields,
    )
