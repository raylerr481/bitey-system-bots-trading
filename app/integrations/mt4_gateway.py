from __future__ import annotations

import os
from typing import Any

import httpx


class MT4GatewayClient:
    """Read-only client for the local MT4 MCP Gateway.

    The gateway remains on the user's desktop. SBT only receives data through
    explicit gateway endpoints and never receives broker credentials.
    """

    def __init__(self, base_url: str | None = None, timeout: float = 10.0) -> None:
        self.base_url = (base_url or os.getenv("MT4_GATEWAY_URL", "http://127.0.0.1:22346")).rstrip("/")
        self.timeout = timeout

    async def _get(self, path: str) -> dict[str, Any]:
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.get(f"{self.base_url}{path}")
            response.raise_for_status()
            data = response.json()
            return data if isinstance(data, dict) else {"data": data}

    async def status(self) -> dict[str, Any]:
        try:
            data = await self._get("/status")
            return {"reachable": True, "gateway": self.base_url, "data": data}
        except httpx.HTTPError as exc:
            return {"reachable": False, "gateway": self.base_url, "error": str(exc)}

    async def account_status(self) -> dict[str, Any]:
        return await self._get("/account_status")

    async def open_positions(self) -> dict[str, Any]:
        return await self._get("/open_positions")

    async def market_data(self, symbol: str) -> dict[str, Any]:
        return await self._get(f"/market_data/{symbol.upper()}")

    async def trade_history(self) -> dict[str, Any]:
        return await self._get("/trade_history")

    async def turtle_audit(self) -> dict[str, Any]:
        return await self._get("/turtle_audit")
