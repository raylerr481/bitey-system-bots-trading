"""Provider registry for Bitey SBT market data.

Provider activation is explicit. No external provider is selected implicitly,
and the SDK has no synthetic-data fallback.
"""

from __future__ import annotations

import os

from .biquote import BiQuoteProvider
from .providers import MarketDataProvider, ProviderError


def build_provider(name: str | None = None) -> MarketDataProvider:
    selected = (name or os.getenv("SBT_MARKET_PROVIDER", "mt5")).strip().lower()
    if selected == "biquote":
        if os.getenv("SBT_BIQUOTE_PUBLIC_APPROVED", "false").lower() != "true":
            raise ProviderError("BiQuote is installed but not approved for public SBT display")
        return BiQuoteProvider()
    raise ProviderError(f"No approved SBT market provider configured: {selected}")
