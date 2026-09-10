"""BiQuote adapter for the Bitey SBT market-data SDK.

This adapter is intentionally dormant until provider licensing is approved for
public SBT display. It normalizes BiQuote data into the SBT-owned contract and
never fabricates prices.
"""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator
from typing import Any

import httpx

from .models import Candle, Quote
from .providers import MarketDataProvider, ProviderError


class BiQuoteProvider(MarketDataProvider):
    """Read-only BiQuote adapter using REST + SignalR."""

    name = "biquote"
    base_url = "https://biquote.io"

    def __init__(self, base_url: str | None = None) -> None:
        self.base_url = (base_url or self.base_url).rstrip("/")

    async def quote(self, symbol: str) -> Quote:
        symbol = symbol.upper()
        try:
            async with httpx.AsyncClient(timeout=5) as client:
                response = await client.get(f"{self.base_url}/api/{symbol}")
                response.raise_for_status()
                payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderError(f"BiQuote quote unavailable: {exc}") from exc

        if not isinstance(payload, dict):
            raise ProviderError("BiQuote returned an invalid quote payload")
        return _quote_from_payload(payload, symbol)

    async def candles(self, symbol: str, timeframe: str, limit: int) -> list[Candle]:
        symbol = symbol.upper()
        interval = _interval(timeframe)
        limit = max(1, min(int(limit), 1000))
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(
                    f"{self.base_url}/api/{symbol}/ohlc",
                    params={"interval": interval, "limit": limit},
                )
                response.raise_for_status()
                payload = response.json()
        except (httpx.HTTPError, ValueError) as exc:
            raise ProviderError(f"BiQuote candles unavailable: {exc}") from exc

        rows: Any = payload.get("bars") if isinstance(payload, dict) else None
        if not isinstance(rows, list):
            raise ProviderError("BiQuote returned an invalid candle envelope")

        candles: list[Candle] = []
        for row in reversed(rows):
            if not isinstance(row, dict):
                continue
            try:
                timestamp = row.get("openTime", row.get("timestamp", row.get("time")))
                if timestamp is None:
                    continue
                candles.append(
                    Candle(
                        timestamp=timestamp,
                        open=float(row["open"]),
                        high=float(row["high"]),
                        low=float(row["low"]),
                        close=float(row["close"]),
                    )
                )
            except (KeyError, TypeError, ValueError):
                continue

        if not candles:
            raise ProviderError("BiQuote returned no valid candles")
        return candles

    async def stream(self, symbol: str) -> AsyncIterator[Quote]:
        """Stream ReceiveTick events from BiQuote SignalR."""
        try:
            from pysignalr.client import SignalRClient
        except ImportError as exc:
            raise ProviderError(
                "BiQuote streaming requires the pysignalr dependency"
            ) from exc

        symbol = symbol.upper()
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[Quote] = asyncio.Queue()
        client = SignalRClient(f"{self.base_url}/hubs/tick")

        async def on_tick(payload: list[dict[str, Any]]) -> None:
            for item in payload:
                if not isinstance(item, dict):
                    continue
                item_symbol = str(item.get("symbol", "")).upper()
                if item_symbol != symbol:
                    continue
                try:
                    quote = _quote_from_payload(item, symbol)
                except ProviderError:
                    continue
                await queue.put(quote)

        def on_open() -> None:
            client.send("Subscribe", [[symbol]])

        client.on("ReceiveTick", on_tick)
        client.on_open(on_open)

        async def run_client() -> None:
            try:
                await client.run()
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                await queue.put(
                    ProviderError(f"BiQuote stream unavailable: {exc}")
                )

        task = asyncio.create_task(run_client())
        try:
            while True:
                item = await queue.get()
                if isinstance(item, ProviderError):
                    raise item
                yield item
        finally:
            task.cancel()
            await asyncio.gather(task, return_exceptions=True)


def _quote_from_payload(payload: dict[str, Any], symbol: str) -> Quote:
    bid = _number(payload.get("bid"))
    ask = _number(payload.get("ask"))
    mid = _number(payload.get("mid"))
    if mid is None and bid is not None and ask is not None:
        mid = (bid + ask) / 2
    if bid is None and ask is None and mid is None:
        raise ProviderError("BiQuote returned no valid price")

    return Quote(
        source="biquote",
        symbol=str(payload.get("symbol", symbol)).upper(),
        timestamp=payload.get("timestamp", payload.get("time")),
        bid=bid,
        ask=ask,
        mid=mid,
        spread=(ask - bid) if bid is not None and ask is not None else None,
    )


def _number(value: object) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _interval(timeframe: str) -> str:
    mapping = {
        "M1": "1m",
        "M5": "5m",
        "M15": "15m",
        "M30": "30m",
        "H1": "1h",
        "H4": "4h",
        "D1": "1d",
    }
    key = timeframe.upper()
    if key not in mapping:
        raise ProviderError(f"Unsupported timeframe: {timeframe}")
    return mapping[key]
