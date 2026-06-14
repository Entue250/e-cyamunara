"""Lightweight feature validation for inference requests."""

from __future__ import annotations

from .error_codes import ErrorCode

_REQUIRED_A = frozenset({"main_category", "region", "starting_price"})
_REQUIRED_BC = _REQUIRED_A


def validate_model_a(features: dict) -> list[dict]:
    """Return a list of validation errors for Model A features. Empty = valid."""
    errors = []
    for field in _REQUIRED_A:
        if features.get(field) is None:
            errors.append({
                "code": ErrorCode.FEATURE_MISSING,
                "field": field,
                "detail": f"Required field '{field}' is missing or null.",
            })
    if features.get("starting_price") is not None:
        try:
            v = float(features["starting_price"])
            if v <= 0:
                errors.append({
                    "code": ErrorCode.FEATURE_INVALID,
                    "field": "starting_price",
                    "detail": "starting_price must be > 0.",
                })
        except (TypeError, ValueError):
            errors.append({
                "code": ErrorCode.FEATURE_INVALID,
                "field": "starting_price",
                "detail": "starting_price must be a number.",
            })
    return errors


def validate_model_bc(features: dict) -> list[dict]:
    """Return a list of validation errors for Models B and C. Empty = valid."""
    errors = validate_model_a(features)
    for field in ("total_bids", "views_count", "unique_bidder_count"):
        val = features.get(field)
        if val is not None:
            try:
                if float(val) < 0:
                    errors.append({
                        "code": ErrorCode.FEATURE_INVALID,
                        "field": field,
                        "detail": f"'{field}' must be >= 0.",
                    })
            except (TypeError, ValueError):
                errors.append({
                    "code": ErrorCode.FEATURE_INVALID,
                    "field": field,
                    "detail": f"'{field}' must be a number.",
                })
    return errors
