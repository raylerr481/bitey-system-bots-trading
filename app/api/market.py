"""Bitey SBT native market connectivity and real-time quote streaming.

The SBT backend owns the market-data contract. Platform-specific terminals are
connectors behind this boundary; the client never talks to broker credentials
or proprietary terminal APIs directly.
"""

from __future__ import annotations

import asyncio
import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, WebSocket, WebSocketDisconnect

router = APIRouter(prefix="/api/v1/market", tags=["market"])
MT5_BRIDGE_URL = os.getenv("MT5_BRIDGE_URL", "").rstrip("/")


async def _mt5_quote(symbol: str) -> dict[str, Any]:
    if not MT5_BRIDGE_URL:
        raise HTTPException(status_code=503, detail="MT5 bridge is not configured")
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            response = await client.get(f"{MT5_BRIDGE_URL}/quote/{symbol.upper()}")
            response.raise_for_status()
            payload = response.json()
            return {
                "source": "mt5",
                "symbol": symbol.upper(),
                "timestamp": payload.get("timestamp"),
                "bid": payload.get("bid"),
                "ask": payload.get("ask"),
                "last": payload.get("last", payload.get("price")),
                "spread": payload.get("spread"),
                "raw": payload,
            }
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"MT5 market feed unavailable: {exc}") from exc


@router.get("/connections")
def connections() -> dict[str, Any]:
    return {
        "owner": "bitey-sbt",
        "contract": "sbt-market-v1",
        "connections": [
            {
                "id": "mt5",
                "name": "MetaTrader 5",
                "kind": "terminal-bridge",
                "market_data": True,
                "real_time_quotes": True,
                "real_time_charts": True,
                "execution_authority": "sbt-risk-gate",
                "configured": bool(MT5_BRIDGE_URL),
            }
        ],
        "credentials_boundary": "Credentials remain outside Bitey SBT; SBT consumes an authorized market connector.",
    }


@router.get("/quote/{symbol}")
async def quote(symbol: str) -> dict[str, Any]:
    return await _mt5_quote(symbol)


@router.websocket("/stream/{symbol}")
async def stream(websocket: WebSocket, symbol: str) -> None:
    await websocket.accept()
    try:
        while True:
            try:
                data = await _mt5_quote(symbol)
                await websocket.send_json(data)
            except HTTPException as exc:
                await websocket.send_json({"source": "mt5", "symbol": symbol.upper(), "error": exc.detail})
            await asyncio.sleep(1)
    except (WebSocketDisconnect, RuntimeError):
        return
