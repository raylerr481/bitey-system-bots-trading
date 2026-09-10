"""Canonical market-data models owned by Bitey SBT."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Quote:
    source: str
    symbol: str
    timestamp: float | int | None
    bid: float | None
    ask: float | None
    mid: float | None
    spread: float | None

    def as_dict(self) -> dict[str, Any]:
        return {
            "contract": "sbt-quote-v1",
            "source": self.source,
            "symbol": self.symbol,
            "timestamp": self.timestamp,
            "bid": self.bid,
            "ask": self.ask,
            "mid": self.mid,
            "spread": self.spread,
        }


@dataclass(frozen=True)
class Candle:
    timestamp: float | int
    open: float
    high: float
    low: float
    close: float

    def as_dict(self) -> dict[str, Any]:
        return {
            "timestamp": self.timestamp,
            "open": self.open,
            "high": self.high,
            "low": self.low,
            "close": self.close,
        }
