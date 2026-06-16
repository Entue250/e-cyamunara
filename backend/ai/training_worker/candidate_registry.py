"""training_worker/candidate_registry.py

Phase 9E — Register a newly trained real-data model as a shadow candidate.

Called by schedule.py and app.py after run_training_job() succeeds on real data.
Makes an HTTP POST to the register-candidate-model Edge Function, which:
  1. Sets ai.model_{name}_shadow_version in ai_feature_flags
  2. Inserts a row in ai_candidate_models (status='evaluating')
  3. Optionally hot-reloads the inference service

The Edge Function URL is derived from SUPABASE_URL (same base URL as all
other Supabase calls). Auth uses SUPABASE_SERVICE_ROLE_KEY.
"""

from __future__ import annotations

import json
import logging
import os
import pathlib
import urllib.request
from typing import Optional

log = logging.getLogger(__name__)

_VALID_MODELS = frozenset({"model_a", "model_b", "model_c"})


class CandidateRegistrationError(Exception):
    """Raised when the Edge Function returns a non-200 response."""


def _read_latest_real_version(
    model_name: str,
    registry_path: pathlib.Path,
) -> Optional[str]:
    """Read the most recently registered real-data version from the local registry JSON.

    Returns the version string or None if no real-data entry exists.
    The registry JSON has structure:
      { "models": { "model_a": { "versions": { "v1.0.0-real": {...}, ... } } } }
    """
    if not registry_path.exists():
        log.warning("Registry file not found: %s", registry_path)
        return None

    try:
        data = json.loads(registry_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        log.warning("Could not read registry %s: %s", registry_path, exc)
        return None

    versions_dict: dict = (
        data.get("models", {})
        .get(model_name, {})
        .get("versions", {})
    )
    # Filter to real-datasource entries and find newest by training_timestamp
    real_entries = [
        (ver, meta)
        for ver, meta in versions_dict.items()
        if (meta.get("dataset_source") or "") == "real"
    ]
    if not real_entries:
        return None

    newest = max(real_entries, key=lambda kv: kv[1].get("training_timestamp", ""))
    return newest[0]


def _read_active_version(
    model_name: str,
    registry_path: pathlib.Path,
) -> Optional[str]:
    """Return the current active version from the local registry JSON."""
    if not registry_path.exists():
        return None
    try:
        data = json.loads(registry_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return None

    return (
        data.get("models", {})
        .get(model_name, {})
        .get("active_version")
    )


def register_candidate(
    model_name: str,
    candidate_version: str,
    active_version: str,
    supabase_url: Optional[str] = None,
    supabase_key: Optional[str] = None,
    timeout: int = 30,
) -> dict:
    """Call register-candidate-model Edge Function for a single model.

    Parameters
    ----------
    model_name:
        One of 'model_a', 'model_b', 'model_c'.
    candidate_version:
        The version string just trained (e.g. 'v1.0.0-real').
    active_version:
        The current active version at registration time (e.g. 'v1.0.3-synthetic').
    supabase_url:
        Base Supabase project URL. Defaults to SUPABASE_URL env var.
    supabase_key:
        Service role key. Defaults to SUPABASE_SERVICE_ROLE_KEY env var.
    timeout:
        HTTP timeout in seconds.

    Returns
    -------
    Parsed JSON response from the Edge Function.

    Raises
    ------
    CandidateRegistrationError
        If the Edge Function returns a non-200 status or the request fails.
    """
    url = supabase_url or os.environ.get("SUPABASE_URL")
    key = supabase_key or os.environ.get("SUPABASE_SERVICE_ROLE_KEY")

    if not url or not key:
        raise CandidateRegistrationError(
            "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required"
        )
    if model_name not in _VALID_MODELS:
        raise CandidateRegistrationError(
            f"Invalid model_name '{model_name}'. Must be one of: {sorted(_VALID_MODELS)}"
        )

    endpoint = f"{url.rstrip('/')}/functions/v1/register-candidate-model"
    payload = json.dumps(
        {
            "model_name": model_name,
            "candidate_version": candidate_version,
            "active_version": active_version,
        }
    ).encode()

    request = urllib.request.Request(
        endpoint,
        data=payload,
        headers={
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )

    try:
        with urllib.request.urlopen(request, timeout=timeout) as resp:
            body = resp.read().decode()
            return json.loads(body)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode()
        raise CandidateRegistrationError(
            f"Edge Function returned {exc.code}: {body}"
        ) from exc
    except Exception as exc:
        raise CandidateRegistrationError(
            f"Request to register-candidate-model failed: {exc}"
        ) from exc


def register_all_candidates(
    model_names: list[str],
    registry_path: pathlib.Path,
    supabase_url: Optional[str] = None,
    supabase_key: Optional[str] = None,
    timeout: int = 30,
) -> dict[str, str]:
    """Register all successfully trained real-data models as candidates.

    Reads candidate_version and active_version from the local registry file,
    then calls register_candidate for each model. Failures are logged but do
    not raise — a single model's registration failure should not abort the
    rest.

    Parameters
    ----------
    model_names:
        Which models to register (e.g. ['model_a', 'model_b', 'model_c']).
    registry_path:
        Path to trained_models_registry.json (read-only).
    supabase_url / supabase_key:
        Credentials for the Edge Function call.

    Returns
    -------
    Dict mapping model_name → status ('registered' | 'skipped:no_version' | error message).
    """
    results: dict[str, str] = {}

    for model_name in model_names:
        if model_name not in _VALID_MODELS:
            results[model_name] = f"skipped:invalid_model"
            continue

        candidate_version = _read_latest_real_version(model_name, registry_path)
        if not candidate_version:
            log.info("No real-data version found for %s — skipping registration", model_name)
            results[model_name] = "skipped:no_real_version"
            continue

        active_version = _read_active_version(model_name, registry_path) or "unknown"

        try:
            resp = register_candidate(
                model_name=model_name,
                candidate_version=candidate_version,
                active_version=active_version,
                supabase_url=supabase_url,
                supabase_key=supabase_key,
                timeout=timeout,
            )
            log.info(
                "Registered candidate %s@%s (reload=%s)",
                model_name,
                candidate_version,
                resp.get("inference_reload", "?"),
            )
            results[model_name] = "registered"
        except CandidateRegistrationError as exc:
            log.error("Failed to register candidate %s: %s", model_name, exc)
            results[model_name] = f"error:{exc}"

    return results
