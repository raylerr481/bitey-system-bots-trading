"""Provider registry for Bitey SBT market data.

Provider selection is fail-closed by default. Public read-only market data
must be explicitly enabled by the deployment environment; tests and local
runs must not silently acquire a market-data provider.
"""

from __future__ import annotations

import os

from .biquote import BiQuoteProvider
from .mt5 import MT5Provider
from .providers import MarketDataProvider, ProviderError


def build_provider(name: str | None = None) -> MarketDataProvider:
    selected = (name or os.getenv("SBT_MARKET_PROVIDER", "none")).strip().lower()
    if selected == "biquote":
        # BiQuote exposes public read-only market data without credentials.
        # An explicit false opt-out remains available for operators.
        if os.getenv("SBT_BIQUOTE_PUBLIC_APPROVED", "true").lower() != "true":
            raise ProviderError("BiQuote public feed disabled by SBT_BIQUOTE_PUBLIC_APPROVED")
        return BiQuoteProvider()
    if selected == "mt5":
        if not os.getenv("MT5_BRIDGE_URL", "").strip():
            raise ProviderError("MT5 demo bridge is not configured")
        return MT5Provider()
    raise ProviderError(f"No approved SBT market provider configured: {selected}")
