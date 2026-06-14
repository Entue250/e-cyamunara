-- supabase/migrations/20260614000001_ai_predictions_coexistence.sql
--
-- Pre-Phase-4A: Option B coexistence support
--
-- FIX 2 (G-PRED-1, G-PRED-2):
--   Add prediction_source and model_stage columns to ai_predictions so that
--   synthetic (Phase 4B) and real (Phase 4A FastAPI) predictions can coexist
--   in the same table and be queried independently without parsing model_version.
--
-- FIX 3 (G-FLAG-1):
--   Add shadow-version staging flags to ai_feature_flags so FastAPI can load
--   a candidate model alongside the active model without overwriting the
--   active-version pointer.
--
-- Safety:
--   - ADD COLUMN IF NOT EXISTS is idempotent (no-op on re-run if column exists)
--   - INSERT ON CONFLICT (key) DO NOTHING is idempotent for feature flags
--   - Existing ai_predictions rows receive DEFAULT 'synthetic' for both columns
--   - No existing RLS policies, indexes, or queries are modified
--   - Rollback block at the bottom reverses all changes
--
-- Idempotency: safe to run multiple times.
-- Prerequisites: migration 20260611000006_ai_prediction_storage.sql applied.

-- ============================================================
-- AUDIT Queries (run before applying to confirm safe)
-- ============================================================

-- A1: Confirm prediction_source does NOT exist:
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ai_predictions'
--   AND column_name IN ('prediction_source','model_stage');
-- Expected: 0 rows

-- A2: Confirm shadow version flags do NOT exist:
-- SELECT key FROM public.ai_feature_flags
-- WHERE key LIKE 'ai.model_%_shadow_version';
-- Expected: 0 rows

-- ============================================================
-- FIX 2 — Part A: prediction_source column
-- ============================================================
-- Identifies whether a prediction was produced by the Phase 4B synthetic
-- formula generator or the Phase 4A real FastAPI inference service.
-- Default 'synthetic' ensures all existing rows remain valid immediately.

ALTER TABLE public.ai_predictions
  ADD COLUMN IF NOT EXISTS prediction_source TEXT NOT NULL DEFAULT 'synthetic'
    CHECK (prediction_source IN ('synthetic', 'real'));

-- ============================================================
-- FIX 2 — Part B: model_stage column
-- ============================================================
-- Tracks the lifecycle stage of the model that produced this prediction:
--   synthetic   — Phase 4B deterministic formula (no trained ML model)
--   shadow      — Phase 4A real model in shadow testing (not yet promoted)
--   candidate   — real model approved for shadow testing, pending production gate
--   production  — real model promoted to production; predictions visible to clients
-- Default 'synthetic' ensures all existing rows remain valid immediately.

ALTER TABLE public.ai_predictions
  ADD COLUMN IF NOT EXISTS model_stage TEXT NOT NULL DEFAULT 'synthetic'
    CHECK (model_stage IN ('synthetic', 'shadow', 'candidate', 'production'));

-- ============================================================
-- FIX 2 — Part C: Index for source/stage-based queries
-- ============================================================
-- Supports queries like "show me only real predictions" or
-- "all shadow-stage predictions for the last 7 days".

CREATE INDEX IF NOT EXISTS idx_ai_predictions_source_stage
  ON public.ai_predictions (prediction_source, model_stage, created_at DESC);

-- ============================================================
-- FIX 3 — Shadow version staging flags
-- ============================================================
-- These flags let FastAPI know which model version (if any) is currently
-- in shadow testing. Empty string means no shadow model is loaded.
-- ON CONFLICT (key) DO NOTHING is idempotent — safe on re-run.

INSERT INTO public.ai_feature_flags (key, value, updated_at) VALUES
  ('ai.model_a_shadow_version', '', NOW()),
  ('ai.model_b_shadow_version', '', NOW()),
  ('ai.model_c_shadow_version', '', NOW())
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- VALIDATION Queries (run after applying to confirm success)
-- ============================================================

-- V1: Both new columns exist with correct defaults:
-- SELECT column_name, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='ai_predictions'
--   AND column_name IN ('prediction_source','model_stage')
-- ORDER BY column_name;
-- Expected: 2 rows
--   model_stage      | 'synthetic'::text | NO
--   prediction_source| 'synthetic'::text | NO

-- V2: All existing rows have 'synthetic' for both new columns:
-- SELECT COUNT(*) FROM public.ai_predictions
-- WHERE prediction_source <> 'synthetic' OR model_stage <> 'synthetic';
-- Expected: 0

-- V3: CHECK constraint rejects invalid values:
-- INSERT INTO public.ai_predictions
--   (auction_id, model_version, prediction_type, feature_snapshot, prediction_source)
-- VALUES (gen_random_uuid(), 'v-test', 'auction_price_estimate', '{}', 'invalid');
-- Expected: ERROR violates check constraint "ai_predictions_prediction_source_check"

-- V4: Shadow version flags exist with empty string value:
-- SELECT key, value FROM public.ai_feature_flags
-- WHERE key LIKE 'ai.model_%_shadow_version'
-- ORDER BY key;
-- Expected: 3 rows — ai.model_a_shadow_version='', model_b='', model_c=''

-- V5: Index exists:
-- SELECT indexname FROM pg_indexes
-- WHERE tablename='ai_predictions' AND indexname='idx_ai_predictions_source_stage';
-- Expected: 1 row

-- ============================================================
-- ROLLBACK Script (undo all changes — run manually if needed)
-- ============================================================

-- Step 1: Remove new index
-- DROP INDEX IF EXISTS public.idx_ai_predictions_source_stage;

-- Step 2: Remove new columns (CASCADE removes their CHECK constraints too)
-- ALTER TABLE public.ai_predictions DROP COLUMN IF EXISTS prediction_source;
-- ALTER TABLE public.ai_predictions DROP COLUMN IF EXISTS model_stage;

-- Step 3: Remove shadow version flags
-- DELETE FROM public.ai_feature_flags
-- WHERE key IN (
--   'ai.model_a_shadow_version',
--   'ai.model_b_shadow_version',
--   'ai.model_c_shadow_version'
-- );
