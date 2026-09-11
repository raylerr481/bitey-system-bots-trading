"""Canonical market-data models owned by Bitey SBT."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any


def _epoch_seconds(value: Any) -> float:
    """Normalize numeric or ISO timestamps to epoch seconds for the SBT contract."""
    if isinstance(value, (int, float)):
        numeric = float(value)
        return numeric / 1000 if numeric > 1e12 else numeric
    if isinstance(value, str):
        text = value.strip()
        try:
            numeric = float(text)
            return numeric / 1000 if numeric > 1e12 else numeric
        except ValueError:
            parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
            if parsed.tzinfo is None:
                parsed = parsed.replace(tzinfo=timezone.utc)
            return parsed.timestamp()
    raise ValueError(f"Unsupported timestamp type: {type(value).__name__}")


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
            "timestamp": _epoch_seconds(self.timestamp),
            "open": self.open,
            "high": self.high,
            "low": self.low,
            "close": self.close,
        }
