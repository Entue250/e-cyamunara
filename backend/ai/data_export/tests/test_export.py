"""Tests for data_export/export_supabase.py.

Uses a mock Supabase client — no real credentials needed.
"""

from __future__ import annotations

import json
import pathlib
from unittest.mock import MagicMock, patch

import pandas as pd
import pytest

from data_export.export_supabase import (
    ExportResult,
    _rows_to_df,
    export,
)


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

_SAMPLE_ROWS = [
    {
        "id": "aaa",
        "main_category": "vehicle",
        "sub_category": "sedan",
        "brand": "Toyota",
        "model": "Corolla",
        "condition": "Good",
        "description": "Well maintained",
        "photo_urls": ["url1.jpg", "url2.jpg"],
        "region": "Central",
        "starting_price": 5_000_000.0,
        "winning_amount": 6_200_000.0,
        "auction_status": "closed",
        "manufacturing_year": 2018,
        "mileage": 80_000.0,
        "fuel_type": "petrol",
        "transmission": "automatic",
        "ownership_history": "first_owner",
        "accident_history": None,
        "insurance_status": "active",
        "total_bids": 5,
        "unique_bidder_count": 3,
        "views_count": 120,
        "time_of_first_bid": "2026-06-01T10:30:00Z",
        "time_of_last_bid": "2026-06-04T07:55:00Z",
        "start_date": "2026-06-01T08:00:00Z",
        "end_date": "2026-06-04T08:00:00Z",
        "closed_at": "2026-06-04T08:00:00Z",
        "created_at": "2026-05-30T12:00:00Z",
    },
    {
        "id": "bbb",
        "main_category": "bicycle",
        "sub_category": "mountain_bike",
        "brand": "Phoenix",
        "model": None,
        "condition": "Fair",
        "description": None,
        "photo_urls": [],
        "region": "Southern",
        "starting_price": 200_000.0,
        "winning_amount": None,
        "auction_status": "active",
        "manufacturing_year": 2020,
        "mileage": None,
        "fuel_type": None,
        "transmission": None,
        "ownership_history": None,
        "accident_history": None,
        "insurance_status": None,
        "total_bids": 0,
        "unique_bidder_count": 0,
        "views_count": 10,
        "time_of_first_bid": None,
        "time_of_last_bid": None,
        "start_date": "2026-06-10T08:00:00Z",
        "end_date": "2026-06-13T08:00:00Z",
        "closed_at": None,
        "created_at": "2026-06-09T10:00:00Z",
    },
]


def _make_mock_client(rows: list[dict], page_size: int = 1000):
    """Return a mock Supabase client that serves rows in pages."""
    mock_client = MagicMock()
    chain = mock_client.table.return_value.select.return_value.range.return_value

    # Simulate single page (all rows fit in one request)
    first_page = rows[:page_size]
    second_page = rows[page_size:]

    responses = [MagicMock(data=first_page)]
    if second_page:
        responses.append(MagicMock(data=second_page))
    responses.append(MagicMock(data=[]))  # empty page signals end

    chain.execute.side_effect = responses
    return mock_client


# ---------------------------------------------------------------------------
# _rows_to_df
# ---------------------------------------------------------------------------

class TestRowsToDf:
    def test_photo_urls_list_serialised_to_json(self):
        df = _rows_to_df(_SAMPLE_ROWS)
        val = df.loc[df["id"] == "aaa", "photo_urls"].iloc[0]
        parsed = json.loads(val)
        assert parsed == ["url1.jpg", "url2.jpg"]

    def test_empty_photo_urls_serialised(self):
        df = _rows_to_df(_SAMPLE_ROWS)
        val = df.loc[df["id"] == "bbb", "photo_urls"].iloc[0]
        assert json.loads(val) == []

    def test_row_count_matches(self):
        df = _rows_to_df(_SAMPLE_ROWS)
        assert len(df) == 2

    def test_none_fields_preserved(self):
        df = _rows_to_df(_SAMPLE_ROWS)
        row = df.loc[df["id"] == "bbb"].iloc[0]
        assert row["winning_amount"] is None or pd.isna(row["winning_amount"])


# ---------------------------------------------------------------------------
# export() — mocked client
# ---------------------------------------------------------------------------

class TestExport:
    def test_writes_csv(self, tmp_path):
        with patch("data_export.export_supabase._fetch_rows", return_value=_SAMPLE_ROWS):
            result = export(url="http://mock", key="mock-key", out_dir=tmp_path)

        assert result.ok
        assert result.row_count == 2
        assert result.out_path.exists()
        df = pd.read_csv(result.out_path)
        assert len(df) == 2

    def test_writes_latest_csv(self, tmp_path):
        with patch("data_export.export_supabase._fetch_rows", return_value=_SAMPLE_ROWS):
            export(url="http://mock", key="mock-key", out_dir=tmp_path)

        assert (tmp_path / "latest.csv").exists()

    def test_custom_filename(self, tmp_path):
        with patch("data_export.export_supabase._fetch_rows", return_value=_SAMPLE_ROWS):
            result = export(
                url="http://mock", key="mock-key",
                out_dir=tmp_path, filename="custom_export.csv"
            )

        assert result.out_path.name == "custom_export.csv"

    def test_fetch_error_returns_failed_result(self, tmp_path):
        with patch(
            "data_export.export_supabase._fetch_rows",
            side_effect=RuntimeError("connection refused"),
        ):
            result = export(url="http://mock", key="mock-key", out_dir=tmp_path)

        assert not result.ok
        assert result.row_count == 0
        assert any("connection refused" in e for e in result.errors)

    def test_empty_dataset(self, tmp_path):
        with patch("data_export.export_supabase._fetch_rows", return_value=[]):
            result = export(url="http://mock", key="mock-key", out_dir=tmp_path)

        assert result.ok
        assert result.row_count == 0
        df = pd.read_csv(result.out_path)
        assert len(df) == 0

    def test_out_dir_created(self, tmp_path):
        nested = tmp_path / "a" / "b" / "c"
        with patch("data_export.export_supabase._fetch_rows", return_value=_SAMPLE_ROWS):
            result = export(url="http://mock", key="mock-key", out_dir=nested)

        assert nested.exists()
        assert result.ok
