"""
training/preprocessing/feature_definitions.py
==============================================
Canonical single source of truth for every feature list, encoding map, and
column-set used across the E-CYAMUNARA ML pipeline.

Importing this module validates its own internal consistency at import time.
If any feature is accidentally listed in both a model's feature matrix and the
FORBIDDEN_FEATURES guard set, an immediate ValueError is raised so the
mistake is caught before any training run begins.

Usage:
    from training.preprocessing.feature_definitions import MODEL_A_FEATURES

No external dependencies — stdlib only.
"""

from __future__ import annotations

# ---------------------------------------------------------------------------
# Version
# ---------------------------------------------------------------------------
FEATURE_SET_VERSION: str = "1.0"

# ---------------------------------------------------------------------------
# Forbidden columns
# ---------------------------------------------------------------------------
FORBIDDEN_FEATURES: frozenset[str] = frozenset(
    {
        # Identifiers / free-text / high-cardinality unique fields
        "auction_id",
        "id",
        "item_name",
        "plate_number",
        "model",            # near-unique generated code field — not the ML model
        "color",
        "description",
        "photo_urls",
        # Admin / user PII columns
        "posted_by_admin_uid",
        "posted_by_admin_name",
        "winner_uid",
        "bidder_uid",
        "bidder_name",
        "bidder_phone",
        # Target leakage — raw outcome columns
        "winning_amount",
        "final_price",
        "current_highest_bid",
        "bid_amount",
        "bid_status",
        # Timestamps (raw) — if temporal features are needed, derived columns
        # such as asset_age or auction_duration_hours are used instead
        "start_date",
        "end_date",
        "closed_at",
        "created_at",
        "updated_at",
        "auction_created_at",
        "time_of_last_bid",
        # Soft-delete / lifecycle flags that must not influence price models
        "is_deleted",
        # Alias that duplicates main_category
        "category",
    }
)

# ---------------------------------------------------------------------------
# Columns that are conditionally NULL by design (not data-quality gaps)
# ---------------------------------------------------------------------------
ALWAYS_NULLABLE: frozenset[str] = frozenset(
    {
        "winning_amount",
        "final_price",
        "winner_uid",
        "closed_at",
        "time_of_first_bid",
        "time_of_last_bid",
        "time_to_first_bid_hours",
        "bids_per_view_ratio",
    }
)

# ---------------------------------------------------------------------------
# Columns for which a binary "known" flag is generated before imputation
# ---------------------------------------------------------------------------
MISSINGNESS_FLAG_COLUMNS: list[str] = [
    "accident_history",
    "insurance_status",
    "mileage",
    "manufacturing_year",
]

# ---------------------------------------------------------------------------
# Ordinal encoding maps
# ---------------------------------------------------------------------------
CONDITION_ORDINAL_MAP: dict[str, int] = {
    "Poor": 0,
    "Fair": 1,
    "Good": 2,
    "Very Good": 3,
    "Excellent": 4,
}

# ---------------------------------------------------------------------------
# Price tiers
# ---------------------------------------------------------------------------
PRICE_TIER_BOUNDARIES: list[float] = [
    500_000.0,
    3_000_000.0,
    15_000_000.0,
    30_000_000.0,
]

PRICE_TIER_LABELS: list[str] = [
    "bicycle_tier",
    "moto_tier",
    "economy_vehicle",
    "mid_vehicle",
    "luxury",
]

# ---------------------------------------------------------------------------
# Valid domain values (used for input validation and data-quality checks)
# ---------------------------------------------------------------------------
VALID_MAIN_CATEGORIES: frozenset[str] = frozenset({"vehicle", "motorcycle", "bicycle"})

VALID_REGIONS: frozenset[str] = frozenset(
    {"Central", "Eastern", "Northern", "Southern", "Western"}
)

VALID_CONDITIONS: frozenset[str] = frozenset(CONDITION_ORDINAL_MAP.keys())

VALID_AUCTION_STATUSES: frozenset[str] = frozenset({"active", "closed", "draft"})

# ---------------------------------------------------------------------------
# Structural NA columns
# ---------------------------------------------------------------------------
BICYCLE_STRUCTURAL_NA_COLUMNS: list[str] = [
    "mileage",
    "fuel_type",
]
# These are "not applicable" for bicycles, NOT "unknown".
# They must be handled before the standard missing-value imputation step so
# that the imputer does not learn spurious patterns from bicycle rows.

# ---------------------------------------------------------------------------
# Encoding strategies by feature group
# ---------------------------------------------------------------------------
ONE_HOT_FEATURES: list[str] = [
    # Low-cardinality categoricals — one-hot encoded
    # Note: region is target-encoded (medium cardinality), so it is excluded here.
    "main_category",
    "fuel_type",
    "transmission",
    "ownership_history",
    "accident_history",
    "insurance_status",
]

TARGET_ENCODED_FEATURES: list[str] = [
    # Medium-cardinality — encoded with smoothed target (mean) encoding
    "brand",
    "sub_category",
    "region",
]

ORDINAL_FEATURES: list[str] = [
    "condition",
]

# ---------------------------------------------------------------------------
# Numeric feature groups
# ---------------------------------------------------------------------------
STATIC_CONTINUOUS_FEATURES: list[str] = [
    # Available at auction-creation time — no live engagement signals needed
    "asset_age",
    "auction_duration_hours",
    "mileage",
]

STATIC_BINARY_FEATURES: list[str] = [
    # Binary flags available at creation time
    "has_description",
    "has_images",
    # Missingness flags (generated from MISSINGNESS_FLAG_COLUMNS)
    "is_accident_history_known",
    "is_insurance_status_known",
    "is_mileage_known",
    "is_manufacturing_year_known",
]

ENGAGEMENT_CONTINUOUS_FEATURES: list[str] = [
    # Only meaningful during an active auction with real bidder activity
    "total_bids",
    "unique_bidder_count",
    "views_count",
    "bid_momentum",
    "view_to_bid_ratio",
    "time_to_first_bid_hours",
    "days_until_close",
    "bid_acceleration",
]

ENGAGEMENT_BINARY_FEATURES: list[str] = [
    "is_first_bid_quick",
]

ENGAGEMENT_CATEGORICAL_FEATURES: list[str] = [
    "price_tier",
]

# ---------------------------------------------------------------------------
# Transform helpers
# ---------------------------------------------------------------------------
LOG1P_FEATURES: list[str] = [
    # Applied after imputation to compress right-skewed distributions.
    # starting_price is included here for Model B where it is an input feature.
    "mileage",
    "total_bids",
    "views_count",
    "starting_price",
]

CREATION_ZERO_FEATURES: list[str] = [
    # Engagement signals explicitly set to zero at auction creation time.
    # These allow Model B/C feature matrices to be constructed even before any
    # bids or views exist (cold-start inference scenario).
    "total_bids",
    "views_count",
    "unique_bidder_count",
    "bid_momentum",
    "view_to_bid_ratio",
    "bid_acceleration",
    "is_first_bid_quick",
]

# ---------------------------------------------------------------------------
# Model feature matrices
# ---------------------------------------------------------------------------

# -- Model A: market value estimation (creation context) --------------------
# Purpose: help clients assess whether an auction is undervalued / fairly priced /
# overpriced by estimating what similar vehicles have sold for at auction.
# Target at training time: winning_amount (closed auctions only).
# starting_price is an INPUT here — the admin's floor price that anchors the estimate.
# Feature order: one-hot | target-encoded | ordinal | static continuous | static binary | price
MODEL_A_FEATURES: list[str] = (
    ONE_HOT_FEATURES
    + TARGET_ENCODED_FEATURES
    + ORDINAL_FEATURES
    + STATIC_CONTINUOUS_FEATURES
    + STATIC_BINARY_FEATURES
    + ["starting_price"]
)

# -- Model B: winning bid prediction (bidding context) ----------------------
# Extends Model A's static features with the full suite of live-auction engagement
# signals.  starting_price is already included via MODEL_A_FEATURES.
MODEL_B_STATIC_FEATURES: list[str] = MODEL_A_FEATURES

MODEL_B_ENGAGEMENT_FEATURES: list[str] = (
    ENGAGEMENT_CONTINUOUS_FEATURES
    + ENGAGEMENT_BINARY_FEATURES
    + ENGAGEMENT_CATEGORICAL_FEATURES
)

MODEL_B_FEATURES: list[str] = MODEL_B_STATIC_FEATURES + MODEL_B_ENGAGEMENT_FEATURES

# -- Model C: bid probability classification (bidding context) ---------------
# Shares the same feature set as Model B; they differ only in their target
# (winning_amount vs binary bid-placed flag).
MODEL_C_FEATURES: list[str] = list(MODEL_B_FEATURES)

# ---------------------------------------------------------------------------
# Import-time self-validation
# ---------------------------------------------------------------------------
def _validate_no_forbidden_features() -> None:
    """Raise ValueError if any feature in a model matrix is also forbidden."""
    checks: list[tuple[str, list[str]]] = [
        ("MODEL_A_FEATURES", MODEL_A_FEATURES),
        ("MODEL_B_FEATURES", MODEL_B_FEATURES),
    ]
    for matrix_name, feature_list in checks:
        conflicts = FORBIDDEN_FEATURES & set(feature_list)
        if conflicts:
            raise ValueError(
                f"Integrity violation: the following column(s) appear in both "
                f"FORBIDDEN_FEATURES and {matrix_name}: {sorted(conflicts)}.  "
                f"Remove them from {matrix_name} or from FORBIDDEN_FEATURES."
            )


_validate_no_forbidden_features()
