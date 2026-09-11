from __future__ import annotations

import asyncio
import os
from collections.abc import AsyncIterator
from typing import Any

import httpx

from app.market_sdk.models import Candle, Quote
from app.market_sdk.providers import MarketDataProvider, ProviderError


class MT5Provider(MarketDataProvider):
    """Read-only MT5 market-data provider.

    The cloud API never connects directly to the MetaTrader terminal. It calls
    an externally hosted/demo bridge through MT5_BRIDGE_URL. No order endpoint
    is exposed here and this provider cannot enable live trading.
    """

    name = "mt5"
    source = "metatrader5"

    def __init__(self, bridge_url: str | None = None) -> None:
        self.bridge_url = (bridge_url or os.getenv("MT5_BRIDGE_URL", "")).rstrip("/")
        self.timeout = float(os.getenv("MT5_BRIDGE_TIMEOUT", "10"))
        self.poll_interval = max(float(os.getenv("MT5_QUOTE_POLL_INTERVAL", "1.0")), 0.25)

    def _request(self, path: str, params: dict[str, Any] | None = None) -> Any:
        if not self.bridge_url:
            raise ProviderError("MT5 demo bridge is not configured")
        try:
            response = httpx.get(
                f"{self.bridge_url}{path}",
                params=params,
                timeout=self.timeout,
            )
            response.raise_for_status()
            return response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderError(f"MT5 bridge request failed: {exc}") from exc

    @staticmethod
    def _payload(data: Any, key: str) -> list[dict[str, Any]]:
        if isinstance(data, dict):
            value = data.get(key, data.get("data", []))
        else:
            value = data
        if not isinstance(value, list):
            raise ProviderError(f"MT5 bridge returned invalid {key} payload")
        return [item for item in value if isinstance(item, dict)]

    @staticmethod
    def _quote_from_payload(symbol: str, data: Any) -> Quote:
        if not isinstance(data, dict):
            raise ProviderError("MT5 bridge returned invalid quote payload")
        bid = data.get("bid")
        ask = data.get("ask")
        last = data.get("last", data.get("price"))
        mid = (float(bid) + float(ask)) / 2 if bid is not None and ask is not None else last
        spread = float(ask) - float(bid) if bid is not None and ask is not None else None
        return Quote(
            source="metatrader5",
            symbol=symbol.upper(),
            timestamp=data.get("timestamp"),
            bid=float(bid) if bid is not None else None,
            ask=float(ask) if ask is not None else None,
            mid=float(mid) if mid is not None else None,
            spread=spread,
        )

    async def quote(self, symbol: str) -> Quote:
        data = await asyncio.to_thread(self._request, f"/quote/{symbol.upper()}")
        return self._quote_from_payload(symbol, data)

    async def candles(self, symbol: str, timeframe: str = "M5", limit: int = 200) -> list[Candle]:
        data = await asyncio.to_thread(
            self._request,
            f"/candles/{symbol.upper()}",
            {"timeframe": timeframe, "limit": min(max(int(limit), 1), 1000)},
        )
        rows = self._payload(data, "candles")
        candles: list[Candle] = []
        for row in rows:
            try:
                candles.append(
                    Candle(
                        timestamp=row.get("timestamp", row.get("time")),
                        open=float(row["open"]),
                        high=float(row["high"]),
                        low=float(row["low"]),
                        close=float(row["close"]),
                    )
                )
            except (KeyError, TypeError, ValueError) as exc:
                raise ProviderError("MT5 bridge returned invalid candle data") from exc
        return candles

    async def stream(self, symbol: str) -> AsyncIterator[Quote]:
        """Poll real MT5 quotes through the bridge; never synthesize prices."""
        last_signature: tuple[Any, ...] | None = None
        while True:
            quote = await self.quote(symbol)
            signature = (quote.timestamp, quote.bid, quote.ask, quote.mid)
            if signature != last_signature:
                last_signature = signature
                yield quote
            await asyncio.sleep(self.poll_interval)
