from __future__ import annotations

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel

from app.registries.ai_provider_registry import list_ai_providers, validate_ai_connection
from app.registries.platform_connector_registry import list_platforms, validate_platform_mode

router = APIRouter(prefix="/api/v1/registry", tags=["registry"])


class AIConnectionRequest(BaseModel):
    provider: str
    connection_mode: Literal["api", "mcp", "direct_user", "other"]


class PlatformModeRequest(BaseModel):
    platform: str
    mode: Literal["demo", "paper", "webhook", "live"]


@router.get("/ai/providers")
def ai_registry():
    return {"providers": list_ai_providers(), "model_agnostic": True}


@router.post("/ai/validate")
def validate_ai(request: AIConnectionRequest):
    return validate_ai_connection(request.provider, request.connection_mode)


@router.get("/platforms")
def platform_registry():
    return {"platforms": list_platforms(), "live_default": False}


@router.post("/platforms/validate")
def validate_platform(request: PlatformModeRequest):
    return validate_platform_mode(request.platform, request.mode)
