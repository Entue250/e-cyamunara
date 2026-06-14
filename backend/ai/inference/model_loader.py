"""Load and cache all three XGBoost models at FastAPI startup."""

from __future__ import annotations

import logging
import pathlib
import sys
import threading
import time
from dataclasses import dataclass
from typing import Optional

import numpy as np
import xgboost as xgb

# Ensure training.* is importable regardless of working directory
_AI_ROOT = pathlib.Path(__file__).resolve().parent.parent
if str(_AI_ROOT) not in sys.path:
    sys.path.insert(0, str(_AI_ROOT))

from training.evaluation.model_registry import ModelRegistry, RegistryEntry
from training.persistence.artifact_io import (
    ArtifactCorruptionError,
    load_calibrated_model,
    load_pipeline,
    load_xgb_model,
)

# PlattScaler must be importable so joblib can deserialize calibrated_model.joblib
from training.train_model_c import PlattScaler  # noqa: F401

from .error_codes import ErrorCode

log = logging.getLogger(__name__)

_MODEL_NAMES = ("model_a", "model_b", "model_c")


@dataclass
class LoadedModel:
    model_name: str
    version: str
    pipeline: object
    xgb_model: object
    calibrated: Optional[object]   # PlattScaler — model_c only
    confidence_score: float
    loaded_at: float               # monotonic clock


class ModelLoadError(Exception):
    def __init__(self, model_name: str, code: ErrorCode, detail: str) -> None:
        self.model_name = model_name
        self.code = code
        self.detail = detail
        super().__init__(f"[{model_name}] {code}: {detail}")


# ---------------------------------------------------------------------------
# Confidence derivation from registry metrics
# ---------------------------------------------------------------------------

def _derive_confidence(entry: RegistryEntry, model_name: str) -> float:
    metrics = entry.metrics
    if model_name == "model_c":
        ece = float(metrics.get("ece", 0.10))
        return round(max(0.50, min(0.99, 1.0 - ece * 10)), 3)
    mape = float(metrics.get("mape", 0.20))
    return round(max(0.50, min(0.99, 1.0 - mape)), 3)


# ---------------------------------------------------------------------------
# Low-level artifact loading
# ---------------------------------------------------------------------------

def _load_one(model_name: str, version: str, artifact_dir: pathlib.Path) -> LoadedModel:
    """Load pipeline + XGB (+ calibrated for model_c) with SHA256 verification."""
    if not artifact_dir.is_dir():
        raise ModelLoadError(
            model_name, ErrorCode.MODEL_LOAD_FAILED,
            f"Artifact directory not found: {artifact_dir}",
        )

    try:
        pipeline = load_pipeline(artifact_dir)
    except ArtifactCorruptionError as exc:
        raise ModelLoadError(model_name, ErrorCode.ARTIFACT_CORRUPT, str(exc)) from exc
    except FileNotFoundError as exc:
        raise ModelLoadError(model_name, ErrorCode.MODEL_LOAD_FAILED, str(exc)) from exc

    model_cls = xgb.XGBClassifier if model_name == "model_c" else xgb.XGBRegressor
    try:
        xgb_model = load_xgb_model(artifact_dir, model_cls=model_cls)
    except ArtifactCorruptionError as exc:
        raise ModelLoadError(model_name, ErrorCode.ARTIFACT_CORRUPT, str(exc)) from exc
    except FileNotFoundError as exc:
        raise ModelLoadError(model_name, ErrorCode.MODEL_LOAD_FAILED, str(exc)) from exc

    calibrated = None
    if model_name == "model_c":
        try:
            calibrated = load_calibrated_model(artifact_dir)
        except ArtifactCorruptionError as exc:
            raise ModelLoadError(model_name, ErrorCode.ARTIFACT_CORRUPT, str(exc)) from exc
        except FileNotFoundError as exc:
            raise ModelLoadError(model_name, ErrorCode.MODEL_LOAD_FAILED, str(exc)) from exc

    return LoadedModel(
        model_name=model_name,
        version=version,
        pipeline=pipeline,
        xgb_model=xgb_model,
        calibrated=calibrated,
        confidence_score=0.0,  # filled by caller
        loaded_at=time.monotonic(),
    )


# ---------------------------------------------------------------------------
# Singleton loader
# ---------------------------------------------------------------------------

class ModelLoader:
    """Thread-safe singleton that holds loaded models for the lifetime of the process."""

    _instance: Optional["ModelLoader"] = None
    _lock: threading.Lock = threading.Lock()

    @classmethod
    def get_instance(cls) -> "ModelLoader":
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = cls()
        return cls._instance

    def __init__(self) -> None:
        self._active: dict[str, LoadedModel] = {}
        self._shadow: dict[str, LoadedModel] = {}
        self._registry: Optional[ModelRegistry] = None
        self._started_at = time.monotonic()

    def load_all(
        self,
        registry_path: pathlib.Path,
        shadow_flags: Optional[dict[str, str]] = None,
    ) -> None:
        """Load all three active models + any shadow models.

        Parameters
        ----------
        registry_path:
            Path to registry.json.
        shadow_flags:
            Dict of ``{'ai.model_a_shadow_version': '', ...}`` read from
            ai_feature_flags. Empty-string values mean no shadow model.
        """
        self._registry = ModelRegistry(registry_path=registry_path)
        base_dir = registry_path.parent

        for name in _MODEL_NAMES:
            entry = self._registry.get_active(name)
            if entry is None:
                raise ModelLoadError(
                    name, ErrorCode.MODEL_NOT_FOUND,
                    f"No active version registered for {name!r}.",
                )
            artifact_dir = base_dir / name / entry.version
            log.info("Loading %s %s from %s", name, entry.version, artifact_dir)
            loaded = _load_one(name, entry.version, artifact_dir)
            loaded.confidence_score = _derive_confidence(entry, name)
            self._active[name] = loaded
            log.info(
                "Loaded %s %s (confidence=%.3f)",
                name, entry.version, loaded.confidence_score,
            )

        if shadow_flags:
            self._load_shadow_models(base_dir, shadow_flags)

    def _load_shadow_models(
        self, base_dir: pathlib.Path, shadow_flags: dict[str, str]
    ) -> None:
        reg_raw = self._registry._load()  # noqa: SLF001

        for name in _MODEL_NAMES:
            flag_key = f"ai.{name}_shadow_version"
            shadow_ver = (shadow_flags.get(flag_key) or "").strip()
            if not shadow_ver:
                continue
            artifact_dir = base_dir / name / shadow_ver
            log.info("Loading shadow %s %s", name, shadow_ver)
            loaded = _load_one(name, shadow_ver, artifact_dir)
            ver_dict = (
                reg_raw.get("models", {})
                .get(name, {})
                .get("versions", {})
                .get(shadow_ver)
            )
            if ver_dict:
                loaded.confidence_score = _derive_confidence(
                    RegistryEntry(**ver_dict), name
                )
            self._shadow[name] = loaded
            log.info("Loaded shadow %s %s", name, shadow_ver)

    # ------------------------------------------------------------------

    def get_active(self, model_name: str) -> LoadedModel:
        if model_name not in self._active:
            raise ModelLoadError(
                model_name, ErrorCode.MODEL_NOT_FOUND,
                f"{model_name!r} is not loaded.",
            )
        return self._active[model_name]

    def get_shadow(self, model_name: str) -> Optional[LoadedModel]:
        return self._shadow.get(model_name)

    def is_loaded(self, model_name: str) -> bool:
        return model_name in self._active

    def shadow_version(self, model_name: str) -> Optional[str]:
        m = self._shadow.get(model_name)
        return m.version if m else None

    def uptime_seconds(self) -> float:
        return time.monotonic() - self._started_at

    def get_registry(self) -> Optional[ModelRegistry]:
        return self._registry
