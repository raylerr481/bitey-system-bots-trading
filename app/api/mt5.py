"""MetaTrader 5 bridge API for safe Demo/Paper integration.

The FastAPI service does not import the MetaTrader5 desktop Python package.
Instead, an MT5 terminal/bridge running on a supported machine exposes a
small HTTP interface. This keeps the main backend deployable on Linux while
allowing MT5 Demo execution later.
"""

import os
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException

router = APIRouter(prefix="/api/v1/mt5", tags=["mt5"])

MT5_BRIDGE_URL = os.getenv("MT5_BRIDGE_URL", "").rstrip("/")
MT5_MODE = os.getenv("MT5_MODE", "demo").lower()


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
    if not MT5_BRIDGE_URL:
        raise HTTPException(status_code=503, detail="MT5 bridge is not configured")
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{MT5_BRIDGE_URL}/quote/{symbol.upper()}")
            response.raise_for_status()
            return response.json()
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"MT5 bridge unavailable: {exc}") from exc
