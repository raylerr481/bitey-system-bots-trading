from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from app.api.turtle import update_from_mt4

router = APIRouter(prefix="/api/v1/mt4", tags=["mt4-bitey"])

MT4_INGEST_TOKEN = os.getenv("MT4_INGEST_TOKEN", "")
BITEY_TRADING_URL = os.getenv(
    "BITEY_TRADING_URL",
    "https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze",
).rstrip("/")
_latest: dict[str, Any] | None = None
_history: list[dict[str, Any]] = []
_backtests: list[dict[str, Any]] = []


class MT4EntryDiagnostic(BaseModel):
    ticket: int | None = None
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    side: str = Field(pattern=r"^(BUY|SELL)$")
    timestamp: str | None = None
    entry_price: float | None = None
    exit_price: float | None = None
    pnl: float = 0.0
    r_multiple: float | None = None
    score: float | None = None
    score_gap: float | None = None
    rsi: float | None = None
    adx: float | None = None
    atr: float | None = None
    ema_fast: float | None = None
    ema_slow: float | None = None
    ema_200: float | None = None
    regime: str = "UNKNOWN"
    htf_direction: str = "NEUTRAL"
    exit_reason: str = "UNKNOWN"
    duration_bars: int | None = None
    mae_pct: float | None = None
    mfe_pct: float | None = None


class MT4EntryDiagnosticsReport(BaseModel):
    source: str = "AI_Trading_Bot_v1.34_Bitey"
    symbol: str = Field(min_length=1, max_length=32)
    timeframe: str = Field(min_length=2, max_length=12)
    report_type: str = "entry_diagnostics"
    trades: list[MT4EntryDiagnostic] = Field(default_factory=list, max_length=5000)


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
    turtle: dict[str, Any] = Field(default_factory=dict)
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
    turtle_state = None
    if report.report_type == "live_snapshot":
        turtle_state = update_from_mt4(payload)
        payload["turtle_controller"] = turtle_state
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
        "turtle_controller": turtle_state,
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


def _bucket(value: float | None, edges: list[float]) -> str:
    if value is None:
        return "UNKNOWN"
    for edge in edges:
        if value < edge:
            return f"<{edge:g}"
    return f">={edges[-1]:g}"


def _diagnostic_summary(trades: list[MT4EntryDiagnostic]) -> dict[str, Any]:
    def group(rows: list[MT4EntryDiagnostic]) -> dict[str, Any]:
        wins = sum(1 for t in rows if t.pnl > 0)
        losses = sum(1 for t in rows if t.pnl < 0)
        pnl = sum(t.pnl for t in rows)
        return {
            "trades": len(rows),
            "wins": wins,
            "losses": losses,
            "win_rate": wins / len(rows) if rows else None,
            "net_pnl": pnl,
            "expectancy": pnl / len(rows) if rows else None,
        }

    losses = [t for t in trades if t.pnl < 0]
    score_buckets: dict[str, list[MT4EntryDiagnostic]] = {}
    for t in trades:
        score_buckets.setdefault(_bucket(t.score, [5, 6, 7, 8]), []).append(t)

    side = {s: group([t for t in trades if t.side == s]) for s in ("BUY", "SELL")}
    regime = {}
    for t in trades:
        regime.setdefault(t.regime, []).append(t)
    regime = {k: group(v) for k, v in regime.items()}

    exit_reason = {}
    for t in trades:
        exit_reason.setdefault(t.exit_reason, []).append(t)
    exit_reason = {k: group(v) for k, v in exit_reason.items()}

    loss_patterns = {
        "losses_by_score_bucket": {k: group(v) for k, v in score_buckets.items()},
        "losses_by_side": {k: group([t for t in losses if t.side == k]) for k in ("BUY", "SELL")},
        "losses_by_regime": {k: group([t for t in losses if t.regime == k]) for k in sorted({t.regime for t in losses})},
        "losses_by_exit_reason": {k: group([t for t in losses if t.exit_reason == k]) for k in sorted({t.exit_reason for t in losses})},
        "low_adx_losses": group([t for t in losses if t.adx is not None and t.adx < 20]),
        "high_rsi_buy_losses": group([t for t in losses if t.side == "BUY" and t.rsi is not None and t.rsi > 65]),
        "low_rsi_sell_losses": group([t for t in losses if t.side == "SELL" and t.rsi is not None and t.rsi < 35]),
    }

    return {
        "contract": "bitey-mt4-entry-diagnostics-v1",
        "trades": group(trades),
        "loss_count": len(losses),
        "loss_patterns": loss_patterns,
        "instruction": "DIAGNOSTIC_ONLY: do not change entry thresholds, SL, TP, ATR or risk from this report alone.",
    }


@router.post("/bitey-entry-diagnostics")
def ingest_entry_diagnostics(report: MT4EntryDiagnosticsReport, x_mt4_token: str | None = Header(default=None)):
    """Analyze individual MT4 entries before any strategy optimization."""
    _check_token(x_mt4_token)
    payload = report.model_dump()
    payload["timestamp"] = datetime.now(timezone.utc).isoformat()
    payload["source_module"] = "Bitey System Bots Trading"
    payload["analysis"] = _diagnostic_summary(report.trades)
    return payload


@router.get("/bitey-entry-diagnostics")
def entry_diagnostics_help():
    return {
        "contract": "bitey-mt4-entry-diagnostics-v1",
        "purpose": "Find which combinations produced losing MT4 entries before optimization.",
        "required_fields": ["side", "pnl", "score", "rsi", "adx", "atr", "regime", "exit_reason"],
        "optimization_locked": True,
    }


@router.get("/bitey-backtests")
def backtest_history(limit: int = 20):
    limit = max(1, min(limit, 100))
    return {"items": list(reversed(_backtests[-limit:])), "count": len(_backtests), "evidence_class": "BACKTEST"}
