from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.bot_builder.hypothesis import TradingHypothesis, evaluate_video_hypothesis

router = APIRouter(prefix="/api/v1/hypothesis", tags=["hypothesis"])


class HypothesisRequest(BaseModel):
    initial_capital: float = Field(default=1000.0, gt=0)
    trades_per_month: int = Field(default=10, ge=1, le=1000)
    months: int = Field(default=24, ge=1, le=240)
    win_rate: float = Field(default=0.40, ge=0, le=1)
    average_win_pct: float = Field(default=0.04, ge=0, le=1)
    average_loss_pct: float = Field(default=0.015, ge=0, le=1)
    risk_per_trade_pct: float = Field(default=0.02, gt=0, le=0.05)
    spread_cost_monthly_pct: float = Field(default=0.005, ge=0, le=1)
    slippage_cost_monthly_pct: float = Field(default=0.003, ge=0, le=1)
    swap_cost_monthly_pct: float = Field(default=0.002, ge=0, le=1)
    retain_pct: float = Field(default=0.50, ge=0, le=1)
    reserve_pct: float = Field(default=0.30, ge=0, le=1)
    local_spend_pct: float = Field(default=0.20, ge=0, le=1)


@router.get("/video")
def video_defaults():
    return evaluate_video_hypothesis(TradingHypothesis())


@router.post("/evaluate")
def evaluate(request: HypothesisRequest):
    return evaluate_video_hypothesis(TradingHypothesis(**request.model_dump()))
