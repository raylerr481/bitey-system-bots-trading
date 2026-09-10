"""Provider interface for Bitey SBT market data."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator

from .models import Candle, Quote


class ProviderError(RuntimeError):
    """Raised when a provider cannot supply valid market data."""


class MarketDataProvider(ABC):
    """Provider-neutral interface consumed by the SBT market layer."""

    name: str = "unknown"

    @abstractmethod
    async def quote(self, symbol: str) -> Quote:
        raise NotImplementedError

    @abstractmethod
    async def candles(self, symbol: str, timeframe: str, limit: int) -> list[Candle]:
        raise NotImplementedError

    @abstractmethod
    async def stream(self, symbol: str) -> AsyncIterator[Quote]:
        raise NotImplementedError
