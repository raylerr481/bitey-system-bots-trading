from __future__ import annotations

from typing import Literal
from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/bot-exchange", tags=["bot-exchange"])

Transport = Literal["api", "mcp", "websocket", "webhook", "sdk", "file"]

PLUGINS = [
    {"id": "bitey-sbt-native", "name": "Bitey SBT", "direction": "bidirectional", "transports": ["api", "mcp", "websocket"]},
    {"id": "bitey-ia", "name": "Bitey IA", "direction": "bidirectional", "transports": ["api", "mcp"]},
    {"id": "mt5", "name": "MetaTrader 5", "direction": "bidirectional", "transports": ["api", "websocket"]},
    {"id": "alpaca", "name": "Alpaca", "direction": "bidirectional", "transports": ["api", "sdk"]},
    {"id": "tradingview", "name": "TradingView", "direction": "bidirectional", "transports": ["webhook", "api"]},
    {"id": "generic-mcp", "name": "Cualquier servidor MCP compatible", "direction": "bidirectional", "transports": ["mcp"]},
    {"id": "generic-api", "name": "Cualquier API autorizada", "direction": "bidirectional", "transports": ["api", "webhook"]},
]

class BotManifest(BaseModel):
    bot_id: str = Field(min_length=1, max_length=120)
    name: str = Field(min_length=1, max_length=120)
    version: str = Field(default="1.0.0", min_length=1, max_length=32)
    strategy: str = Field(min_length=1, max_length=120)
    instruments: list[str] = Field(default_factory=list, max_length=50)
    timeframes: list[str] = Field(default_factory=list, max_length=20)
    parameters: dict = Field(default_factory=dict)
    risk_rules: dict = Field(default_factory=dict)
    validation: dict = Field(default_factory=dict)
    allowed_modes: list[str] = Field(default_factory=lambda: ["research", "backtest", "demo", "paper"])

class TransferRequest(BaseModel):
    bot: BotManifest
    source: str = Field(min_length=1, max_length=120)
    destination: str = Field(min_length=1, max_length=120)
    transport: Transport = "api"
    direction: Literal["export", "import"] = "export"

@router.get("/catalog")
def catalog():
    return {
        "contract": "bitey-bot-exchange-v1",
        "mode": "free-first",
        "plugins": PLUGINS,
        "directions": ["Bitey IA -> SBT", "SBT -> Bitey IA", "SBT <-> external AI", "SBT <-> platform"],
        "billing": {"automatic": False, "paid_calls_without_consent": False, "priority": ["local", "open-source", "free-tier"]},
        "real_money": False,
    }

@router.post("/manifest")
def manifest(bot: BotManifest):
    return {
        "contract": "bitey-bot-exchange-v1",
        "bot": bot.model_dump(),
        "portable": True,
        "execution": {"research": True, "backtest": True, "demo": True, "paper": True, "real": False, "risk_gate": "mandatory"},
    }

@router.post("/transfer")
def transfer(request: TransferRequest):
    if request.source == request.destination:
        return {"accepted": False, "reason": "source_and_destination_must_differ"}
    if request.direction == "export" and request.destination == "live":
        return {"accepted": False, "reason": "real_money_execution_is_disabled"}
    return {
        "accepted": True,
        "contract": "bitey-bot-exchange-v1",
        "direction": request.direction,
        "source": request.source,
        "destination": request.destination,
        "transport": request.transport,
        "bot": request.bot.model_dump(),
        "execution": {"order_created": False, "real_money": False, "risk_gate": "mandatory"},
    }
