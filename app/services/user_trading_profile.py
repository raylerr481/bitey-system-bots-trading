from __future__ import annotations

from typing import Any

from app.supabase_client import supabase


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


def get_user_trading_profile(user_id: str) -> dict[str, Any]:
    response = (
        supabase.table("sbt_user_trading_profiles")
        .select("*")
        .eq("user_id", user_id)
        .limit(1)
        .execute()
    )
    if response.data:
        return response.data[0]
    return {"user_id": user_id, **DEFAULT_PROFILE}


def upsert_user_trading_profile(user_id: str, payload: dict[str, Any]) -> dict[str, Any]:
    data = {"user_id": user_id, **DEFAULT_PROFILE, **payload}
    data.pop("id", None)
    response = (
        supabase.table("sbt_user_trading_profiles")
        .upsert(data, on_conflict="user_id")
        .execute()
    )
    return response.data[0] if response.data else get_user_trading_profile(user_id)
