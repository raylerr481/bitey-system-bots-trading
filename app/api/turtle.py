from __future__ import annotations

from typing import Any

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.turtle.controller import TurtleController

router = APIRouter(prefix="/api/v1/turtle", tags=["turtle-controller"])
_controller = TurtleController()


class TurtleSnapshot(BaseModel):
    status: str = "RUNNING"
    mode: str = "DEMO"
    symbol: str = ""
    timeframe: str = ""
    regime: str = "UNKNOWN"
    signal: str = "NONE"
    position_count: int = Field(default=0, ge=0)
    risk_pct: float = Field(default=0.25, ge=0)
    drawdown_pct: float = Field(default=0, ge=0)
    last_trade_pnl: float | None = None
    market: dict[str, Any] = Field(default_factory=dict)


class TurtleTrade(BaseModel):
    pnl: float
    metadata: dict[str, Any] = Field(default_factory=dict)


class TurtleEvaluation(BaseModel):
    metrics: dict[str, Any] = Field(default_factory=dict)


@router.get("/status")
def turtle_status():
    return _controller.status()


@router.post("/observe")
def turtle_observe(snapshot: TurtleSnapshot):
    return _controller.observe(snapshot.model_dump())


@router.post("/trade")
def turtle_trade(trade: TurtleTrade):
    _controller.record_trade(trade.pnl, trade.metadata)
    return _controller.status()


@router.post("/evaluate")
def turtle_evaluate(evaluation: TurtleEvaluation):
    return _controller.evaluate_learning(evaluation.metrics)


@router.get("/capabilities")
def turtle_capabilities():
    return {
        "controller": "Turtle Controller",
        "read_status": True,
        "observe_mt4_snapshot": True,
        "record_trade": True,
        "learning_evaluation": True,
        "automatic_live_parameter_change": False,
        "requires_backtest_before_change": True,
        "risk_gate_authoritative": True,
        "execution_modes": ["DEMO", "PAPER"],
    }
