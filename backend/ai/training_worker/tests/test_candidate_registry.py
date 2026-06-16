"""Tests for training_worker/candidate_registry.py."""

from __future__ import annotations

import json
import pathlib
from unittest.mock import MagicMock, patch

import pytest

from training_worker.candidate_registry import (
    CandidateRegistrationError,
    _read_active_version,
    _read_latest_real_version,
    register_all_candidates,
    register_candidate,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

def _write_registry(tmp_path: pathlib.Path, data: dict) -> pathlib.Path:
    path = tmp_path / "trained_models_registry.json"
    path.write_text(json.dumps(data), encoding="utf-8")
    return path


def _registry_with_versions(
    model_name: str,
    versions: dict,
    active_version: str | None = None,
) -> dict:
    return {
        "models": {
            model_name: {
                "active_version": active_version,
                "versions": versions,
            }
        }
    }


# ---------------------------------------------------------------------------
# _read_latest_real_version
# ---------------------------------------------------------------------------

def test_read_latest_real_version_returns_version(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, _registry_with_versions(
        "model_a",
        {
            "v1.0.0-synthetic": {"dataset_source": "synthetic", "training_timestamp": "2026-01-01T00:00:00"},
            "v1.0.1-real": {"dataset_source": "real", "training_timestamp": "2026-06-16T12:00:00"},
        },
        active_version="v1.0.0-synthetic",
    ))
    assert _read_latest_real_version("model_a", reg) == "v1.0.1-real"


def test_read_latest_real_version_picks_newest_when_multiple_real(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, _registry_with_versions(
        "model_a",
        {
            "v1.0.1-real": {"dataset_source": "real", "training_timestamp": "2026-06-10T00:00:00"},
            "v1.0.2-real": {"dataset_source": "real", "training_timestamp": "2026-06-16T00:00:00"},
        },
    ))
    assert _read_latest_real_version("model_a", reg) == "v1.0.2-real"


def test_read_latest_real_version_returns_none_when_no_real(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, _registry_with_versions(
        "model_a",
        {"v1.0.0-synthetic": {"dataset_source": "synthetic", "training_timestamp": "2026-01-01T00:00:00"}},
    ))
    assert _read_latest_real_version("model_a", reg) is None


def test_read_latest_real_version_returns_none_when_registry_missing(tmp_path: pathlib.Path) -> None:
    missing_path = tmp_path / "nonexistent.json"
    assert _read_latest_real_version("model_a", missing_path) is None


def test_read_latest_real_version_returns_none_on_invalid_json(tmp_path: pathlib.Path) -> None:
    bad = tmp_path / "bad.json"
    bad.write_text("not-json", encoding="utf-8")
    assert _read_latest_real_version("model_a", bad) is None


# ---------------------------------------------------------------------------
# _read_active_version
# ---------------------------------------------------------------------------

def test_read_active_version_returns_active(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, _registry_with_versions(
        "model_b",
        {"v1.0.0-synthetic": {}},
        active_version="v1.0.0-synthetic",
    ))
    assert _read_active_version("model_b", reg) == "v1.0.0-synthetic"


def test_read_active_version_returns_none_when_not_set(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, _registry_with_versions("model_b", {}))
    assert _read_active_version("model_b", reg) is None


# ---------------------------------------------------------------------------
# register_candidate — HTTP layer (stdlib urllib)
# ---------------------------------------------------------------------------

def _make_mock_response(status: int, body: dict) -> MagicMock:
    mock_resp = MagicMock()
    mock_resp.__enter__ = lambda s: s
    mock_resp.__exit__ = MagicMock(return_value=False)
    mock_resp.read.return_value = json.dumps(body).encode()
    return mock_resp


def test_register_candidate_returns_response_on_success() -> None:
    fake_body = {"registered": True, "model_name": "model_a", "candidate_version": "v1.0.0-real"}
    with patch("urllib.request.urlopen") as mock_open:
        mock_open.return_value = _make_mock_response(200, fake_body)
        result = register_candidate(
            "model_a",
            "v1.0.0-real",
            "v1.0.0-synthetic",
            supabase_url="https://example.supabase.co",
            supabase_key="service-key",
        )
    assert result["registered"] is True
    assert result["model_name"] == "model_a"


def test_register_candidate_raises_on_http_error() -> None:
    import urllib.error
    with patch("urllib.request.urlopen") as mock_open:
        err = urllib.error.HTTPError(
            url="http://x", code=403, msg="Forbidden",
            hdrs=None, fp=MagicMock(read=lambda: b'{"error":"forbidden"}')
        )
        mock_open.side_effect = err
        with pytest.raises(CandidateRegistrationError, match="403"):
            register_candidate(
                "model_a", "v1.0.0-real", "v1.0.0-synthetic",
                supabase_url="https://example.supabase.co",
                supabase_key="key",
            )


def test_register_candidate_raises_on_missing_credentials() -> None:
    with patch.dict("os.environ", {}, clear=True):
        with pytest.raises(CandidateRegistrationError, match="required"):
            register_candidate("model_a", "v1.0.0-real", "v1.0.0-synthetic")


def test_register_candidate_raises_on_invalid_model_name() -> None:
    with pytest.raises(CandidateRegistrationError, match="Invalid model_name"):
        register_candidate(
            "model_x", "v1.0.0-real", "v1.0.0-synthetic",
            supabase_url="https://x.supabase.co",
            supabase_key="key",
        )


# ---------------------------------------------------------------------------
# register_all_candidates
# ---------------------------------------------------------------------------

def test_register_all_candidates_registers_passed_models(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, {
        "models": {
            "model_a": {
                "active_version": "v1.0.0-synthetic",
                "versions": {
                    "v1.0.0-synthetic": {"dataset_source": "synthetic", "training_timestamp": "2026-01-01T00:00:00"},
                    "v1.0.1-real": {"dataset_source": "real", "training_timestamp": "2026-06-16T12:00:00"},
                },
            },
            "model_b": {
                "active_version": "v1.0.0-synthetic",
                "versions": {
                    "v1.0.1-real": {"dataset_source": "real", "training_timestamp": "2026-06-16T12:00:00"},
                },
            },
        }
    })

    with patch("training_worker.candidate_registry.register_candidate") as mock_reg:
        mock_reg.return_value = {"registered": True, "inference_reload": "ok"}
        results = register_all_candidates(
            model_names=["model_a", "model_b"],
            registry_path=reg,
            supabase_url="https://x.supabase.co",
            supabase_key="key",
        )

    assert results["model_a"] == "registered"
    assert results["model_b"] == "registered"
    assert mock_reg.call_count == 2


def test_register_all_candidates_skips_when_no_real_version(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, {
        "models": {
            "model_a": {
                "versions": {
                    "v1.0.0-synthetic": {"dataset_source": "synthetic", "training_timestamp": "2026-01-01T00:00:00"},
                },
            }
        }
    })
    with patch("training_worker.candidate_registry.register_candidate") as mock_reg:
        results = register_all_candidates(["model_a"], registry_path=reg)
    assert results["model_a"] == "skipped:no_real_version"
    mock_reg.assert_not_called()


def test_register_all_candidates_captures_error_per_model(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, {
        "models": {
            "model_a": {
                "versions": {"v1.0.1-real": {"dataset_source": "real", "training_timestamp": "2026-06-16T00:00:00"}},
            }
        }
    })
    with patch("training_worker.candidate_registry.register_candidate") as mock_reg:
        mock_reg.side_effect = CandidateRegistrationError("boom")
        results = register_all_candidates(["model_a"], registry_path=reg,
                                          supabase_url="x", supabase_key="y")
    assert "error:" in results["model_a"]


def test_register_all_candidates_skips_invalid_model_name(tmp_path: pathlib.Path) -> None:
    reg = _write_registry(tmp_path, {"models": {}})
    results = register_all_candidates(["invalid_model"], registry_path=reg)
    assert "skipped:invalid_model" in results["invalid_model"]
