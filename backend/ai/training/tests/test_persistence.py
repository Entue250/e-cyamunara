"""Phase 3D — Unit tests for training.persistence.*"""
from __future__ import annotations

import json
import pathlib
import tempfile

import numpy as np
import pytest
import xgboost as xgb
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

from training.train_model_c import PlattScaler

from training.evaluation.model_registry import ModelRegistry, make_entry
from training.evaluation.acceptance import check_model_a
from training.persistence.artifact_io import (
    ArtifactCorruptionError,
    artifact_checksum,
    artifact_dir,
    compute_and_write_checksum,
    ensure_artifact_dir,
    load_calibrated_model,
    load_pipeline,
    load_xgb_model,
    save_calibrated_model,
    save_metrics,
    save_pipeline,
    save_provenance,
    save_xgb_model,
    verify_artifact,
)
from training.persistence.version_manager import (
    format_version,
    next_version,
    parse_version,
)
from training.persistence.training_history import (
    TrainingRun,
    dataset_hash,
    last_run,
    load_history,
    log_run,
    new_run_id,
)


# ---------------------------------------------------------------------------
# Tiny training fixtures (all use deterministic seed=42)
# ---------------------------------------------------------------------------

_RNG = np.random.default_rng(42)
_X = _RNG.random((60, 3)).astype(np.float32)
_Y_REG = _RNG.random(60).astype(np.float32)
_Y_CLF = (_RNG.random(60) > 0.5).astype(int)


@pytest.fixture
def toy_pipeline():
    p = Pipeline([("scaler", StandardScaler())])
    p.fit(_X)
    return p


@pytest.fixture
def toy_xgb_regressor():
    m = xgb.XGBRegressor(n_estimators=5, random_state=42)
    m.fit(_X, _Y_REG)
    return m


@pytest.fixture
def toy_xgb_classifier():
    m = xgb.XGBClassifier(n_estimators=5, random_state=42, eval_metric="logloss")
    m.fit(_X, _Y_CLF)
    return m


@pytest.fixture
def toy_calibrated(toy_xgb_classifier):
    scaler = PlattScaler(toy_xgb_classifier)
    scaler.fit(_X, _Y_CLF)
    return scaler


@pytest.fixture
def tmp_dir():
    with tempfile.TemporaryDirectory() as d:
        yield pathlib.Path(d)


@pytest.fixture
def registry(tmp_dir):
    return ModelRegistry(registry_path=tmp_dir / "registry.json")


# ===========================================================================
# artifact_io — pipeline
# ===========================================================================

def test_save_pipeline_creates_files(toy_pipeline, tmp_dir):
    save_pipeline(toy_pipeline, tmp_dir)
    assert (tmp_dir / "pipeline.joblib").exists()
    assert (tmp_dir / "pipeline.joblib.sha256").exists()


def test_save_load_pipeline_roundtrip(toy_pipeline, tmp_dir):
    save_pipeline(toy_pipeline, tmp_dir)
    loaded = load_pipeline(tmp_dir)
    expected = toy_pipeline.transform(_X)
    actual = loaded.transform(_X)
    np.testing.assert_allclose(expected, actual)


def test_load_pipeline_missing_sidecar_raises(toy_pipeline, tmp_dir):
    save_pipeline(toy_pipeline, tmp_dir)
    (tmp_dir / "pipeline.joblib.sha256").unlink()
    with pytest.raises(ArtifactCorruptionError):
        load_pipeline(tmp_dir)


def test_load_pipeline_corrupted_raises(toy_pipeline, tmp_dir):
    save_pipeline(toy_pipeline, tmp_dir)
    # Corrupt the artifact
    ppath = tmp_dir / "pipeline.joblib"
    ppath.write_bytes(b"not a real joblib file")
    with pytest.raises(ArtifactCorruptionError):
        load_pipeline(tmp_dir)


# ===========================================================================
# artifact_io — XGBoost model
# ===========================================================================

def test_save_xgb_creates_files(toy_xgb_regressor, tmp_dir):
    save_xgb_model(toy_xgb_regressor, tmp_dir)
    assert (tmp_dir / "model.ubj").exists()
    assert (tmp_dir / "model.ubj.sha256").exists()


def test_save_load_xgb_regressor_roundtrip(toy_xgb_regressor, tmp_dir):
    save_xgb_model(toy_xgb_regressor, tmp_dir)
    loaded = load_xgb_model(tmp_dir, model_cls=xgb.XGBRegressor)
    expected = toy_xgb_regressor.predict(_X)
    actual = loaded.predict(_X)
    np.testing.assert_allclose(expected, actual, rtol=1e-5)


def test_save_load_xgb_classifier_roundtrip(toy_xgb_classifier, tmp_dir):
    save_xgb_model(toy_xgb_classifier, tmp_dir)
    loaded = load_xgb_model(tmp_dir, model_cls=xgb.XGBClassifier)
    expected = toy_xgb_classifier.predict(_X)
    actual = loaded.predict(_X)
    np.testing.assert_array_equal(expected, actual)


def test_load_xgb_corrupted_raises(toy_xgb_regressor, tmp_dir):
    save_xgb_model(toy_xgb_regressor, tmp_dir)
    (tmp_dir / "model.ubj").write_bytes(b"\x00\x01\x02")
    with pytest.raises(ArtifactCorruptionError):
        load_xgb_model(tmp_dir)


# ===========================================================================
# artifact_io — calibrated classifier
# ===========================================================================

def test_save_calibrated_creates_files(toy_calibrated, tmp_dir):
    save_calibrated_model(toy_calibrated, tmp_dir)
    assert (tmp_dir / "calibrated_model.joblib").exists()
    assert (tmp_dir / "calibrated_model.joblib.sha256").exists()


def test_save_load_calibrated_roundtrip(toy_calibrated, tmp_dir):
    save_calibrated_model(toy_calibrated, tmp_dir)
    loaded = load_calibrated_model(tmp_dir)
    expected = toy_calibrated.predict_proba(_X)
    actual = loaded.predict_proba(_X)
    np.testing.assert_allclose(expected, actual, rtol=1e-5)


def test_load_calibrated_corrupted_raises(toy_calibrated, tmp_dir):
    save_calibrated_model(toy_calibrated, tmp_dir)
    (tmp_dir / "calibrated_model.joblib").write_bytes(b"garbage")
    with pytest.raises(ArtifactCorruptionError):
        load_calibrated_model(tmp_dir)


# ===========================================================================
# artifact_io — checksum helpers
# ===========================================================================

def test_verify_artifact_passes(tmp_dir):
    f = tmp_dir / "data.bin"
    f.write_bytes(b"hello world")
    compute_and_write_checksum(f)
    assert verify_artifact(f) is True


def test_verify_artifact_missing_sidecar(tmp_dir):
    f = tmp_dir / "data.bin"
    f.write_bytes(b"hello world")
    assert verify_artifact(f) is False


def test_verify_artifact_after_corruption(tmp_dir):
    f = tmp_dir / "data.bin"
    f.write_bytes(b"original")
    compute_and_write_checksum(f)
    f.write_bytes(b"tampered")
    assert verify_artifact(f) is False


def test_artifact_checksum_deterministic(tmp_dir):
    f = tmp_dir / "data.bin"
    f.write_bytes(b"deterministic")
    h1 = artifact_checksum(f)
    h2 = artifact_checksum(f)
    assert h1 == h2
    assert len(h1) == 64  # SHA-256 hex = 64 chars


# ===========================================================================
# artifact_io — JSON side-cars
# ===========================================================================

def test_save_metrics_json(tmp_dir):
    save_metrics({"r2": 0.95, "mape": 0.08}, tmp_dir)
    data = json.loads((tmp_dir / "metrics.json").read_text())
    assert data["r2"] == pytest.approx(0.95)
    assert data["mape"] == pytest.approx(0.08)


def test_save_provenance_json(tmp_dir):
    save_provenance({"dataset_source": "synthetic", "feature_set_version": "1.0"}, tmp_dir)
    data = json.loads((tmp_dir / "dataset_provenance.json").read_text())
    assert data["dataset_source"] == "synthetic"


def test_save_metrics_serialises_numpy(tmp_dir):
    save_metrics({"r2": np.float64(0.92), "n": np.int64(1000)}, tmp_dir)
    data = json.loads((tmp_dir / "metrics.json").read_text())
    assert isinstance(data["r2"], float)
    assert isinstance(data["n"], int)


# ===========================================================================
# artifact_io — directory helpers
# ===========================================================================

def test_artifact_dir_path(tmp_dir):
    p = artifact_dir("model_a", "v1.0.0-synthetic", tmp_dir)
    assert p == tmp_dir / "model_a" / "v1.0.0-synthetic"


def test_ensure_artifact_dir_creates(tmp_dir):
    d = ensure_artifact_dir("model_b", "v2.1.0-real", tmp_dir)
    assert d.is_dir()
    assert d == tmp_dir / "model_b" / "v2.1.0-real"


# ===========================================================================
# version_manager
# ===========================================================================

def test_parse_version_valid():
    assert parse_version("v1.0.0-synthetic") == (1, 0, 0, "synthetic")
    assert parse_version("v2.3.7-real") == (2, 3, 7, "real")


def test_parse_version_invalid_raises():
    with pytest.raises(ValueError):
        parse_version("1.0.0-synthetic")      # missing 'v' prefix
    with pytest.raises(ValueError):
        parse_version("v1.0-synthetic")        # missing patch
    with pytest.raises(ValueError):
        parse_version("v1.0.0")                # missing datasource


def test_format_version():
    assert format_version(1, 0, 0, "synthetic") == "v1.0.0-synthetic"
    assert format_version(2, 3, 7, "real") == "v2.3.7-real"


def test_format_parse_roundtrip():
    v = format_version(3, 1, 4, "staging")
    major, minor, patch, ds = parse_version(v)
    assert (major, minor, patch, ds) == (3, 1, 4, "staging")


def test_next_version_empty_registry(registry):
    assert next_version(registry, "model_a", "synthetic") == "v1.0.0-synthetic"


def test_next_version_bumps_patch(registry):
    entry = make_entry("model_a", "v1.0.0-synthetic", {"r2": 0.95, "mape": 0.08},
                       0, check_model_a({"r2": 0.95, "mape": 0.08}))
    registry.register(entry)
    assert next_version(registry, "model_a", "synthetic") == "v1.0.1-synthetic"


def test_next_version_after_multiple(registry):
    for v in ("v1.0.0-synthetic", "v1.0.1-synthetic", "v1.0.2-synthetic"):
        e = make_entry("model_a", v, {"r2": 0.95, "mape": 0.08}, 0,
                       check_model_a({"r2": 0.95, "mape": 0.08}))
        registry.register(e)
    assert next_version(registry, "model_a", "synthetic") == "v1.0.3-synthetic"


def test_next_version_different_datasource(registry):
    e = make_entry("model_a", "v1.0.0-synthetic", {"r2": 0.95, "mape": 0.08},
                   0, check_model_a({"r2": 0.95, "mape": 0.08}))
    registry.register(e)
    # First real-datasource run should start at v1.0.0
    assert next_version(registry, "model_a", "real") == "v1.0.0-real"


def test_next_version_counts_rejected(registry):
    # Rejected version is still counted when bumping PATCH
    e = make_entry("model_a", "v1.0.0-synthetic", {"r2": 0.50, "mape": 0.40},
                   0, check_model_a({"r2": 0.50, "mape": 0.40}))
    registry.register(e)  # status=rejected, not set as active
    assert next_version(registry, "model_a", "synthetic") == "v1.0.1-synthetic"


def test_next_version_independent_per_model(registry):
    # Versions for model_b don't affect model_a versioning
    e = make_entry("model_b", "v1.0.5-synthetic", {"r2": 0.80, "mae": 500_000},
                   0, None)
    registry.register(e)
    assert next_version(registry, "model_a", "synthetic") == "v1.0.0-synthetic"


# ===========================================================================
# training_history
# ===========================================================================

def _make_run(model_name: str = "model_a", version: str = "v1.0.0-synthetic",
              passed: bool = True) -> TrainingRun:
    return TrainingRun(
        run_id=new_run_id(),
        model_name=model_name,
        version=version,
        training_timestamp="2026-06-11T10:00:00+00:00",
        dataset_source="synthetic",
        training_rows=120_000,
        val_rows=20_000,
        test_rows=20_000,
        metrics={"r2": 0.93, "mape": 0.08},
        acceptance_passed=passed,
        acceptance_grade="excellent" if passed else "fail",
        acceptance_failures=[] if passed else ["FAIL r2: 0.50 < min 0.70"],
        duration_seconds=42.5,
        dataset_hash="abc123",
    )


def test_log_run_creates_file(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run(), path)
    assert path.exists()
    lines = path.read_text().strip().splitlines()
    assert len(lines) == 1


def test_log_run_appends(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run(), path)
    log_run(_make_run(), path)
    lines = path.read_text().strip().splitlines()
    assert len(lines) == 2


def test_load_history_missing_file(tmp_dir):
    assert load_history(tmp_dir / "nonexistent.jsonl") == []


def test_load_history_returns_all(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run("model_a"), path)
    log_run(_make_run("model_b"), path)
    log_run(_make_run("model_c"), path)
    assert len(load_history(path)) == 3


def test_load_history_filter_by_model(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run("model_a"), path)
    log_run(_make_run("model_b"), path)
    log_run(_make_run("model_a"), path)
    runs = load_history(path, model_name="model_a")
    assert len(runs) == 2
    assert all(r.model_name == "model_a" for r in runs)


def test_last_run_returns_most_recent(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run("model_a", "v1.0.0-synthetic"), path)
    log_run(_make_run("model_a", "v1.0.1-synthetic"), path)
    r = last_run(path, "model_a")
    assert r is not None
    assert r.version == "v1.0.1-synthetic"


def test_last_run_no_history_returns_none(tmp_dir):
    assert last_run(tmp_dir / "nonexistent.jsonl", "model_a") is None


def test_last_run_no_match_returns_none(tmp_dir):
    path = tmp_dir / "history.jsonl"
    log_run(_make_run("model_b"), path)
    assert last_run(path, "model_a") is None


def test_roundtrip_all_fields(tmp_dir):
    path = tmp_dir / "history.jsonl"
    original = _make_run("model_c", "v1.0.0-synthetic", passed=False)
    log_run(original, path)
    [loaded] = load_history(path)
    assert loaded.run_id == original.run_id
    assert loaded.model_name == "model_c"
    assert loaded.acceptance_passed is False
    assert loaded.acceptance_grade == "fail"
    assert loaded.acceptance_failures == ["FAIL r2: 0.50 < min 0.70"]
    assert loaded.duration_seconds == pytest.approx(42.5)
    assert loaded.dataset_hash == "abc123"
    assert loaded.training_rows == 120_000


def test_dataset_hash_is_deterministic(tmp_dir):
    f = tmp_dir / "data.csv"
    f.write_text("col1,col2\n1,2\n3,4\n", encoding="utf-8")
    h1 = dataset_hash(f)
    h2 = dataset_hash(f)
    assert h1 == h2
    assert len(h1) == 64


def test_dataset_hash_changes_with_content(tmp_dir):
    f1 = tmp_dir / "v1.csv"
    f2 = tmp_dir / "v2.csv"
    f1.write_text("col1,col2\n1,2\n", encoding="utf-8")
    f2.write_text("col1,col2\n1,2\n3,4\n", encoding="utf-8")
    assert dataset_hash(f1) != dataset_hash(f2)


def test_new_run_id_unique():
    ids = {new_run_id() for _ in range(100)}
    assert len(ids) == 100
