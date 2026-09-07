from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.quant.engine import QuantEngine, position_size

router = APIRouter(prefix="/api/v1/quant", tags=["quant"])


class QuantRequest(BaseModel):
    close: list[float] = Field(min_length=30)
    period: int = Field(default=14, ge=2, le=200)


class OhlcRequest(BaseModel):
    high: list[float] = Field(min_length=15)
    low: list[float] = Field(min_length=15)
    close: list[float] = Field(min_length=15)
    period: int = Field(default=14, ge=2, le=200)


class PositionSizeRequest(BaseModel):
    capital: float = Field(gt=0)
    risk_pct: float = Field(gt=0, le=1)
    entry: float = Field(gt=0)
    stop: float = Field(gt=0)


@router.get("/catalog")
def catalog():
    return {
        "contract": "sbt-quant-v1",
        "engine": "deterministic",
        "execution": "research-demo-paper",
        "indicators": ["SMA", "EMA", "RSI", "ATR", "MACD", "Bollinger Bands", "returns", "volatility"],
        "statistics": ["max_drawdown", "Sharpe", "Sortino"],
        "risk": ["position_size"],
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }


@router.post("/indicators")
def indicators(request: QuantRequest):
    result = QuantEngine.indicators(request.close, request.period)
    return {"contract": "sbt-quant-v1", "result": result, "research_only": True, "live": False, "real_money": False, "broker_orders": 0}


@router.post("/ohlc")
def ohlc(request: OhlcRequest):
    result = QuantEngine.ohlc_indicators(request.high, request.low, request.close, request.period)
    return {"contract": "sbt-quant-v1", "result": result, "research_only": True, "live": False, "real_money": False, "broker_orders": 0}


@router.post("/risk/position-size")
def risk_position_size(request: PositionSizeRequest):
    size = position_size(request.capital, request.risk_pct, request.entry, request.stop)
    return {"contract": "sbt-quant-v1", "position_size": size, "risk_cash": request.capital * request.risk_pct, "live": False, "real_money": False, "broker_orders": 0}
