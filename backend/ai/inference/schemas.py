"""Pydantic request/response models for the inference API."""

from __future__ import annotations

from typing import Any, Optional

from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Shared request base
# ---------------------------------------------------------------------------

class _AuctionBase(BaseModel):
    """Raw auction-level fields that the pipeline processes internally.

    These match Supabase `auctions` column names. Derived features
    (asset_age, auction_duration_hours, has_description, has_images,
    bid_momentum, price_tier, etc.) are computed by the sklearn pipeline —
    do NOT send them as inputs.
    """

    # Core categoricals
    main_category: str
    region: str
    starting_price: float

    fuel_type: Optional[str] = None
    transmission: Optional[str] = None
    ownership_history: Optional[str] = None
    accident_history: Optional[str] = None  # None means "unknown"
    insurance_status: Optional[str] = None  # None means "unknown"
    brand: Optional[str] = None
    sub_category: Optional[str] = None
    condition: Optional[str] = None

    # Raw fields used to derive asset_age and auction_duration_hours
    manufacturing_year: Optional[float] = None
    start_date: Optional[str] = None   # ISO-8601 string or null
    end_date: Optional[str] = None     # ISO-8601 string or null

    # Raw content fields → has_description / has_images derived by pipeline
    description: Optional[str] = None
    photo_urls: Optional[Any] = None   # str, list, or null

    # Continuous raw
    mileage: Optional[float] = None    # None means mileage not recorded


class _PredictRequestBase(BaseModel):
    auction_id: Optional[str] = None   # UUID; if provided and store=True, stored
    store_prediction: bool = True


# ---------------------------------------------------------------------------
# Model A — market value estimation
# ---------------------------------------------------------------------------

class ModelARequest(_PredictRequestBase):
    features: _AuctionBase


class ModelAResponse(BaseModel):
    prediction_id: Optional[str] = None
    model_version: str
    prediction_source: str = "real"
    model_stage: str
    expected_auction_price: float = Field(description="Estimated fair market value in RWF")
    value_signal: str = Field(description="'undervalued' | 'fairly_priced' | 'overpriced'")
    value_ratio: float = Field(description="expected_price / starting_price")
    confidence_score: float
    inference_ms: int


# ---------------------------------------------------------------------------
# Model B — winning bid prediction
# ---------------------------------------------------------------------------

class _EngagementFeatures(_AuctionBase):
    """Adds live engagement signals for Models B and C."""

    total_bids: Optional[float] = 0.0
    unique_bidder_count: Optional[float] = 0.0
    views_count: Optional[float] = 0.0
    # time_of_first_bid → pipeline derives time_to_first_bid_hours / is_first_bid_quick
    time_of_first_bid: Optional[str] = None


class ModelBRequest(_PredictRequestBase):
    features: _EngagementFeatures


class ModelBResponse(BaseModel):
    prediction_id: Optional[str] = None
    model_version: str
    prediction_source: str = "real"
    model_stage: str
    predicted_winning_bid: float = Field(description="Expected final winning bid in RWF")
    confidence_score: float
    inference_ms: int


# ---------------------------------------------------------------------------
# Model C — bid probability classification
# ---------------------------------------------------------------------------

class ModelCRequest(_PredictRequestBase):
    features: _EngagementFeatures


class ModelCResponse(BaseModel):
    prediction_id: Optional[str] = None
    model_version: str
    prediction_source: str = "real"
    model_stage: str
    predicted_probability: float = Field(description="Probability [0, 1] that auction receives ≥1 bid")
    confidence_score: float
    inference_ms: int


# ---------------------------------------------------------------------------
# Health and registry
# ---------------------------------------------------------------------------

class ModelStatus(BaseModel):
    loaded: bool
    version: Optional[str] = None
    shadow_version: Optional[str] = None


class HealthResponse(BaseModel):
    status: str
    models: dict[str, ModelStatus]
    uptime_seconds: float


class VersionInfo(BaseModel):
    version: str
    status: str
    acceptance_grade: str
    training_rows: int
    metrics: dict[str, Any]
    feature_count: int


class ModelsActiveResponse(BaseModel):
    model_a: VersionInfo
    model_b: VersionInfo
    model_c: VersionInfo
