from __future__ import annotations

import os

import httpx

from app.brokers.base import BrokerAccount, BrokerCapabilities, BrokerQuote


class MT5Adapter:
    """Safe MT5 bridge adapter.

    The cloud API talks to a local/demo bridge. It intentionally has no live
    order method: the bridge remains a data/demo boundary for this milestone.
    """

    broker_id = "mt5"

    def __init__(self, bridge_url: str | None = None):
        self.bridge_url = (bridge_url or os.getenv("MT5_BRIDGE_URL", "")).rstrip("/")

    def capabilities(self) -> BrokerCapabilities:
        return BrokerCapabilities(
            market_data=True,
            paper=False,
            demo=True,
            live=False,
            order_submission=False,
        )

    def _get(self, path: str) -> dict:
        if not self.bridge_url:
            raise RuntimeError("MT5 demo bridge is not configured")
        response = httpx.get(f"{self.bridge_url}{path}", timeout=10)
        response.raise_for_status()
        return response.json()

    def account(self) -> BrokerAccount:
        data = self._get("/account")
        return BrokerAccount(
            broker=self.broker_id,
            mode="demo",
            status=str(data.get("status", "unknown")),
            equity=str(data.get("equity")) if data.get("equity") is not None else None,
            cash=str(data.get("cash")) if data.get("cash") is not None else None,
            currency=data.get("currency"),
        )

    def quote(self, symbol: str) -> BrokerQuote:
        data = self._get(f"/quote/{symbol.upper()}")
        return BrokerQuote(
            broker=self.broker_id,
            symbol=symbol.upper(),
            bid=float(data["bid"]) if data.get("bid") is not None else None,
            ask=float(data["ask"]) if data.get("ask") is not None else None,
            last=float(data["last"]) if data.get("last") is not None else None,
            timestamp=data.get("timestamp"),
        )

    def submit_order(self, symbol: str, side: str, quantity: float) -> dict:
        raise RuntimeError("MT5 live/demo order submission is disabled at the broker adapter boundary")
