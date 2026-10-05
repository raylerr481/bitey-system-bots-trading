"""Persistent MT4 backtest evidence store.

Uses Supabase REST when SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are configured.
The service role key is server-side only and must never be exposed to the browser.
If unavailable, callers can safely fall back to the in-memory test ledger.
"""
from __future__ import annotations

import hashlib
import json
import os
from typing import Any
from urllib import request

TABLE = "backtest_evidence"


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


def evidence_key(payload: dict[str, Any]) -> str:
    bot = payload.get("bot") or {}
    material = {
        "strategy_id": bot.get("strategy") or payload.get("strategy_id") or payload.get("strategy"),
        "version": bot.get("version") or payload.get("version"),
        "symbol": payload.get("symbol"),
        "timeframe": payload.get("timeframe"),
        "timestamp": payload.get("timestamp"),
        "metrics": payload.get("metrics") or payload.get("results") or {},
        "parameters": bot.get("parameters") or payload.get("parameters") or {},
    }
    raw = json.dumps(material, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(raw.encode()).hexdigest()


def save(payload: dict[str, Any]) -> dict[str, Any]:
    if not enabled():
        return {"persisted": False, "reason": "SUPABASE_NOT_CONFIGURED"}

    bot = payload.get("bot") or {}
    row = {
        "evidence_key": evidence_key(payload),
        "source": payload.get("source", "MT4"),
        "evidence_class": payload.get("evidence_class", "BACKTEST"),
        "strategy_id": bot.get("strategy") or payload.get("strategy_id") or payload.get("strategy"),
        "strategy_version": bot.get("version") or payload.get("version"),
        "bot_id": bot.get("id") or payload.get("bot_id"),
        "symbol": payload.get("symbol"),
        "timeframe": payload.get("timeframe"),
        "parameters": bot.get("parameters") or payload.get("parameters") or {},
        "metrics": payload.get("metrics") or payload.get("results") or {},
        "costs": payload.get("costs") or {},
        "validation": payload.get("validation") or {},
        "market_context": payload.get("market") or {},
        "raw_report": payload,
    }
    req = request.Request(_url(), data=json.dumps(row, default=str).encode(), headers=_headers(), method="POST")
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return {"persisted": True, "row": parsed[0] if isinstance(parsed, list) and parsed else parsed}


def list_recent(limit: int = 100) -> list[dict[str, Any]]:
    if not enabled():
        return []
    url = _url() + "?select=*&order=created_at.desc&limit=" + str(max(1, min(limit, 500)))
    req = request.Request(url, headers=_headers(), method="GET")
    with request.urlopen(req, timeout=8) as response:
        body = response.read().decode() or "[]"
    parsed = json.loads(body)
    return parsed if isinstance(parsed, list) else []
