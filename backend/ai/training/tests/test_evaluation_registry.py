"""Phase 3C — Unit tests for training.evaluation.model_registry."""
from __future__ import annotations

import json
import pathlib
import tempfile

import pytest

from training.evaluation.model_registry import (
    ModelRegistry,
    RegistryEntry,
    make_entry,
    generate_version,
    KNOWN_MODELS,
)
from training.evaluation.acceptance import check_model_a, AcceptanceResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _passing_acceptance() -> AcceptanceResult:
    """Return a passing AcceptanceResult for model_a."""
    return check_model_a({"r2": 0.93, "mape": 0.08})


def _failing_acceptance() -> AcceptanceResult:
    """Return a failing AcceptanceResult for model_a."""
    return check_model_a({"r2": 0.50, "mape": 0.30})


def _make_registry(tmp_dir: str) -> ModelRegistry:
    registry_path = pathlib.Path(tmp_dir) / "registry.json"
    return ModelRegistry(registry_path=registry_path)


# ---------------------------------------------------------------------------
# generate_version tests
# ---------------------------------------------------------------------------

def test_generate_version_format():
    assert generate_version() == "v1.0.0-synthetic"


def test_generate_version_custom():
    assert generate_version(2, 1, 3, "real") == "v2.1.3-real"


# ---------------------------------------------------------------------------
# make_entry tests
# ---------------------------------------------------------------------------

def test_make_entry_status_registered():
    result = _passing_acceptance()
    entry = make_entry(
        "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
        acceptance_result=result,
    )
    assert entry.status == "registered"


def test_make_entry_status_rejected():
    result = _failing_acceptance()
    entry = make_entry(
        "model_a", "v1.0.0-synthetic", {"r2": 0.50}, 10_000,
        acceptance_result=result,
    )
    assert entry.status == "rejected"


def test_make_entry_feature_count():
    result = _passing_acceptance()
    entry = make_entry(
        "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 5_000,
        acceptance_result=result,
    )
    assert entry.feature_count == len(entry.feature_names)


# ---------------------------------------------------------------------------
# ModelRegistry tests (all use temp directories)
# ---------------------------------------------------------------------------

def test_registry_register_and_retrieve():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93, "mape": 0.08}, 10_000,
            acceptance_result=acceptance,
        )
        reg.register(entry)
        active = reg.get_active("model_a")
        assert active is not None
        assert active.model_name == "model_a"
        assert active.version == "v1.0.0-synthetic"


def test_registry_empty_get_active():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        result = reg.get_active("model_a")
        assert result is None


def test_registry_list_versions():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry1 = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.90}, 5_000,
            acceptance_result=acceptance,
        )
        entry2 = make_entry(
            "model_a", "v1.1.0-synthetic", {"r2": 0.91}, 6_000,
            acceptance_result=acceptance,
        )
        reg.register(entry1)
        reg.register(entry2)
        versions = reg.list_versions("model_a")
        assert len(versions) == 2


def test_registry_reject():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        reg.register(entry)
        reg.reject("model_a", "v1.0.0-synthetic", "test rejection reason")
        versions = reg.list_versions("model_a")
        found = [v for v in versions if v.version == "v1.0.0-synthetic"]
        assert found[0].status == "rejected"


def test_registry_reject_missing_raises():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        with pytest.raises(KeyError):
            reg.reject("model_a", "v99.0.0-synthetic", "no such version")


def test_registry_set_active():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry1 = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.90}, 5_000,
            acceptance_result=acceptance,
        )
        entry2 = make_entry(
            "model_a", "v1.1.0-synthetic", {"r2": 0.92}, 6_000,
            acceptance_result=acceptance,
        )
        reg.register(entry1)
        reg.register(entry2)
        reg.set_active("model_a", "v1.1.0-synthetic")
        active = reg.get_active("model_a")
        assert active.version == "v1.1.0-synthetic"


def test_registry_persists_across_instances():
    with tempfile.TemporaryDirectory() as tmp:
        registry_path = pathlib.Path(tmp) / "registry.json"
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        # Write with first instance
        reg1 = ModelRegistry(registry_path=registry_path)
        reg1.register(entry)
        # Read with second instance
        reg2 = ModelRegistry(registry_path=registry_path)
        active = reg2.get_active("model_a")
        assert active is not None
        assert active.version == "v1.0.0-synthetic"


# ---------------------------------------------------------------------------
# Model card tests
# ---------------------------------------------------------------------------

def test_generate_model_card_keys():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        card = reg.generate_model_card(entry)
        expected_keys = {
            "model_name", "version", "task", "training_dataset", "dataset_source",
            "training_timestamp", "training_rows", "feature_count", "feature_names",
            "metrics", "acceptance", "limitations", "intended_use",
        }
        assert expected_keys.issubset(set(card.keys()))


def test_generate_model_card_model_a_task():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        card = reg.generate_model_card(entry)
        assert card["task"] == "starting_price_regression"


def test_save_model_card_creates_file():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        reg.register(entry)
        output_dir = pathlib.Path(tmp) / "cards"
        card_path = reg.save_model_card(entry, output_dir=output_dir)
        assert card_path.exists()


def test_save_model_card_valid_json():
    with tempfile.TemporaryDirectory() as tmp:
        reg = _make_registry(tmp)
        acceptance = _passing_acceptance()
        entry = make_entry(
            "model_a", "v1.0.0-synthetic", {"r2": 0.93}, 10_000,
            acceptance_result=acceptance,
        )
        reg.register(entry)
        output_dir = pathlib.Path(tmp) / "cards"
        card_path = reg.save_model_card(entry, output_dir=output_dir)
        loaded = json.loads(card_path.read_text(encoding="utf-8"))
        assert "model_name" in loaded
        assert loaded["model_name"] == "model_a"


# ---------------------------------------------------------------------------
# KNOWN_MODELS tests
# ---------------------------------------------------------------------------

def test_known_models_has_all_three():
    assert set(KNOWN_MODELS.keys()) == {"model_a", "model_b", "model_c"}


def test_known_models_limitations_nonempty():
    for model_name, info in KNOWN_MODELS.items():
        assert len(info["limitations"]) > 0, f"{model_name} has empty limitations"
