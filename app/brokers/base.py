from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


@dataclass(frozen=True)
class BrokerCapabilities:
    market_data: bool
    paper: bool
    demo: bool
    live: bool
    order_submission: bool


@dataclass(frozen=True)
class BrokerAccount:
    broker: str
    mode: str
    status: str
    equity: str | None = None
    cash: str | None = None
    currency: str | None = None


@dataclass(frozen=True)
class BrokerQuote:
    broker: str
    symbol: str
    bid: float | None
    ask: float | None
    last: float | None
    timestamp: str | None = None


class BrokerAdapter(Protocol):
    """Internal SBT contract; implementations must enforce their safe mode."""

    broker_id: str

    def capabilities(self) -> BrokerCapabilities: ...

    def account(self) -> BrokerAccount: ...

    def quote(self, symbol: str) -> BrokerQuote: ...

    def submit_order(self, symbol: str, side: str, quantity: float) -> dict: ...
