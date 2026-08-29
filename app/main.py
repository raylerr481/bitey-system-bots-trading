from fastapi import FastAPI
from pydantic import BaseModel, Field
from typing import Literal

from app.api.alpaca import router as alpaca_router
from app.api.backtest import router as backtest_router
from app.api.bot_groups import router as bot_groups_router
from app.api.demo import router as demo_router
from app.api.intelligence import router as intelligence_router
from app.api.mt5 import router as mt5_router
from app.api.strategy import router as strategy_router
from app.api.trading import router as trading_router

app = FastAPI(
    title="Bitey System Bots Trading",
    version="0.7.0",
    description=("Trading bot platform for Bitey IA. Supports demo trading, paper trading, "
                 "MT5 demo market data, bot groups and market intelligence. "
                 "Live trading remains protected and disabled by default."),
)

app.include_router(trading_router)
app.include_router(alpaca_router)
app.include_router(mt5_router)
app.include_router(strategy_router)
app.include_router(backtest_router)
app.include_router(demo_router)
app.include_router(bot_groups_router)
app.include_router(intelligence_router)

Mode = Literal["demo", "paper", "live"]
ExecutionProvider = Literal["virtual", "alpaca_paper", "mt5_demo", "mt5_live"]

class TradingConfig(BaseModel):
    mode: Mode = "demo"
    execution_provider: ExecutionProvider = "virtual"
    initial_capital: float = Field(default=10000, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)
    currency: str = Field(default="USD", min_length=3, max_length=3)
    bot_group: str | None = None

@app.get("/health")
def health():
    return {"status": "ok", "module": "bitey-system-bots-trading", "version": "0.7.0", "market_intelligence": "ready"}

@app.get("/api/v1/system")
def system():
    return {
        "module": "Bitey System Bots Trading",
        "parent": "Bitey IA",
        "sibling_module": "Bitey Trainer",
        "live_trading_enabled": False,
        "default_execution": "virtual",
        "supported_modes": ["demo", "paper"],
        "available_future_mode": "live",
        "integrations": ["TradingView webhook", "Alpaca Paper Trading", "MetaTrader 5 Demo bridge"],
        "strategies": ["sma-crossover-v1"],
        "capabilities": [
            "backtesting", "risk-controls", "paper-orders", "mt5-demo-bridge",
            "demo-trading-loop", "bot-groups", "multi-currency-display", "capital-allocation",
            "news-impact-analysis", "domino-effect-analysis", "market-regime-analysis", "opportunity-scoring",
        ],
        "supported_display_currencies": ["USD", "BRL", "EUR"],
        "live_execution_requires": [
            "explicit user authorization", "broker connection", "broker account validation",
            "risk configuration", "capital confirmation", "live-trading safety checks",
        ],
    }

@app.post("/api/v1/config/validate")
def validate_config(config: TradingConfig):
    if config.mode == "live":
        return {"valid": False, "live_trading_enabled": False,
                "reason": "Live trading is currently disabled. The configuration can be prepared, but no real order will be submitted.",
                "config": config.model_dump()}
    if config.execution_provider == "mt5_live":
        return {"valid": False, "live_trading_enabled": False,
                "reason": "MT5 live execution is disabled. Only MT5 demo/read-only market data is currently supported.",
                "config": config.model_dump()}
    if config.max_position_pct > 0.50:
        return {"valid": False, "reason": "max_position_pct cannot exceed 50% of available capital in the current safety profile.", "config": config.model_dump()}
    if config.currency.upper() not in {"USD", "BRL", "EUR"}:
        return {"valid": False, "reason": "Unsupported currency. Supported currencies are USD, BRL and EUR.", "config": config.model_dump()}
    if config.bot_group and config.bot_group not in {"conservative", "balanced", "aggressive", "capital_protection"}:
        return {"valid": False, "reason": f"Unknown bot group: {config.bot_group}", "config": config.model_dump()}
    return {"valid": True, "live_trading_enabled": False, "config": config.model_dump()}
