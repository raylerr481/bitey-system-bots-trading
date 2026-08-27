import MetaTrader5 as mt5
from fastapi import FastAPI, HTTPException
from typing import Any

app = FastAPI(
    title="Bitey MT5 Demo Bridge",
    version="0.1.0",
    description="Read-only HTTP bridge for MetaTrader 5 Demo."
)


def initialize_mt5():
    if not mt5.initialize():
        raise RuntimeError(f"MT5 initialize failed: {mt5.last_error()}")


@app.get("/health")
def health():
    initialize_mt5()

    terminal = mt5.terminal_info()

    if terminal is None:
        mt5.shutdown()
        raise HTTPException(status_code=503, detail="MT5 terminal unavailable")

    result = {
        "status": "ok",
        "provider": "metatrader5",
        "mode": "demo",
        "read_only": True,
        "connected": bool(terminal.connected),
        "trade_allowed": bool(terminal.trade_allowed),
        "path": terminal.path,
    }

    mt5.shutdown()
    return result


@app.get("/status")
def status():
    initialize_mt5()

    terminal = mt5.terminal_info()

    if terminal is None:
        mt5.shutdown()
        raise HTTPException(status_code=503, detail="MT5 terminal unavailable")

    result = {
        "provider": "metatrader5",
        "mode": "demo",
        "connected": bool(terminal.connected),
        "trade_allowed": bool(terminal.trade_allowed),
        "read_only": True,
        "live_trading_enabled": False,
    }

    mt5.shutdown()
    return result


@app.get("/account")
def account() -> Any:
    initialize_mt5()

    info = mt5.account_info()

    if info is None:
        error = mt5.last_error()
        mt5.shutdown()
        raise HTTPException(
            status_code=503,
            detail=f"MT5 account unavailable: {error}"
        )

    result = {
        "login": info.login,
        "server": info.server,
        "company": info.company,
        "name": info.name,
        "currency": info.currency,
        "balance": info.balance,
        "equity": info.equity,
        "profit": info.profit,
        "margin": info.margin,
        "margin_free": info.margin_free,
        "leverage": info.leverage,
        "trade_mode": info.trade_mode,
        "trade_allowed": bool(info.trade_allowed),
        "trade_expert": bool(info.trade_expert),
        "mode": "demo",
        "read_only": True,
    }

    mt5.shutdown()
    return result


@app.get("/quote/{symbol}")
def quote(symbol: str) -> Any:
    initialize_mt5()

    symbol = symbol.strip().upper()

    if not symbol:
        mt5.shutdown()
        raise HTTPException(status_code=400, detail="Symbol is required")

    if not mt5.symbol_select(symbol, True):
        error = mt5.last_error()
        mt5.shutdown()
        raise HTTPException(
            status_code=404,
            detail=f"Symbol unavailable: {symbol} ({error})"
        )

    tick = mt5.symbol_info_tick(symbol)

    if tick is None:
        error = mt5.last_error()
        mt5.shutdown()
        raise HTTPException(
            status_code=503,
            detail=f"Quote unavailable: {symbol} ({error})"
        )

    result = {
        "symbol": symbol,
        "bid": float(tick.bid),
        "ask": float(tick.ask),
        "last": float(tick.last),
        "volume": int(tick.volume),
        "time": int(tick.time),
        "mode": "demo",
        "read_only": True,
    }

    mt5.shutdown()
    return result


@app.get("/candles/{symbol}")
def candles(
    symbol: str,
    timeframe: str = "M5",
    count: int = 30,
) -> Any:

    initialize_mt5()

    symbol = symbol.strip().upper()
    timeframe = timeframe.strip().upper()

    if count < 1 or count > 5000:
        mt5.shutdown()
        raise HTTPException(
            status_code=400,
            detail="count must be between 1 and 5000"
        )

    timeframe_map = {
        "M1": mt5.TIMEFRAME_M1,
        "M5": mt5.TIMEFRAME_M5,
        "M15": mt5.TIMEFRAME_M15,
        "M30": mt5.TIMEFRAME_M30,
        "H1": mt5.TIMEFRAME_H1,
        "H4": mt5.TIMEFRAME_H4,
        "D1": mt5.TIMEFRAME_D1,
    }

    if timeframe not in timeframe_map:
        mt5.shutdown()
        raise HTTPException(
            status_code=400,
            detail=f"Unsupported timeframe: {timeframe}"
        )

    if not mt5.symbol_select(symbol, True):
        error = mt5.last_error()
        mt5.shutdown()
        raise HTTPException(
            status_code=404,
            detail=f"Symbol unavailable: {symbol} ({error})"
        )

    rates = mt5.copy_rates_from_pos(
        symbol,
        timeframe_map[timeframe],
        0,
        count,
    )

    if rates is None:
        error = mt5.last_error()
        mt5.shutdown()
        raise HTTPException(
            status_code=503,
            detail=f"MT5 candles unavailable: {error}"
        )

    rows = []

    for row in rates:
        rows.append({
            "time": int(row["time"]),
            "open": float(row["open"]),
            "high": float(row["high"]),
            "low": float(row["low"]),
            "close": float(row["close"]),
            "tick_volume": int(row["tick_volume"]),
            "spread": int(row["spread"]),
            "real_volume": int(row["real_volume"]),
        })

    mt5.shutdown()

    return {
        "symbol": symbol,
        "timeframe": timeframe,
        "count": len(rows),
        "candles": rows,
        "mode": "demo",
        "read_only": True,
    }


@app.get("/orders")
def orders():
    return {
        "enabled": False,
        "read_only": True,
        "message": "Order execution is disabled in the MT5 demo bridge."
    }


@app.post("/order")
def order_disabled():
    raise HTTPException(
        status_code=403,
        detail="Order execution is disabled. This bridge is read-only."
    )
