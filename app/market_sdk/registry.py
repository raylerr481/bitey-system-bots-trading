"""Provider registry for Bitey SBT market data.

Provider activation is explicit. No external provider is selected implicitly,
and the SDK has no synthetic-data fallback.
"""

from __future__ import annotations

import os

from .biquote import BiQuoteProvider
from .mt5 import MT5Provider
from .providers import MarketDataProvider, ProviderError


def build_provider(name: str | None = None) -> MarketDataProvider:
    selected = (name or os.getenv("SBT_MARKET_PROVIDER", "none")).strip().lower()
    if selected == "biquote":
        if os.getenv("SBT_BIQUOTE_PUBLIC_APPROVED", "false").lower() != "true":
            raise ProviderError("BiQuote is installed but not approved for public SBT display")
        return BiQuoteProvider()
    if selected == "mt5":
        if not os.getenv("MT5_BRIDGE_URL", "").strip():
            raise ProviderError("MT5 demo bridge is not configured")
        return MT5Provider()
    raise ProviderError(f"No approved SBT market provider configured: {selected}")
