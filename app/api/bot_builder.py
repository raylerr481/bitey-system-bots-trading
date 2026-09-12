from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.pipeline import run_pipeline
from app.bot_builder.generator import generate_candidates
from app.bot_builder.batch import rank_candidates
from app.bot_builder.ar001 import ar001_spec, size_staged_entries, evaluate_ar001_evidence, backtest_ar001_ohlc
from app.bot_builder.ar001_evidence import run_ar001_ohlc_evidence
from app.bot_builder.ar002 import ar002_spec, detect_liquidity_events, liquidity_signal_backtest

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-bot-v1","languages":["python","mql5","pine","typescript"],"steps":["specify","generate","quant","batch-backtest","rank","stress-test","risk-gate","virtual-validation","generate-code"],"hypotheses":["AR-001","AR-002"],"live":False,"real_money":False,"broker_orders":0}

class GenerateRequest(BaseModel):
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    timeframe: str = Field(default="M5", min_length=2, max_length=8)
    max_candidates: int = Field(default=100, ge=1, le=5000)
    directions: list[str] = Field(default_factory=lambda: ["long", "short"], min_length=1, max_length=2)

@router.post("/generate")
def generate(request: GenerateRequest):
    candidates = generate_candidates(request.symbol, request.timeframe, request.max_candidates, tuple(request.directions))
    return {"contract":"sbt-strategy-generation-v1","mode":"deterministic-candidate-generation","symbol":request.symbol,"timeframe":request.timeframe,"count":len(candidates),"candidates":[candidate.model_dump() for candidate in candidates],"safety":{"live":False,"real_money":False,"broker_orders":0},"next_stage":"backtest-and-rank"}

class BatchBacktestRequest(BaseModel):
    candidates: list[BotSpecification] = Field(min_length=1, max_length=5000)
    prices: list[float] = Field(min_length=30, max_length=10000)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)
    top_n: int = Field(default=20, ge=1, le=100)

@router.post("/batch-backtest")
def batch_backtest(request: BatchBacktestRequest):
    ranked = rank_candidates(request.candidates, request.prices, request.fee_pct, request.top_n)
    return {"contract":"sbt-batch-backtest-v1","mode":"research-ranking","candidate_count":len(request.candidates),"returned":len(ranked),"ranking":ranked,"safety":{"live":False,"real_money":False,"broker_orders":0},"next_stage":"robustness-oos-monte-carlo-walk-forward"}

@router.get("/hypotheses/ar-001")
def get_ar001(): return ar001_spec()
@router.get("/hypotheses/ar-002")
def get_ar002(): return ar002_spec()

class AR001SizingRequest(BaseModel):
    capital: float = Field(default=10000, gt=0)
    risk_pct: float = Field(default=0.01, gt=0, le=0.05)
    entries: list[float] = Field(min_length=3, max_length=3)
    stop: float = Field(gt=0)
    weights: list[float] | None = Field(default=None, min_length=3, max_length=3)
    point_value: float = Field(default=1.0, gt=0)

@router.post("/hypotheses/ar-001/size")
def size_ar001(request: AR001SizingRequest): return size_staged_entries(request.capital, request.risk_pct, request.entries, request.stop, request.weights, request.point_value)

class AR001EvidenceRequest(BaseModel):
    r_multiples: list[float] = Field(min_length=1, max_length=100000)
    oos_start: int | None = Field(default=None, ge=1)
    stress_results: list[float] = Field(default_factory=list, max_length=1000)
    risk_sizing_ok: bool = True
    bootstrap_samples: int = Field(default=2000, ge=2000, le=100000)

@router.post("/hypotheses/ar-001/evaluate")
def evaluate_ar001(request: AR001EvidenceRequest): return evaluate_ar001_evidence(request.r_multiples, request.oos_start, request.stress_results, request.risk_sizing_ok, request.bootstrap_samples)

class AR001OHLCRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=30, max_length=100000)
    initial_capital: float = Field(default=10000, gt=0)
    risk_pct: float = Field(default=0.01, gt=0, le=0.05)
    atr_period: int = Field(default=14, ge=2, le=200)
    entry_multipliers: list[float] | None = Field(default=None, min_length=3, max_length=3)
    stop_atr: float = Field(default=4.0, gt=0)
    take_profit_r: float = Field(default=3.0, gt=0)
    direction: str = Field(default="long", pattern="^(long|short)$")
    fee_bps: float = Field(default=1.0, ge=0, le=1000)
    slippage_bps: float = Field(default=1.0, ge=0, le=1000)
    weights: list[float] | None = Field(default=None, min_length=3, max_length=3)
    point_value: float = Field(default=1.0, gt=0)
    max_bars_per_trade: int = Field(default=250, ge=1, le=5000)

@router.post("/hypotheses/ar-001/backtest")
def backtest_ar001(request: AR001OHLCRequest): return backtest_ar001_ohlc(**request.model_dump())

class AR001EvidenceOHLCRequest(AR001OHLCRequest):
    oos_start: int | None = Field(default=None, ge=1)
    bootstrap_samples: int = Field(default=2000, ge=2000, le=100000)

@router.post("/hypotheses/ar-001/backtest/evidence")
def backtest_ar001_evidence(request: AR001EvidenceOHLCRequest): return run_ar001_ohlc_evidence(**request.model_dump())

class AR002EventStudyRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=30, max_length=10000)
    horizon: int = Field(default=5, ge=1, le=100)

@router.post("/hypotheses/ar-002/detect")
def detect_ar002(request: AR002EventStudyRequest): return {"contract":"sbt-ar002-detection-v1","hypothesis_id":"AR-002","events":detect_liquidity_events(request.bars),"data_mode":"OHLCV_proxy","safety":{"live":False,"real_money":False,"broker_orders":0}}
@router.post("/hypotheses/ar-002/test")
def test_ar002(request: AR002EventStudyRequest): return liquidity_signal_backtest(request.bars, request.horizon)
@router.post("/build")
def build(spec: BotSpecification): return build_bot(spec)

class BacktestBuildRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=3, max_length=10000)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)

@router.post("/backtest")
def backtest_build(request: BacktestBuildRequest): return run_spec_backtest(request.specification, request.prices, request.fee_pct)

class PipelineRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=30, max_length=10000)

@router.post("/run")
def run(request: PipelineRequest): return run_pipeline(request.specification, request.prices)
