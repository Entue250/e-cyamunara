# Phase 2: AI Dataset Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build ML-ready dataset infrastructure for E-CYAMUNARA — `ai_predictions` storage table, `v_auction_ml_features` feature view, synthetic training data generator (200K auctions / 100K bids / 250K views), export pipeline, and validation tooling.

**Architecture:** Two idempotent SQL migrations create the `ai_predictions` table and `v_auction_ml_features` view. Three Python scripts generate synthetic training data (no real production data exists), export from Supabase, and validate dataset quality. No prediction logic, no FastAPI, no Flutter AI widgets — dataset foundation only.

**Tech Stack:** PostgreSQL 15 (Supabase), Python 3.11+, pandas 2.x, numpy 1.24+, supabase-py 2.x

---

## File Map

| Action | File |
|---|---|
| Create | `supabase/migrations/20260611000006_ai_prediction_storage.sql` |
| Create | `supabase/migrations/20260611000007_v_auction_ml_features.sql` |
| Create | `backend/ai/requirements.txt` |
| Create | `backend/ai/__init__.py` |
| Create | `backend/ai/scripts/__init__.py` |
| Create | `backend/ai/scripts/generate_synthetic_dataset.py` |
| Create | `backend/ai/scripts/export_training_dataset.py` |
| Create | `backend/ai/scripts/validate_training_data.py` |
| Create | `backend/ai/data/.gitkeep` |
| Create | `docs/ai_dataset_architecture.md` |

---

## Task 1: Verify Phase 1 Schema Prerequisites

**Files:**
- Read: `supabase/migrations/20260610000002_bid_behavioral_fields.sql` through `20260610000005_update_accept_bid_rpc.sql`

Confirm that all Phase 1 migrations are intact before adding Phase 2 objects. Run queries in Supabase SQL Editor. Stop if any expected result fails.

- [ ] **Step 1.1: Verify bid behavioral fields exist**

```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'bids'
  AND column_name IN ('bid_sequence','seconds_before_end','bid_increment','is_bid_update')
ORDER BY column_name;
```

Expected: 4 rows — `bid_increment (numeric)`, `bid_sequence (integer)`, `is_bid_update (boolean)`, `seconds_before_end (integer)`

- [ ] **Step 1.2: Verify auction engagement columns exist**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'auctions'
  AND column_name IN (
    'main_category','sub_category','brand','model','manufacturing_year',
    'mileage','fuel_type','transmission','ownership_history','accident_history',
    'insurance_status','color','views_count','unique_bidder_count',
    'time_of_first_bid','time_of_last_bid'
  )
ORDER BY column_name;
```

Expected: 16 rows.

- [ ] **Step 1.3: Verify auction_views table exists**

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'auction_views'
ORDER BY ordinal_position;
```

Expected: 7 rows — id, auction_id, viewer_uid, viewed_at, region, device_type, view_duration_seconds.

- [ ] **Step 1.4: Verify accept_bid RPC is SECURITY DEFINER**

```sql
SELECT routine_name, security_type
FROM information_schema.routines
WHERE routine_schema = 'public' AND routine_name = 'accept_bid';
```

Expected: 1 row, `security_type = DEFINER`.

If all checks pass, proceed to Task 2.

---

## Task 2: Create ai_predictions Storage Migration

**Files:**
- Create: `supabase/migrations/20260611000006_ai_prediction_storage.sql`

- [ ] **Step 2.1: Write the migration file**

Create `supabase/migrations/20260611000006_ai_prediction_storage.sql` with this exact content:

```sql
-- supabase/migrations/20260611000006_ai_prediction_storage.sql
--
-- Phase 2 AI Dataset Foundation: ai_predictions storage table
--
-- Purpose: Stores ML model inference outputs per auction.
--          Table is EMPTY until Phase 3 inference pipeline is built.
--          This is PREPARATION ONLY — no prediction logic is implemented here.
--
-- Security:
--   RLS enabled: only super_admins can SELECT, only service_role can INSERT.
--   No direct INSERT from authenticated/anon clients.
--
-- Idempotency: CREATE TABLE IF NOT EXISTS, DROP/CREATE POLICY, CREATE INDEX IF NOT EXISTS.
-- Prerequisites: migrations 000000–000005 applied.
-- Rollback: see bottom of file.

-- ============================================================
-- BEFORE Validation Queries
-- ============================================================

-- V0-1: Confirm ai_predictions does NOT yet exist:
-- SELECT EXISTS (
--   SELECT 1 FROM information_schema.tables
--   WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ) AS table_exists;
-- Expected: false

-- ============================================================
-- Part A: Create ai_predictions table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ai_predictions (
  id                           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  auction_id                   UUID         NOT NULL REFERENCES public.auctions(id) ON DELETE CASCADE,
  model_version                TEXT         NOT NULL,
  prediction_type              TEXT         NOT NULL
                                 CHECK (prediction_type IN ('auction_price_estimate', 'winning_bid', 'bid_probability')),
  -- Model A: auction price estimate
  expected_auction_price       NUMERIC      CHECK (expected_auction_price IS NULL OR expected_auction_price >= 0),
  value_signal                 TEXT         CHECK (value_signal IS NULL OR value_signal IN ('undervalued', 'fairly_priced', 'overpriced')),
  value_ratio                  NUMERIC      CHECK (value_ratio IS NULL OR value_ratio >= 0),
  starting_price_at_prediction NUMERIC      CHECK (starting_price_at_prediction IS NULL OR starting_price_at_prediction >= 0),
  -- Model B
  predicted_winning_bid        NUMERIC      CHECK (predicted_winning_bid IS NULL OR predicted_winning_bid >= 0),
  -- Model C
  predicted_probability        NUMERIC      CHECK (predicted_probability IS NULL OR (predicted_probability >= 0 AND predicted_probability <= 1)),
  -- Shared
  confidence_score             NUMERIC      CHECK (confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 1)),
  feature_snapshot             JSONB        NOT NULL DEFAULT '{}',
  created_at                   TIMESTAMPTZ  NOT NULL DEFAULT now()
);

-- ============================================================
-- Part B: Enable RLS
-- ============================================================

ALTER TABLE public.ai_predictions ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- Part C: RLS Policies
-- ============================================================

-- Only active super_admins may read predictions
DROP POLICY IF EXISTS super_admin_read_ai_predictions ON public.ai_predictions;
CREATE POLICY super_admin_read_ai_predictions
  ON public.ai_predictions
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.super_admins
      WHERE id = auth.uid()
        AND account_status = 'active'
    )
  );

-- No INSERT/UPDATE/DELETE for authenticated/anon — only service_role (bypasses RLS) writes.
-- This prevents client-side prediction injection.

-- ============================================================
-- Part D: Indexes
-- ============================================================

-- Most common query: latest prediction for a given auction
CREATE INDEX IF NOT EXISTS idx_ai_predictions_auction_created
  ON public.ai_predictions (auction_id, created_at DESC);

-- Audit trail: all predictions from a given model version
CREATE INDEX IF NOT EXISTS idx_ai_predictions_model_version
  ON public.ai_predictions (model_version, prediction_type, created_at DESC);

-- Analytical: all predictions of a given type
CREATE INDEX IF NOT EXISTS idx_ai_predictions_type
  ON public.ai_predictions (prediction_type, created_at DESC);

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- V1: Table exists with 10 columns:
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'ai_predictions'
-- ORDER BY ordinal_position;
-- Expected: 10 columns

-- V2: RLS is enabled:
-- SELECT relrowsecurity FROM pg_class WHERE relname = 'ai_predictions';
-- Expected: true

-- V3: Policy exists:
-- SELECT policyname, cmd FROM pg_policies WHERE tablename = 'ai_predictions';
-- Expected: 1 row — super_admin_read_ai_predictions, SELECT

-- V4: Three indexes exist (plus PK):
-- SELECT indexname FROM pg_indexes WHERE tablename = 'ai_predictions'
-- ORDER BY indexname;
-- Expected: idx_ai_predictions_auction_created, idx_ai_predictions_model_version,
--           idx_ai_predictions_type, ai_predictions_pkey

-- V5: FK constraint works — bad auction_id fails:
-- INSERT INTO public.ai_predictions (auction_id, model_version, prediction_type, feature_snapshot)
-- VALUES (gen_random_uuid(), 'v0-test', 'auction_price_estimate', '{}');
-- Expected: ERROR violates foreign key constraint (invalid auction_id UUID)

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DROP TABLE IF EXISTS public.ai_predictions CASCADE;
```

- [ ] **Step 2.2: Run BEFORE validation queries**

In Supabase SQL Editor run the V0-1 query from the migration file.
Expected: `table_exists = false`.

- [ ] **Step 2.3: Apply migration in Supabase SQL Editor**

Copy the migration body (Part A through Part D) and run it in the Supabase SQL Editor.

- [ ] **Step 2.4: Run AFTER validation queries**

Run V1–V4 from the migration file. All must return expected results.

- [ ] **Step 2.5: Commit**

```bash
git add supabase/migrations/20260611000006_ai_prediction_storage.sql
git commit -m "feat(ai-data): Phase 2 — ai_predictions storage table"
```

---

## Task 3: Create v_auction_ml_features View Migration

**Files:**
- Create: `supabase/migrations/20260611000007_v_auction_ml_features.sql`

- [ ] **Step 3.1: Write the migration file**

Create `supabase/migrations/20260611000007_v_auction_ml_features.sql` with this exact content:

```sql
-- supabase/migrations/20260611000007_v_auction_ml_features.sql
--
-- Phase 2 AI Dataset Foundation: v_auction_ml_features view
--
-- Purpose:
--   Single source of truth for ML feature extraction.
--   Combines auction direct columns + Phase 1 pre-aggregated engagement fields.
--   Used by export_training_dataset.py and future Phase 3 feature pipelines.
--
-- Idempotency: CREATE OR REPLACE VIEW — safe to re-run.
-- Prerequisites: migrations 000000–000006 applied.
-- Security: Inherits auctions RLS (is_deleted = false filter).
--
-- Rollback: DROP VIEW IF EXISTS public.v_auction_ml_features;

-- ============================================================
-- BEFORE Validation Queries
-- ============================================================

-- V0-1: Confirm all Phase 1 prerequisite columns exist on auctions (expect 16 rows):
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'auctions'
--   AND column_name IN (
--     'main_category','sub_category','brand','model','manufacturing_year',
--     'mileage','fuel_type','transmission','ownership_history','accident_history',
--     'insurance_status','color','views_count','unique_bidder_count',
--     'time_of_first_bid','time_of_last_bid'
--   );
-- Expected: 16 rows

-- ============================================================
-- View: v_auction_ml_features
-- ============================================================

CREATE OR REPLACE VIEW public.v_auction_ml_features AS
SELECT
  -- ── Auction identity ──────────────────────────────────────────────────────
  a.id                                                        AS auction_id,

  -- ── Auction features (direct columns) ────────────────────────────────────
  a.region,
  a.main_category,
  a.sub_category,
  a.brand,
  a.model,
  a.manufacturing_year,
  a.mileage,
  a.condition,
  a.fuel_type,
  a.transmission,
  a.ownership_history,
  a.accident_history,
  a.insurance_status,
  a.color,
  a.starting_price,

  -- ── Derived features ──────────────────────────────────────────────────────

  -- asset_age: integer years since manufacturing; NULL if year not recorded
  CASE
    WHEN a.manufacturing_year IS NOT NULL
    THEN EXTRACT(YEAR FROM CURRENT_DATE)::INTEGER - a.manufacturing_year
    ELSE NULL
  END                                                         AS asset_age,

  -- auction_duration_hours: planned duration in hours (continuous)
  ROUND(
    EXTRACT(EPOCH FROM (a.end_date - a.start_date)) / 3600.0,
    2
  )                                                           AS auction_duration_hours,

  -- total_bids: maintained atomically by accept_bid() RPC
  a.total_bids,

  -- unique_bidder_count: maintained atomically by accept_bid() RPC
  a.unique_bidder_count,

  -- views_count: maintained atomically by record_auction_view() RPC
  a.views_count,

  -- bids_per_view_ratio: NULL when views_count = 0 (avoids division by zero)
  CASE
    WHEN a.views_count > 0
    THEN ROUND(a.total_bids::NUMERIC / a.views_count::NUMERIC, 4)
    ELSE NULL
  END                                                         AS bids_per_view_ratio,

  -- days_until_close: positive = future, negative = past end_date
  ROUND(
    EXTRACT(EPOCH FROM (a.end_date - NOW())) / 86400.0,
    2
  )                                                           AS days_until_close,

  -- time_to_first_bid_hours: hours from start_date until first bid arrived;
  -- NULL if no bids placed
  CASE
    WHEN a.time_of_first_bid IS NOT NULL
    THEN ROUND(
      EXTRACT(EPOCH FROM (a.time_of_first_bid - a.start_date)) / 3600.0,
      2
    )
    ELSE NULL
  END                                                         AS time_to_first_bid_hours,

  -- ── Outcome features ──────────────────────────────────────────────────────
  a.auction_status,
  -- final_price = canonical ML label name for winning_amount
  a.winning_amount                                            AS final_price,
  a.winner_uid,
  a.winning_amount,

  -- ── Feature quality indicators ────────────────────────────────────────────

  -- metadata_completeness_score: fraction of 10 core ML fields present (0.00–1.00)
  -- Use as sample weight in future model training to discount sparse records
  ROUND(
    (
      (CASE WHEN a.brand              IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.model              IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.manufacturing_year IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.mileage            IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.fuel_type          IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.transmission       IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.condition          IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.ownership_history  IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.accident_history   IS NOT NULL THEN 1 ELSE 0 END) +
      (CASE WHEN a.insurance_status   IS NOT NULL THEN 1 ELSE 0 END)
    )::NUMERIC / 10.0,
    2
  )                                                           AS metadata_completeness_score,

  -- has_images: true if at least one photo URL is present
  (
    a.photo_urls IS NOT NULL
    AND array_length(a.photo_urls, 1) IS NOT NULL
    AND array_length(a.photo_urls, 1) > 0
  )                                                           AS has_images,

  -- has_description: true if description is non-empty after trimming
  (
    a.description IS NOT NULL
    AND length(trim(a.description)) > 0
  )                                                           AS has_description,

  -- ── Raw timestamps for time-based feature engineering ────────────────────
  a.start_date,
  a.end_date,
  a.created_at                                                AS auction_created_at,
  a.time_of_first_bid,
  a.time_of_last_bid

FROM public.auctions a
WHERE a.is_deleted = false;

-- ============================================================
-- AFTER Validation Queries
-- ============================================================

-- V1: View is queryable and returns expected columns:
-- SELECT auction_id, region, main_category, asset_age,
--        auction_duration_hours, bids_per_view_ratio,
--        metadata_completeness_score, has_images, has_description
-- FROM public.v_auction_ml_features LIMIT 3;
-- Expected: rows returned with those columns

-- V2: Column count is 36:
-- SELECT COUNT(*) FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'v_auction_ml_features';
-- Expected: 36

-- V3: metadata_completeness_score stays in [0, 1]:
-- SELECT MIN(metadata_completeness_score), MAX(metadata_completeness_score)
-- FROM public.v_auction_ml_features;
-- Expected: MIN >= 0, MAX <= 1

-- V4: bids_per_view_ratio is NULL when views_count = 0:
-- SELECT COUNT(*) FROM public.v_auction_ml_features
-- WHERE views_count = 0 AND bids_per_view_ratio IS NOT NULL;
-- Expected: 0

-- V5: Soft-deleted auctions excluded:
-- SELECT COUNT(*) AS total FROM public.auctions;
-- SELECT COUNT(*) AS deleted FROM public.auctions WHERE is_deleted = true;
-- SELECT COUNT(*) AS in_view FROM public.v_auction_ml_features;
-- Expected: in_view = total - deleted

-- ============================================================
-- ROLLBACK Script
-- ============================================================

-- DROP VIEW IF EXISTS public.v_auction_ml_features;
```

- [ ] **Step 3.2: Run BEFORE validation (V0-1)**

In Supabase SQL Editor — confirm 16 prerequisite columns. Stop if fewer than 16.

- [ ] **Step 3.3: Apply view in Supabase SQL Editor**

Run the `CREATE OR REPLACE VIEW` block.

- [ ] **Step 3.4: Run AFTER validation queries V1–V5**

All must pass.

- [ ] **Step 3.5: Commit**

```bash
git add supabase/migrations/20260611000007_v_auction_ml_features.sql
git commit -m "feat(ai-data): Phase 2 — v_auction_ml_features ML feature view"
```

---

## Task 4: Set Up Python Project Structure

**Files:**
- Create: `backend/ai/requirements.txt`
- Create: `backend/ai/__init__.py`
- Create: `backend/ai/scripts/__init__.py`
- Create: `backend/ai/data/.gitkeep`

- [ ] **Step 4.1: Create directory structure**

```bash
mkdir -p backend/ai/scripts
mkdir -p backend/ai/data
```

- [ ] **Step 4.2: Create backend/ai/requirements.txt**

```
pandas>=2.0.0
numpy>=1.24.0
python-dotenv>=1.0.0
supabase>=2.3.0
pyarrow>=14.0.0
```

- [ ] **Step 4.3: Create empty __init__ files**

Create `backend/ai/__init__.py` — empty file.
Create `backend/ai/scripts/__init__.py` — empty file.

- [ ] **Step 4.4: Create backend/ai/data/.gitkeep**

Empty file. Keeps the data/ directory in git while keeping generated CSVs out
(add `backend/ai/data/*.csv` and `backend/ai/data/*.parquet` to `.gitignore`).

- [ ] **Step 4.5: Add CSV/Parquet outputs to .gitignore**

Open `.gitignore` and add these lines if not already present:

```
backend/ai/data/*.csv
backend/ai/data/*.parquet
backend/ai/data/*.json
backend/ai/.env
```

- [ ] **Step 4.6: Verify Python version**

```bash
python --version
```

Expected: Python 3.11 or 3.12. If lower than 3.10, install Python 3.11.

- [ ] **Step 4.7: Install dependencies**

```bash
pip install -r backend/ai/requirements.txt
```

Expected: all packages install without errors.

- [ ] **Step 4.8: Commit**

```bash
git add backend/ai/requirements.txt backend/ai/__init__.py backend/ai/scripts/__init__.py backend/ai/data/.gitkeep .gitignore
git commit -m "feat(ai-data): Phase 2 — Python AI scripts project scaffold"
```

---

## Task 5: Write generate_synthetic_dataset.py

**Files:**
- Create: `backend/ai/scripts/generate_synthetic_dataset.py`

- [ ] **Step 5.1: Write the complete script**

Create `backend/ai/scripts/generate_synthetic_dataset.py` with this exact content:

```python
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
        print(f"  {name}: {len(df):,} rows → {path}")

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
```

- [ ] **Step 5.2: Run a smoke test with small counts**

```bash
python backend/ai/scripts/generate_synthetic_dataset.py --auctions 500 --bids 250 --views 625
```

Expected output (approximate):
```
[1/4] Generating 500 auction records (seed=42)...
[2/4] Generating up to 250 bid records...
[3/4] Generating up to 625 view records...
[4/4] Writing output files...
  synthetic_auctions: 500 rows → ...
  synthetic_bids: ~250 rows → ...
  synthetic_views: ~625 rows → ...
```

Verify the CSV files exist in `backend/ai/data/`:
```bash
ls -la backend/ai/data/
```

- [ ] **Step 5.3: Run full generation**

```bash
python backend/ai/scripts/generate_synthetic_dataset.py
```

This will take 1–3 minutes for 200K+100K+250K records. Expected:
- `synthetic_auctions.csv` ≈ 200,000 rows
- `synthetic_bids.csv` ≈ 85,000–100,000 rows (Poisson sparse)
- `synthetic_views.csv` ≈ 200,000–250,000 rows

- [ ] **Step 5.4: Commit**

```bash
git add backend/ai/scripts/generate_synthetic_dataset.py
git commit -m "feat(ai-data): Phase 2 — synthetic training data generator (200K auctions)"
```

---

## Task 6: Write export_training_dataset.py

**Files:**
- Create: `backend/ai/scripts/export_training_dataset.py`

- [ ] **Step 6.1: Write the complete script**

Create `backend/ai/scripts/export_training_dataset.py` with this exact content:

```python
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
    region: str | None,
    status: str | None,
    from_date: str | None,
    to_date: str | None,
) -> list[dict]:
    all_rows: list[dict] = []
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
    region: str | None = None,
    status: str | None = None,
    from_date: str | None = None,
    to_date: str | None = None,
    prefix: str = "training_snapshot",
    write_parquet: bool = False,
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
    print(f"  CSV → {out_csv}  ({len(df):,} rows)")

    if write_parquet:
        out_parquet = DATA_DIR / f"{prefix}_{ts}.parquet"
        df.to_parquet(out_parquet, index=False)
        print(f"  Parquet → {out_parquet}")

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
    print(f"  Metadata → {meta_path}")

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
```

- [ ] **Step 6.2: Verify the script parses arguments without a Supabase connection**

```bash
python backend/ai/scripts/export_training_dataset.py --help
```

Expected: prints the help message with all argument options.

- [ ] **Step 6.3: Commit**

```bash
git add backend/ai/scripts/export_training_dataset.py
git commit -m "feat(ai-data): Phase 2 — training dataset export pipeline from Supabase"
```

---

## Task 7: Write validate_training_data.py

**Files:**
- Create: `backend/ai/scripts/validate_training_data.py`

- [ ] **Step 7.1: Write the complete script**

Create `backend/ai/scripts/validate_training_data.py` with this exact content:

```python
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
  - Outlier detection via IQR (3× fence)

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
RANGE_CHECKS: dict[str, tuple] = {
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
        icon = "✓" if rep["summary"]["status"] == "pass" else "✗"
        print(f"  {icon} {path.name}: "
              f"quality={rep['summary']['quality_score']}, "
              f"issues={rep['summary']['issues']}")

    combined = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "files_validated": len(reports),
        "reports": reports,
    }
    args.output.write_text(json.dumps(combined, indent=2))
    print(f"\nReport → {args.output}")

    if any(r["summary"]["status"] == "fail" for r in reports):
        sys.exit(1)


if __name__ == "__main__":
    main()
```

- [ ] **Step 7.2: Run validation against the synthetic data**

First ensure `generate_synthetic_dataset.py` was run (Task 5 Step 5.3).

```bash
python backend/ai/scripts/validate_training_data.py
```

Expected output:
```
Validating 3 file(s)...
  Loading synthetic_auctions.csv...
    Shape: (200000, ...)
  ✓ synthetic_auctions.csv: quality=0.9, issues=[]
  Loading synthetic_bids.csv...
    Shape: (~85000, ...)
  ✓ synthetic_bids.csv: quality=0.9, issues=[]
  Loading synthetic_views.csv...
    Shape: (~220000, ...)
  ✓ synthetic_views.csv: quality=0.9, issues=[]
Report → backend/ai/data/training_data_quality_report.json
```

Exit code should be 0.

- [ ] **Step 7.3: Verify the JSON report was created**

```bash
python -c "
import json; from pathlib import Path
r = json.loads(Path('backend/ai/data/training_data_quality_report.json').read_text())
print('Files validated:', r['files_validated'])
for rep in r['reports']:
    print(rep['file'], '→', rep['summary'])
"
```

Expected: 3 files validated, all `status: pass`.

- [ ] **Step 7.4: Commit**

```bash
git add backend/ai/scripts/validate_training_data.py
git commit -m "feat(ai-data): Phase 2 — training data quality validation script"
```

---

## Task 8: Write docs/ai_dataset_architecture.md

**Files:**
- Create: `docs/ai_dataset_architecture.md`

- [ ] **Step 8.1: Write the documentation file**

Create `docs/ai_dataset_architecture.md` with this exact content:

```markdown
# AI Dataset Architecture — E-CYAMUNARA

## Phase Context

| Phase | Status | Scope |
|-------|--------|-------|
| Phase 0 | ✅ Complete | AI readiness audit |
| Phase 1 | ✅ Complete | Passive data collection — bid behavioral fields, auction views, engagement metrics |
| **Phase 2** | **✅ Complete** | **Dataset foundation — storage schema, feature view, synthetic data, export/validate scripts** |
| Phase 3 | Planned | Feature engineering, model training (XGBoost/Random Forest) |
| Phase 4 | Planned | Prediction APIs (FastAPI) and Flutter AI widgets |

---

## Schema Feature Audit

### Existing ML Features (Post Phase 1 + Phase 2)

#### auctions — Direct Features

| Feature | Type | ML Role | Notes |
|---------|------|---------|-------|
| region | TEXT | Categorical input | 100% present |
| main_category | TEXT | Categorical input | ~85% present |
| sub_category | TEXT | Categorical input | ~80% present |
| brand | TEXT | Categorical input | ~75% present |
| model | TEXT | Categorical input | ~70% present |
| manufacturing_year | INTEGER | Ordinal/continuous | ~75% present |
| mileage | INTEGER | Continuous (vehicle/moto) | ~65% present |
| condition | TEXT | Ordinal input | 100% present |
| fuel_type | TEXT | Categorical input | ~70% present |
| transmission | TEXT | Categorical input | ~70% present |
| ownership_history | TEXT | Categorical input | ~60% present |
| accident_history | TEXT | Categorical input | ~55% present |
| insurance_status | TEXT | Categorical input | ~60% present |
| color | TEXT | Low-signal categorical | ~65% present |
| starting_price | NUMERIC | Continuous input + price anchor | 100% present |

#### auctions — Phase 1 Engagement Features

| Feature | Type | ML Role |
|---------|------|---------|
| views_count | INTEGER | Market interest proxy |
| unique_bidder_count | INTEGER | Competition intensity |
| total_bids | INTEGER | Engagement depth |
| time_of_first_bid | TIMESTAMPTZ | Demand immediacy signal |
| time_of_last_bid | TIMESTAMPTZ | Engagement recency |

#### bids — Phase 1 Behavioral Features

| Feature | Type | ML Role |
|---------|------|---------|
| bid_sequence | INTEGER | Bidding position |
| bid_increment | NUMERIC | Bidder aggressiveness |
| seconds_before_end | INTEGER | Urgency/sniping signal |
| is_bid_update | BOOLEAN | Bid revision behavior |

#### auction_views — Phase 1 View Events

| Feature | Type | ML Role |
|---------|------|---------|
| view_duration_seconds | INTEGER | Intent depth signal |
| device_type | TEXT | Platform signal |
| region | TEXT | Geographic demand |

### Derived Features (v_auction_ml_features view)

| Feature | Derivation | ML Role |
|---------|-----------|---------|
| asset_age | EXTRACT(YEAR FROM NOW()) - manufacturing_year | Depreciation proxy |
| auction_duration_hours | (end_date - start_date) / 3600 | Competition window |
| bids_per_view_ratio | total_bids / views_count | Conversion quality |
| days_until_close | (end_date - NOW()) / 86400 | Urgency signal |
| time_to_first_bid_hours | (time_of_first_bid - start_date) / 3600 | Demand immediacy |
| metadata_completeness_score | count(non-null ML fields) / 10 | Prediction confidence weight |
| has_images | array_length(photo_urls) > 0 | Presentation quality |
| has_description | len(trim(description)) > 0 | Presentation quality |

### Missing Features (future data collection opportunities)

| Feature | Why Useful | How to Collect |
|---------|-----------|---------------|
| inspector_condition_score | Numeric RNP inspector grade | Add field to PostAuction screen |
| accident_severity_score | Quantified damage level | Expand accident_history options |
| service_history_present | Whether service book is available | Add to vehicle metadata form |
| past_auction_count_for_asset | How often same plate was auctioned | Query by plate_number |
| photos_quality_score | Auto-assessed image quality | Phase 4 computer vision |

---

## ai_predictions Table

Stores model inference outputs per auction. **Empty until Phase 3.**

| Column | Purpose |
|--------|---------|
| auction_id | Which auction this prediction covers |
| model_version | Semantic version string (e.g. "v1.0.0") |
| prediction_type | `"auction_price_estimate"` / `"winning_bid"` / `"bid_probability"` |
| expected_auction_price | Model A: expected selling price in RWF (`auction_price_estimate` rows) |
| value_signal | `"undervalued"` / `"fairly_priced"` / `"overpriced"` (derived from `starting_price / expected_auction_price`) |
| value_ratio | `starting_price / expected_auction_price` numeric ratio |
| starting_price_at_prediction | Admin-set `starting_price` captured at inference time (immutable snapshot) |
| predicted_winning_bid | Model B: predicted final winning amount in RWF |
| predicted_probability | Model C: P(auction receives ≥1 bid) — range [0, 1] |
| confidence_score | Model confidence — range [0, 1] |
| feature_snapshot | JSONB snapshot of features used at inference time |
| created_at | Timestamp of prediction |

**Security:** `service_role` only writes (bypasses RLS). Active `super_admins` read all rows. Active clients read `auction_price_estimate` rows only for auctions with status `active` or `closed`.

---

## Synthetic Data Assumptions

### Why Synthetic Data
The application is still under development. No meaningful real-world auction history
exists. Synthetic data enables ML architecture experiments, feature engineering
validation, and pipeline smoke tests before production data is available.

### Generation Model

**Volume:**
- 200,000 auction records (spanning ~730 days, 5 regions, 3 categories)
- ~85,000–100,000 bid records (Poisson sparse — avg ~0.5 bids/eligible auction)
- ~200,000–250,000 view records (proportional to auction popularity)

**Price simulation** (multiplicative model):
```
starting_price = base_price(brand, sub_category)
               × (1 - depreciation_rate)^asset_age
               × condition_multiplier
               × mileage_factor              [vehicles/motorcycles only]
               × regional_demand_factor
               × uniform_noise(0.90, 1.10)
```
Rounded to nearest 50,000 RWF (matches RNP auction floor practice).

**Depreciation rates per year:** vehicle 15%, motorcycle 12%, bicycle 8%.

**Condition multipliers:** Excellent 1.05 → Poor 0.40.

**Regional demand:** Central +15%, Eastern +5%, Western baseline, Northern/Southern -5%.

**Bid timing:** clustered 25% in first 15% of auction window + 50% in last 20%
(simulates real sniping behavior observed in online auctions).

### Known Biases in Synthetic Data

1. **Artificial distributions** — category weights (70/20/10) are assumed, not measured.
2. **No seasonal effects** — real RNP auctions may cluster around police operations.
3. **No repeat bidders** — each synthetic bid has a fresh UUID bidder.
4. **No admin behavior patterns** — posting frequency is random, not admin-specific.
5. **No geographic micro-variation** — Rwanda regions have complex local economies not captured.

These biases are corrected as real data accumulates.

---

## Dataset Lifecycle

### Current (Phase 2): Bootstrap with Synthetic Data

```
generate_synthetic_dataset.py
  → backend/ai/data/synthetic_auctions.csv   (200K rows)
  → backend/ai/data/synthetic_bids.csv       (~85K rows)
  → backend/ai/data/synthetic_views.csv      (~220K rows)

validate_training_data.py
  → backend/ai/data/training_data_quality_report.json
```

### Near-term (Phase 3): Hybrid Approach

As real auctions close, supplement synthetic data:

```
export_training_dataset.py --status closed
  → backend/ai/data/training_snapshot_YYYYMMDD.csv (real data)
  → merge with synthetic data for augmentation
  → feature engineering transforms (Phase 3)
  → model training (XGBoost / Random Forest)
```

### Long-term (Phase 4+): Real Data Dominates

Phase 1 passive sensors continuously collect real signals:
- `accept_bid()` → populates bid behavioral fields (sequence, increment, secs_before_end)
- `record_auction_view()` → populates view events and views_count
- `v_auction_ml_features` → always-current feature snapshot

`ai_predictions` stores inference outputs. Quarterly retraining triggered by
≥100 new closed auctions.

---

## Transition: Synthetic → Real Data

### Trigger Conditions for Retiring Synthetic Data

1. ≥ 1,000 real closed auctions with complete metadata
2. ≥ 500 auctions per major category (vehicle, motorcycle)
3. At least 6 months of real auction history in the database

### Validation Before Transition

Run `validate_training_data.py` on the real export. Compare:
- `metadata_completeness_score` distribution (real vs synthetic assumptions)
- `bids_per_view_ratio` distribution (real competition patterns)
- Regional price distributions (actual demand vs assumed factors)

Update `generate_synthetic_dataset.py` simulation parameters if the real
distributions diverge significantly, or retire synthetic data entirely.

---

## Future Retraining Flow (Phase 3+)

```
[Trigger: quarterly OR >100 new closed auctions]
  │
  ├─ Export:    export_training_dataset.py --status closed
  ├─ Validate:  validate_training_data.py
  ├─ Features:  (Phase 3) feature engineering transforms
  ├─ Train:     (Phase 3) XGBoost / Random Forest
  ├─ Evaluate:  holdout set metrics
  ├─ Version:   bump model_version tag
  └─ Store:     write predictions to ai_predictions via service_role
```
```

- [ ] **Step 8.2: Commit**

```bash
git add docs/ai_dataset_architecture.md
git commit -m "docs(ai-data): Phase 2 — AI dataset architecture documentation"
```

---

## Task 9: Final Verification

**Files:** none — read-only verification

- [ ] **Step 9.1: Run flutter analyze to confirm no Flutter regressions**

```bash
flutter analyze
```

Expected: `No issues found!`
Phase 2 adds no Flutter code, but verify anyway to confirm Phase 1 remains clean.

- [ ] **Step 9.2: Verify migration idempotency**

Re-run both migrations in Supabase SQL Editor by executing only the DDL portions
(Part A–D in migration 000006, the CREATE OR REPLACE VIEW in 000007).

Expected: both run without errors (`CREATE TABLE` returns `already exists` notice,
`CREATE OR REPLACE VIEW` succeeds cleanly).

- [ ] **Step 9.3: Verify RLS security**

In Supabase SQL Editor, attempt an INSERT as `authenticated` role (not service_role):

```sql
-- Run as authenticated user (not postgres/service_role)
INSERT INTO public.ai_predictions
  (auction_id, model_version, prediction_type, feature_snapshot)
VALUES
  ((SELECT id FROM public.auctions LIMIT 1), 'v0-test', 'auction_price_estimate', '{}');
```

Expected: `ERROR: new row violates row-level security policy` — confirms no client
can inject predictions.

- [ ] **Step 9.4: Verify synthetic generator produces consistent output**

Run twice with the same seed and confirm identical output:

```bash
python backend/ai/scripts/generate_synthetic_dataset.py --auctions 100 --bids 50 --views 150 --seed 99
python -c "
import pandas as pd
df1 = pd.read_csv('backend/ai/data/synthetic_auctions.csv')
print('Row count:', len(df1))
print('First auction_id:', df1['id'].iloc[0])
"
```

Run again with `--seed 99` and confirm the first `auction_id` is identical.

- [ ] **Step 9.5: Verify validate script exits 0**

```bash
python backend/ai/scripts/validate_training_data.py
echo "Exit code: $?"
```

Expected: `Exit code: 0` (all files pass quality threshold).

- [ ] **Step 9.6: Verify export script --help works**

```bash
python backend/ai/scripts/export_training_dataset.py --help
```

Expected: prints usage without errors (no Supabase connection needed for --help).

- [ ] **Step 9.7: Final commit tagging Phase 2 complete**

```bash
git add .
git status  # review: only expected files (no .env, no data/*.csv, no .pyc)
git commit -m "feat(ai-data): Phase 2 complete — AI dataset foundation"
```

---

## Deliverables Summary

| Artifact | Path | Purpose |
|----------|------|---------|
| ai_predictions table | `supabase/migrations/20260611000006_ai_prediction_storage.sql` | Future ML inference output storage |
| ML feature view | `supabase/migrations/20260611000007_v_auction_ml_features.sql` | Single source of truth for features |
| Python requirements | `backend/ai/requirements.txt` | pandas, numpy, supabase-py, pyarrow |
| Synthetic generator | `backend/ai/scripts/generate_synthetic_dataset.py` | 200K/100K/250K synthetic records |
| Export pipeline | `backend/ai/scripts/export_training_dataset.py` | CSV/Parquet export from Supabase |
| Validation script | `backend/ai/scripts/validate_training_data.py` | Quality report JSON |
| Architecture docs | `docs/ai_dataset_architecture.md` | Feature audit, assumptions, lifecycle |

---

## Risks

| Risk | Severity | Mitigation |
|------|----------|-----------|
| Supabase export blocked by RLS | Medium | Use service_role key in export script — never anon/authenticated key |
| Synthetic data biases Phase 3 model | Medium | Document biases clearly; replace with real data once 1K+ closed auctions exist |
| view `days_until_close` is time-dependent | Low | Negative values are valid (past auctions) — document in Phase 3 feature engineering |
| Python version < 3.10 on developer machine | Low | `int \| None` type hint requires 3.10+; scripts include `python --version` check in Task 4 |
| Large CSV files in git | Low | `.gitignore` excludes `*.csv`, `*.parquet`, `*.json` in data/ |

---

## Recommended Phase 3 Scope

1. **Feature engineering pipeline** — encode categoricals, normalize prices, handle nulls with imputation strategy, create polynomial features (price × age × condition)
2. **Train/validation/test split** — stratified by region + category + status
3. **Baseline models** — XGBoost for price prediction, Logistic Regression for bid probability
4. **Evaluation framework** — MAE/RMSE for price, AUC-ROC for bid probability
5. **Model versioning** — semantic version tags → `ai_predictions.model_version`
6. **Retraining trigger** — Supabase pg_cron or Edge Function to detect >100 new closed auctions
