-- supabase/migrations/20260609000000_ml_ready_auction_metadata.sql
-- ML-ready auction metadata — adds 19 nullable columns to auctions.
-- All columns are nullable so existing rows are unaffected.

ALTER TABLE auctions
  ADD COLUMN IF NOT EXISTS main_category      TEXT,
  ADD COLUMN IF NOT EXISTS sub_category       TEXT,
  ADD COLUMN IF NOT EXISTS brand              TEXT,
  ADD COLUMN IF NOT EXISTS model              TEXT,
  ADD COLUMN IF NOT EXISTS manufacturing_year INTEGER,
  ADD COLUMN IF NOT EXISTS color              TEXT,
  ADD COLUMN IF NOT EXISTS mileage            INTEGER,
  ADD COLUMN IF NOT EXISTS fuel_type          TEXT,
  ADD COLUMN IF NOT EXISTS transmission       TEXT,
  ADD COLUMN IF NOT EXISTS engine_size        NUMERIC(4,1),
  ADD COLUMN IF NOT EXISTS engine_cc          INTEGER,
  ADD COLUMN IF NOT EXISTS drivetrain         TEXT,
  ADD COLUMN IF NOT EXISTS seating_capacity   INTEGER,
  ADD COLUMN IF NOT EXISTS frame_material     TEXT,
  ADD COLUMN IF NOT EXISTS gear_count         INTEGER,
  ADD COLUMN IF NOT EXISTS suspension_type    TEXT,
  ADD COLUMN IF NOT EXISTS brake_type         TEXT,
  ADD COLUMN IF NOT EXISTS ownership_history  TEXT,
  ADD COLUMN IF NOT EXISTS accident_history   TEXT,
  ADD COLUMN IF NOT EXISTS insurance_status   TEXT;

-- Drop the old category check constraint (whitelisted 'car'), rename to 'vehicle',
-- then recreate the constraint with the updated allowed values.
ALTER TABLE auctions DROP CONSTRAINT IF EXISTS auctions_category_check;

UPDATE auctions SET category = 'vehicle' WHERE category = 'car';

ALTER TABLE auctions
  ADD CONSTRAINT auctions_category_check
  CHECK (category IN ('vehicle', 'motorcycle', 'bicycle'));

-- Backfill main_category from the existing category column
UPDATE auctions SET main_category = category WHERE main_category IS NULL;
