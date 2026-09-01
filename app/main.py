from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from typing import Literal

from app.api.ai import router as ai_router
from app.api.alpaca import router as alpaca_router
from app.api.backtest import router as backtest_router
from app.api.bot_profiles import router as bot_profiles_router
from app.api.demo import router as demo_router
from app.api.mt5 import router as mt5_router
from app.api.strategy import router as strategy_router
from app.api.trading import router as trading_router

app = FastAPI(title="TradingSystemBot", version="0.7.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_credentials=False, allow_methods=["*"], allow_headers=["*"])
app.include_router(trading_router)
app.include_router(alpaca_router)
app.include_router(mt5_router)
app.include_router(strategy_router)
app.include_router(backtest_router)
app.include_router(demo_router)
app.include_router(bot_profiles_router)
app.include_router(ai_router)

Mode = Literal["demo", "paper", "live"]

class TradingConfig(BaseModel):
    mode: Mode = "demo"
    initial_capital: float = Field(default=10000, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)

@app.get("/health")
def health():
    return {"status": "ok", "module": "tradingsystembot", "version": "0.7.0"}

@app.get("/api/v1/system")
def system():
    return {
        "module": "TradingSystemBot",
        "parent": "Bitey IA",
        "live_trading_enabled": False,
        "default_execution": "alpaca_paper",
        "supported_modes": ["demo", "paper"],
        "integrations": ["TradingView webhook", "Alpaca Paper Trading", "MetaTrader 5 Demo bridge", "ChatGPT via OpenAI Responses API"],
        "strategies": ["sma-crossover-v1"],
        "capabilities": ["AI research", "backtesting", "risk-controls", "paper-orders", "mt5-demo-bridge", "demo-trading-loop", "bot-profiles", "risk-preview", "live-safety-gates", "multilingual-ui"],
    }

@app.post("/api/v1/config/validate")
def validate_config(config: TradingConfig):
    if config.mode == "live":
        return {"valid": False, "reason": "Live trading is disabled in the current milestone", "next_stage": "safety-gates"}
    return {"valid": True, "config": config.model_dump()}

# The same application can serve the Cloudflare-ready static UI when deployed as one service.
app.mount("/", StaticFiles(directory="web", html=True), name="web")
