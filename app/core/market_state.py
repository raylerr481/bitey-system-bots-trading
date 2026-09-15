"""Canonical runtime state for SBT market-data availability.

This module is deliberately provider-neutral. It reports configuration state
without fabricating quotes, candles, or stream health.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Literal

from app.market_sdk.registry import build_provider
from app.market_sdk.providers import ProviderError

MarketState = Literal["OFFLINE", "CONNECTING", "LIVE", "DEGRADED", "STALE", "ERROR"]


@dataclass(frozen=True)
class BiteySBTMarketState:
    provider: str | None
    connection: str
    market_available: bool
    quote_available: bool
    candles_available: bool
    stream_available: bool
    symbol: str | None
    timeframe: str | None
    state: MarketState
    execution_enabled: bool = False

    def as_dict(self) -> dict[str, object]:
        return {
            "contract": "sbt-market-state-v1",
            "provider": self.provider,
            "connection": self.connection,
            "market_available": self.market_available,
            "quote_available": self.quote_available,
            "candles_available": self.candles_available,
            "stream_available": self.stream_available,
            "symbol": self.symbol,
            "timeframe": self.timeframe,
            "state": self.state,
            "execution_enabled": self.execution_enabled,
        }


def read_market_state(symbol: str | None = None, timeframe: str | None = None) -> BiteySBTMarketState:
    """Return configuration-level market readiness without making a data claim."""
    selected = os.getenv("SBT_MARKET_PROVIDER", "none").strip().lower()
    try:
        provider = build_provider()
    except ProviderError:
        return BiteySBTMarketState(
            provider=selected if selected != "none" else None,
            connection="not-configured",
            market_available=False,
            quote_available=False,
            candles_available=False,
            stream_available=False,
            symbol=symbol.upper() if symbol else None,
            timeframe=timeframe.upper() if timeframe else None,
            state="OFFLINE",
        )

    return BiteySBTMarketState(
        provider=provider.name,
        connection="configured",
        market_available=True,
        quote_available=True,
        candles_available=True,
        stream_available=True,
        symbol=symbol.upper() if symbol else None,
        timeframe=timeframe.upper() if timeframe else None,
        state="CONNECTING",
    )
