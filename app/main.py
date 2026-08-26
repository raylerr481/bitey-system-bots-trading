from fastapi import FastAPI
from pydantic import BaseModel, Field
from typing import Literal

from app.api.alpaca import router as alpaca_router
from app.api.backtest import router as backtest_router
from app.api.strategy import router as strategy_router
from app.api.trading import router as trading_router

app = FastAPI(title="Bitey System Bots Trading", version="0.4.0")
app.include_router(trading_router)
app.include_router(alpaca_router)
app.include_router(strategy_router)
app.include_router(backtest_router)

Mode = Literal["demo", "paper", "live"]


class TradingConfig(BaseModel):
    mode: Mode = "demo"
    initial_capital: float = Field(default=10000, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)


@app.get("/health")
def health():
    return {"status": "ok", "module": "bitey-system-bots-trading", "version": "0.4.0"}


@app.get("/api/v1/system")
def system():
    return {
        "module": "Bitey System Bots Trading",
        "parent": "Bitey IA",
        "sibling_module": "Bitey Trainer",
        "live_trading_enabled": False,
        "default_execution": "alpaca_paper",
        "supported_modes": ["demo", "paper"],
        "integrations": ["TradingView webhook", "Alpaca Paper Trading"],
        "strategies": ["sma-crossover-v1"],
        "capabilities": ["backtesting", "risk-controls", "paper-orders"],
    }


@app.post("/api/v1/config/validate")
def validate_config(config: TradingConfig):
    if config.mode == "live":
        return {"valid": False, "reason": "Live trading is disabled in the current milestone"}
    return {"valid": True, "config": config.model_dump()}
