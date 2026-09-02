from __future__ import annotations

import os
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from app.registries.ai_provider_registry import validate_ai_connection
from app.registries.platform_connector_registry import get_platform, validate_platform_mode
from app.services.user_trading_profile import get_user_trading_profile, upsert_user_trading_profile

router = APIRouter(prefix="/api/v1/user", tags=["user-profile"])


class TradingProfileRequest(BaseModel):
    ai_provider: str = Field(default="bitey", min_length=1, max_length=50)
    ai_connection_mode: str = Field(default="api", min_length=1, max_length=50)
    platform: str | None = Field(default=None, max_length=50)
    execution_mode: str = Field(default="demo", pattern="^(demo|paper)$")
    permissions: list[str] = Field(default_factory=list)
    risk_limits: dict[str, float] = Field(default_factory=lambda: {"max_position_pct": 0.02, "max_daily_loss_pct": 0.01})
    bot_id: str | None = None
    strategy_id: str | None = None
    automation_enabled: bool = False
    status: str = Field(default="draft", max_length=30)
    metadata: dict[str, Any] = Field(default_factory=dict)


def _validate_profile(request: TradingProfileRequest) -> None:
    ai_result = validate_ai_connection(request.ai_provider, request.ai_connection_mode)  # type: ignore[arg-type]
    if not ai_result["valid"]:
        raise HTTPException(status_code=400, detail=ai_result["reason"])

    if request.platform:
        platform = get_platform(request.platform)
        if not platform:
            raise HTTPException(status_code=400, detail="Unsupported trading platform")
        platform_result = validate_platform_mode(request.platform, request.execution_mode)
        if not platform_result["valid"]:
            raise HTTPException(status_code=400, detail=platform_result["reason"])
    elif request.execution_mode != "demo":
        raise HTTPException(status_code=400, detail="A trading platform is required for Paper mode")

    allowed_permissions = {"read_market", "read_account", "research", "strategy_write", "demo_execute", "paper_execute", "live_execute", "admin"}
    unknown = sorted(set(request.permissions) - allowed_permissions)
    if unknown:
        raise HTTPException(status_code=400, detail=f"Unsupported permission: {unknown[0]}")
    if "live_execute" in request.permissions:
        raise HTTPException(status_code=400, detail="Live trading permission is locked")

    if request.automation_enabled:
        required = "demo_execute" if request.execution_mode == "demo" else "paper_execute"
        if required not in request.permissions:
            raise HTTPException(status_code=400, detail=f"Automation requires explicit permission: {required}")

    max_position = request.risk_limits.get("max_position_pct", 0.02)
    max_daily_loss = request.risk_limits.get("max_daily_loss_pct", 0.01)
    if not 0 < max_position <= 0.20:
        raise HTTPException(status_code=400, detail="max_position_pct must be between 0 and 0.20")
    if not 0 < max_daily_loss <= 0.20:
        raise HTTPException(status_code=400, detail="max_daily_loss_pct must be between 0 and 0.20")


async def _resolve_user(access_token: str) -> str:
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    key = os.getenv("SUPABASE_ANON_KEY", "")
    if not url or not key:
        raise HTTPException(status_code=503, detail="Supabase Auth is not configured")
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get(f"{url}/auth/v1/user", headers={"apikey": key, "Authorization": f"Bearer {access_token}"})
    if response.status_code >= 400:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")
    user = response.json()
    user_id = user.get("id")
    if not user_id:
        raise HTTPException(status_code=401, detail="Authenticated user id is missing")
    return user_id


async def _token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Bearer access token required")
    token = authorization.split(" ", 1)[1].strip()
    if not token:
        raise HTTPException(status_code=401, detail="Bearer access token required")
    return token


@router.get("/trading-profile")
async def read_trading_profile(authorization: str | None = Header(default=None)):
    token = await _token(authorization)
    user_id = await _resolve_user(token)
    try:
        return await get_user_trading_profile(user_id, token)
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.put("/trading-profile")
async def save_trading_profile(request: TradingProfileRequest, authorization: str | None = Header(default=None)):
    token = await _token(authorization)
    user_id = await _resolve_user(token)
    _validate_profile(request)
    try:
        return await upsert_user_trading_profile(user_id, token, request.model_dump())
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
