from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.pipeline import run_pipeline
from app.bot_builder.ar001 import ar001_spec, size_staged_entries

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-bot-v1","languages":["python","mql5","pine","typescript"],"steps":["specify","quant","backtest","stress-test","risk-gate","virtual-validation","generate"],"hypotheses":["AR-001"],"live":False,"real_money":False,"broker_orders":0}

@router.get("/hypotheses/ar-001")
def get_ar001():
    return ar001_spec()

class AR001SizingRequest(BaseModel):
    capital: float = Field(default=10000, gt=0)
    risk_pct: float = Field(default=0.01, gt=0, le=0.05)
    entries: list[float] = Field(min_length=3, max_length=3)
    stop: float = Field(gt=0)
    weights: list[float] | None = Field(default=None, min_length=3, max_length=3)
    point_value: float = Field(default=1.0, gt=0)

@router.post("/hypotheses/ar-001/size")
def size_ar001(request: AR001SizingRequest):
    return size_staged_entries(request.capital, request.risk_pct, request.entries, request.stop, request.weights, request.point_value)

@router.post("/build")
def build(spec: BotSpecification):
    return build_bot(spec)

class BacktestBuildRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=3, max_length=10000)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)

@router.post("/backtest")
def backtest_build(request: BacktestBuildRequest):
    return run_spec_backtest(request.specification, request.prices, request.fee_pct)

class PipelineRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=30, max_length=10000)

@router.post("/run")
def run(request: PipelineRequest):
    return run_pipeline(request.specification, request.prices)
