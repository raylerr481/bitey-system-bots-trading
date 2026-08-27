"""Minimal read-only MT5 bridge for a Windows MT5 terminal.

Run this component on the machine where MetaTrader5 is installed. It exposes
market data only; there is deliberately no order endpoint.
"""

from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query
import MetaTrader5 as mt5

app = FastAPI(title="Bitey MT5 Read-Only Bridge", version="1.0.0")

TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
}


def ensure_mt5():
    if mt5.initialize():
        return
    raise HTTPException(status_code=503, detail=f"MT5 initialize failed: {mt5.last_error()}")


@app.get("/health")
def health():
    return {"status": "ok", "provider": "metatrader5", "mode": "demo", "read_only": True}


@app.get("/account")
def account():
    ensure_mt5()
    info = mt5.account_info()
    if info is None:
        raise HTTPException(status_code=503, detail=f"MT5 account unavailable: {mt5.last_error()}")
    return {
        "login": info.login,
        "server": info.server,
        "currency": info.currency,
        "balance": info.balance,
        "equity": info.equity,
        "margin_free": info.margin_free,
    }


@app.get("/quote/{symbol}")
def quote(symbol: str):
    ensure_mt5()
    symbol = symbol.upper()
    if not mt5.symbol_select(symbol, True):
        raise HTTPException(status_code=404, detail=f"Symbol unavailable: {symbol}")
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise HTTPException(status_code=503, detail=f"Quote unavailable: {mt5.last_error()}")
    return {
        "symbol": symbol,
        "bid": tick.bid,
        "ask": tick.ask,
        "last": tick.last,
        "time": datetime.fromtimestamp(tick.time, tz=timezone.utc).isoformat(),
    }


@app.get("/candles/{symbol}")
def candles(
    symbol: str,
    timeframe: str = Query("M5"),
    count: int = Query(30, ge=1, le=5000),
):
    ensure_mt5()
    symbol = symbol.upper()
    tf = TIMEFRAMES.get(timeframe.upper())
    if tf is None:
        raise HTTPException(status_code=400, detail=f"Unsupported timeframe: {timeframe}")
    if not mt5.symbol_select(symbol, True):
        raise HTTPException(status_code=404, detail=f"Symbol unavailable: {symbol}")

    rates = mt5.copy_rates_from_pos(symbol, tf, 0, count)
    if rates is None:
        raise HTTPException(status_code=503, detail=f"Candles unavailable: {mt5.last_error()}")

    return {
        "symbol": symbol,
        "timeframe": timeframe.upper(),
        "count": len(rates),
        "candles": [
            {
                "time": datetime.fromtimestamp(int(row["time"]), tz=timezone.utc).isoformat(),
                "open": float(row["open"]),
                "high": float(row["high"]),
                "low": float(row["low"]),
                "close": float(row["close"]),
                "tick_volume": int(row["tick_volume"]),
                "spread": int(row["spread"]),
            }
            for row in rates
        ],
    }
