from datetime import datetime, timezone

from fastapi import FastAPI, HTTPException, Query
import MetaTrader5 as mt5

app = FastAPI(title="Bitey MT5 Demo Bridge", version="1.0.0")

TIMEFRAMES = {
    "M1": mt5.TIMEFRAME_M1,
    "M3": mt5.TIMEFRAME_M3,
    "M5": mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "M30": mt5.TIMEFRAME_M30,
    "H1": mt5.TIMEFRAME_H1,
    "H4": mt5.TIMEFRAME_H4,
    "D1": mt5.TIMEFRAME_D1,
    "W1": mt5.TIMEFRAME_W1,
    "MN1": mt5.TIMEFRAME_MN1,
}


def ensure_terminal() -> None:
    if mt5.terminal_info() is None:
        if not mt5.initialize():
            raise HTTPException(status_code=503, detail="MT5 terminal is not connected")


def ensure_symbol(symbol: str) -> str:
    ensure_terminal()
    symbol = symbol.strip().upper()
    info = mt5.symbol_info(symbol)
    if info is None:
        raise HTTPException(status_code=404, detail=f"MT5 symbol not found: {symbol}")
    if not info.visible and not mt5.symbol_select(symbol, True):
        raise HTTPException(status_code=503, detail=f"MT5 symbol unavailable: {symbol}")
    return symbol


@app.get("/health")
def health():
    terminal = mt5.terminal_info()
    return {
        "status": "ok" if terminal is not None else "degraded",
        "mode": "demo",
        "live_trading_enabled": False,
        "order_execution_enabled": False,
        "terminal_connected": terminal is not None,
    }


@app.get("/quote/{symbol}")
def quote(symbol: str):
    symbol = ensure_symbol(symbol)
    tick = mt5.symbol_info_tick(symbol)
    if tick is None:
        raise HTTPException(status_code=503, detail=f"No tick available: {symbol}")
    return {
        "symbol": symbol,
        "timestamp": datetime.fromtimestamp(tick.time, timezone.utc).isoformat(),
        "bid": float(tick.bid),
        "ask": float(tick.ask),
        "last": float(tick.last),
        "volume": float(tick.volume),
    }


@app.get("/candles/{symbol}")
def candles(
    symbol: str,
    timeframe: str = Query("M1"),
    limit: int = Query(100, ge=1, le=1000),
):
    symbol = ensure_symbol(symbol)
    timeframe = timeframe.strip().upper()
    tf = TIMEFRAMES.get(timeframe)
    if tf is None:
        raise HTTPException(status_code=400, detail=f"Unsupported timeframe: {timeframe}")

    rates = mt5.copy_rates_from_pos(symbol, tf, 0, limit)
    if rates is None or len(rates) == 0:
        raise HTTPException(status_code=503, detail=f"No candle data available: {symbol} {timeframe}")

    result = []
    for row in rates:
        result.append({
            "timestamp": datetime.fromtimestamp(int(row["time"]), timezone.utc).isoformat(),
            "open": float(row["open"]),
            "high": float(row["high"]),
            "low": float(row["low"]),
            "close": float(row["close"]),
            "volume": float(row["tick_volume"]),
        })

    return {
        "symbol": symbol,
        "timeframe": timeframe,
        "count": len(result),
        "candles": result,
    }
