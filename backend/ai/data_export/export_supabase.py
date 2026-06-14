"""Export production auction data from Supabase to a versioned CSV.

Usage (CLI):
    python -m data_export.export_supabase
    python -m data_export.export_supabase --out data/real/auctions.csv

Usage (Python):
    from data_export.export_supabase import export, ExportResult
    result = export(url=..., key=..., out_dir=pathlib.Path("data/real"))

The auctions table already stores pre-aggregated engagement columns
(unique_bidder_count, time_of_first_bid, time_of_last_bid, views_count)
so no JOIN with the bids table is needed for model training.

photo_urls is a PostgreSQL array; it is serialised as a JSON string in the CSV
so the downstream pipeline can parse it with json.loads() if needed.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import pathlib
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone

import pandas as pd

log = logging.getLogger(__name__)

# Columns fetched from the auctions table — order preserved in CSV output
_SELECT_COLS = [
    "id",
    "main_category",
    "sub_category",
    "brand",
    "model",
    "condition",
    "description",
    "photo_urls",
    "region",
    "starting_price",
    "winning_amount",
    "auction_status",
    "manufacturing_year",
    "mileage",
    "fuel_type",
    "transmission",
    "ownership_history",
    "accident_history",
    "insurance_status",
    "total_bids",
    "unique_bidder_count",
    "views_count",
    "time_of_first_bid",
    "time_of_last_bid",
    "start_date",
    "end_date",
    "closed_at",
    "created_at",
]

_DEFAULT_OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "real"


@dataclass
class ExportResult:
    out_path: pathlib.Path
    row_count: int
    export_timestamp: str
    errors: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def _fetch_rows(url: str, key: str) -> list[dict]:
    """Pull all rows from auctions via the Supabase Python client (service role)."""
    try:
        from supabase import create_client
    except ImportError as exc:
        raise RuntimeError(
            "supabase package not installed — run: pip install supabase"
        ) from exc

    client = create_client(url, key)
    rows: list[dict] = []
    page_size = 1000
    offset = 0

    while True:
        resp = (
            client.table("auctions")
            .select(", ".join(_SELECT_COLS))
            .range(offset, offset + page_size - 1)
            .execute()
        )
        batch = resp.data or []
        rows.extend(batch)
        if len(batch) < page_size:
            break
        offset += page_size

    return rows


def _rows_to_df(rows: list[dict]) -> pd.DataFrame:
    df = pd.DataFrame(rows, columns=_SELECT_COLS)

    # photo_urls arrives as a Python list from the JSON response; serialise to string
    if "photo_urls" in df.columns:
        df["photo_urls"] = df["photo_urls"].apply(
            lambda v: json.dumps(v) if isinstance(v, list) else v
        )

    return df


def export(
    url: str,
    key: str,
    out_dir: pathlib.Path = _DEFAULT_OUT_DIR,
    filename: str | None = None,
) -> ExportResult:
    """Fetch auctions from Supabase and write a timestamped CSV.

    Parameters
    ----------
    url:
        Supabase project URL.
    key:
        Service-role API key (bypasses RLS — never use the anon key here).
    out_dir:
        Directory to write the CSV into. Created if it does not exist.
    filename:
        Override the auto-generated timestamped filename.
    """
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    fname = filename or f"auctions_{timestamp}.csv"
    out_path = out_dir / fname

    errors: list[str] = []
    rows: list[dict] = []

    try:
        log.info("Connecting to Supabase: %s", url)
        rows = _fetch_rows(url, key)
        log.info("Fetched %d auction rows", len(rows))
    except Exception as exc:
        errors.append(f"fetch failed: {exc}")
        return ExportResult(
            out_path=out_path,
            row_count=0,
            export_timestamp=timestamp,
            errors=errors,
        )

    df = _rows_to_df(rows)
    df.to_csv(out_path, index=False)
    log.info("Wrote %d rows to %s", len(df), out_path)

    # Write a stable "latest.csv" pointer for the training pipeline
    latest = out_dir / "latest.csv"
    df.to_csv(latest, index=False)

    return ExportResult(
        out_path=out_path,
        row_count=len(df),
        export_timestamp=timestamp,
        errors=errors,
    )


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Export Supabase auctions to CSV")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", ""))
    parser.add_argument(
        "--key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "")
    )
    parser.add_argument("--out", type=pathlib.Path, default=None)
    args = parser.parse_args()

    if not args.url or not args.key:
        print(
            "ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set "
            "(env vars or --url / --key flags)",
            file=sys.stderr,
        )
        sys.exit(1)

    out_dir = args.out.parent if (args.out and args.out.suffix) else (
        args.out or _DEFAULT_OUT_DIR
    )
    filename = args.out.name if (args.out and args.out.suffix) else None

    result = export(url=args.url, key=args.key, out_dir=out_dir, filename=filename)

    if result.ok:
        print(f"Exported {result.row_count} rows -> {result.out_path}")
    else:
        for err in result.errors:
            print(f"ERROR: {err}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
