"""Deterministic multi-strategy signal generation and append-only signal audit.

This module proposes signals only; it never sends broker orders. Configure
SBT_SIGNAL_DB_PATH to a persistent disk path in hosted deployments.
"""
from __future__ import annotations

import json
import math
import os
import sqlite3
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path
from statistics import mean
from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field, model_validator

router = APIRouter(prefix="/api/v1/signals", tags=["continuous-signals"])

OPERATING_CAPITAL_USD = 500.0
RISK_TARGET_USD = 1.25
RISK_HARD_MAX_USD = 2.00
DAILY_LOSS_LIMIT_USD = 10.00
MAX_TRADES_PER_DAY = 3
MAX_OPEN_POSITIONS = 1
MIN_RR = 1.50


class Candle(BaseModel):
    time: str = Field(min_length=1, max_length=64)
    open: float = Field(gt=0)
    high: float = Field(gt=0)
    low: float = Field(gt=0)
    close: float = Field(gt=0)
    volume: float = Field(default=0, ge=0)

    @model_validator(mode="after")
    def validate_ohlc(self):
        if self.high < max(self.open, self.close, self.low):
            raise ValueError("invalid_candle_high")
        if self.low > min(self.open, self.close, self.high):
            raise ValueError("invalid_candle_low")
        return self


class SignalRequest(BaseModel):
    symbol: str = Field(default="EURUSD", min_length=3, max_length=32)
    timeframe: str = Field(default="H1", min_length=1, max_length=8)
    candles: list[Candle] = Field(min_length=60, max_length=2000)
    spread_points: float = Field(default=0, ge=0)
    point_size: float = Field(default=0.00001, gt=0)
    daily_realized_pnl_usd: float = Field(default=0, le=500, ge=-500)
    trades_today: int = Field(default=0, ge=0, le=1000)
    open_positions: int = Field(default=0, ge=0, le=1000)
    data_fresh: bool = True


def _ema(values: list[float], period: int) -> float:
    alpha = 2.0 / (period + 1)
    result = values[0]
    for value in values[1:]:
        result = alpha * value + (1 - alpha) * result
    return result


def _rsi(values: list[float], period: int = 14) -> float:
    changes = [values[i] - values[i - 1] for i in range(len(values) - period, len(values))]
    gains = sum(max(x, 0) for x in changes) / period
    losses = sum(max(-x, 0) for x in changes) / period
    if losses == 0:
        return 100.0 if gains > 0 else 50.0
    return 100 - (100 / (1 + gains / losses))


def _atr(candles: list[Candle], period: int = 14) -> float:
    subset = candles[-(period + 1):]
    trs = []
    for i in range(1, len(subset)):
        c, prev = subset[i], subset[i - 1]
        trs.append(max(c.high - c.low, abs(c.high - prev.close), abs(c.low - prev.close)))
    return mean(trs)


def _evaluate(req: SignalRequest) -> dict:
    candles = req.candles
    closes = [c.close for c in candles]
    last = candles[-1]
    atr = _atr(candles)
    if not math.isfinite(atr) or atr <= 0:
        return {"action": "WAIT", "reason": "invalid_atr", "votes": {}}

    votes: dict[str, str] = {}
    # Trend-following: EMA 20/50 direction with recent price confirmation.
    e20, e50 = _ema(closes[-100:], 20), _ema(closes[-150:], 50)
    votes["ema_trend"] = "BUY" if e20 > e50 and last.close > e20 else "SELL" if e20 < e50 and last.close < e20 else "WAIT"
    # Donchian breakout uses prior bars only, avoiding current-bar look-ahead.
    prior = candles[-21:-1]
    votes["donchian_20"] = "BUY" if last.close > max(c.high for c in prior) else "SELL" if last.close < min(c.low for c in prior) else "WAIT"
    # Mean reversion is only active when trend strength proxy is modest.
    rsi = _rsi(closes)
    trend_strength = abs(e20 - e50) / atr
    votes["rsi_mean_reversion"] = "BUY" if rsi <= 28 and trend_strength < 1.2 else "SELL" if rsi >= 72 and trend_strength < 1.2 else "WAIT"
    # Short-horizon momentum confirmation.
    momentum = closes[-1] - closes[-6]
    votes["momentum_5"] = "BUY" if momentum > atr * 0.25 else "SELL" if momentum < -atr * 0.25 else "WAIT"

    buy_votes = sum(v == "BUY" for v in votes.values())
    sell_votes = sum(v == "SELL" for v in votes.values())
    action = "BUY" if buy_votes >= 3 and sell_votes == 0 else "SELL" if sell_votes >= 3 and buy_votes == 0 else "WAIT"
    # Stops are ATR-based and minimum RR is enforced; no model can override this.
    entry = last.close
    stop_distance = max(1.3 * atr, req.spread_points * req.point_size * 2.0)
    target_distance = stop_distance * MIN_RR
    if action == "BUY":
        stop, target = entry - stop_distance, entry + target_distance
    elif action == "SELL":
        stop, target = entry + stop_distance, entry - target_distance
    else:
        stop = target = None

    reasons = []
    if not req.data_fresh:
        reasons.append("stale_market_data")
    if req.spread_points * req.point_size > atr * 0.15:
        reasons.append("spread_exceeds_15pct_of_ATR")
    if req.daily_realized_pnl_usd <= -DAILY_LOSS_LIMIT_USD:
        reasons.append("daily_loss_limit_reached")
    if req.trades_today >= MAX_TRADES_PER_DAY:
        reasons.append("daily_trade_limit_reached")
    if req.open_positions >= MAX_OPEN_POSITIONS:
        reasons.append("max_open_positions_reached")
    if action == "WAIT":
        reasons.append("insufficient_strategy_consensus")
    if reasons:
        action, stop, target = "WAIT", None, None

    # Risk is capped at $1.25 target, never above $2.00. Actual lot sizing
    # remains broker/symbol-specific and must be validated by MT4 before entry.
    confidence = max(buy_votes, sell_votes) / len(votes)
    return {
        "action": action,
        "symbol": req.symbol.upper(),
        "timeframe": req.timeframe.upper(),
        "candle_time": last.time,
        "entry_reference": entry,
        "stop_loss": stop,
        "take_profit": target,
        "atr": atr,
        "rsi14": rsi,
        "strategy_votes": votes,
        "buy_votes": buy_votes,
        "sell_votes": sell_votes,
        "consensus": round(confidence, 3),
        "minimum_risk_reward": MIN_RR,
        "operating_capital_usd": OPERATING_CAPITAL_USD,
        "target_risk_usd": RISK_TARGET_USD,
        "hard_risk_cap_usd": RISK_HARD_MAX_USD,
        "daily_loss_limit_usd": DAILY_LOSS_LIMIT_USD,
        "reason_codes": reasons,
        "execution_mode": "signal_only",
        "broker_order_sent": False,
    }


def _db_path() -> str:
    return os.getenv("SBT_SIGNAL_DB_PATH", "/tmp/bitey_sbt_signal_audit.sqlite3")


def _persist(record: dict) -> None:
    path = Path(_db_path())
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(str(path), timeout=5) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS signal_audit (
                signal_id TEXT PRIMARY KEY,
                created_at TEXT NOT NULL,
                symbol TEXT NOT NULL,
                timeframe TEXT NOT NULL,
                candle_time TEXT NOT NULL,
                action TEXT NOT NULL,
                payload_json TEXT NOT NULL,
                UNIQUE(symbol, timeframe, candle_time)
            )
        """)
        conn.execute(
            """INSERT OR IGNORE INTO signal_audit
               (signal_id, created_at, symbol, timeframe, candle_time, action, payload_json)
               VALUES (?, ?, ?, ?, ?, ?, ?)""",
            (record["signal_id"], record["created_at"], record["symbol"], record["timeframe"],
             record["candle_time"], record["action"], json.dumps(record, separators=(",", ":"))),
        )
        conn.commit()


@router.post("/analyze")
def analyze_signals(request: SignalRequest):
    if not request.data_fresh:
        # Still records WAIT below; stale data must never yield BUY/SELL.
        pass
    result = _evaluate(request)
    record = {
        **result,
        "signal_id": str(uuid.uuid4()),
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    try:
        _persist(record)
    except Exception as exc:
        raise HTTPException(status_code=503, detail=f"signal_audit_persistence_failed:{type(exc).__name__}") from exc
    return {**record, "audit_persisted": True, "idempotency_key": f"{record['symbol']}:{record['timeframe']}:{record['candle_time']}"}


@router.get("/strategies")
def strategy_registry():
    return {
        "status": "research_candidates",
        "strategies": [
            {"id": "ema_trend", "family": "trend_following", "role": "trend direction"},
            {"id": "donchian_20", "family": "breakout", "role": "20-bar breakout"},
            {"id": "rsi_mean_reversion", "family": "mean_reversion", "role": "range-only reversal"},
            {"id": "momentum_5", "family": "short_horizon_momentum", "role": "directional confirmation"},
        ],
        "promotion_rule": "No strategy is promoted based on reputation alone; require net-of-costs out-of-sample and demo evidence.",
        "real_money_execution": False,
    }


@router.get("/recent")
def recent_signals(limit: int = 50):
    limit = max(1, min(200, limit))
    try:
        with sqlite3.connect(_db_path(), timeout=5) as conn:
            conn.row_factory = sqlite3.Row
            rows = conn.execute(
                "SELECT payload_json FROM signal_audit ORDER BY created_at DESC LIMIT ?", (limit,)
            ).fetchall()
        return {"signals": [json.loads(row["payload_json"]) for row in rows], "count": len(rows)}
    except sqlite3.OperationalError:
        return {"signals": [], "count": 0, "audit_initialized": False}
