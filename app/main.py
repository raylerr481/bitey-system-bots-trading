from fastapi import FastAPI
from pydantic import BaseModel, Field
from typing import Literal

from app.api.alpaca import router as alpaca_router
from app.api.backtest import router as backtest_router
from app.api.bot_profiles import router as bot_profiles_router
from app.api.demo import router as demo_router
from app.api.mt5 import router as mt5_router
from app.api.strategy import router as strategy_router
from app.api.trading import router as trading_router
from app.intelligence.provider_guard import AIProvider, BillingOwner, ConnectionMode, ProviderPolicy, evaluate_provider_call

app = FastAPI(title="Bitey System Bots Trading", version="0.6.0")
app.include_router(trading_router)
app.include_router(alpaca_router)
app.include_router(mt5_router)
app.include_router(strategy_router)
app.include_router(backtest_router)
app.include_router(demo_router)
app.include_router(bot_profiles_router)

Mode = Literal["demo", "paper", "live"]

class TradingConfig(BaseModel):
    mode: Mode = "demo"
    initial_capital: float = Field(default=10000, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)

class ProviderPolicyRequest(BaseModel):
    provider: AIProvider
    model: str = Field(min_length=1, max_length=120)
    connection_mode: ConnectionMode = ConnectionMode.API
    exclusive: bool = True
    allow_paid_external: bool = False
    ask_before_paid_call: bool = True
    background_usage: bool = False
    max_spend_per_operation: float | None = Field(default=None, ge=0)
    max_spend_per_period: float | None = Field(default=None, ge=0)
    billing_owner: BillingOwner = BillingOwner.UNKNOWN
    cost_known: bool = False
    consented: bool = False
    estimated_cost: float | None = Field(default=None, ge=0)
    background: bool = False
    fallback_provider: AIProvider | None = None

@app.get("/health")
def health():
    return {"status": "ok", "module": "bitey-system-bots-trading", "version": "0.6.0"}

@app.get("/api/v1/system")
def system():
    return {
        "module": "Bitey System Bots Trading", "parent": "Bitey IA", "sibling_module": "Bitey Trainer",
        "live_trading_enabled": False, "default_execution": "alpaca_paper", "supported_modes": ["demo", "paper"],
        "integrations": ["TradingView webhook", "Alpaca Paper Trading", "MetaTrader 5 Demo bridge"],
        "strategies": ["sma-crossover-v1"],
        "capabilities": ["backtesting", "risk-controls", "paper-orders", "mt5-demo-bridge", "demo-trading-loop", "bot-profiles", "risk-preview", "live-safety-gates", "ai-provider-cost-guard", "multi-ai-provider", "tool-calling", "mcp-ready"],
        "ai_policy": {"model_agnostic": True, "supported_providers": ["bitey", "chatgpt", "claude", "gemini", "deepseek", "other"], "exclusive_provider_supported": True, "automatic_fallback_default": False, "user_pays_external_ai": True},
    }

@app.get("/api/v1/ai/providers")
def ai_providers():
    return {"providers": [
        {"id": "bitey", "name": "Bitey Trading Intelligence", "connection_modes": ["api"]},
        {"id": "chatgpt", "name": "ChatGPT / OpenAI", "connection_modes": ["api", "direct_user"]},
        {"id": "claude", "name": "Claude / Anthropic", "connection_modes": ["api", "mcp", "direct_user"]},
        {"id": "gemini", "name": "Gemini / Google", "connection_modes": ["api", "direct_user"]},
        {"id": "deepseek", "name": "DeepSeek", "connection_modes": ["api", "direct_user"]},
        {"id": "other", "name": "Other supported provider", "connection_modes": ["api", "mcp", "direct_user", "other"]},
    ], "note": "External provider usage is authorized by the user and is not silently paid by Bitey."}

@app.get("/api/v1/tools/catalog")
def tools_catalog():
    return {"transports": [
        {"id": "api", "description": "REST/HTTP APIs and broker/exchange APIs"},
        {"id": "mcp", "description": "Model Context Protocol tool servers"},
        {"id": "function_calling", "description": "Structured model function/tool calls executed by SBT"},
        {"id": "webhook", "description": "Webhooks such as TradingView"},
        {"id": "sdk", "description": "Official broker/exchange SDKs"},
        {"id": "cli", "description": "Local command-line/terminal tools when explicitly authorized"},
    ], "execution_boundary": "AI proposes tool calls; SBT validates parameters and Risk Gate before trading actions."}

@app.post("/api/v1/config/validate")
def validate_config(config: TradingConfig):
    if config.mode == "live":
        return {"valid": False, "reason": "Live trading is disabled in the current milestone", "next_stage": "safety-gates"}
    return {"valid": True, "config": config.model_dump()}

@app.post("/api/v1/ai/provider-policy/evaluate")
def evaluate_provider_policy(request: ProviderPolicyRequest):
    policy = ProviderPolicy(**request.model_dump(exclude={"estimated_cost", "background", "fallback_provider"}))
    return evaluate_provider_call(policy, estimated_cost=request.estimated_cost, background=request.background, fallback_provider=request.fallback_provider).model_dump()
