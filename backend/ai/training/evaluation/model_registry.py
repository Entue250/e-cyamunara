from __future__ import annotations

import json
import pathlib
from dataclasses import dataclass, field, asdict
from datetime import datetime, timezone
from typing import Optional

import filelock

from training.config import CONFIG
from training.preprocessing.feature_definitions import (
    MODEL_A_FEATURES, MODEL_B_FEATURES, MODEL_C_FEATURES, FEATURE_SET_VERSION,
)

KNOWN_MODELS: dict[str, dict] = {
    "model_a": {
        "task": "market_value_regression",
        "feature_names": MODEL_A_FEATURES,
        "intended_use": (
            "Estimate the fair market value of a vehicle at auction time, helping "
            "RNP clients (bidders) assess whether a listed auction is undervalued, "
            "fairly priced, or overpriced relative to comparable historical sales. "
            "Model A does NOT suggest or influence the admin-defined starting price — "
            "the starting price is the minimum allowed bid, set manually by region admins."
        ),
        "limitations": [
            "Trained on synthetic data — may not reflect real RNP auction market prices.",
            "Regional demand factors are modeled as fixed multipliers, not live market data.",
            "No seasonal price effects captured.",
            "High-value segment (vehicle price > 10M RWF) has wider prediction intervals.",
            "starting_price is an input feature: estimates are anchored to the admin floor "
            "price and may underestimate value if the starting price is set unusually low.",
        ],
    },
    "model_b": {
        "task": "winning_bid_regression",
        "feature_names": MODEL_B_FEATURES,
        "intended_use": (
            "Estimate the expected final winning bid for an active auction, "
            "assisting RNP clients in bid strategy and admins in reserve price decisions."
        ),
        "limitations": [
            "Trained on synthetic data with simulated bidding behavior.",
            "Requires at least some engagement signal for reliable predictions.",
            "Bidding spikes near auction close are partially captured but noisy.",
            "Does not account for repeat bidder behavior (no bidder history modeled).",
        ],
    },
    "model_c": {
        "task": "bid_probability_classification",
        "feature_names": MODEL_C_FEATURES,
        "intended_use": (
            "Predict the probability that an auction will receive at least one bid, "
            "enabling admins to identify at-risk auctions requiring promotion or repricing."
        ),
        "limitations": [
            "Trained on closed auctions only — active auctions have incomplete signals.",
            "Calibrated via Platt scaling on a single validation split.",
            "Class imbalance (many zero-bid auctions) requires threshold tuning for deployment.",
            "Synthetic bidder behavior does not capture real user intent patterns.",
        ],
    },
}


def _default_feature_names(model_name: str) -> list[str]:
    """Return the canonical feature list for the given model."""
    return list(KNOWN_MODELS.get(model_name, {}).get("feature_names", []))


def generate_version(
    major: int = 1,
    minor: int = 0,
    patch: int = 0,
    datasource: str = "synthetic",
) -> str:
    """Return a version string like 'v1.0.0-synthetic'."""
    return f"v{major}.{minor}.{patch}-{datasource}"


@dataclass
class RegistryEntry:
    """Metadata for one trained model version."""
    model_name: str
    version: str
    status: str
    training_timestamp: str
    dataset_source: str
    feature_set_version: str
    feature_names: list[str] = field(default_factory=list)
    feature_count: int = 0
    training_rows: int = 0
    metrics: dict = field(default_factory=dict)
    acceptance_passed: bool = False
    acceptance_grade: str = "unknown"
    rejection_reason: str = ""
    model_card_path: str = ""


def make_entry(
    model_name: str,
    version: str,
    metrics: dict,
    training_rows: int,
    acceptance_result=None,
    dataset_source: str = "synthetic",
    feature_names: list[str] | None = None,
) -> RegistryEntry:
    """Construct a RegistryEntry from training outputs."""
    names = feature_names if feature_names is not None else _default_feature_names(model_name)
    passed = acceptance_result.passed if acceptance_result else False
    grade  = acceptance_result.grade  if acceptance_result else "unknown"
    return RegistryEntry(
        model_name=model_name,
        version=version,
        status="registered" if passed else "rejected",
        training_timestamp=datetime.now(timezone.utc).isoformat(),
        dataset_source=dataset_source,
        feature_set_version=FEATURE_SET_VERSION,
        feature_names=names,
        feature_count=len(names),
        training_rows=training_rows,
        metrics=dict(metrics),
        acceptance_passed=passed,
        acceptance_grade=grade,
    )


class ModelRegistry:
    """JSON-backed registry of trained model versions."""

    SCHEMA_VERSION = "1"

    def __init__(self, registry_path: pathlib.Path | None = None) -> None:
        self._path = pathlib.Path(registry_path or CONFIG.paths.registry_file)
        self._lock_path = self._path.with_suffix(".lock")

    def _load(self) -> dict:
        """Load registry from disk; return empty structure if file missing."""
        if not self._path.exists():
            return {"schema_version": self.SCHEMA_VERSION, "models": {}}
        return json.loads(self._path.read_text(encoding="utf-8"))

    def _save(self, registry: dict) -> None:
        """Atomically write registry to disk with file locking."""
        self._path.parent.mkdir(parents=True, exist_ok=True)
        with filelock.FileLock(str(self._lock_path)):
            self._path.write_text(
                json.dumps(registry, indent=2, ensure_ascii=False),
                encoding="utf-8",
            )

    def register(self, entry: RegistryEntry) -> None:
        """Add or overwrite a version entry in the registry."""
        reg = self._load()
        models = reg.setdefault("models", {})
        model_block = models.setdefault(entry.model_name, {"active": None, "versions": {}})
        model_block["versions"][entry.version] = asdict(entry)
        if model_block["active"] is None and entry.acceptance_passed:
            model_block["active"] = entry.version
        self._save(reg)

    def reject(self, model_name: str, version: str, reason: str) -> None:
        """Mark a version as rejected with a reason string."""
        reg = self._load()
        ver_block = reg.get("models", {}).get(model_name, {}).get("versions", {})
        if version not in ver_block:
            raise KeyError(f"Version {version!r} of {model_name!r} not found in registry.")
        ver_block[version]["status"] = "rejected"
        ver_block[version]["rejection_reason"] = reason
        self._save(reg)

    def set_active(self, model_name: str, version: str) -> None:
        """Promote a version to active for the given model."""
        reg = self._load()
        model_block = reg.get("models", {}).get(model_name, {})
        if not model_block:
            raise KeyError(f"Model {model_name!r} not found in registry.")
        if version not in model_block.get("versions", {}):
            raise KeyError(f"Version {version!r} of {model_name!r} not found.")
        model_block["active"] = version
        self._save(reg)

    def get_active(self, model_name: str) -> RegistryEntry | None:
        """Return the active RegistryEntry for a model, or None if none set."""
        reg = self._load()
        model_block = reg.get("models", {}).get(model_name, {})
        active_ver = model_block.get("active")
        if not active_ver:
            return None
        entry_dict = model_block.get("versions", {}).get(active_ver)
        if not entry_dict:
            return None
        return RegistryEntry(**entry_dict)

    def list_versions(self, model_name: str) -> list[RegistryEntry]:
        """Return all RegistryEntry objects for a model, sorted by training_timestamp."""
        reg = self._load()
        versions = reg.get("models", {}).get(model_name, {}).get("versions", {})
        entries = [RegistryEntry(**v) for v in versions.values()]
        return sorted(entries, key=lambda e: e.training_timestamp)

    def generate_model_card(
        self,
        entry: RegistryEntry,
        limitations: list[str] | None = None,
        intended_use: str = "",
    ) -> dict:
        """Build the model_card dict for an entry."""
        known = KNOWN_MODELS.get(entry.model_name, {})
        return {
            "model_name": entry.model_name,
            "version": entry.version,
            "task": known.get("task", "unknown"),
            "training_dataset": f"synthetic_auctions_{entry.feature_set_version}",
            "dataset_source": entry.dataset_source,
            "training_timestamp": entry.training_timestamp,
            "training_rows": entry.training_rows,
            "feature_set_version": entry.feature_set_version,
            "feature_count": entry.feature_count,
            "feature_names": entry.feature_names,
            "metrics": entry.metrics,
            "acceptance": {
                "passed": entry.acceptance_passed,
                "grade": entry.acceptance_grade,
            },
            "limitations": limitations or known.get("limitations", []),
            "intended_use": intended_use or known.get("intended_use", ""),
        }

    def save_model_card(
        self,
        entry: RegistryEntry,
        output_dir: pathlib.Path | None = None,
        limitations: list[str] | None = None,
        intended_use: str = "",
    ) -> pathlib.Path:
        """Write model_card.json to output_dir; update entry.model_card_path in registry."""
        out_dir = pathlib.Path(output_dir or CONFIG.paths.models_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        card = self.generate_model_card(entry, limitations=limitations, intended_use=intended_use)
        card_filename = f"{entry.model_name}_{entry.version}_card.json"
        card_path = out_dir / card_filename
        card_path.write_text(json.dumps(card, indent=2, ensure_ascii=False), encoding="utf-8")
        reg = self._load()
        ver_block = reg.get("models", {}).get(entry.model_name, {}).get("versions", {})
        if entry.version in ver_block:
            ver_block[entry.version]["model_card_path"] = str(card_path)
        self._save(reg)
        return card_path
