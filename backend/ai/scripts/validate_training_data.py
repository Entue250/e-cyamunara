#!/usr/bin/env python3
"""
validate_training_data.py

Validates synthetic or exported ML training data CSV files.
Generates training_data_quality_report.json in backend/ai/data/.

Checks:
  - Null percentages per column
  - Feature completeness across 15 ML-critical fields
  - Numeric range violations (price, year, mileage, etc.)
  - Invalid categorical values (region, category, status)
  - Duplicate records (by id and by full-row)
  - Outlier detection via IQR (3x fence)

Usage:
  python backend/ai/scripts/validate_training_data.py
  python backend/ai/scripts/validate_training_data.py --file backend/ai/data/synthetic_auctions.csv
  python backend/ai/scripts/validate_training_data.py --output /tmp/report.json
"""

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR   = SCRIPT_DIR.parent / "data"

# ── Valid value sets ───────────────────────────────────────────────────────────
VALID_REGIONS    = {"Central", "Northern", "Southern", "Eastern", "Western"}
VALID_STATUSES   = {"active", "closed", "draft"}
VALID_CATEGORIES = {"vehicle", "motorcycle", "bicycle"}

# ── Columns expected to be present in the auctions CSV ───────────────────────
FEATURE_COLS = [
    "region", "main_category", "sub_category", "brand", "model",
    "manufacturing_year", "mileage", "condition", "fuel_type", "transmission",
    "ownership_history", "accident_history", "insurance_status", "color",
    "starting_price",
]

# Columns always-nullable — not flagged as "high_null"
ALWAYS_NULLABLE = {
    "winning_amount", "winner_uid", "closed_at", "time_of_first_bid",
    "time_of_last_bid", "current_winner_uid", "current_winner_name",
    "description", "viewer_uid",
}

# ── Numeric range expectations ────────────────────────────────────────────────
RANGE_CHECKS: dict = {
    "starting_price":              (0, 200_000_000),
    "manufacturing_year":          (1980, 2026),
    "mileage":                     (0, 1_000_000),
    "metadata_completeness_score": (0.0, 1.0),
    "bids_per_view_ratio":         (0.0, 100.0),
    "bid_sequence":                (1, 1_000),
    "seconds_before_end":          (0, 30 * 24 * 3600),
    "view_duration_seconds":       (0, 86_400),
    "confidence_score":            (0.0, 1.0),
    "predicted_probability":       (0.0, 1.0),
}


def null_report(df: pd.DataFrame) -> dict:
    n = len(df)
    out = {}
    for col in df.columns:
        cnt = int(df[col].isna().sum())
        pct = round(cnt / n * 100, 2) if n > 0 else 0.0
        is_nullable = col in ALWAYS_NULLABLE
        out[col] = {
            "null_count": cnt,
            "null_pct": pct,
            "status": "ok" if (pct <= 50 or is_nullable) else "high_null",
        }
    return out


def feature_completeness(df: pd.DataFrame) -> dict:
    present = [c for c in FEATURE_COLS if c in df.columns]
    if not present:
        return {"status": "no_feature_columns_found"}
    scores = df[present].notna().sum(axis=1) / len(present)
    return {
        "checked_features": present,
        "mean_completeness":       round(float(scores.mean()), 4),
        "median_completeness":     round(float(scores.median()), 4),
        "pct_fully_complete":      round(float((scores == 1.0).mean() * 100), 2),
        "pct_below_50pct":         round(float((scores < 0.5).mean() * 100), 2),
        "status": "ok",
    }


def categorical_validation(df: pd.DataFrame) -> dict:
    results = {}
    checks = {
        "region":        VALID_REGIONS,
        "main_category": VALID_CATEGORIES,
        "auction_status": VALID_STATUSES,
    }
    for col, valid_set in checks.items():
        if col not in df.columns:
            results[col] = {"status": "missing_column"}
            continue
        series = df[col].dropna()
        invalid = series[~series.isin(valid_set)]
        results[col] = {
            "valid_values":    sorted(valid_set),
            "found_values":    sorted(series.unique().tolist()),
            "invalid_count":   int(len(invalid)),
            "invalid_examples": invalid.head(5).tolist(),
            "status": "ok" if len(invalid) == 0 else "invalid_values_found",
        }
    return results


def numeric_ranges(df: pd.DataFrame) -> dict:
    results = {}
    for col, (lo, hi) in RANGE_CHECKS.items():
        if col not in df.columns:
            results[col] = {"status": "missing_column"}
            continue
        series = pd.to_numeric(df[col], errors="coerce").dropna()
        if series.empty:
            results[col] = {"status": "all_null"}
            continue
        oob = series[(series < lo) | (series > hi)]
        results[col] = {
            "min": round(float(series.min()), 4),
            "max": round(float(series.max()), 4),
            "expected_range": [lo, hi],
            "out_of_range_count": int(len(oob)),
            "status": "ok" if len(oob) == 0 else "out_of_range",
        }
    return results


def outlier_report(df: pd.DataFrame, factor: float = 3.0) -> dict:
    numeric_cols = [
        "starting_price", "total_bids", "unique_bidder_count", "views_count",
        "bid_amount", "bid_increment", "view_duration_seconds",
    ]
    results = {}
    for col in numeric_cols:
        if col not in df.columns:
            continue
        series = pd.to_numeric(df[col], errors="coerce").dropna()
        if len(series) < 10:
            continue
        q1 = float(series.quantile(0.25))
        q3 = float(series.quantile(0.75))
        iqr = q3 - q1
        lo  = q1 - factor * iqr
        hi  = q3 + factor * iqr
        cnt = int(((series < lo) | (series > hi)).sum())
        results[col] = {
            "q1": round(q1, 2), "q3": round(q3, 2), "iqr": round(iqr, 2),
            "lower_fence": round(lo, 2), "upper_fence": round(hi, 2),
            "outlier_count": cnt,
            "outlier_pct": round(cnt / len(series) * 100, 2),
        }
    return results


def duplicate_check(df: pd.DataFrame) -> dict:
    dup_rows = int(df.duplicated().sum())
    dup_ids  = int(df["id"].duplicated().sum()) if "id" in df.columns else None
    return {
        "total_rows": len(df),
        "duplicate_rows": dup_rows,
        "duplicate_id_count": dup_ids,
        "status": "ok" if (dup_rows == 0 and (dup_ids is None or dup_ids == 0))
                  else "duplicates_found",
    }


def validate(path: Path) -> dict:
    print(f"  Loading {path.name}...")
    df = pd.read_csv(path, low_memory=False)
    print(f"    Shape: {df.shape}")

    nulls  = null_report(df)
    feats  = feature_completeness(df)
    cats   = categorical_validation(df)
    ranges = numeric_ranges(df)
    dups   = duplicate_check(df)
    outs   = outlier_report(df)

    issues = []
    if dups["status"] != "ok":
        issues.append("duplicate_records")
    for col, info in cats.items():
        if info.get("status") not in ("ok", "missing_column"):
            issues.append(f"invalid_categoricals:{col}")
    for col, info in ranges.items():
        if info.get("status") == "out_of_range":
            issues.append(f"range_violation:{col}")
    high_null = [
        c for c, info in nulls.items()
        if info["status"] == "high_null"
    ]
    if high_null:
        issues.append(f"high_null_columns:{high_null}")

    quality = round(max(0.0, 1.0 - len(issues) * 0.08), 2)

    return {
        "file": str(path),
        "validated_at": datetime.now(timezone.utc).isoformat(),
        "row_count": len(df),
        "column_count": len(df.columns),
        "columns": list(df.columns),
        "null_report": nulls,
        "feature_completeness": feats,
        "categorical_validation": cats,
        "numeric_range_checks": ranges,
        "outlier_report": outs,
        "duplicates": dups,
        "summary": {
            "quality_score": quality,
            "issues": issues,
            "status": "pass" if quality >= 0.70 else "fail",
        },
    }


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate E-CYAMUNARA ML training data CSV files"
    )
    parser.add_argument(
        "--file", type=Path, default=None,
        help="CSV to validate. Default: all synthetic_*.csv in data/",
    )
    parser.add_argument(
        "--output", type=Path,
        default=DATA_DIR / "training_data_quality_report.json",
        help="Output path for quality report JSON",
    )
    args = parser.parse_args()

    if args.file:
        targets = [args.file]
    else:
        targets = sorted(DATA_DIR.glob("synthetic_*.csv"))
        if not targets:
            targets = sorted(DATA_DIR.glob("training_snapshot_*.csv"))

    if not targets:
        print("No CSV files found. Run generate_synthetic_dataset.py first.")
        sys.exit(1)

    print(f"Validating {len(targets)} file(s)...")
    reports = []
    for path in targets:
        rep = validate(path)
        reports.append(rep)
        icon = "pass" if rep["summary"]["status"] == "pass" else "FAIL"
        print(f"  [{icon}] {path.name}: "
              f"quality={rep['summary']['quality_score']}, "
              f"issues={rep['summary']['issues']}")

    combined = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "files_validated": len(reports),
        "reports": reports,
    }
    args.output.write_text(json.dumps(combined, indent=2))
    print(f"\nReport -> {args.output}")

    if any(r["summary"]["status"] == "fail" for r in reports):
        sys.exit(1)


if __name__ == "__main__":
    main()
