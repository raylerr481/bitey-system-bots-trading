"""Read-only MT5 API plus Demo strategy execution."""

import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Query

from app.services.mt5_demo_loop import MT5DemoLoop
from app.services.mt5_market_data import MT5MarketData

router = APIRouter(prefix="/api/v1/mt5", tags=["mt5"])

MT5_BRIDGE_URL = os.getenv("MT5_BRIDGE_URL", "").rstrip("/")
MT5_MODE = os.getenv("MT5_MODE", "demo").lower()


def market_data() -> MT5MarketData:
    return MT5MarketData(MT5_BRIDGE_URL)


@router.get("/status")
def status() -> dict[str, Any]:
    return {
        "provider": "metatrader5",
        "mode": MT5_MODE,
        "live_trading_enabled": False,
        "bridge_configured": bool(MT5_BRIDGE_URL),
    }


@router.get("/account")
async def account() -> Any:
    if not MT5_BRIDGE_URL:
        raise HTTPException(status_code=503, detail="MT5 bridge is not configured")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{MT5_BRIDGE_URL}/account")
            response.raise_for_status()
            return response.json()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"MT5 bridge unavailable: {exc}") from exc


@router.get("/quote/{symbol}")
async def quote(symbol: str) -> Any:
    try:
        return await market_data().quote(symbol)
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/candles/{symbol}")
async def candles(
    symbol: str,
    timeframe: str = Query("M5"),
    count: int = Query(30, ge=1, le=5000),
) -> Any:
    try:
        closes = await market_data().candles(symbol, timeframe, count)
        return {
            "symbol": symbol.upper(),
            "timeframe": timeframe.upper(),
            "count": len(closes),
            "closes": closes,
        }
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.post("/demo/run")
async def mt5_demo_run(
    symbol: str,
    timeframe: str = Query("M5"),
    count: int = Query(30, ge=1, le=5000),
    fast_window: int = Query(10, ge=2),
    slow_window: int = Query(30, ge=3),
    quantity: float = Query(1, gt=0),
) -> Any:
    if fast_window >= slow_window:
        raise HTTPException(status_code=400, detail="fast_window must be smaller than slow_window")
    if MT5_MODE != "demo":
        raise HTTPException(status_code=409, detail="MT5 demo execution requires MT5_MODE=demo")

    try:
        return await MT5DemoLoop(market_data()).run(
            symbol=symbol,
            timeframe=timeframe,
            count=count,
            fast_window=fast_window,
            slow_window=slow_window,
            quantity=quantity,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
