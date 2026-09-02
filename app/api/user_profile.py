from __future__ import annotations

import os
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

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
    return authorization.split(" ", 1)[1].strip()


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
    if "live" in request.execution_mode.lower():
        raise HTTPException(status_code=400, detail="Live trading is disabled")
    try:
        return await upsert_user_trading_profile(user_id, token, request.model_dump())
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
