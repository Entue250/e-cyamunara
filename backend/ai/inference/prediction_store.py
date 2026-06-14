"""Write real-inference predictions to ai_predictions in Supabase."""

from __future__ import annotations

import logging
from typing import Any, Optional

log = logging.getLogger(__name__)


class PredictionStore:
    """Thin wrapper around the Supabase Python client for inserting predictions."""

    def __init__(self, url: str, service_role_key: str) -> None:
        from supabase import create_client
        self._client = create_client(url, service_role_key)

    def store(self, row: dict[str, Any]) -> Optional[str]:
        """Insert a prediction row; return the generated id or None on failure."""
        try:
            result = (
                self._client.table("ai_predictions")
                .insert(row)
                .execute()
            )
            if result.data:
                return result.data[0].get("id")
            return None
        except Exception as exc:
            log.warning("prediction_store: insert failed — %s", exc)
            return None


class NullPredictionStore:
    """No-op store used when Supabase is not configured or store is disabled."""

    def store(self, row: dict[str, Any]) -> Optional[str]:  # noqa: ARG002
        return None
