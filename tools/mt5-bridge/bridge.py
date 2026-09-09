"""Read-only MetaTrader 5 market-data bridge for Bitey SBT.

Runs on the Windows machine hosting the MT5 terminal. It exposes market data
only and intentionally has no order-submission endpoint.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

from fastapi import FastAPI, HTTPException

try:
    import MetaTrader5 as mt5
except ImportError:  # pragma: no cover - dependency is installed on the MT5 host
    mt5 = None

app = FastAPI(title="Bitey SBT MT5 Bridge", version="1.0.0")

HOST = os.getenv("MT5_BRIDGE_HOST", "127.0.0.1")
PORT = int(os.getenv("MT5_BRIDGE_PORT", "8765"))
DEFAULT_TIMEFRAME = os.getenv("MT5_DEFAULT_TIMEFRAME", "M5").upper()
TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1 if mt5 else 1,
    "M5": mt5.TIMEFRAME_M5 if mt5 else 5,
    "M15": mt5.TIMEFRAME_M15 if mt5 else 15,
    "M30": mt5.TIMEFRAME_M30 if mt5 else 30,
    "H1": mt5.TIMEFRAME_H1 if mt5 else 60,
    "H4": mt5.TIMEFRAME_H4 if mt5 else 240,
    "D1": mt5.TIMEFRAME_D1 if mt5 else 1440,
}


def ensure_mt5() -> None:
    if mt5 is None:
        raise HTTPException(status_code=503, detail="MetaTrader5 package is unavailable")
    if not mt5.initialize():
        error = mt5.last_error()
        raise HTTPException(status_code=503, detail=f"MT5 terminal unavailable: {error}")


def ensure_symbol(symbol: str) -> str:
    symbol = symbol.upper().strip()
    ensure_mt5()
    info = mt5.symbol_info(symbol)
    if info is None:
        raise HTTPException(status_code=404, detail=f"MT5 symbol not found: {symbol}")
    if not info.visible and not mt5.symbol_select(symbol, True):
        raise HTTPException(status_code=503, detail=f"MT5 symbol unavailable: {symbol}")
    return symbol


def iso_timestamp(value: int | float) -> str:
    return datetime.fromtimestamp(float(value), tz=timezone.utc).isoformat()


@app.get("/health")
def health() -> dict[str, Any]:
    if mt5 is None:
        return {"ok": False, "provider": "metatrader5", "connected": False}
    connected = bool(mt5.initialize())
    account = None
    if connected:
        info = mt5.account_info()
        account = getattr(info, "login", None) if info else None
    return {
        "ok": connected,
        "provider": "metatrader5",
        "connected": connected,
        "account_login": account,
        "live_trading_enabled": False,
        "broker_orders": 0,
    }


@app.get("/quote/{symbol}")
def quote(symbol: str) -> dict[str, Any]:
    symbol = ensure_symbol(symbol)
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise HTTPException(status_code=503, detail=f"MT5 quote unavailable: {symbol}")
    timestamp = getattr(tick, "time_msc", 0) or getattr(tick, "time", 0)
    return {
        "source": "mt5",
        "symbol": symbol,
        "bid": float(tick.bid),
        "ask": float(tick.ask),
        "last": float(tick.last),
        "timestamp": int(timestamp),
        "timestamp_iso": iso_timestamp(timestamp / 1000 if timestamp > 10_000_000_000 else timestamp),
    }


@app.get("/candles/{symbol}")
def candles(symbol: str, timeframe: str = DEFAULT_TIMEFRAME, limit: int = 200) -> dict[str, Any]:
    symbol = ensure_symbol(symbol)
    timeframe = timeframe.upper()
    if timeframe not in TIMEFRAMES:
        raise HTTPException(status_code=400, detail=f"Unsupported timeframe: {timeframe}")
    limit = max(20, min(int(limit), 500))
    rates = mt5.copy_rates_from_pos(symbol, TIMEFRAMES[timeframe], 0, limit)
    if rates is None or len(rates) == 0:
        raise HTTPException(status_code=503, detail=f"MT5 candles unavailable: {symbol} {timeframe}")
    result = []
    for row in rates:
        ts = int(row["time"])
        result.append({
            "time": ts,
            "timestamp": ts,
            "timestamp_iso": iso_timestamp(ts),
            "open": float(row["open"]),
            "high": float(row["high"]),
            "low": float(row["low"]),
            "close": float(row["close"]),
            "volume": int(row["tick_volume"]),
        })
    return {
        "contract": "sbt-candles-v1",
        "source": "mt5",
        "symbol": symbol,
        "timeframe": timeframe,
        "limit": len(result),
        "candles": result,
    }
