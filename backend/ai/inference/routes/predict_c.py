"""POST /predict/model-c — bid probability classification."""

from __future__ import annotations

import logging
import time
from typing import Any, Optional

from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader, get_store
from ..df_utils import build_inference_df
from ..error_codes import ErrorCode
from ..feature_validator import validate_model_bc
from ..schemas import ModelCRequest, ModelCResponse

log = logging.getLogger(__name__)

router = APIRouter(tags=["predict"])


def _run_inference(loaded, features_dict: dict) -> float:
    """Return calibrated bid probability [0, 1]."""
    df = build_inference_df(features_dict)
    X = loaded.pipeline.transform(df)
    # PlattScaler.predict_proba returns shape (n, 2); column 1 is P(bid)
    proba = loaded.calibrated.predict_proba(X)
    return float(proba[0, 1])


def _build_store_row(
    auction_id: Optional[str],
    loaded,
    features_dict: dict,
    probability: float,
    confidence: float,
    inference_ms: int,
) -> dict[str, Any]:
    return {
        "auction_id": auction_id,
        "model_version": loaded.version,
        "prediction_type": "bid_probability",
        "predicted_probability": probability,
        "confidence_score": confidence,
        "feature_snapshot": features_dict,
        "prediction_source": "real",
        "model_stage": "shadow",
    }


@router.post("/predict/model-c", response_model=ModelCResponse)
def predict_model_c(body: ModelCRequest, request: Request) -> ModelCResponse:
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
        loaded = loader.get_active("model_c")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    t0 = time.perf_counter()
    try:
        probability = _run_inference(loaded, features_dict)
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
            probability, loaded.confidence_score, inference_ms,
        )
        prediction_id = store.store(row)

    # Phase 9E — candidate model inference (non-blocking; failure silently omitted)
    candidate_fields: dict[str, Any] = {}
    shadow = loader.get_shadow("model_c")
    if shadow is not None:
        try:
            c_t0 = time.perf_counter()
            c_prob = _run_inference(shadow, features_dict)
            c_ms = int((time.perf_counter() - c_t0) * 1000)
            candidate_fields = {
                "candidate_version": shadow.version,
                "candidate_predicted_probability": round(c_prob, 4),
                "candidate_confidence_score": shadow.confidence_score,
                "candidate_inference_ms": c_ms,
            }
        except Exception as exc:
            log.warning("Candidate model_c inference failed (skipped): %s", exc)

    return ModelCResponse(
        prediction_id=prediction_id,
        model_version=loaded.version,
        model_stage="shadow",
        predicted_probability=round(probability, 4),
        confidence_score=loaded.confidence_score,
        inference_ms=inference_ms,
        **candidate_fields,
    )
