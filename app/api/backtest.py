from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.backtest import run_backtest

router = APIRouter(prefix="/api/v1/backtest", tags=["backtest"])


class BacktestRequest(BaseModel):
    prices: list[float] = Field(min_length=2)
    initial_capital: float = Field(default=10_000, gt=0)
    fast_window: int = Field(default=10, ge=2)
    slow_window: int = Field(default=30, ge=3)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)


def crossover_signal(prices: list[float], i: int, fast: int, slow: int) -> str:
    if i < slow:
        return "hold"
    fast_now = sum(prices[i-fast+1:i+1]) / fast
    slow_now = sum(prices[i-slow+1:i+1]) / slow
    fast_prev = sum(prices[i-fast:i]) / fast
    slow_prev = sum(prices[i-slow:i]) / slow
    if fast_prev <= slow_prev and fast_now > slow_now:
        return "buy"
    if fast_prev >= slow_prev and fast_now < slow_now:
        return "sell"
    return "hold"


@router.post("")
def backtest(request: BacktestRequest):
    result = run_backtest(
        request.prices,
        lambda prices, i: crossover_signal(
            prices, i, request.fast_window, request.slow_window
        ),
        initial_capital=request.initial_capital,
        fee_pct=request.fee_pct,
    )
    return {"strategy": "sma-crossover-v1", **result.__dict__}
