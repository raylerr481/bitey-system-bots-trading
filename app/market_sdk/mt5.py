from __future__ import annotations

import os
from typing import Any, Iterator

import httpx

from app.market_sdk.models import Candle, Quote
from app.market_sdk.providers import MarketDataProvider, ProviderError


class MT5Provider(MarketDataProvider):
    """Read-only MT5 market-data provider.

    The cloud API never connects directly to the MetaTrader terminal. It calls
    an externally hosted/demo bridge through MT5_BRIDGE_URL. No order endpoint
    is exposed here and this provider cannot enable live trading.
    """

    source = "metatrader5"

    def __init__(self, bridge_url: str | None = None) -> None:
        self.bridge_url = (bridge_url or os.getenv("MT5_BRIDGE_URL", "")).rstrip("/")
        self.timeout = float(os.getenv("MT5_BRIDGE_TIMEOUT", "10"))

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

    def quote(self, symbol: str) -> Quote:
        data = self._request(f"/quote/{symbol.upper()}")
        if not isinstance(data, dict):
            raise ProviderError("MT5 bridge returned invalid quote payload")
        bid = data.get("bid")
        ask = data.get("ask")
        last = data.get("last", data.get("price"))
        mid = (float(bid) + float(ask)) / 2 if bid is not None and ask is not None else last
        spread = float(ask) - float(bid) if bid is not None and ask is not None else None
        return Quote(
            source=self.source,
            symbol=symbol.upper(),
            timestamp=data.get("timestamp"),
            bid=float(bid) if bid is not None else None,
            ask=float(ask) if ask is not None else None,
            mid=float(mid) if mid is not None else None,
            spread=spread,
        )

    def candles(self, symbol: str, timeframe: str = "M5", limit: int = 200) -> list[Candle]:
        data = self._request(
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

    def stream(self, symbol: str) -> Iterator[Quote]:
        raise ProviderError(
            "MT5 live tick stream is not exposed by the current bridge contract; "
            "historical candles are supported only when /candles/{symbol} exists"
        )
