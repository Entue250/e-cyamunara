# Inference Service — Rollback Guide (Phase 4A)

## Rollback Scenarios

### 1. Stop the inference service

Simply stop the Docker container or kill the uvicorn process. No database changes needed — the service only **writes** to `ai_predictions`; it never modifies the synthetic pipeline or feature flags.

```bash
docker stop <container-id>
# or
kill $(lsof -ti :8000)
```

The pg_cron synthetic pipeline (Phase 4B) continues unaffected.

### 2. Purge real predictions from ai_predictions

If you need to remove all shadow-stage real predictions (e.g., after a bad model load):

```sql
-- CAUTION: This deletes all real predictions. Only run if intended.
DELETE FROM public.ai_predictions
WHERE prediction_source = 'real'
  AND model_stage = 'shadow';
```

Synthetic predictions (`prediction_source = 'synthetic'`) are untouched.

### 3. Roll back a promoted active model version

If `set_active()` was called to promote a bad version:

```python
from training.evaluation.model_registry import ModelRegistry
import pathlib

reg = ModelRegistry(registry_path=pathlib.Path("backend/ai/trained_models/registry.json"))
# Revert model_a to previous version
reg.set_active("model_a", "v1.0.4-synthetic")
# Then restart the inference service to reload
```

The old version becomes `active`, the bad version becomes `deprecated`.

### 4. Disable shadow model loading

Set the flag to empty in Supabase (via SQL Editor):

```sql
UPDATE public.ai_feature_flags
SET value = '', updated_at = NOW()
WHERE key IN (
  'ai.model_a_shadow_version',
  'ai.model_b_shadow_version',
  'ai.model_c_shadow_version'
);
```

Then restart the inference service. Shadow models will not be loaded.

### 5. Emergency: restore ai_predictions_coexistence migration

If the `prediction_source` / `model_stage` columns need to be removed (extreme case):

```sql
-- See supabase/migrations/20260614000001_ai_predictions_coexistence.sql ROLLBACK block
DROP INDEX IF EXISTS public.idx_ai_predictions_source_stage;
ALTER TABLE public.ai_predictions DROP COLUMN IF EXISTS prediction_source;
ALTER TABLE public.ai_predictions DROP COLUMN IF EXISTS model_stage;
DELETE FROM public.ai_feature_flags
WHERE key IN (
  'ai.model_a_shadow_version',
  'ai.model_b_shadow_version',
  'ai.model_c_shadow_version'
);
```

This restores the table to its pre-Phase-4A state.

## What is NOT affected by inference service rollback

- Flutter app (predictions are never exposed to clients in Phase 4A)
- pg_cron synthetic pipeline (runs independently)
- ai_shadow_metrics (continues collecting from synthetic predictions)
- ModelRegistry (registry.json is read-only by the inference service)
- Active model artifacts (not modified at inference time)
