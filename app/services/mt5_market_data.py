"""Read-only MT5 market-data adapter.

This module intentionally has no order/execution methods. It converts bridge
responses into the price list consumed by the Demo strategy loop.
"""

from typing import Any

import httpx


class MT5MarketDataError(RuntimeError):
    pass


class MT5MarketData:
    def __init__(self, bridge_url: str, timeout: float = 10.0):
        self.bridge_url = bridge_url.rstrip("/")
        self.timeout = timeout

    async def quote(self, symbol: str) -> dict[str, Any]:
        if not self.bridge_url:
            raise MT5MarketDataError("MT5 bridge is not configured")
        symbol = symbol.strip().upper()
        if not symbol:
            raise MT5MarketDataError("Symbol is required")
        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(f"{self.bridge_url}/quote/{symbol}")
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise MT5MarketDataError(f"Unable to read MT5 quote: {exc}") from exc
        return data

    async def candles(self, symbol: str, timeframe: str = "M5", count: int = 30) -> list[float]:
        """Return close prices from a read-only bridge candles endpoint."""
        if not self.bridge_url:
            raise MT5MarketDataError("MT5 bridge is not configured")
        symbol = symbol.strip().upper()
        if not symbol:
            raise MT5MarketDataError("Symbol is required")
        if count < 1 or count > 5000:
            raise MT5MarketDataError("count must be between 1 and 5000")

        try:
            async with httpx.AsyncClient(timeout=self.timeout) as client:
                response = await client.get(
                    f"{self.bridge_url}/candles/{symbol}",
                    params={"timeframe": timeframe.upper(), "count": count},
                )
                response.raise_for_status()
                data = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise MT5MarketDataError(f"Unable to read MT5 candles: {exc}") from exc

        rows = data.get("candles", data) if isinstance(data, dict) else data
        if not isinstance(rows, list):
            raise MT5MarketDataError("Invalid candles response")

        closes: list[float] = []
        for row in rows:
            if isinstance(row, dict) and "close" in row:
                closes.append(float(row["close"]))
            elif isinstance(row, (int, float)):
                closes.append(float(row))

        if not closes:
            raise MT5MarketDataError("MT5 returned no close prices")
        return closes
