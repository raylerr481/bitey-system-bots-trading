"""Native SBT trading-platform contract.

SBT is the platform abstraction; brokers/venues are adapters behind it.
No broker credentials are stored here. Real execution stays explicitly gated.
"""

from typing import Any

PLATFORM = {
    "id": "bitey-sbt-native",
    "name": "Bitey SBT Trading Platform",
    "version": "sbt-platform-v1",
    "market_data": {"quotes": True, "candles": True, "streaming": True},
    "ai": {"api": True, "mcp": True, "tool_calling": True},
    "bots": {"create": True, "validate": True, "backtest": True, "demo": True, "paper": True, "deploy": True},
    "execution": {"real_money": False, "risk_gate_required": True},
}

PLATFORM_ADAPTERS = [
    {"id": "mt5", "name": "MetaTrader 5", "role": "broker/terminal adapter", "market_data": True, "demo": True, "paper": False, "real": False},
    {"id": "alpaca", "name": "Alpaca", "role": "broker API adapter", "market_data": True, "demo": False, "paper": True, "real": False},
    {"id": "tradingview", "name": "TradingView", "role": "analysis/alerts adapter", "market_data": True, "demo": False, "paper": True, "real": False},
]


def platform_capabilities() -> dict[str, Any]:
    return {"platform": PLATFORM, "adapters": PLATFORM_ADAPTERS}


def build_chart_contract(symbol: str, timeframe: str = "M1") -> dict[str, Any]:
    return {
        "contract": "sbt-chart-v1",
        "symbol": symbol.upper(),
        "timeframe": timeframe.upper(),
        "stream": f"/api/v1/market/stream/{symbol.upper()}",
        "quote": f"/api/v1/market/quote/{symbol.upper()}",
        "candles": f"/api/v1/market/candles/{symbol.upper()}?timeframe={timeframe.upper()}",
        "source_authority": "SBT market gateway",
        "live_trading": False,
    }
