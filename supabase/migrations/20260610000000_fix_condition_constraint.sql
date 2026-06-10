-- supabase/migrations/20260610000000_fix_condition_constraint.sql
--
-- The original auctions_condition_check used lowercase values
-- ('excellent','good','fair','poor'). The ML-ready Flutter form
-- (auction_form_data.dart) stores Title Case values with five options.
-- This migration aligns the database constraint with the Flutter schema.

-- Step 1: Drop the old constraint
ALTER TABLE auctions DROP CONSTRAINT IF EXISTS auctions_condition_check;

-- Step 2: Backfill any existing rows from lowercase to Title Case
UPDATE auctions SET condition = 'Excellent' WHERE condition = 'excellent';
UPDATE auctions SET condition = 'Good'      WHERE condition = 'good';
UPDATE auctions SET condition = 'Fair'      WHERE condition = 'fair';
UPDATE auctions SET condition = 'Poor'      WHERE condition = 'poor';

-- Step 3: Add the updated constraint matching auction_form_data.dart
ALTER TABLE auctions
  ADD CONSTRAINT auctions_condition_check
  CHECK (condition IN ('Excellent', 'Very Good', 'Good', 'Fair', 'Poor'));
