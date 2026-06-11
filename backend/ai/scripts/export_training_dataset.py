#!/usr/bin/env python3
"""
export_training_dataset.py

Exports ML-ready datasets from the Supabase v_auction_ml_features view.
Requires Phase 2 migrations applied and a live Supabase instance.

Environment (set in backend/ai/.env or shell):
  SUPABASE_URL=https://your-project.supabase.co
  SUPABASE_SERVICE_ROLE_KEY=eyJ...

Usage:
  python backend/ai/scripts/export_training_dataset.py
  python backend/ai/scripts/export_training_dataset.py --region Central
  python backend/ai/scripts/export_training_dataset.py --status closed
  python backend/ai/scripts/export_training_dataset.py --from-date 2025-01-01 --to-date 2026-01-01
  python backend/ai/scripts/export_training_dataset.py --parquet --prefix my_export
"""

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR   = SCRIPT_DIR.parent / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

VALID_REGIONS  = ["Central", "Northern", "Southern", "Eastern", "Western"]
VALID_STATUSES = ["active", "closed", "draft"]
VIEW_NAME      = "v_auction_ml_features"
PAGE_SIZE      = 1000


def _load_env() -> None:
    env_path = SCRIPT_DIR.parent / ".env"
    if env_path.exists():
        try:
            from dotenv import load_dotenv
            load_dotenv(env_path)
        except ImportError:
            pass  # python-dotenv not installed; rely on shell env


def _get_client():
    from supabase import create_client
    url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        print(
            "ERROR: Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in environment "
            "or backend/ai/.env",
            file=sys.stderr,
        )
        sys.exit(1)
    return create_client(url, key)


def fetch_view(
    client,
    *,
    region,
    status,
    from_date,
    to_date,
) -> list:
    all_rows = []
    page = 0

    while True:
        q = client.table(VIEW_NAME).select("*")
        if region:
            q = q.eq("region", region)
        if status:
            q = q.eq("auction_status", status)
        if from_date:
            q = q.gte("auction_created_at", from_date)
        if to_date:
            q = q.lte("auction_created_at", to_date)

        start = page * PAGE_SIZE
        end   = start + PAGE_SIZE - 1
        result = q.range(start, end).execute()
        rows = result.data or []
        all_rows.extend(rows)

        print(f"  Page {page + 1}: {len(rows)} rows (total: {len(all_rows):,})")

        if len(rows) < PAGE_SIZE:
            break
        page += 1

    return all_rows


def export(
    client,
    *,
    region=None,
    status=None,
    from_date=None,
    to_date=None,
    prefix="training_snapshot",
    write_parquet=False,
) -> pd.DataFrame:
    print(f"Querying {VIEW_NAME} (region={region}, status={status}, "
          f"from={from_date}, to={to_date})...")

    rows = fetch_view(client, region=region, status=status,
                      from_date=from_date, to_date=to_date)
    if not rows:
        print("WARNING: No rows returned. Check filters and Supabase connection.")
        return pd.DataFrame()

    df = pd.DataFrame(rows)
    ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")

    out_csv = DATA_DIR / f"{prefix}_{ts}.csv"
    df.to_csv(out_csv, index=False)
    print(f"  CSV -> {out_csv}  ({len(df):,} rows)")

    if write_parquet:
        out_parquet = DATA_DIR / f"{prefix}_{ts}.parquet"
        df.to_parquet(out_parquet, index=False)
        print(f"  Parquet -> {out_parquet}")

    meta = {
        "exported_at": datetime.now(timezone.utc).isoformat(),
        "source_view": VIEW_NAME,
        "filters": {
            "region": region,
            "status": status,
            "from_date": from_date,
            "to_date": to_date,
        },
        "row_count": len(df),
        "columns": list(df.columns),
    }
    meta_path = DATA_DIR / f"{prefix}_{ts}_meta.json"
    meta_path.write_text(json.dumps(meta, indent=2))
    print(f"  Metadata -> {meta_path}")

    return df


def main() -> None:
    parser = argparse.ArgumentParser(
        description=f"Export ML training data from Supabase {VIEW_NAME} view"
    )
    parser.add_argument("--region",    choices=VALID_REGIONS,  default=None)
    parser.add_argument("--status",    choices=VALID_STATUSES, default=None)
    parser.add_argument("--from-date", dest="from_date",       default=None,
                        help="Filter auction_created_at >= YYYY-MM-DD")
    parser.add_argument("--to-date",   dest="to_date",         default=None,
                        help="Filter auction_created_at <= YYYY-MM-DD")
    parser.add_argument("--prefix",    default="training_snapshot",
                        help="Output filename prefix")
    parser.add_argument("--parquet",   action="store_true")
    args = parser.parse_args()

    _load_env()
    client = _get_client()
    df = export(
        client,
        region=args.region,
        status=args.status,
        from_date=args.from_date,
        to_date=args.to_date,
        prefix=args.prefix,
        write_parquet=args.parquet,
    )
    if df.empty:
        sys.exit(1)
    print(f"\nDone. {len(df):,} rows exported.")


if __name__ == "__main__":
    main()
