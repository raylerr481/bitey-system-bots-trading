"""Persistent MT4 closed-trade ledger for DEMO/live observation.

The service stores closed trades only; execution remains entirely local to MT4.
"""
from __future__ import annotations

import hashlib
import json
import os
from typing import Any
from urllib import request

TABLE = "mt4_closed_trades"

def enabled() -> bool:
    return bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_SERVICE_ROLE_KEY"))

def _headers() -> dict[str, str]:
    key = os.environ["SUPABASE_SERVICE_ROLE_KEY"]
    return {"apikey": key, "Authorization": f"Bearer {key}", "Content-Type": "application/json",
            "Prefer": "resolution=merge-duplicates,return=representation"}

def _url() -> str:
    return os.environ["SUPABASE_URL"].rstrip("/") + f"/rest/v1/{TABLE}"

def trade_key(payload: dict[str, Any]) -> str:
    material = {k: payload.get(k) for k in ("ticket","magic","symbol","side","open_time","close_time","close_price","pnl")}
    return hashlib.sha256(json.dumps(material, sort_keys=True, default=str).encode()).hexdigest()

def save(payload: dict[str, Any]) -> dict[str, Any]:
    if not enabled():
        return {"persisted": False, "reason": "SUPABASE_NOT_CONFIGURED"}
    row = {
        "trade_key": trade_key(payload),
        "source": payload.get("source", "MT4_DESKTOP"),
        "account_mode": payload.get("account_mode", "UNKNOWN"),
        "ticket": payload.get("ticket"),
        "magic": payload.get("magic"),
        "bot_id": payload.get("bot_id"),
        "strategy": payload.get("strategy"),
        "version": payload.get("version"),
        "symbol": payload.get("symbol"),
        "timeframe": payload.get("timeframe"),
        "side": payload.get("side"),
        "lots": payload.get("lots"),
        "open_time": payload.get("open_time"),
        "close_time": payload.get("close_time"),
        "open_price": payload.get("open_price"),
        "close_price": payload.get("close_price"),
        "stop_loss": payload.get("stop_loss"),
        "take_profit": payload.get("take_profit"),
        "pnl": payload.get("pnl", 0),
        "commission": payload.get("commission", 0),
        "swap": payload.get("swap", 0),
        "cost": payload.get("cost", 0),
        "exit_reason": payload.get("exit_reason"),
        "r_multiple": payload.get("r_multiple"),
        "metadata": payload.get("metadata") or {},
        "raw_trade": payload,
    }
    req = request.Request(_url(), data=json.dumps(row, default=str).encode(), headers=_headers(), method="POST")
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return {"persisted": True, "row": parsed[0] if isinstance(parsed, list) and parsed else parsed}

def list_recent(limit: int = 500) -> list[dict[str, Any]]:
    if not enabled():
        return []
    url = _url() + "?select=*&order=close_time.desc&limit=" + str(max(1, min(limit, 5000)))
    req = request.Request(url, headers=_headers(), method="GET")
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return parsed if isinstance(parsed, list) else []
