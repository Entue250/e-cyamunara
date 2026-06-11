#!/usr/bin/env python3
"""
generate_synthetic_dataset.py

Generates synthetic training data for E-CYAMUNARA auction price prediction.
No real production data is available — this creates statistically realistic
synthetic records for bootstrapping ML model development.

Outputs (in backend/ai/data/):
  synthetic_auctions.csv   — up to 200,000 auction records
  synthetic_bids.csv       — up to 100,000 bid records
  synthetic_views.csv      — up to 250,000 view records

Usage:
  python backend/ai/scripts/generate_synthetic_dataset.py
  python backend/ai/scripts/generate_synthetic_dataset.py --seed 42
  python backend/ai/scripts/generate_synthetic_dataset.py --auctions 1000 --bids 500 --views 1500
  python backend/ai/scripts/generate_synthetic_dataset.py --parquet
"""

import argparse
import uuid
from datetime import datetime, timedelta, timezone
from pathlib import Path

import numpy as np
import pandas as pd

# ── Paths ─────────────────────────────────────────────────────────────────────
SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR.parent / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)

# ── Reference date: all synthetic timestamps computed relative to this ─────────
REF_DATE = datetime(2026, 6, 11, tzinfo=timezone.utc)

# ── Category taxonomy ─────────────────────────────────────────────────────────
TAXONOMY: dict = {
    "vehicle": {
        "weight": 0.70,
        "sub_categories": ["SUV", "Sedan", "Hatchback", "Pickup", "Truck", "Van", "Bus"],
        "sub_weights": [0.25, 0.30, 0.15, 0.15, 0.05, 0.05, 0.05],
        "brands": ["Toyota", "Nissan", "Hyundai", "Isuzu", "Mitsubishi", "Mercedes", "BMW", "Kia", "Honda", "Ford"],
        "brand_weights": [0.25, 0.18, 0.12, 0.12, 0.10, 0.08, 0.05, 0.05, 0.03, 0.02],
        "fuel_types": ["Petrol", "Diesel", "Electric", "Hybrid"],
        "fuel_weights": [0.40, 0.45, 0.05, 0.10],
        "transmissions": ["Automatic", "Manual"],
        "trans_weights": [0.65, 0.35],
    },
    "motorcycle": {
        "weight": 0.20,
        "sub_categories": ["Sport Bike", "Cruiser", "Touring", "Scooter", "Dirt Bike", "Electric Motorcycle"],
        "sub_weights": [0.20, 0.15, 0.10, 0.30, 0.15, 0.10],
        "brands": ["Honda", "Yamaha", "Suzuki", "TVS", "Kawasaki", "Bajaj"],
        "brand_weights": [0.30, 0.25, 0.18, 0.12, 0.10, 0.05],
        "fuel_types": ["Petrol", "Electric"],
        "fuel_weights": [0.90, 0.10],
        "transmissions": ["Manual", "Automatic"],
        "trans_weights": [0.70, 0.30],
    },
    "bicycle": {
        "weight": 0.10,
        "sub_categories": ["Mountain Bike", "Road Bike", "BMX", "Hybrid Bike", "Electric Bicycle"],
        "sub_weights": [0.30, 0.25, 0.10, 0.20, 0.15],
        "brands": ["Giant", "Trek", "Specialized", "Hero", "Phoenix"],
        "brand_weights": [0.30, 0.25, 0.15, 0.20, 0.10],
        "fuel_types": ["N/A"],
        "fuel_weights": [1.00],
        "transmissions": ["N/A", "Manual"],
        "trans_weights": [0.60, 0.40],
    },
}

# ── Base prices in RWF (well-maintained ~2020 vintage) ─────────────────────────
VEHICLE_BASE: dict = {
    "Toyota":     {"SUV": 22_000_000, "Sedan": 14_000_000, "Hatchback": 9_000_000, "Pickup": 20_000_000, "Truck": 32_000_000, "Van": 16_000_000, "Bus": 45_000_000},
    "Nissan":     {"SUV": 20_000_000, "Sedan": 12_000_000, "Hatchback": 8_500_000, "Pickup": 18_000_000, "Truck": 28_000_000, "Van": 14_000_000, "Bus": 40_000_000},
    "Hyundai":    {"SUV": 18_000_000, "Sedan": 11_000_000, "Hatchback": 7_500_000, "Pickup": 15_000_000, "Truck": 24_000_000, "Van": 12_000_000, "Bus": 35_000_000},
    "Isuzu":      {"SUV": 19_000_000, "Sedan": 10_000_000, "Hatchback": 7_000_000, "Pickup": 21_000_000, "Truck": 35_000_000, "Van": 15_000_000, "Bus": 48_000_000},
    "Mitsubishi": {"SUV": 21_000_000, "Sedan": 12_000_000, "Hatchback": 8_000_000, "Pickup": 19_000_000, "Truck": 30_000_000, "Van": 14_000_000, "Bus": 42_000_000},
    "Mercedes":   {"SUV": 55_000_000, "Sedan": 45_000_000, "Hatchback": 30_000_000, "Pickup": 40_000_000, "Truck": 60_000_000, "Van": 35_000_000, "Bus": 80_000_000},
    "BMW":        {"SUV": 50_000_000, "Sedan": 42_000_000, "Hatchback": 28_000_000, "Pickup": 38_000_000, "Truck": 55_000_000, "Van": 32_000_000, "Bus": 75_000_000},
    "Kia":        {"SUV": 16_000_000, "Sedan": 10_000_000, "Hatchback": 7_000_000, "Pickup": 14_000_000, "Truck": 22_000_000, "Van": 11_000_000, "Bus": 32_000_000},
    "Honda":      {"SUV": 17_000_000, "Sedan": 11_000_000, "Hatchback": 7_500_000, "Pickup": 15_000_000, "Truck": 23_000_000, "Van": 12_000_000, "Bus": 33_000_000},
    "Ford":       {"SUV": 19_000_000, "Sedan": 11_500_000, "Hatchback": 8_000_000, "Pickup": 22_000_000, "Truck": 33_000_000, "Van": 15_000_000, "Bus": 44_000_000},
}

MOTO_BASE: dict = {
    "Honda":    {"Sport Bike": 1_800_000, "Cruiser": 1_500_000, "Touring": 2_500_000, "Scooter": 800_000, "Dirt Bike": 1_200_000, "Electric Motorcycle": 1_600_000},
    "Yamaha":   {"Sport Bike": 1_900_000, "Cruiser": 1_600_000, "Touring": 2_600_000, "Scooter": 850_000, "Dirt Bike": 1_300_000, "Electric Motorcycle": 1_700_000},
    "Suzuki":   {"Sport Bike": 1_700_000, "Cruiser": 1_400_000, "Touring": 2_400_000, "Scooter": 750_000, "Dirt Bike": 1_100_000, "Electric Motorcycle": 1_500_000},
    "TVS":      {"Sport Bike": 900_000,   "Cruiser": 800_000,   "Touring": 1_200_000, "Scooter": 600_000, "Dirt Bike": 750_000,   "Electric Motorcycle": 1_000_000},
    "Kawasaki": {"Sport Bike": 2_200_000, "Cruiser": 1_800_000, "Touring": 3_000_000, "Scooter": 950_000, "Dirt Bike": 1_500_000, "Electric Motorcycle": 2_000_000},
    "Bajaj":    {"Sport Bike": 800_000,   "Cruiser": 700_000,   "Touring": 1_000_000, "Scooter": 500_000, "Dirt Bike": 650_000,   "Electric Motorcycle": 900_000},
}

BICYCLE_BASE: dict = {
    "Giant":       {"Mountain Bike": 350_000, "Road Bike": 400_000, "BMX": 200_000, "Hybrid Bike": 300_000, "Electric Bicycle": 800_000},
    "Trek":        {"Mountain Bike": 400_000, "Road Bike": 450_000, "BMX": 220_000, "Hybrid Bike": 350_000, "Electric Bicycle": 900_000},
    "Specialized": {"Mountain Bike": 450_000, "Road Bike": 500_000, "BMX": 250_000, "Hybrid Bike": 380_000, "Electric Bicycle": 950_000},
    "Hero":        {"Mountain Bike": 180_000, "Road Bike": 200_000, "BMX": 120_000, "Hybrid Bike": 160_000, "Electric Bicycle": 400_000},
    "Phoenix":     {"Mountain Bike": 150_000, "Road Bike": 170_000, "BMX": 100_000, "Hybrid Bike": 140_000, "Electric Bicycle": 350_000},
}

# ── Conditions ─────────────────────────────────────────────────────────────────
CONDITIONS = ["Excellent", "Very Good", "Good", "Fair", "Poor"]
CONDITION_WEIGHTS = [0.10, 0.25, 0.40, 0.18, 0.07]
CONDITION_MULT = {"Excellent": 1.05, "Very Good": 0.88, "Good": 0.72, "Fair": 0.56, "Poor": 0.40}

# ── Regions ────────────────────────────────────────────────────────────────────
REGIONS = ["Central", "Northern", "Southern", "Eastern", "Western"]
REGION_WEIGHTS = [0.35, 0.15, 0.15, 0.20, 0.15]
REGION_DEMAND = {"Central": 1.15, "Eastern": 1.05, "Western": 1.00, "Northern": 0.95, "Southern": 0.95}

# ── Auction statuses ───────────────────────────────────────────────────────────
STATUSES = ["closed", "active", "draft"]
STATUS_WEIGHTS = [0.60, 0.25, 0.15]

# ── Depreciation rates per year ───────────────────────────────────────────────
DEPRECIATION = {"vehicle": 0.15, "motorcycle": 0.12, "bicycle": 0.08}

COLORS = ["White", "Black", "Silver", "Red", "Blue", "Grey", "Green", "Brown", "Beige"]
OWNERSHIP = ["First Owner", "Second Owner", "Third Owner", "Fleet Vehicle"]
ACCIDENT = ["No Accidents", "Minor Accident", "Major Accident"]
INSURANCE = ["Fully Insured", "Third Party Only", "Uninsured"]
DISTRICTS = ["Gasabo", "Kicukiro", "Nyarugenge", "Bugesera", "Rwamagana",
             "Rubavu", "Musanze", "Huye", "Muhanga", "Rusizi"]


def _mileage_factor(mileage: int) -> float:
    if mileage < 50_000:   return 1.00
    if mileage < 100_000:  return 0.90
    if mileage < 150_000:  return 0.80
    if mileage < 200_000:  return 0.70
    return 0.60


def _base_price(category: str, sub_cat: str, brand: str) -> float:
    if category == "vehicle":
        return float(VEHICLE_BASE.get(brand, {}).get(sub_cat, 10_000_000))
    if category == "motorcycle":
        return float(MOTO_BASE.get(brand, {}).get(sub_cat, 1_000_000))
    return float(BICYCLE_BASE.get(brand, {}).get(sub_cat, 250_000))


def _starting_price(
    category: str, sub_cat: str, brand: str, year: int,
    condition: str, region: str, mileage: int, rng: np.random.Generator,
) -> float:
    age = max(0, REF_DATE.year - year)
    price = _base_price(category, sub_cat, brand)
    price *= (1 - DEPRECIATION[category]) ** age
    price *= CONDITION_MULT[condition]
    if category in ("vehicle", "motorcycle") and mileage > 0:
        price *= _mileage_factor(mileage)
    price *= REGION_DEMAND[region]
    price *= rng.uniform(0.90, 1.10)
    return float(round(price / 50_000) * 50_000)


def generate_auctions(n: int, rng: np.random.Generator) -> pd.DataFrame:
    cats = list(TAXONOMY.keys())
    cat_w = [TAXONOMY[c]["weight"] for c in cats]

    records = []
    for _ in range(n):
        cat = rng.choice(cats, p=cat_w)
        cfg = TAXONOMY[cat]
        sub   = rng.choice(cfg["sub_categories"], p=cfg["sub_weights"])
        brand = rng.choice(cfg["brands"], p=cfg["brand_weights"])
        region = rng.choice(REGIONS, p=REGION_WEIGHTS)
        cond  = rng.choice(CONDITIONS, p=CONDITION_WEIGHTS)
        status = rng.choice(STATUSES, p=STATUS_WEIGHTS)
        fuel  = rng.choice(cfg["fuel_types"], p=cfg["fuel_weights"])
        trans = rng.choice(cfg["transmissions"], p=cfg["trans_weights"])

        year = int(rng.integers(2005, 2024))
        mileage = int(rng.integers(0, 250_000)) if cat in ("vehicle", "motorcycle") else 0

        sp = _starting_price(cat, sub, brand, year, cond, region, mileage, rng)

        days_ago = int(rng.integers(7, 730))
        start_dt = REF_DATE - timedelta(days=days_ago)
        dur_days  = int(rng.integers(3, 31))
        end_dt    = start_dt + timedelta(days=dur_days)

        winner_uid = winning_amount = closed_at = None
        if status == "closed" and rng.random() > 0.40:
            mult = 1.0 + rng.exponential(0.18)
            winning_amount = float(round(sp * mult / 50_000) * 50_000)
            winner_uid = str(uuid.uuid4())
            closed_at = (end_dt + timedelta(hours=int(rng.integers(1, 24)))).isoformat()

        # Completeness probability: vehicles best-documented, bicycles least
        cp = 0.85 if cat == "vehicle" else (0.70 if cat == "motorcycle" else 0.50)

        plate = (
            f"RAC {int(rng.integers(100,999))} {chr(int(rng.integers(65,91)))}"
            if cat == "vehicle"
            else f"N/A-{int(rng.integers(1000,9999))}"
        )

        records.append({
            "id":                  str(uuid.uuid4()),
            "item_name":           f"{brand} {sub} {year}",
            "category":            cat,
            "main_category":       cat if rng.random() < cp else None,
            "sub_category":        sub if rng.random() < cp else None,
            "plate_number":        plate,
            "condition":           cond,
            "description":         (
                f"{'Well-maintained' if cond in ('Excellent','Very Good') else 'Used'} "
                f"{year} {brand} {sub} in {cond} condition. Available in {region}."
                if rng.random() > 0.10 else None
            ),
            "starting_price":      sp,
            "current_highest_bid": winning_amount if winning_amount else (
                float(round(sp * rng.uniform(1.0, 1.5) / 50_000) * 50_000)
                if status == "active" else sp
            ),
            "total_bids":          0,   # backfilled by generate_bids
            "region":              region,
            "posted_by_admin_uid": str(uuid.uuid4()),
            "posted_by_admin_name": f"Admin-{region[:3]}",
            "auction_status":      status,
            "start_date":          start_dt.isoformat(),
            "end_date":            end_dt.isoformat(),
            "closed_at":           closed_at,
            "winner_uid":          winner_uid,
            "winning_amount":      winning_amount,
            "is_deleted":          False,
            "created_at":          (start_dt - timedelta(days=int(rng.integers(1,7)))).isoformat(),
            "updated_at":          end_dt.isoformat() if status == "closed" else start_dt.isoformat(),
            # ML metadata
            "brand":               brand if rng.random() < cp else None,
            "model":               f"{brand[:3]}{sub[:3]}{year % 100}".upper() if rng.random() < cp else None,
            "manufacturing_year":  year if rng.random() < cp else None,
            "color":               rng.choice(COLORS) if rng.random() < cp else None,
            "mileage":             mileage if (cat in ("vehicle","motorcycle") and rng.random() < cp) else None,
            "fuel_type":           fuel if rng.random() < cp else None,
            "transmission":        trans if rng.random() < cp else None,
            "ownership_history":   rng.choice(OWNERSHIP) if rng.random() < cp else None,
            "accident_history":    rng.choice(ACCIDENT) if rng.random() < (cp * 0.7) else None,
            "insurance_status":    rng.choice(INSURANCE) if rng.random() < (cp * 0.8) else None,
            # Phase 1 engagement — backfilled below
            "views_count":         0,
            "unique_bidder_count": 0,
            "time_of_first_bid":   None,
            "time_of_last_bid":    None,
        })

    return pd.DataFrame(records)


def generate_bids(
    auctions: pd.DataFrame, n_target: int, rng: np.random.Generator
) -> pd.DataFrame:
    """
    One bid row per unique (auction_id, bidder_uid) pair — matching the
    UNIQUE(auction_id, bidder_uid) constraint on the real bids table.
    is_bid_update=True simulates bidders who updated their bid after initial placement.
    """
    eligible = auctions[auctions["auction_status"] != "draft"]
    avg_per_auction = n_target / max(1, len(eligible))

    records = []
    for idx, auction in eligible.iterrows():
        lam = avg_per_auction * (1.6 if auction["auction_status"] == "closed" else 0.7)
        n_bidders = min(int(rng.poisson(lam)), 20)
        if n_bidders == 0:
            continue

        start_dt = datetime.fromisoformat(auction["start_date"])
        end_dt   = datetime.fromisoformat(auction["end_date"])
        auction_secs = max(1.0, (end_dt - start_dt).total_seconds())

        current_price = float(auction["starting_price"])
        first_bid_time = last_bid_time = None

        for seq in range(1, n_bidders + 1):
            bidder_uid = str(uuid.uuid4())
            is_update  = rng.random() < 0.20

            # Bid amount: raise current highest by 2–20%
            pct = rng.uniform(0.02, 0.20)
            bid_amount = float(round(current_price * (1 + pct) / 50_000) * 50_000)
            bid_increment = bid_amount - current_price
            current_price = bid_amount

            # Timing: 25% early, 50% late, 25% mid
            bucket = rng.random()
            if bucket < 0.25:
                frac = rng.uniform(0.00, 0.15)
            elif bucket < 0.75:
                frac = rng.uniform(0.80, 0.99)
            else:
                frac = rng.uniform(0.15, 0.80)

            bid_time = start_dt + timedelta(seconds=frac * auction_secs)
            secs_before_end = max(0, int(auction_secs - frac * auction_secs))

            if first_bid_time is None or bid_time < first_bid_time:
                first_bid_time = bid_time
            if last_bid_time is None or bid_time > last_bid_time:
                last_bid_time = bid_time

            records.append({
                "id":                str(uuid.uuid4()),
                "auction_id":        auction["id"],
                "bidder_uid":        bidder_uid,
                "bidder_name":       f"Bidder-{bidder_uid[:8]}",
                "bidder_phone":      f"07{int(rng.integers(20,99))}{int(rng.integers(100_000,999_999))}",
                "bidder_district":   rng.choice(DISTRICTS),
                "bid_amount":        bid_amount,
                "bid_status":        "winning" if seq == n_bidders else "outbid",
                "created_at":        bid_time.isoformat(),
                "updated_at":        bid_time.isoformat(),
                "bid_sequence":      seq,
                "bid_increment":     bid_increment,
                "seconds_before_end": secs_before_end,
                "is_bid_update":     is_update,
            })

        # Backfill engagement columns onto the auction row
        auctions.at[idx, "total_bids"]          = n_bidders
        auctions.at[idx, "unique_bidder_count"]  = n_bidders
        if first_bid_time:
            auctions.at[idx, "time_of_first_bid"] = first_bid_time.isoformat()
            auctions.at[idx, "time_of_last_bid"]  = last_bid_time.isoformat()

    bids_df = pd.DataFrame(records)
    if len(bids_df) > n_target:
        bids_df = bids_df.sample(n=n_target, random_state=int(rng.integers(0, 99_999)))
    return bids_df


def generate_views(
    auctions: pd.DataFrame, n_target: int, rng: np.random.Generator
) -> pd.DataFrame:
    eligible = auctions[auctions["auction_status"] != "draft"]
    max_bids = max(1.0, float(auctions["total_bids"].max()))
    avg_per_auction = n_target / max(1, len(eligible))

    device_types = ["mobile", "web", "unknown"]
    device_w     = [0.80, 0.15, 0.05]

    records = []
    for idx, auction in eligible.iterrows():
        popularity = float(auction["total_bids"]) / max_bids
        lam = avg_per_auction * (0.5 + 2.5 * popularity)
        n_views = max(0, int(rng.poisson(lam)))
        if n_views == 0:
            continue

        start_dt = datetime.fromisoformat(auction["start_date"])
        end_dt   = datetime.fromisoformat(auction["end_date"])
        auction_secs = max(1.0, (end_dt - start_dt).total_seconds())

        for _ in range(n_views):
            viewer_uid = str(uuid.uuid4()) if rng.random() > 0.30 else None
            frac = float(rng.beta(1.5, 1.0))
            view_time = start_dt + timedelta(seconds=frac * auction_secs)
            duration  = min(max(int(rng.exponential(90)), 5), 3600)

            records.append({
                "id":                    str(uuid.uuid4()),
                "auction_id":            auction["id"],
                "viewer_uid":            viewer_uid,
                "viewed_at":             view_time.isoformat(),
                "region":                auction["region"],
                "device_type":           rng.choice(device_types, p=device_w),
                "view_duration_seconds": duration,
            })

        auctions.at[idx, "views_count"] = n_views

    views_df = pd.DataFrame(records)
    if len(views_df) > n_target:
        views_df = views_df.sample(n=n_target, random_state=int(rng.integers(0, 99_999)))
    return views_df


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate synthetic E-CYAMUNARA training data"
    )
    parser.add_argument("--seed",     type=int, default=42,       help="Random seed")
    parser.add_argument("--auctions", type=int, default=200_000,  help="Auction record count")
    parser.add_argument("--bids",     type=int, default=100_000,  help="Bid record count")
    parser.add_argument("--views",    type=int, default=250_000,  help="View record count")
    parser.add_argument("--parquet",  action="store_true",         help="Also write Parquet")
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)

    print(f"[1/4] Generating {args.auctions:,} auction records (seed={args.seed})...")
    auctions_df = generate_auctions(args.auctions, rng)

    print(f"[2/4] Generating up to {args.bids:,} bid records...")
    bids_df = generate_bids(auctions_df, args.bids, rng)

    print(f"[3/4] Generating up to {args.views:,} view records...")
    views_df = generate_views(auctions_df, args.views, rng)

    print("[4/4] Writing output files...")
    for df, name in [
        (auctions_df, "synthetic_auctions"),
        (bids_df,     "synthetic_bids"),
        (views_df,    "synthetic_views"),
    ]:
        path = DATA_DIR / f"{name}.csv"
        df.to_csv(path, index=False)
        if args.parquet:
            df.to_parquet(DATA_DIR / f"{name}.parquet", index=False)
        print(f"  {name}: {len(df):,} rows -> {path}")

    print("\nCategory distribution:")
    print(auctions_df["category"].value_counts().to_string())
    print("\nStatus distribution:")
    print(auctions_df["auction_status"].value_counts().to_string())
    print("\nRegion distribution:")
    print(auctions_df["region"].value_counts().to_string())
    print(f"\nAuctions with bids: {(auctions_df['total_bids'] > 0).sum():,}")
    print(f"Auctions with views: {(auctions_df['views_count'] > 0).sum():,}")


if __name__ == "__main__":
    main()
