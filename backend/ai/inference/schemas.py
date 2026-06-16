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
    # Phase 9E — candidate model fields (present when a candidate model is loaded)
    candidate_version: Optional[str] = None
    candidate_expected_auction_price: Optional[float] = None
    candidate_value_signal: Optional[str] = None
    candidate_value_ratio: Optional[float] = None
    candidate_confidence_score: Optional[float] = None
    candidate_inference_ms: Optional[int] = None


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
    # Phase 9E — candidate model fields
    candidate_version: Optional[str] = None
    candidate_predicted_winning_bid: Optional[float] = None
    candidate_confidence_score: Optional[float] = None
    candidate_inference_ms: Optional[int] = None


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
    # Phase 9E — candidate model fields
    candidate_version: Optional[str] = None
    candidate_predicted_probability: Optional[float] = None
    candidate_confidence_score: Optional[float] = None
    candidate_inference_ms: Optional[int] = None


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


# ---------------------------------------------------------------------------
# Phase 6 — Retraining
# ---------------------------------------------------------------------------

class RetrainRequest(BaseModel):
    model_name: str = Field(
        description="'model_a', 'model_b', 'model_c', or 'all'",
        pattern=r"^(model_a|model_b|model_c|all)$",
    )
    datasource: str = Field(
        default="synthetic",
        description="'synthetic' or 'real'",
        pattern=r"^(synthetic|real)$",
    )
    data_path: Optional[str] = Field(
        default=None,
        description="Absolute path to a pre-exported CSV (skips Supabase export)",
    )


class RetrainResponse(BaseModel):
    job_id: str
    status: str
    model_name: str
    datasource: str
    message: str


class TrainingJobStatus(BaseModel):
    job_id: str
    model_name: str
    datasource: str
    status: str
    elapsed_seconds: Optional[float] = None
    result: Optional[dict[str, Any]] = None
    error: Optional[str] = None


# ---------------------------------------------------------------------------
# Phase 6 — Lifecycle management
# ---------------------------------------------------------------------------

class PromoteRequest(BaseModel):
    version: str = Field(description="Version string to promote, e.g. 'v1.0.4-synthetic'")


class PromoteResponse(BaseModel):
    model_name: str
    promoted_version: str
    previous_version: Optional[str]
    message: str


class RollbackResponse(BaseModel):
    model_name: str
    rolled_back_from: str
    rolled_back_to: str
    message: str


class ModelVersionInfo(BaseModel):
    version: str
    status: str
    acceptance_grade: str
    training_rows: int
    metrics: dict[str, Any]
    training_timestamp: str
    dataset_source: str


class ModelHistoryResponse(BaseModel):
    model_name: str
    active_version: Optional[str]
    versions: list[ModelVersionInfo]


class PromotionCandidate(BaseModel):
    model_name: str
    version: str
    acceptance_grade: str
    metrics: dict[str, Any]
    training_timestamp: str


class PromotionCandidatesResponse(BaseModel):
    candidates: list[PromotionCandidate]
