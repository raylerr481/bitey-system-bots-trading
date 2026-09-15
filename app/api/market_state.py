"""Canonical SBT market-state endpoint."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.core.market_state import read_market_state

router = APIRouter(prefix="/api/v1/market-state", tags=["market-state"])


@router.get("")
def market_state(
    symbol: str | None = Query(default=None, min_length=1, max_length=30),
    timeframe: str | None = Query(default=None, min_length=2, max_length=4),
) -> dict[str, Any]:
    """Expose one authoritative readiness contract for SBT market consumers."""
    return read_market_state(symbol=symbol, timeframe=timeframe).as_dict()
