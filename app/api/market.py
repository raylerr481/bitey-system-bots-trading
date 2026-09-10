"""Bitey SBT provider-neutral market data API.

The API owns the SBT market contract. External providers are isolated behind
the Market SDK and no endpoint fabricates market data or submits orders.
"""

from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect

from app.market_sdk import Candle, ProviderError
from app.market_sdk.registry import build_provider

router = APIRouter(prefix="/api/v1/market", tags=["market"])


def _provider_or_http_error():
    try:
        return build_provider()
    except ProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


def _epoch_seconds(value: Any) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        value = float(value)
        return value / 1000 if value > 1e12 else value
    if isinstance(value, str):
        text = value.strip()
        try:
            numeric = float(text)
            return numeric / 1000 if numeric > 1e12 else numeric
        except ValueError:
            pass
        try:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.timestamp()
        except ValueError:
            return None
    return None


def _m5_bucket(timestamp: Any) -> int | None:
    epoch = _epoch_seconds(timestamp)
    if epoch is None:
        return None
    return int(epoch // 300) * 300


def _apply_tick(candle: Candle | None, quote: Any) -> Candle | None:
    price = quote.mid if quote.mid is not None else quote.bid
    bucket = _m5_bucket(quote.timestamp)
    if price is None or bucket is None:
        return candle
    if candle is None or int(candle.timestamp) != bucket:
        return Candle(timestamp=bucket, open=price, high=price, low=price, close=price)
    return Candle(
        timestamp=candle.timestamp,
        open=candle.open,
        high=max(candle.high, price),
        low=min(candle.low, price),
        close=price,
    )


@router.get("/connections")
def connections() -> dict[str, Any]:
    provider = os.getenv("SBT_MARKET_PROVIDER", "none").strip().lower()
    approved = os.getenv("SBT_BIQUOTE_PUBLIC_APPROVED", "false").lower() == "true"
    configured = provider == "biquote" and approved
    return {
        "owner": "bitey-sbt",
        "contract": "sbt-market-v1",
        "mode": "market-data-only",
        "execution_enabled": False,
        "connections": [
            {
                "id": provider,
                "name": "BiQuote" if provider == "biquote" else "No public provider",
                "kind": "market-data-provider",
                "market_data": configured,
                "real_time_quotes": configured,
                "real_time_charts": configured,
                "ohlc_candles": configured,
                "execution_authority": "disabled",
                "configured": configured,
            }
        ],
        "credentials_boundary": "SBT consumes normalized market data only; no broker credentials or order execution are exposed.",
    }


@router.get("/quote/{symbol}")
async def quote(symbol: str) -> dict[str, Any]:
    provider = _provider_or_http_error()
    try:
        return (await provider.quote(symbol)).as_dict()
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc


@router.get("/candles/{symbol}")
async def candles(
    symbol: str,
    timeframe: str = Query(default="M5", min_length=2, max_length=4),
    limit: int = Query(default=100, ge=20, le=500),
) -> dict[str, Any]:
    provider = _provider_or_http_error()
    try:
        rows = await provider.candles(symbol, timeframe, limit)
    except ProviderError as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    return {
        "contract": "sbt-candles-v1",
        "source": provider.name,
        "symbol": symbol.upper(),
        "timeframe": timeframe.upper(),
        "limit": len(rows),
        "candles": [row.as_dict() for row in rows],
    }


@router.websocket("/stream/{symbol}")
async def stream(websocket: WebSocket, symbol: str) -> None:
    await websocket.accept()
    try:
        provider = build_provider()
        symbol = symbol.upper()
        history = await provider.candles(symbol, "M5", 200)
        current_candle = history[-1] if history else None

        await websocket.send_json(
            {
                "contract": "sbt-market-stream-v1",
                "source": provider.name,
                "symbol": symbol,
                "state": "CONNECTING",
                "execution_enabled": False,
                "historical_candles": [row.as_dict() for row in history],
            }
        )

        async for quote in provider.stream(symbol):
            next_candle = _apply_tick(current_candle, quote)
            candle_changed = next_candle is not None and next_candle != current_candle
            current_candle = next_candle
            payload = {
                **quote.as_dict(),
                "state": "LIVE",
                "execution_enabled": False,
                "first_tick": True,
                "candle_timeframe": "M5",
                "candle": current_candle.as_dict() if candle_changed else None,
            }
            await websocket.send_json(payload)
    except ProviderError as exc:
        try:
            await websocket.send_json(
                {
                    "contract": "sbt-market-stream-v1",
                    "source": "none",
                    "symbol": symbol.upper(),
                    "state": "OFFLINE",
                    "execution_enabled": False,
                    "error": str(exc),
                }
            )
        except RuntimeError:
            pass
    except WebSocketDisconnect:
        return
    except RuntimeError:
        return
