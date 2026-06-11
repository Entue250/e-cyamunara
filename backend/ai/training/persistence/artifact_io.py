"""
training/persistence/artifact_io.py
====================================
Versioned model artifact save/load with SHA-256 integrity verification.

Each save function writes the artifact and a .sha256 sidecar file alongside it.
Each load function verifies the checksum before returning the object, raising
ArtifactCorruptionError if the file has been modified or the sidecar is missing.
"""
from __future__ import annotations

import hashlib
import json
import pathlib

import joblib
import numpy as np
import xgboost as xgb


class ArtifactCorruptionError(IOError):
    """Raised when a saved artifact fails its SHA-256 checksum verification."""


# ---------------------------------------------------------------------------
# Checksum helpers
# ---------------------------------------------------------------------------

def artifact_checksum(path: pathlib.Path) -> str:
    """Return the SHA-256 hex digest of the file at *path*."""
    sha = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65_536), b""):
            sha.update(chunk)
    return sha.hexdigest()


def compute_and_write_checksum(path: pathlib.Path) -> str:
    """Write a <filename>.sha256 sidecar next to *path*; return the digest.

    Works on any file — the sidecar is always named by appending ".sha256"
    to the full filename (e.g., pipeline.joblib → pipeline.joblib.sha256).
    """
    path = pathlib.Path(path)
    digest = artifact_checksum(path)
    sidecar = path.with_suffix(path.suffix + ".sha256")
    sidecar.write_text(digest, encoding="utf-8")
    return digest


def verify_artifact(path: pathlib.Path) -> bool:
    """Return True iff the file's current SHA-256 matches its stored sidecar."""
    path = pathlib.Path(path)
    sidecar = path.with_suffix(path.suffix + ".sha256")
    if not path.exists() or not sidecar.exists():
        return False
    expected = sidecar.read_text(encoding="utf-8").strip()
    return artifact_checksum(path) == expected


# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------

def save_pipeline(pipeline, dir_path: pathlib.Path) -> str:
    """Dump sklearn pipeline to pipeline.joblib + sidecar; return checksum."""
    path = pathlib.Path(dir_path) / "pipeline.joblib"
    joblib.dump(pipeline, path)
    return compute_and_write_checksum(path)


def load_pipeline(dir_path: pathlib.Path, filename: str = "pipeline.joblib"):
    """Load a sklearn pipeline after checksum verification.

    Parameters
    ----------
    dir_path:
        Directory containing the pipeline file and its .sha256 sidecar.
    filename:
        Name of the file to load.  Defaults to ``pipeline.joblib``.
    """
    path = pathlib.Path(dir_path) / filename
    if not verify_artifact(path):
        raise ArtifactCorruptionError(
            f"Checksum mismatch or missing sidecar for: {path}"
        )
    return joblib.load(path)


# ---------------------------------------------------------------------------
# XGBoost native binary (.ubj)
# ---------------------------------------------------------------------------

def save_xgb_model(model, dir_path: pathlib.Path) -> str:
    """Save XGBoost model to model.ubj + sidecar; return checksum."""
    path = pathlib.Path(dir_path) / "model.ubj"
    model.save_model(str(path))
    return compute_and_write_checksum(path)


def load_xgb_model(
    dir_path: pathlib.Path,
    model_cls=None,
    filename: str = "model.ubj",
):
    """Load an XGBoost model after checksum verification.

    Parameters
    ----------
    dir_path:
        Directory that contains the model file and its .sha256 sidecar.
    model_cls:
        XGBoost class to instantiate (XGBRegressor or XGBClassifier).
        Defaults to XGBRegressor.
    filename:
        Name of the model file.  Defaults to ``model.ubj``.
    """
    path = pathlib.Path(dir_path) / filename
    if not verify_artifact(path):
        raise ArtifactCorruptionError(
            f"Checksum mismatch or missing sidecar for: {path}"
        )
    cls = model_cls if model_cls is not None else xgb.XGBRegressor
    m = cls()
    m.load_model(str(path))
    return m


# ---------------------------------------------------------------------------
# Calibrated classifier (Model C)
# ---------------------------------------------------------------------------

def save_calibrated_model(calibrated, dir_path: pathlib.Path) -> str:
    """Dump CalibratedClassifierCV to calibrated_model.joblib + sidecar."""
    path = pathlib.Path(dir_path) / "calibrated_model.joblib"
    joblib.dump(calibrated, path)
    return compute_and_write_checksum(path)


def load_calibrated_model(dir_path: pathlib.Path):
    """Load calibrated_model.joblib after checksum verification."""
    path = pathlib.Path(dir_path) / "calibrated_model.joblib"
    if not verify_artifact(path):
        raise ArtifactCorruptionError(
            f"Checksum mismatch or missing sidecar for: {path}"
        )
    return joblib.load(path)


# ---------------------------------------------------------------------------
# JSON side-cars
# ---------------------------------------------------------------------------

def _json_default(obj):
    if isinstance(obj, np.integer):
        return int(obj)
    if isinstance(obj, np.floating):
        return float(obj)
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def save_metrics(metrics: dict, dir_path: pathlib.Path) -> None:
    """Write metrics dict to metrics.json (UTF-8, 2-space indent)."""
    path = pathlib.Path(dir_path) / "metrics.json"
    path.write_text(
        json.dumps(metrics, indent=2, default=_json_default), encoding="utf-8"
    )


def save_provenance(provenance: dict, dir_path: pathlib.Path) -> None:
    """Write dataset provenance dict to dataset_provenance.json."""
    path = pathlib.Path(dir_path) / "dataset_provenance.json"
    path.write_text(
        json.dumps(provenance, indent=2, default=_json_default), encoding="utf-8"
    )


# ---------------------------------------------------------------------------
# Directory helpers
# ---------------------------------------------------------------------------

def artifact_dir(model_name: str, version: str, base: pathlib.Path) -> pathlib.Path:
    """Return base/model_name/version/ (does NOT create it)."""
    return pathlib.Path(base) / model_name / version


def ensure_artifact_dir(
    model_name: str, version: str, base: pathlib.Path
) -> pathlib.Path:
    """Create and return base/model_name/version/."""
    d = artifact_dir(model_name, version, base)
    d.mkdir(parents=True, exist_ok=True)
    return d
