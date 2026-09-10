"""Bitey SBT provider-neutral market data API.

The API owns the SBT market contract. External providers are isolated behind
the Market SDK and no endpoint fabricates market data or submits orders.
"""

from __future__ import annotations

import os
from typing import Any

from fastapi import APIRouter, HTTPException, Query, WebSocket, WebSocketDisconnect

from app.market_sdk import ProviderError
from app.market_sdk.registry import build_provider

router = APIRouter(prefix="/api/v1/market", tags=["market"])


def _provider_or_http_error():
    try:
        return build_provider()
    except ProviderError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


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
        await websocket.send_json(
            {
                "contract": "sbt-market-stream-v1",
                "source": provider.name,
                "symbol": symbol.upper(),
                "state": "CONNECTING",
                "execution_enabled": False,
            }
        )
        async for quote in provider.stream(symbol):
            await websocket.send_json(
                {
                    **quote.as_dict(),
                    "state": "LIVE",
                    "execution_enabled": False,
                }
            )
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
