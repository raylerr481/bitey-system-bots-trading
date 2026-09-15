"""Canonical runtime state for SBT market-data availability.

The state is provider-neutral and fail-closed. Configuration alone never
counts as live market data; LIVE requires a confirmed provider tick.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Literal

from app.market_sdk.registry import build_provider
from app.market_sdk.providers import ProviderError

MarketState = Literal["OFFLINE", "CONNECTING", "LIVE", "DEGRADED", "STALE", "ERROR"]
STALE_AFTER_SECONDS = 15.0


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
    last_quote: dict[str, object] | None = None
    last_candle: dict[str, object] | None = None
    last_update: float | None = None
    latency: float | None = None
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
            "last_quote": self.last_quote,
            "last_candle": self.last_candle,
            "last_update": self.last_update,
            "latency": self.latency,
            "execution_enabled": self.execution_enabled,
        }


_runtime: dict[tuple[str, str], BiteySBTMarketState] = {}


def _key(symbol: str | None, timeframe: str | None) -> tuple[str, str]:
    return ((symbol or "").upper(), (timeframe or "").upper())


def mark_connecting(symbol: str, timeframe: str, provider: str) -> BiteySBTMarketState:
    state = BiteySBTMarketState(
        provider=provider,
        connection="configured",
        market_available=False,
        quote_available=False,
        candles_available=False,
        stream_available=True,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="CONNECTING",
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def mark_historical(symbol: str, timeframe: str, provider: str) -> BiteySBTMarketState:
    state = BiteySBTMarketState(
        provider=provider,
        connection="connected",
        market_available=True,
        quote_available=False,
        candles_available=True,
        stream_available=True,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="DEGRADED",
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def mark_live(
    symbol: str,
    timeframe: str,
    provider: str,
    quote: dict[str, object],
    candle: dict[str, object] | None = None,
    latency: float | None = None,
) -> BiteySBTMarketState:
    now = time.time()
    state = BiteySBTMarketState(
        provider=provider,
        connection="connected",
        market_available=True,
        quote_available=True,
        candles_available=candle is not None,
        stream_available=True,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="LIVE",
        last_quote=quote,
        last_candle=candle,
        last_update=now,
        latency=latency,
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def mark_error(symbol: str, timeframe: str, provider: str | None, error: str) -> BiteySBTMarketState:
    state = BiteySBTMarketState(
        provider=provider,
        connection="error",
        market_available=False,
        quote_available=False,
        candles_available=False,
        stream_available=False,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="ERROR",
        last_quote={"error": error},
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def read_market_state(symbol: str | None = None, timeframe: str | None = None) -> BiteySBTMarketState:
    """Return runtime state, or configuration-level readiness if not started."""
    selected = os.getenv("SBT_MARKET_PROVIDER", "none").strip().lower()
    key = _key(symbol, timeframe)
    current = _runtime.get(key)
    if current is not None:
        if current.last_update is not None and time.time() - current.last_update > STALE_AFTER_SECONDS:
            return BiteySBTMarketState(
                **{**current.__dict__, "state": "STALE", "stream_available": True}
            )
        return current

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
        market_available=False,
        quote_available=False,
        candles_available=False,
        stream_available=False,
        symbol=symbol.upper() if symbol else None,
        timeframe=timeframe.upper() if timeframe else None,
        state="CONNECTING",
    )
