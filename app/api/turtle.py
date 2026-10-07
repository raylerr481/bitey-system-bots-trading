from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.turtle.controller import get_turtle_controller
from app.turtle.readiness import TurtleReadinessEngine

router = APIRouter(prefix="/api/v1/turtle", tags=["turtle-controller"])
_controller = get_turtle_controller()
_readiness = TurtleReadinessEngine()


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


class TurtleExecutionMode(BaseModel):
    mode: str = Field(pattern=r"^(DEMO|PAPER|LIVE)$")


@router.get("/execution-mode")
def turtle_execution_mode():
    state = _controller.status()
    return {
        "mode": state["mode"],
        "demo_execution_enabled": state["mode"] == "DEMO",
        "paper_execution_enabled": state["mode"] == "PAPER",
        "live_execution_enabled": False,
        "live_locked": True,
        "account_guard_required": True,
        "message": "DEMO/PAPER may be prepared; LIVE remains permanently locked in this controller."
    }


@router.post("/execution-mode")
def set_turtle_execution_mode(request: TurtleExecutionMode):
    mode = request.mode.upper()
    if mode == "LIVE":
        raise HTTPException(status_code=403, detail="LIVE execution is locked. Real-money execution requires a separate explicit production authorization layer.")
    _controller.state.mode = mode
    return turtle_execution_mode()


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


@router.post("/readiness/evaluate")
def turtle_readiness_evaluate(evaluation: TurtleEvaluation):
    return _readiness.evaluate(evaluation.metrics, mode=_controller.state.mode)


@router.get("/readiness")
def turtle_readiness_status():
    return _readiness.evaluate({}, mode=_controller.state.mode)


@router.get("/demo-multiplier")
def demo_multiplier_status():
    return _controller.demo_multiplier_status()


@router.post("/demo-multiplier/select")
def select_demo_multiplier(evaluation: TurtleEvaluation):
    return _controller.select_demo_multiplier(evaluation.metrics)


@router.get("/capabilities")
@router.get("/context")
def turtle_context():
    """Stable, compact read model for external cognitive clients such as Bitey IA."""
    state = _controller.status()
    # Import locally to avoid a module-level circular dependency: app.api.mt4
    # synchronizes snapshots into this controller.
    from app.api.mt4 import _latest
    return {
        "source": "Bitey System Bots Trading",
        "controller": state["controller"],
        "observed": bool(state["symbol"]),
        "state": state,
        "mt4_snapshot": _latest,
        "evidence_class": "MT4_LIVE_SNAPSHOT" if _latest else "NO_EVIDENCE",
        "execution_authority": "SBT_RISK_GATE",
        "live_parameter_change": False,
        "execution_enabled": False,
    }



def update_from_mt4(payload: dict[str, Any]) -> dict[str, Any]:
    """Synchronize a validated MT4 live snapshot into the shared Turtle Controller.

    Only explicit MT4 fields are consumed; missing values use safe controller
    defaults and are never inferred from unrelated strategy scores.
    """
    metrics = payload.get("metrics") or {}
    account = payload.get("account") or {}

    signal = payload.get("signal") or metrics.get("signal") or "NONE"
    position_count = account.get("position_count", payload.get("position_count", 0))
    risk_pct = account.get("risk_pct", payload.get("risk_pct", 0.25))
    drawdown_pct = account.get("drawdown_pct", payload.get("drawdown_pct", 0.0))
    last_trade_pnl = account.get("last_trade_pnl", payload.get("last_trade_pnl"))
    turtle = payload.get("turtle") or payload.get("turtle_controller") or {}
    market = payload.get("market") or {}

    snapshot = {
        "status": payload.get("status") or "RUNNING",
        "mode": payload.get("mode") or "DEMO",
        "symbol": payload.get("symbol") or "",
        "timeframe": payload.get("timeframe") or "",
        "regime": payload.get("regime") or "UNKNOWN",
        "signal": signal,
        "position_count": position_count,
        "risk_pct": risk_pct,
        "drawdown_pct": drawdown_pct,
        "last_trade_pnl": last_trade_pnl,
        "market": market,
        "last_entry": turtle.get("last_entry"),
        "campaign_n": turtle.get("campaign_n"),
        "s1_skip_next": turtle.get("s1_skip_next"),
        "s1_skip_latched": turtle.get("s1_skip_latched"),
    }
    return _controller.observe(snapshot)


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
        "execution_modes": ["DEMO", "PAPER", "LIVE_LOCKED"],
        "demo_execution_gate": True,
        "live_execution_gate": False,
    }
