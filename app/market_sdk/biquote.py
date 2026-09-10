"""BiQuote adapter for the Bitey SBT market-data SDK.

This adapter is intentionally dormant until provider licensing is approved for
public SBT display. It normalizes BiQuote data into the SBT-owned contract and
never fabricates prices.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator

import httpx

from .models import Candle, Quote
from .providers import MarketDataProvider, ProviderError


class BiQuoteProvider(MarketDataProvider):
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

        bid = _number(payload.get("bid"))
        ask = _number(payload.get("ask"))
        mid = _number(payload.get("mid"))
        if mid is None and bid is not None and ask is not None:
            mid = (bid + ask) / 2
        if bid is None and ask is None and mid is None:
            raise ProviderError("BiQuote returned no valid price")

        return Quote(
            source=self.name,
            symbol=symbol,
            timestamp=payload.get("timestamp"),
            bid=bid,
            ask=ask,
            mid=mid,
            spread=(ask - bid) if bid is not None and ask is not None else None,
        )

    async def candles(self, symbol: str, timeframe: str, limit: int) -> list[Candle]:
        symbol = symbol.upper()
        interval = _interval(timeframe)
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

        rows = payload.get("candles", payload) if isinstance(payload, dict) else payload
        if not isinstance(rows, list):
            raise ProviderError("BiQuote returned an invalid candle payload")

        candles: list[Candle] = []
        for row in rows:
            if not isinstance(row, dict):
                continue
            try:
                timestamp = row.get("timestamp", row.get("time"))
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
        """Stream ticks from BiQuote SignalR without exposing its wire format."""
        try:
            from signalrcore.hub_connection_builder import HubConnectionBuilder
        except ImportError as exc:
            raise ProviderError(
                "BiQuote streaming requires the optional signalrcore dependency"
            ) from exc

        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[Quote] = asyncio.Queue()
        connection = (
            HubConnectionBuilder()
            .with_url(f"{self.base_url.replace('https://', 'wss://')}/hubs/tick")
            .build()
        )

        def on_tick(payload: object) -> None:
            try:
                data = payload if isinstance(payload, dict) else json.loads(str(payload))
                bid = _number(data.get("bid"))
                ask = _number(data.get("ask"))
                mid = _number(data.get("mid"))
                if mid is None and bid is not None and ask is not None:
                    mid = (bid + ask) / 2
                if mid is None:
                    return
                quote = Quote(
                    source=self.name,
                    symbol=str(data.get("symbol", symbol)).upper(),
                    timestamp=data.get("timestamp"),
                    bid=bid,
                    ask=ask,
                    mid=mid,
                    spread=(ask - bid) if bid is not None and ask is not None else None,
                )
                asyncio.run_coroutine_threadsafe(queue.put(quote), loop)
            except (TypeError, ValueError, json.JSONDecodeError):
                return

        connection.on("tick", on_tick)
        connection.start()
        try:
            while True:
                yield await queue.get()
        finally:
            connection.stop()


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
