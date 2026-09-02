from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from app.registries.ai_provider_registry import validate_ai_connection
from app.registries.platform_connector_registry import validate_platform_mode
from app.services.user_trading_profile import get_user_trading_profile, upsert_user_trading_profile

router = APIRouter(prefix="/api/v1/user/trading-profile", tags=["user-trading-profile"])


class TradingProfileUpdate(BaseModel):
    ai_provider: str = Field(default="bitey", min_length=1, max_length=80)
    ai_connection_mode: Literal["api", "mcp", "direct_user", "other"] = "direct_user"
    platform: str | None = Field(default=None, max_length=80)
    execution_mode: Literal["demo", "paper", "live"] = "demo"
    permissions: list[str] = Field(default_factory=list)
    risk_limits: dict[str, float] = Field(default_factory=lambda: {"max_position_pct": 0.02, "max_daily_loss_pct": 0.01})
    bot_id: str | None = None
    strategy_id: str | None = None
    automation_enabled: bool = False
    status: Literal["draft", "ready", "active", "paused", "disabled"] = "draft"
    metadata: dict[str, Any] = Field(default_factory=dict)


def _token(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Bearer access token required")
    return authorization.split(" ", 1)[1].strip()


async def _user_id(access_token: str) -> str:
    import os
    import httpx
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    key = os.getenv("SUPABASE_ANON_KEY", "")
    if not url or not key:
        raise HTTPException(status_code=503, detail="Supabase Auth is not configured")
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get(f"{url}/auth/v1/user", headers={"apikey": key, "Authorization": f"Bearer {access_token}"})
    if response.status_code >= 400:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")
    return response.json()["id"]


@router.get("")
async def read_profile(authorization: str | None = Header(default=None)):
    token = _token(authorization)
    user_id = await _user_id(token)
    return {"profile": await get_user_trading_profile(user_id, token)}


@router.put("")
async def save_profile(request: TradingProfileUpdate, authorization: str | None = Header(default=None)):
    token = _token(authorization)
    user_id = await _user_id(token)

    if request.execution_mode == "live":
        raise HTTPException(status_code=403, detail="Live trading is locked")
    ai_check = validate_ai_connection(request.ai_provider, request.ai_connection_mode)
    if not ai_check.get("valid"):
        raise HTTPException(status_code=400, detail=ai_check.get("reason", "Invalid AI connection"))
    if request.platform:
        platform_check = validate_platform_mode(request.platform, request.execution_mode)
        if not platform_check.get("valid"):
            raise HTTPException(status_code=400, detail=platform_check.get("reason", "Invalid platform/mode"))
    if request.automation_enabled and not any(p in request.permissions for p in ("demo_execute", "paper_execute")):
        raise HTTPException(status_code=400, detail="Automation requires explicit execution permission")

    if request.risk_limits.get("max_position_pct", 0) <= 0 or request.risk_limits.get("max_daily_loss_pct", 0) <= 0:
        raise HTTPException(status_code=400, detail="Risk limits must be positive")

    profile = await upsert_user_trading_profile(user_id, token, request.model_dump())
    return {"saved": True, "profile": profile}
