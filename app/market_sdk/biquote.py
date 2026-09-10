"""BiQuote adapter for the Bitey SBT market-data SDK.

This adapter is intentionally dormant until provider licensing is approved for
public SBT display. It normalizes BiQuote data into the SBT-owned contract and
never fabricates prices.
"""

from __future__ import annotations

import asyncio
import json
from collections.abc import AsyncIterator
from typing import Any

import httpx
from websockets.asyncio.client import connect

from .models import Candle, Quote
from .providers import MarketDataProvider, ProviderError


class BiQuoteProvider(MarketDataProvider):
    """Read-only BiQuote adapter using REST + native SignalR WebSocket."""

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
        """Stream ReceiveTick events from BiQuote SignalR without extra packages."""
        symbol = symbol.upper()
        url = f"{self.base_url}/hubs/tick"

        try:
            async with connect(url, open_timeout=10, ping_interval=20, ping_timeout=20) as ws:
                # SignalR JSON Hub Protocol handshake.
                await ws.send(json.dumps({"protocol": "json", "version": 1}) + "\x1e")
                handshake = await asyncio.wait_for(ws.recv(), timeout=10)
                if isinstance(handshake, bytes):
                    handshake = handshake.decode("utf-8")
                handshake_message = str(handshake).rstrip("\x1e")
                if handshake_message:
                    handshake_payload = json.loads(handshake_message)
                    if handshake_payload.get("error"):
                        raise ProviderError(
                            f"BiQuote SignalR handshake failed: {handshake_payload['error']}"
                        )

                # Hub invocation: Subscribe([["EURUSD"]]).
                await ws.send(
                    json.dumps(
                        {
                            "type": 1,
                            "invocationId": "sbt-1",
                            "target": "Subscribe",
                            "arguments": [[symbol]],
                        }
                    )
                    + "\x1e"
                )

                async for raw in ws:
                    if isinstance(raw, bytes):
                        raw = raw.decode("utf-8")
                    for frame in str(raw).split("\x1e"):
                        if not frame:
                            continue
                        try:
                            message = json.loads(frame)
                        except json.JSONDecodeError:
                            continue

                        # SignalR completion/error for the subscription invocation.
                        if message.get("type") == 3 and message.get("error"):
                            raise ProviderError(
                                f"BiQuote subscription failed: {message['error']}"
                            )

                        if message.get("type") != 1:
                            continue
                        if message.get("target") != "ReceiveTick":
                            continue

                        arguments = message.get("arguments")
                        if not isinstance(arguments, list):
                            continue
                        for item in arguments:
                            if not isinstance(item, dict):
                                continue
                            item_symbol = str(item.get("symbol", "")).upper()
                            if item_symbol != symbol:
                                continue
                            try:
                                yield _quote_from_payload(item, symbol)
                            except ProviderError:
                                continue
        except ProviderError:
            raise
        except (OSError, asyncio.TimeoutError, json.JSONDecodeError, Exception) as exc:
            raise ProviderError(f"BiQuote stream unavailable: {exc}") from exc


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
