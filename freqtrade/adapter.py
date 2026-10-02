"""Read-only Freqtrade connector for Bitey SBT.

The adapter is intentionally limited to health/status/report reads.
Execution commands are not exposed here. Any future DEMO/LIVE action must
pass through the SBT permission and Risk Gate layers first.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any

import httpx


@dataclass(frozen=True)
class FreqtradeSettings:
    base_url: str = os.getenv("BITEY_FREQTRADE_URL", "http://127.0.0.1:8080")
    username: str = os.getenv("BITEY_FREQTRADE_USER", "")
    password: str = os.getenv("BITEY_FREQTRADE_PASSWORD", "")
    timeout_seconds: float = float(os.getenv("BITEY_FREQTRADE_TIMEOUT", "10"))


class FreqtradeReadOnlyClient:
    """Safe READ connector for a local or protected Freqtrade API."""

    def __init__(self, settings: FreqtradeSettings | None = None) -> None:
        self.settings = settings or FreqtradeSettings()

    def _client(self) -> httpx.Client:
        auth = None
        if self.settings.username:
            auth = (self.settings.username, self.settings.password)

        return httpx.Client(
            base_url=self.settings.base_url.rstrip("/"),
            auth=auth,
            timeout=self.settings.timeout_seconds,
            follow_redirects=False,
        )

    def ping(self) -> dict[str, Any]:
        return self._get("/api/v1/ping")

    def status(self) -> dict[str, Any]:
        return self._get("/api/v1/status")

    def balance(self) -> dict[str, Any]:
        return self._get("/api/v1/balance")

    def trades(self, limit: int = 50) -> dict[str, Any]:
        if limit < 1 or limit > 500:
            raise ValueError("limit must be between 1 and 500")
        return self._get("/api/v1/trades", params={"limit": limit})

    def _get(self, path: str, params: dict[str, Any] | None = None) -> dict[str, Any]:
        with self._client() as client:
            response = client.get(path, params=params)
            response.raise_for_status()
            payload = response.json()
            if not isinstance(payload, dict):
                raise ValueError("Freqtrade response must be a JSON object")
            return payload
