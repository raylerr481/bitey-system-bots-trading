"""Supabase persistence for monthly compound-growth reports."""
from __future__ import annotations

import json
import os
from typing import Any, Mapping
from urllib import request

TABLE = "trading_monthly_growth"


def enabled() -> bool:
    return bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_SERVICE_ROLE_KEY"))


def _headers() -> dict[str, str]:
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=representation",
    }


def _url() -> str:
    return os.environ["SUPABASE_URL"].rstrip("/") + f"/rest/v1/{TABLE}"


def save(result: Mapping[str, Any]) -> dict[str, Any]:
    if not enabled():
        return {"persisted": False, "reason": "SUPABASE_NOT_CONFIGURED"}

    row = {
        "scope_key": result.get("scope_key"),
        "month_start": result.get("month_start"),
        "month_end": result.get("month_end"),
        "environment": result.get("environment", "DEMO"),
        "initial_capital_usd": result.get("initial_capital_usd"),
        "opening_capital_usd": result.get("opening_capital_usd"),
        "net_pnl_usd": result.get("net_pnl_usd"),
        "capital_end_usd": result.get("capital_end_usd"),
        "growth_pct": result.get("growth_pct"),
        "gross_profit_usd": result.get("gross_profit_usd"),
        "gross_loss_usd": result.get("gross_loss_usd"),
        "trades": result.get("trades", 0),
        "wins": result.get("wins", 0),
        "losses": result.get("losses", 0),
        "win_rate_pct": result.get("win_rate_pct"),
        "max_drawdown_usd": result.get("max_drawdown_usd"),
        "max_drawdown_pct": result.get("max_drawdown_pct"),
        "q_learning_reward": result.get("q_learning_reward"),
        "risk_gate": result.get("risk_gate") or {},
        "safety": result.get("safety") or {},
        "report": result.get("report") or {},
    }
    req = request.Request(
        _url(),
        data=json.dumps(row, default=str).encode(),
        headers=_headers(),
        method="POST",
    )
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return {"persisted": True, "row": parsed[0] if isinstance(parsed, list) and parsed else parsed}


def list_recent(limit: int = 24) -> list[dict[str, Any]]:
    if not enabled():
        return []
    safe_limit = max(1, min(int(limit), 120))
    url = _url() + f"?select=*&order=month_start.desc&limit={safe_limit}"
    req = request.Request(url, headers=_headers(), method="GET")
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return parsed if isinstance(parsed, list) else []
