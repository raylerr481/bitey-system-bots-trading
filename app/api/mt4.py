from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/mt4", tags=["mt4-bitey"])

MT4_INGEST_TOKEN = os.getenv("MT4_INGEST_TOKEN", "")
BITEY_TRADING_URL = os.getenv(
    "BITEY_TRADING_URL",
    "https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze",
).rstrip("/")
_latest: dict[str, Any] | None = None
_history: list[dict[str, Any]] = []
_backtests: list[dict[str, Any]] = []


class MT4TradingReport(BaseModel):
    source: str = "AI_Trading_Bot_v1.34_Bitey"
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    timestamp: str | None = None
    mode: str = "AI_ASSIST"
    execution_enabled: bool = False
    regime: str = "UNKNOWN"
    hurst: float | None = None
    best_strategy: str | None = None
    best_score: float | None = None
    metrics: dict[str, Any] = Field(default_factory=dict)
    strategies: list[dict[str, Any]] = Field(default_factory=list, max_length=16)
    market: dict[str, Any] = Field(default_factory=dict)
    ai: dict[str, Any] = Field(default_factory=dict)
    risk_gate: dict[str, Any] = Field(default_factory=dict)
    account: dict[str, Any] = Field(default_factory=dict)
    report_type: str = "live_snapshot"


def _check_token(token: str | None) -> None:
    if MT4_INGEST_TOKEN and token != MT4_INGEST_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid MT4 ingestion token")


@router.post("/bitey-report")
async def ingest_report(
    report: MT4TradingReport,
    x_mt4_token: str | None = Header(default=None),
):
    _check_token(x_mt4_token)
    global _latest
    payload = report.model_dump()
    payload["timestamp"] = payload["timestamp"] or datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    _latest = payload
    _history.append(payload)
    if len(_history) > 100:
        del _history[:-100]

    ai = None
    if BITEY_TRADING_URL and report.report_type == "live_snapshot":
        try:
            snapshot = {
                **report.market,
                "symbol": report.symbol,
                "timeframe": report.timeframe,
                "regime": report.regime,
                "entry_score": report.metrics.get("entry_score", 0),
                "score_gap": report.metrics.get("score_gap", 0),
                "htf_direction": report.metrics.get("htf_direction", "NEUTRAL"),
            }
            async with httpx.AsyncClient(timeout=8) as client:
                response = await client.post(BITEY_TRADING_URL, json=snapshot)
                if response.status_code < 400:
                    ai = response.json()
                    payload["ai"] = {**report.ai, **(ai if isinstance(ai, dict) else {})}
                    _latest = payload
        except (httpx.HTTPError, ValueError):
            ai = {"status": "unavailable", "fallback": "local_risk_gate"}

    return {
        "accepted": True,
        "stored": True,
        "source": report.source,
        "timestamp": payload["timestamp"],
        "bitey_ai": ai,
        "execution": "local_mt4_risk_gate",
    }


@router.get("/bitey-latest")
def latest_report():
    return {
        "available": _latest is not None,
        "report": _latest,
        "history_count": len(_history),
    }


@router.get("/bitey-history")
def report_history(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"items": list(reversed(_history[-limit:])), "count": len(_history)}


@router.post("/bitey-backtest")
async def ingest_backtest(
    report: MT4TradingReport,
    x_mt4_token: str | None = Header(default=None),
):
    """Store a Strategy Tester/research result without treating it as live trading evidence."""
    _check_token(x_mt4_token)
    if report.report_type not in {"backtest", "strategy_tester", "research"}:
        report.report_type = "backtest"

    payload = report.model_dump()
    payload["timestamp"] = payload["timestamp"] or datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    payload["evidence_class"] = "BACKTEST"
    payload["execution"] = "none"
    _backtests.append(payload)
    if len(_backtests) > 100:
        del _backtests[:-100]

    return {
        "accepted": True,
        "stored": True,
        "evidence_class": "BACKTEST",
        "source": report.source,
        "timestamp": payload["timestamp"],
        "live_execution": False,
    }


@router.get("/bitey-backtests")
def backtest_history(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"items": list(reversed(_backtests[-limit:])), "count": len(_backtests), "evidence_class": "BACKTEST"}
