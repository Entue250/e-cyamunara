"""POST /predict/model-a — market value estimation."""

from __future__ import annotations

import time
from typing import Any, Optional

import numpy as np
from fastapi import APIRouter, HTTPException, Request

from ..deps import get_loader, get_store
from ..df_utils import build_inference_df
from ..error_codes import ErrorCode
from ..feature_validator import validate_model_a
from ..schemas import ModelARequest, ModelAResponse

router = APIRouter(tags=["predict"])

_VALUE_SIGNAL_HIGH = 1.30   # ratio > HIGH  → undervalued
_VALUE_SIGNAL_LOW = 1.10    # ratio < LOW   → overpriced


def _value_signal(ratio: float) -> str:
    if ratio > _VALUE_SIGNAL_HIGH:
        return "undervalued"
    if ratio < _VALUE_SIGNAL_LOW:
        return "overpriced"
    return "fairly_priced"


def _run_inference(loaded, features_dict: dict) -> tuple[float, str, float]:
    """Return (predicted_price_rwf, value_signal, value_ratio)."""
    df = build_inference_df(features_dict)
    X = loaded.pipeline.transform(df)
    raw_log = loaded.xgb_model.predict(X)
    price = float(np.expm1(raw_log[0]))
    starting = float(features_dict.get("starting_price") or 0)
    ratio = round(price / starting, 4) if starting > 0 else 1.0
    return price, _value_signal(ratio), ratio


def _build_store_row(
    auction_id: Optional[str],
    loaded,
    features_dict: dict,
    price: float,
    signal: str,
    ratio: float,
    confidence: float,
    inference_ms: int,
) -> dict[str, Any]:
    return {
        "auction_id": auction_id,
        "model_version": loaded.version,
        "prediction_type": "auction_price_estimate",
        "expected_auction_price": price,
        "confidence_score": confidence,
        "feature_snapshot": features_dict,
        "value_signal": signal,
        "value_ratio": ratio,
        "starting_price_at_prediction": features_dict.get("starting_price"),
        "prediction_source": "real",
        "model_stage": "shadow",
    }


@router.post("/predict/model-a", response_model=ModelAResponse)
def predict_model_a(body: ModelARequest, request: Request) -> ModelAResponse:
    loader = get_loader(request)
    store = get_store(request)

    features_dict = body.features.model_dump()
    errors = validate_model_a(features_dict)
    if errors:
        raise HTTPException(
            status_code=422,
            detail={"code": ErrorCode.FEATURE_MISSING, "errors": errors},
        )

    try:
        loaded = loader.get_active("model_a")
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    t0 = time.perf_counter()
    try:
        price, signal, ratio = _run_inference(loaded, features_dict)
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
            price, signal, ratio, loaded.confidence_score, inference_ms,
        )
        prediction_id = store.store(row)

    return ModelAResponse(
        prediction_id=prediction_id,
        model_version=loaded.version,
        model_stage="shadow",
        expected_auction_price=round(price, 2),
        value_signal=signal,
        value_ratio=ratio,
        confidence_score=loaded.confidence_score,
        inference_ms=inference_ms,
    )
