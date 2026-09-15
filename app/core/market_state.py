"""Canonical runtime state for SBT market-data availability.

The state is provider-neutral and fail-closed. A configured provider is never
reported as live until an actual market-data tick has been observed.
"""

from __future__ import annotations

import os
import time
from dataclasses import dataclass
from typing import Any, Literal

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
    last_quote: dict[str, Any] | None = None
    last_candle: dict[str, Any] | None = None
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


# SBT's current deployment is intentionally simple: one process-local tracker.
# It is only an observation cache; it never enables order execution.
_runtime: dict[tuple[str, str], BiteySBTMarketState] = {}
_STALE_AFTER_SECONDS = 30.0


def _key(symbol: str | None, timeframe: str | None) -> tuple[str, str]:
    return ((symbol or "").upper(), (timeframe or "").upper())


def _configured_state(symbol: str | None, timeframe: str | None) -> BiteySBTMarketState:
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
        market_available=False,
        quote_available=False,
        candles_available=False,
        stream_available=False,
        symbol=symbol.upper() if symbol else None,
        timeframe=timeframe.upper() if timeframe else None,
        state="CONNECTING",
    )


def read_market_state(symbol: str | None = None, timeframe: str | None = None) -> BiteySBTMarketState:
    """Return observed market readiness; configuration alone is not LIVE."""
    key = _key(symbol, timeframe)
    current = _runtime.get(key)
    if current is None:
        return _configured_state(symbol, timeframe)

    if current.state == "LIVE" and current.last_update is not None:
        if time.time() - current.last_update > _STALE_AFTER_SECONDS:
            return BiteySBTMarketState(
                **{**current.__dict__, "state": "STALE", "connection": "stale"}
            )
    return current


def mark_connecting(
    provider: str,
    symbol: str,
    timeframe: str,
    candles_available: bool = False,
    last_candle: dict[str, Any] | None = None,
) -> BiteySBTMarketState:
    """Record provider connection without claiming a live quote."""
    state = BiteySBTMarketState(
        provider=provider,
        connection="connected",
        market_available=bool(candles_available),
        quote_available=False,
        candles_available=bool(candles_available),
        stream_available=False,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="CONNECTING",
        last_candle=last_candle,
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def mark_quote(
    provider: str,
    symbol: str,
    timeframe: str,
    quote: dict[str, Any],
    candle: dict[str, Any] | None = None,
    latency: float | None = None,
) -> BiteySBTMarketState:
    """Record an observed tick and promote the state to LIVE."""
    state = BiteySBTMarketState(
        provider=provider,
        connection="connected",
        market_available=True,
        quote_available=True,
        candles_available=True,
        stream_available=True,
        symbol=symbol.upper(),
        timeframe=timeframe.upper(),
        state="LIVE",
        last_quote=quote,
        last_candle=candle,
        last_update=time.time(),
        latency=latency,
    )
    _runtime[_key(symbol, timeframe)] = state
    return state


def mark_error(
    provider: str | None,
    symbol: str,
    timeframe: str,
) -> BiteySBTMarketState:
    """Record a runtime provider error without exposing execution authority."""
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
    )
    _runtime[_key(symbol, timeframe)] = state
    return state
