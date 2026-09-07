from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.pipeline import run_pipeline

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-bot-v1","languages":["python","mql5","pine","typescript"],"steps":["specify","quant","backtest","stress-test","risk-gate","virtual-validation","generate"],"live":False,"real_money":False,"broker_orders":0}

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
