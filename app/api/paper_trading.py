from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.paper_trading import PaperConfig, simulate_signal

router = APIRouter(prefix="/api/v1/sbt/paper", tags=["paper-trading"])


class PaperSignalRequest(BaseModel):
    action: str = Field(min_length=1, max_length=10)
    entry: float = Field(gt=0)
    stop: float = Field(gt=0)
    target: float = Field(gt=0)
    confidence: float = Field(default=0.0, ge=0.0, le=1.0)
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    strategy_version: str = Field(default="research-v1", min_length=1, max_length=80)
    initial_capital: float = Field(default=10000.0, gt=0)
    risk_per_trade: float = Field(default=0.005, gt=0, le=0.02)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    fee_rate: float = Field(default=0.0005, ge=0, le=0.1)
    slippage_bps: float = Field(default=2.0, ge=0, le=1000)


@router.post("/simulate")
def simulate(request: PaperSignalRequest):
    result = simulate_signal(
        request.model_dump(),
        PaperConfig(
            initial_capital=request.initial_capital,
            fee_rate=request.fee_rate,
            slippage_bps=request.slippage_bps,
            risk_per_trade=request.risk_per_trade,
            max_position_pct=request.max_position_pct,
        ),
    )
    result["symbol"] = request.symbol.upper()
    result["strategy_version"] = request.strategy_version
    result["ai_confidence"] = request.confidence
    result["ai_can_bypass_risk_gate"] = False
    return result
