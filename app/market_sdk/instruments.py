"""Provider-neutral instrument catalog for Bitey SBT.

The catalog describes SBT's supported market classes and safe symbol aliases.
It is not a claim that live prices or candles are available for every symbol.
Actual availability must still be confirmed by the active provider.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict


SUPPORTED_TIMEFRAMES = ("M1", "M5", "M15", "M30", "H1", "H4", "D1")


@dataclass(frozen=True)
class Instrument:
    symbol: str
    name: str
    asset_class: str
    quote_currency: str | None = None
    exchange: str | None = None
    providers: tuple[str, ...] = ()
    supported_timeframes: tuple[str, ...] = SUPPORTED_TIMEFRAMES
    availability: str = "provider-dependent"

    def as_dict(self) -> dict:
        value = asdict(self)
        value["providers"] = list(self.providers)
        value["supported_timeframes"] = list(self.supported_timeframes)
        return value


# Canonical research universe. These entries are aliases/configuration, not
# fabricated market data and not proof that a provider currently serves them.
INSTRUMENTS: tuple[Instrument, ...] = (
    Instrument("EURUSD", "Euro / US Dollar", "forex", "USD"),
    Instrument("GBPUSD", "British Pound / US Dollar", "forex", "USD"),
    Instrument("USDJPY", "US Dollar / Japanese Yen", "forex", "JPY"),
    Instrument("AUDUSD", "Australian Dollar / US Dollar", "forex", "USD"),
    Instrument("USDCAD", "US Dollar / Canadian Dollar", "forex", "CAD"),
    Instrument("USDCHF", "US Dollar / Swiss Franc", "forex", "CHF"),
    Instrument("BTCUSD", "Bitcoin / US Dollar", "crypto", "USD"),
    Instrument("ETHUSD", "Ether / US Dollar", "crypto", "USD"),
    Instrument("XAUUSD", "Gold / US Dollar", "commodity", "USD"),
    Instrument("XAGUSD", "Silver / US Dollar", "commodity", "USD"),
    Instrument("US500", "US 500 Index", "index", "USD"),
    Instrument("NAS100", "US Tech 100 Index", "index", "USD"),
    Instrument("US30", "US 30 Index", "index", "USD"),
    Instrument("GER40", "Germany 40 Index", "index", "EUR"),
    Instrument("UK100", "UK 100 Index", "index", "GBP"),
    Instrument("AAPL", "Apple", "stock", "USD"),
    Instrument("MSFT", "Microsoft", "stock", "USD"),
    Instrument("NVDA", "NVIDIA", "stock", "USD"),
    Instrument("AMZN", "Amazon", "stock", "USD"),
    Instrument("SPY", "SPDR S&P 500 ETF", "etf", "USD"),
    Instrument("QQQ", "Invesco QQQ ETF", "etf", "USD"),
)


def list_instruments(asset_class: str | None = None) -> list[Instrument]:
    if not asset_class or asset_class.lower() == "all":
        return list(INSTRUMENTS)
    key = asset_class.strip().lower()
    return [item for item in INSTRUMENTS if item.asset_class == key]


def asset_classes() -> list[str]:
    return sorted({item.asset_class for item in INSTRUMENTS})
