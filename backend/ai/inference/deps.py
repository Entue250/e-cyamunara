"""FastAPI dependency injection functions shared across routes."""

from __future__ import annotations

from typing import Any

from fastapi import Request

from .model_loader import ModelLoader


def get_loader(request: Request) -> ModelLoader:
    return request.app.state.loader


def get_store(request: Request) -> Any:
    return request.app.state.store
