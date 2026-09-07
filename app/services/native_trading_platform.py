"""Native SBT trading-platform contract.

SBT is the platform abstraction; brokers/venues and AI clients are adapters behind it.
Credentials stay on the user's side. Real execution remains explicitly gated.
"""

from typing import Any

PLATFORM = {
    "id": "bitey-sbt-native",
    "name": "Bitey SBT Trading Platform",
    "version": "sbt-platform-v1",
    "market_data": {"quotes": True, "candles": True, "streaming": True},
    "ai": {"api": True, "mcp": True, "tool_calling": True, "local_ai": True},
    "bots": {"create": True, "validate": True, "backtest": True, "demo": True, "paper": True, "deploy": True, "export": True, "import": True},
    "connectivity": {"bidirectional": True, "api": True, "mcp": True, "websocket": True, "webhook": True},
    "execution": {"real_money": False, "risk_gate_required": True},
}

# External execution/market adapters. They never become the SBT authority.
PLATFORM_ADAPTERS = [
    {"id": "mt5", "name": "MetaTrader 5", "role": "broker/terminal adapter", "market_data": True, "demo": True, "paper": False, "real": False, "bidirectional": True},
    {"id": "alpaca", "name": "Alpaca", "role": "broker API adapter", "market_data": True, "demo": False, "paper": True, "real": False, "bidirectional": True},
    {"id": "tradingview", "name": "TradingView", "role": "analysis/alerts adapter", "market_data": True, "demo": False, "paper": True, "real": False, "bidirectional": True},
    {"id": "webhook-generic", "name": "Generic Webhook", "role": "portable signal/event adapter", "market_data": False, "demo": True, "paper": True, "real": False, "bidirectional": True},
    {"id": "api-generic", "name": "Generic REST API", "role": "portable bot/signal adapter", "market_data": True, "demo": True, "paper": True, "real": False, "bidirectional": True},
]

# Zero-cost/local AI connectivity. SBT does not silently pay for inference.
AI_ADAPTERS = [
    {"id": "ollama", "name": "Ollama", "transport": "local-api", "cost_policy": "user-hosted", "bidirectional": True},
    {"id": "lm-studio", "name": "LM Studio", "transport": "local-api", "cost_policy": "user-hosted", "bidirectional": True},
    {"id": "mcp-local", "name": "Local MCP Server", "transport": "mcp", "cost_policy": "free/open", "bidirectional": True},
    {"id": "openai-compatible-local", "name": "OpenAI-compatible local endpoint", "transport": "api", "cost_policy": "user-hosted", "bidirectional": True},
]


def platform_capabilities() -> dict[str, Any]:
    return {"platform": PLATFORM, "adapters": PLATFORM_ADAPTERS, "ai_adapters": AI_ADAPTERS}


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
