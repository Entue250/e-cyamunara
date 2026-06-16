"""
data_export/dataset_builder.py
================================
Phase 9B — Versioned training dataset builder.

Builds closed-auction-only training snapshots from Supabase (or any DataFrame
already in memory) with a SHA-256 integrity hash, semantic version tag, and
training-window metadata stored in a companion manifest JSON.

Invariants enforced:
  1. Only auction_status = 'closed' rows enter the snapshot — active/draft rows
     would leak future signal into training.
  2. Rows with null closed_at are dropped — they cannot be placed in a window.
  3. The manifest records training_window_start/end from the closed_at range so
     every model artefact can be traced to a specific time window of real data.

Usage (CLI):
    python -m data_export.dataset_builder
    python -m data_export.dataset_builder --from-date 2025-01-01
    python -m data_export.dataset_builder --to-date 2026-06-30

Usage (Python):
    from data_export.dataset_builder import build_dataset
    manifest = build_dataset(df, out_dir=pathlib.Path("data/real"))
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import os
import pathlib
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone

import pandas as pd

log = logging.getLogger(__name__)

_DEFAULT_OUT_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "real"


@dataclass
class DatasetManifest:
    dataset_version: str               # e.g. "2026.06.16.0"
    dataset_hash: str                  # SHA-256 hex digest of the CSV bytes
    dataset_created_at: str            # UTC ISO timestamp of this build
    training_window_start: str | None  # earliest closed_at ISO timestamp in snapshot
    training_window_end: str | None    # latest closed_at ISO timestamp in snapshot
    row_count: int                     # total rows in snapshot
    row_count_with_target: int         # rows where winning_amount is non-null (usable for A/B)
    out_path: str
    manifest_path: str

    @property
    def ok(self) -> bool:
        return self.row_count > 0


def _next_version(out_dir: pathlib.Path) -> str:
    today = datetime.now(timezone.utc).strftime("%Y.%m.%d")
    n = 0
    while (out_dir / f"dataset_{today}.{n}.csv").exists():
        n += 1
    return f"{today}.{n}"


def _sha256_of_csv(df: pd.DataFrame) -> str:
    csv_bytes = df.to_csv(index=False).encode("utf-8")
    return hashlib.sha256(csv_bytes).hexdigest()


def build_dataset(
    df: pd.DataFrame,
    out_dir: pathlib.Path = _DEFAULT_OUT_DIR,
    *,
    from_date: str | None = None,
    to_date: str | None = None,
) -> DatasetManifest | None:
    """Build a versioned training snapshot from a DataFrame.

    Enforces closed-only invariant and optional closed_at window.
    Returns None if no rows survive all filters.

    Parameters
    ----------
    df:
        Raw DataFrame — may contain any auction_status mix.
    out_dir:
        Directory to write the CSV and manifest into.
    from_date:
        Keep only rows with closed_at >= from_date (YYYY-MM-DD).
    to_date:
        Keep only rows with closed_at <= to_date (YYYY-MM-DD).
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    df = df.copy()

    # ── Closed-only filter ──────────────────────────────────────────────────
    if "auction_status" in df.columns:
        n_before = len(df)
        df = df[df["auction_status"] == "closed"]
        n_dropped = n_before - len(df)
        if n_dropped:
            log.warning("Dropped %d non-closed rows (active/draft leak future signal)", n_dropped)

    # ── Drop rows with null closed_at ───────────────────────────────────────
    if "closed_at" in df.columns:
        df["closed_at"] = pd.to_datetime(df["closed_at"], utc=True, errors="coerce")
        n_before = len(df)
        df = df[df["closed_at"].notna()]
        n_dropped = n_before - len(df)
        if n_dropped:
            log.warning("Dropped %d rows with null closed_at", n_dropped)

        # ── Optional training window filter ─────────────────────────────────
        if from_date:
            df = df[df["closed_at"] >= pd.Timestamp(from_date, tz="UTC")]
        if to_date:
            df = df[df["closed_at"] <= pd.Timestamp(to_date, tz="UTC")]

    if df.empty:
        log.error("No rows remain after filters — snapshot not written")
        return None

    # ── Training window ─────────────────────────────────────────────────────
    window_start: str | None = None
    window_end: str | None = None
    if "closed_at" in df.columns and df["closed_at"].notna().any():
        window_start = df["closed_at"].min().isoformat()
        window_end = df["closed_at"].max().isoformat()

    # ── Row count with target ───────────────────────────────────────────────
    row_count_with_target = (
        int(df["winning_amount"].notna().sum())
        if "winning_amount" in df.columns
        else 0
    )

    # ── Version, hash, write ────────────────────────────────────────────────
    version = _next_version(out_dir)
    csv_hash = _sha256_of_csv(df)
    now_iso = datetime.now(timezone.utc).isoformat()

    out_path = out_dir / f"dataset_{version}.csv"
    manifest_path = out_dir / f"dataset_{version}_manifest.json"

    df.to_csv(out_path, index=False)
    log.info("Wrote %d rows -> %s", len(df), out_path)

    manifest = DatasetManifest(
        dataset_version=version,
        dataset_hash=csv_hash,
        dataset_created_at=now_iso,
        training_window_start=window_start,
        training_window_end=window_end,
        row_count=len(df),
        row_count_with_target=row_count_with_target,
        out_path=str(out_path),
        manifest_path=str(manifest_path),
    )
    manifest_path.write_text(json.dumps(asdict(manifest), indent=2))
    log.info("Manifest -> %s", manifest_path)

    return manifest


def fetch_and_build(
    url: str,
    key: str,
    out_dir: pathlib.Path = _DEFAULT_OUT_DIR,
    *,
    from_date: str | None = None,
    to_date: str | None = None,
) -> DatasetManifest | None:
    """Fetch closed auctions from Supabase v_auction_ml_features and build a snapshot."""
    try:
        from supabase import create_client
    except ImportError as exc:
        raise RuntimeError("pip install supabase") from exc

    client = create_client(url, key)
    rows: list[dict] = []
    page_size = 1_000
    offset = 0

    log.info("Fetching closed auctions from v_auction_ml_features...")
    while True:
        q = (
            client.table("v_auction_ml_features")
            .select("*")
            .eq("auction_status", "closed")
        )
        if from_date:
            q = q.gte("closed_at", from_date)
        if to_date:
            q = q.lte("closed_at", to_date)
        resp = q.range(offset, offset + page_size - 1).execute()
        batch = resp.data or []
        rows.extend(batch)
        log.info("  page %d: %d rows (total %d)", offset // page_size + 1, len(batch), len(rows))
        if len(batch) < page_size:
            break
        offset += page_size

    if not rows:
        log.error("No closed auctions returned from Supabase")
        return None

    return build_dataset(pd.DataFrame(rows), out_dir, from_date=from_date, to_date=to_date)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description="Build versioned ML training dataset")
    parser.add_argument("--url", default=os.environ.get("SUPABASE_URL", ""))
    parser.add_argument("--key", default=os.environ.get("SUPABASE_SERVICE_ROLE_KEY", ""))
    parser.add_argument("--from-date", dest="from_date", default=None,
                        help="closed_at >= YYYY-MM-DD")
    parser.add_argument("--to-date", dest="to_date", default=None,
                        help="closed_at <= YYYY-MM-DD")
    parser.add_argument("--out-dir", type=pathlib.Path, default=_DEFAULT_OUT_DIR)
    args = parser.parse_args()

    if not args.url or not args.key:
        print("ERROR: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY required", file=sys.stderr)
        sys.exit(1)

    manifest = fetch_and_build(
        args.url, args.key, args.out_dir,
        from_date=args.from_date, to_date=args.to_date,
    )
    if manifest is None:
        sys.exit(1)

    print(f"Dataset v{manifest.dataset_version}: {manifest.row_count} rows")
    print(f"  Hash   : {manifest.dataset_hash[:16]}...")
    print(f"  Window : {manifest.training_window_start} → {manifest.training_window_end}")
    print(f"  Target : {manifest.row_count_with_target} rows with winning_amount")
    print(f"  CSV    : {manifest.out_path}")
    print(f"  Manifest: {manifest.manifest_path}")


if __name__ == "__main__":
    main()
