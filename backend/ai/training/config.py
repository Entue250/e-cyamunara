"""
training/config.py
==================
Central configuration for the E-CYAMUNARA ML pipeline.

All paths are resolved relative to this file's location so the package works
regardless of where it is cloned.  Import the ready-made singleton at the
bottom of this module:

    from training.config import CONFIG

No external dependencies — stdlib only.
"""

from __future__ import annotations

import pathlib
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# Resolved base directories
# ---------------------------------------------------------------------------
_TRAINING_DIR = pathlib.Path(__file__).resolve().parent  # .../backend/ai/training/
_AI_DIR = _TRAINING_DIR.parent                           # .../backend/ai/


# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
@dataclass
class Paths:
    """File-system locations used throughout the pipeline.

    Not frozen because Path values are computed from __file__ at construction
    time and cannot be expressed as frozen-dataclass field defaults portably.
    """

    ai_dir: pathlib.Path = field(default_factory=lambda: _AI_DIR)
    data_dir: pathlib.Path = field(default_factory=lambda: _AI_DIR / "data")
    models_dir: pathlib.Path = field(default_factory=lambda: _AI_DIR / "models")
    registry_file: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "models" / "registry.json"
    )
    eval_history: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "models" / "evaluation_history.jsonl"
    )
    logs_dir: pathlib.Path = field(default_factory=lambda: _AI_DIR / "logs")
    synthetic_auctions: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "data" / "synthetic_auctions.csv"
    )
    synthetic_bids: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "data" / "synthetic_bids.csv"
    )
    synthetic_views: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "data" / "synthetic_views.csv"
    )
    trained_models_dir: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "trained_models"
    )
    trained_models_registry_file: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "trained_models" / "registry.json"
    )
    training_history_file: pathlib.Path = field(
        default_factory=lambda: _AI_DIR / "trained_models" / "training_history.jsonl"
    )


# ---------------------------------------------------------------------------
# Train / validation / test split
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class SplitConfig:
    """Controls how the 200 K-record dataset is split for training and evaluation."""

    test_pct: float = 0.10
    val_pct: float = 0.10
    random_state: int = 42
    n_folds: int = 5
    temporal_col: str = "start_date"
    min_val_rows: int = 5_000
    min_test_rows: int = 2_000
    min_category_test_rows: int = 20


# ---------------------------------------------------------------------------
# Model hyper-parameters
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class PriceModelHyperparams:
    """XGBoost hyper-parameters for Model A (market value estimation).

    All defaults represent a sensible starting point; values are expected to be
    tuned via cross-validation before a production release is promoted.
    """

    n_estimators: int = 1_000
    max_depth: int = 6
    learning_rate: float = 0.05
    subsample: float = 0.8
    colsample_bytree: float = 0.8
    reg_alpha: float = 0.1
    reg_lambda: float = 1.0
    min_child_weight: int = 5
    early_stopping_rounds: int = 50
    random_state: int = 42


@dataclass(frozen=True)
class WinningBidHyperparams:
    """XGBoost hyper-parameters for Model B (winning bid prediction).

    Identical structure to PriceModelHyperparams; max_depth and
    min_child_weight are reduced to reflect the noisier winning-bid target.
    """

    n_estimators: int = 1_000
    max_depth: int = 5
    learning_rate: float = 0.05
    subsample: float = 0.8
    colsample_bytree: float = 0.8
    reg_alpha: float = 0.1
    reg_lambda: float = 1.0
    min_child_weight: int = 10
    early_stopping_rounds: int = 50
    random_state: int = 42


@dataclass(frozen=True)
class BidProbabilityHyperparams:
    """Hyper-parameters for Model C (bid probability classification).

    Shares the XGBoost backbone with Models A/B.  scale_pos_weight handles
    class imbalance in the binary bid-placed target.  lr_* fields govern the
    fallback logistic-regression calibration layer.
    """

    n_estimators: int = 1_000
    max_depth: int = 5
    learning_rate: float = 0.05
    subsample: float = 0.8
    colsample_bytree: float = 0.8
    reg_alpha: float = 0.1
    reg_lambda: float = 1.0
    min_child_weight: int = 10
    early_stopping_rounds: int = 50
    random_state: int = 42
    # Classification-specific
    scale_pos_weight: float = 0.67   # ~ratio of negative/positive class weight
    lr_C: float = 1.0                # Logistic regression regularisation strength
    lr_max_iter: int = 1_000         # Logistic regression solver max iterations


# ---------------------------------------------------------------------------
# Acceptance thresholds
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class PriceModelThresholds:
    """Minimum, target, and excellent performance thresholds for Model A.

    A model must surpass *_min on every metric to be registered.  *_target
    is the KPI for a production-quality release.  *_excellent flags
    exceptional performance worth noting in the eval history.

    All RWF amounts are in absolute Rwandan Francs.
    MAPE values are proportions (0.15 == 15 %).
    """

    # Mean absolute error (lower is better)
    mae_rwf_min: float = 800_000.0
    mae_rwf_target: float = 400_000.0
    mae_rwf_excellent: float = 200_000.0

    # Root mean squared error (lower is better)
    rmse_rwf_min: float = 2_000_000.0
    rmse_rwf_target: float = 1_000_000.0
    rmse_rwf_excellent: float = 500_000.0

    # Mean absolute percentage error (lower is better)
    mape_min: float = 0.25
    mape_target: float = 0.15
    mape_excellent: float = 0.09

    # R² (higher is better)
    r2_min: float = 0.70
    r2_target: float = 0.85
    r2_excellent: float = 0.92

    # Per-category MAPE minimums (categories differ in price variance)
    mape_vehicle_min: float = 0.25
    mape_motorcycle_min: float = 0.28
    mape_bicycle_min: float = 0.35
    mape_luxury_min: float = 0.35   # luxury = starting_price > 10 M RWF


@dataclass(frozen=True)
class WinningBidThresholds:
    """Acceptance thresholds for Model B (winning bid prediction).

    Thresholds are looser than Model A because the winning amount depends on
    live bidding behaviour that is inherently harder to predict at auction
    creation time.
    """

    mae_rwf_min: float = 1_000_000.0
    mae_rwf_target: float = 600_000.0
    mae_rwf_excellent: float = 300_000.0

    rmse_rwf_min: float = 3_000_000.0
    rmse_rwf_target: float = 1_500_000.0
    rmse_rwf_excellent: float = 750_000.0

    mape_min: float = 0.30
    mape_target: float = 0.20
    mape_excellent: float = 0.12

    r2_min: float = 0.60
    r2_target: float = 0.78
    r2_excellent: float = 0.88

    # Premium segment (high-value lots) is harder to predict
    premium_mape_min: float = 0.22


@dataclass(frozen=True)
class BidProbabilityThresholds:
    """Acceptance thresholds for Model C (bid probability classification).

    ECE (Expected Calibration Error) is bounded from above — lower is better.
    All other metrics are bounded from below.
    """

    auc_roc_min: float = 0.70
    auc_roc_target: float = 0.80
    auc_roc_excellent: float = 0.88

    pr_auc_min: float = 0.65
    f1_min: float = 0.65
    precision_min: float = 0.60
    recall_min: float = 0.65

    ece_max: float = 0.10   # Expected Calibration Error — lower is better


# ---------------------------------------------------------------------------
# Inference / serving configuration
# ---------------------------------------------------------------------------
@dataclass(frozen=True)
class InferenceConfig:
    """Run-time parameters used by the model-serving layer."""

    # How long (minutes) a market value estimate response is cached on the client
    cache_ttl_minutes: int = 30

    # RWF threshold that separates standard from luxury auctions
    luxury_tier_threshold_rwf: float = 10_000_000.0

    # Confidence score: floor factor when completeness is low (0–1 scale)
    confidence_min_completeness_factor: float = 0.5

    # Confidence score: additive boost from engagement signals (0–1 scale)
    confidence_engagement_boost: float = 0.5

    # First bid placed within this many hours of auction start = "quick"
    first_bid_quick_threshold_hours: float = 2.0

    # Minimum elapsed days before bid_acceleration signal is meaningful
    bid_acceleration_min_days: float = 0.5


# ---------------------------------------------------------------------------
# Top-level composite config
# ---------------------------------------------------------------------------
@dataclass
class Config:
    """Top-level configuration for the E-CYAMUNARA ML pipeline.

    Not frozen because it embeds a Paths instance (which is also not frozen).
    Construct with no arguments for a fully-defaulted instance:

        from training.config import CONFIG   # preferred — use the singleton
    """

    feature_set_version: str = "1.0"
    ref_year: int = 2026

    # Price tier boundaries in RWF (ascending).  Five tiers result from four
    # boundaries: bicycle_tier | moto_tier | economy_vehicle | mid_vehicle | luxury
    price_tier_boundaries: tuple = (
        500_000.0,
        3_000_000.0,
        15_000_000.0,
        30_000_000.0,
    )

    # Sub-configs — all have zero-argument defaults
    paths: Paths = field(default_factory=Paths)
    split: SplitConfig = field(default_factory=SplitConfig)

    price_hyperparams: PriceModelHyperparams = field(
        default_factory=PriceModelHyperparams
    )
    winning_bid_hyperparams: WinningBidHyperparams = field(
        default_factory=WinningBidHyperparams
    )
    bid_prob_hyperparams: BidProbabilityHyperparams = field(
        default_factory=BidProbabilityHyperparams
    )

    price_thresholds: PriceModelThresholds = field(
        default_factory=PriceModelThresholds
    )
    winning_bid_thresholds: WinningBidThresholds = field(
        default_factory=WinningBidThresholds
    )
    bid_prob_thresholds: BidProbabilityThresholds = field(
        default_factory=BidProbabilityThresholds
    )

    inference: InferenceConfig = field(default_factory=InferenceConfig)


# ---------------------------------------------------------------------------
# Module-level singleton — import this rather than constructing Config()
# ---------------------------------------------------------------------------
CONFIG: Config = Config()
