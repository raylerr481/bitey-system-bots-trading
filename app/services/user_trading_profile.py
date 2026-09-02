from __future__ import annotations

import os
from typing import Any

import httpx


DEFAULT_PROFILE = {
    "ai_provider": "bitey",
    "ai_connection_mode": "direct_user",
    "platform": None,
    "execution_mode": "demo",
    "permissions": [],
    "risk_limits": {"max_position_pct": 0.02, "max_daily_loss_pct": 0.01},
    "bot_id": None,
    "strategy_id": None,
    "automation_enabled": False,
    "status": "draft",
    "metadata": {},
}


def _config() -> tuple[str, str]:
    url = os.getenv("SUPABASE_URL", "").rstrip("/")
    key = os.getenv("SUPABASE_ANON_KEY", "")
    if not url or not key:
        raise RuntimeError("Supabase Auth/REST is not configured")
    return url, key


def _headers(access_token: str) -> dict[str, str]:
    url, key = _config()
    return {"apikey": key, "Authorization": f"Bearer {access_token}", "Content-Type": "application/json", "Prefer": "return=representation"}


async def get_user_trading_profile(user_id: str, access_token: str) -> dict[str, Any]:
    url, _ = _config()
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.get(f"{url}/rest/v1/sbt_user_trading_profiles", headers=_headers(access_token), params={"user_id": f"eq.{user_id}", "limit": "1"})
    if response.status_code >= 400:
        raise RuntimeError(f"Trading profile read failed: {response.status_code}")
    rows = response.json()
    return rows[0] if rows else {"user_id": user_id, **DEFAULT_PROFILE}


async def upsert_user_trading_profile(user_id: str, access_token: str, payload: dict[str, Any]) -> dict[str, Any]:
    url, _ = _config()
    data = {"user_id": user_id, **DEFAULT_PROFILE, **payload}
    data.pop("id", None)
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f"{url}/rest/v1/sbt_user_trading_profiles", headers={**_headers(access_token), "Prefer": "resolution=merge-duplicates,return=representation"}, json=data)
    if response.status_code >= 400:
        raise RuntimeError(f"Trading profile write failed: {response.status_code}")
    rows = response.json()
    return rows[0] if rows else await get_user_trading_profile(user_id, access_token)
