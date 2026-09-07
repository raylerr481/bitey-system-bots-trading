from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.strategies.technical import TechnicalSignalRequest, technical_signal, EmaRsiAtrRequest, ema_rsi_atr_signal
from app.strategies.smc import SMCSignalRequest, smc_signal
from app.risk.engine import RiskEngine

router = APIRouter(prefix="/api/v1/strategy", tags=["strategy"])

STRATEGIES = [
    {"id": "sma-crossover-v1", "name": "SMA Crossover", "type": "technical", "status": "active", "execution": "research-demo-paper", "live_enabled": False},
    {"id": "ema-rsi-atr-v1", "name": "EMA + RSI + ATR", "type": "technical", "status": "active", "execution": "research-demo-paper", "live_enabled": False},
    {"id": "smc-v1", "name": "Smart Money Concepts", "type": "structure", "status": "active", "execution": "research-demo-paper", "live_enabled": False},
]


@router.get("/registry")
def registry():
    return {"contract": "sbt-strategy-registry-v1", "strategies": STRATEGIES, "live_trading_enabled": False}


class RiskGateRequest(BaseModel):
    capital: float = Field(gt=0)
    notional: float = Field(gt=0)
    daily_pnl: float = 0.0
    symbol: str = "EURUSD"
    quantity: float | None = Field(default=None, ge=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=1)


@router.post("/risk-gate/evaluate")
def risk_gate(request: RiskGateRequest):
    engine = RiskEngine(
        max_position_pct=request.max_position_pct,
        max_daily_loss_pct=request.max_daily_loss_pct,
        allowed_symbols={"EURUSD"},
    )
    decision = engine.approve(
        capital=request.capital,
        notional=request.notional,
        daily_pnl=request.daily_pnl,
        symbol=request.symbol.upper(),
        quantity=request.quantity,
    )
    return {
        "contract": "sbt-risk-gate-v1",
        "allowed": decision.allowed,
        "reason": decision.reason,
        "authoritative": True,
        "live_trading_enabled": False,
        "real_money": False,
        "broker_orders": 0,
    }


@router.get("/risk-gate/status")
def risk_gate_status():
    return {
        "contract": "sbt-risk-gate-v1",
        "status": "active",
        "authoritative": True,
        "live_trading_enabled": False,
        "real_money": False,
        "broker_orders": 0,
        "controls": ["allowed_symbol", "max_position_pct", "max_daily_loss_pct"],
    }


@router.post("/signal")
def signal(request: TechnicalSignalRequest):
    return technical_signal(request)


@router.post("/ema-rsi-atr")
def ema_rsi_atr(request: EmaRsiAtrRequest):
    return ema_rsi_atr_signal(request)


@router.post("/smc")
def smc(request: SMCSignalRequest):
    return smc_signal(request)
