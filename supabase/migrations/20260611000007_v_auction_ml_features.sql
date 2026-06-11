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
