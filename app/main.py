from fastapi import FastAPI
from pydantic import BaseModel, Field
from typing import Literal

app = FastAPI(title="Bitey System Bots Trading", version="0.1.0")

Mode = Literal["demo", "paper", "live"]


class TradingConfig(BaseModel):
    mode: Mode = "demo"
    initial_capital: float = Field(default=10000, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)


@app.get("/health")
def health():
    return {"status": "ok", "module": "bitey-system-bots-trading", "version": "0.1.0"}


@app.get("/api/v1/system")
def system():
    return {
        "module": "Bitey System Bots Trading",
        "parent": "Bitey IA",
        "sibling_module": "Bitey Trainer",
        "live_trading_enabled": False,
        "supported_modes": ["demo", "paper", "live"],
    }


@app.post("/api/v1/config/validate")
def validate_config(config: TradingConfig):
    # Live mode is deliberately rejected in the first milestone.
    if config.mode == "live":
        return {"valid": False, "reason": "Live trading is disabled in v0.1.0"}
    return {"valid": True, "config": config.model_dump()}
