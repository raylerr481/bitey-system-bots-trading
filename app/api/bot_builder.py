from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.pipeline import run_pipeline
from app.bot_builder.generator import generate_candidates
from app.bot_builder.batch import rank_candidates
from app.bot_builder.robustness import robustness_report, oos_test, parameter_sensitivity, cost_stress, monte_carlo_paths, walk_forward
from app.bot_builder.ar001 import ar001_spec, size_staged_entries, evaluate_ar001_evidence, backtest_ar001_ohlc
from app.bot_builder.ar001_evidence import run_ar001_ohlc_evidence
from app.bot_builder.ar002 import ar002_spec, detect_liquidity_events, liquidity_signal_backtest
from app.strategy_discovery.engine import discover, evolve
from app.strategy_discovery.models import DiscoveryRequest, EvolutionRequest
from app.strategy_discovery.blocks import INDICATORS, OPERATORS
from app.strategy_discovery.generator import complexity_of, mutate
from app.strategy_discovery.fitness import fitness, metrics_from_result
from app.strategy_discovery.matrix import build_matrix
import random

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-bot-v1","languages":["python","mql5","pine","typescript"],"steps":["specify","generate","quant","batch-backtest","rank","robustness","oos","monte-carlo","walk-forward","stress-test","risk-gate","virtual-validation","generate-code"],"hypotheses":["AR-001","AR-002"],"live":False,"real_money":False,"broker_orders":0}

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

class ResearchRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=60, max_length=10000)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)
    monte_carlo_samples: int = Field(default=200, ge=200, le=2000)

@router.post("/robustness")
def robustness(request: ResearchRequest): return robustness_report(request.specification, request.prices, request.fee_pct, request.monte_carlo_samples)
@router.post("/oos")
def oos(request: ResearchRequest): return oos_test(request.specification, request.prices, 70.0, request.fee_pct)
@router.post("/sensitivity")
def sensitivity(request: ResearchRequest): return parameter_sensitivity(request.specification, request.prices, request.fee_pct)
@router.post("/cost-stress")
def cost_stress_endpoint(request: ResearchRequest): return cost_stress(request.specification, request.prices, request.fee_pct)
@router.post("/monte-carlo")
def monte_carlo(request: ResearchRequest): return monte_carlo_paths(request.specification, request.prices, request.fee_pct, request.monte_carlo_samples)

class WalkForwardRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=90, max_length=10000)
    train_size: int = Field(default=120, ge=30, le=2000)
    test_size: int = Field(default=60, ge=20, le=1000)
    step: int = Field(default=60, ge=1, le=1000)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)

@router.post("/walk-forward")
def walk_forward_endpoint(request: WalkForwardRequest): return walk_forward(request.specification, request.prices, request.train_size, request.test_size, request.step, request.fee_pct)
@router.get("/hypotheses/ar-001")
def get_ar001(): return ar001_spec()
@router.get("/hypotheses/ar-002")
def get_ar002(): return ar002_spec()

class AR001SizingRequest(BaseModel):
    capital: float = Field(default=10000, gt=0); risk_pct: float = Field(default=0.01, gt=0, le=0.05); entries: list[float] = Field(min_length=3, max_length=3); stop: float = Field(gt=0); weights: list[float] | None = Field(default=None, min_length=3, max_length=3); point_value: float = Field(default=1.0, gt=0)
@router.post("/hypotheses/ar-001/size")
def size_ar001(request: AR001SizingRequest): return size_staged_entries(request.capital, request.risk_pct, request.entries, request.stop, request.weights, request.point_value)

class AR001EvidenceRequest(BaseModel):
    r_multiples: list[float] = Field(min_length=1, max_length=100000); oos_start: int | None = Field(default=None, ge=1); stress_results: list[float] = Field(default_factory=list, max_length=1000); risk_sizing_ok: bool = True; bootstrap_samples: int = Field(default=2000, ge=2000, le=100000)
@router.post("/hypotheses/ar-001/evaluate")
def evaluate_ar001(request: AR001EvidenceRequest): return evaluate_ar001_evidence(request.r_multiples, request.oos_start, request.stress_results, request.risk_sizing_ok, request.bootstrap_samples)

class AR001OHLCRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=30, max_length=100000); initial_capital: float = Field(default=10000, gt=0); risk_pct: float = Field(default=0.01, gt=0, le=0.05); atr_period: int = Field(default=14, ge=2, le=200); entry_multipliers: list[float] | None = Field(default=None, min_length=3, max_length=3); stop_atr: float = Field(default=4.0, gt=0); take_profit_r: float = Field(default=3.0, gt=0); direction: str = Field(default="long", pattern="^(long|short)$"); fee_bps: float = Field(default=1.0, ge=0, le=1000); slippage_bps: float = Field(default=1.0, ge=0, le=1000); weights: list[float] | None = Field(default=None, min_length=3, max_length=3); point_value: float = Field(default=1.0, gt=0); max_bars_per_trade: int = Field(default=250, ge=1, le=5000)
@router.post("/hypotheses/ar-001/backtest")
def backtest_ar001(request: AR001OHLCRequest): return backtest_ar001_ohlc(**request.model_dump())
class AR001EvidenceOHLCRequest(AR001OHLCRequest):
    oos_start: int | None = Field(default=None, ge=1); bootstrap_samples: int = Field(default=2000, ge=2000, le=100000)
@router.post("/hypotheses/ar-001/backtest/evidence")
def backtest_ar001_evidence(request: AR001EvidenceOHLCRequest): return run_ar001_ohlc_evidence(**request.model_dump())
class AR002EventStudyRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=30, max_length=10000); horizon: int = Field(default=5, ge=1, le=100)
@router.post("/hypotheses/ar-002/detect")
def detect_ar002(request: AR002EventStudyRequest): return {"contract":"sbt-ar002-detection-v1","hypothesis_id":"AR-002","events":detect_liquidity_events(request.bars),"data_mode":"OHLCV_proxy","safety":{"live":False,"real_money":False,"broker_orders":0}}
@router.post("/hypotheses/ar-002/test")
def test_ar002(request: AR002EventStudyRequest): return liquidity_signal_backtest(request.bars, request.horizon)
@router.post("/build")
def build(spec: BotSpecification): return build_bot(spec)
class BacktestBuildRequest(BaseModel):
    specification: BotSpecification; prices: list[float] = Field(min_length=3, max_length=10000); fee_pct: float = Field(default=0.001, ge=0, lt=0.1)
@router.post("/backtest")
def backtest_build(request: BacktestBuildRequest): return run_spec_backtest(request.specification, request.prices, request.fee_pct)
class PipelineRequest(BaseModel):
    specification: BotSpecification; prices: list[float] = Field(min_length=30, max_length=10000)
@router.post("/run")
def run(request: PipelineRequest): return run_pipeline(request.specification, request.prices)

# Free Strategy Discovery: StrategyQuant-inspired workflow, implemented independently.
class DiscoveryPricesRequest(DiscoveryRequest):
    prices: list[float] = Field(min_length=30, max_length=10000)
@router.get("/strategy-discovery/catalog")
def strategy_discovery_catalog():
    return {"contract":"sbt-strategy-discovery-v1","mode":"free-deterministic-research","building_blocks":[name for name, _ in INDICATORS],"operators":list(OPERATORS),"pipeline":["generate","backtest","filter","rank","evolve","oos","cost-stress","monte-carlo","walk-forward","multi-market","multi-timeframe","portfolio","risk-gate"],"limits":{"max_candidates":1000,"max_conditions":6,"max_generations":10},"ai_role":"proposal-only; deterministic SBT engines perform validation","safety":{"live":False,"real_money":False,"broker_orders":0}}
@router.post("/strategy-discovery/generate")
def strategy_discovery_generate(request: DiscoveryPricesRequest): return discover(request, request.prices).model_dump()
class EvolutionPricesRequest(EvolutionRequest):
    prices: list[float] = Field(min_length=60, max_length=10000)
@router.post("/strategy-discovery/evolve")
def strategy_discovery_evolve(request: EvolutionPricesRequest): return evolve(request, request.prices).model_dump()
class ImproveRequest(BaseModel):
    specification: BotSpecification; prices: list[float] = Field(min_length=60, max_length=10000); iterations: int = Field(default=20, ge=1, le=100); seed: int = Field(default=42, ge=0); fee_pct: float = Field(default=0.001, ge=0, lt=0.1)
@router.post("/strategy-discovery/improve")
def strategy_discovery_improve(request: ImproveRequest):
    rng = random.Random(request.seed)
    current = request.specification
    best_result = run_spec_backtest(current, request.prices, request.fee_pct)
    best_metrics = metrics_from_result(best_result, complexity_of(current)); best_score = fitness(best_metrics); history = []
    for _ in range(request.iterations):
        proposal = mutate(current, rng, 6, 1); result = run_spec_backtest(proposal, request.prices, request.fee_pct); metrics = metrics_from_result(result, complexity_of(proposal)); score = fitness(metrics)
        history.append({"score":score,"metrics":metrics,"strategy_name":proposal.name})
        if score > best_score: current, best_score, best_metrics = proposal, score, metrics
    return {"contract":"sbt-strategy-improver-v1","accepted":True,"iterations":request.iterations,"best":{"score":best_score,"metrics":best_metrics,"specification":current.model_dump()},"history":sorted(history,key=lambda x:x["score"],reverse=True)[:20],"safety":{"live":False,"real_money":False,"broker_orders":0}}

class MatrixRequest(BaseModel):
    symbols: list[str] = Field(min_length=1, max_length=100)
    timeframes: list[str] = Field(min_length=1, max_length=20)
    max_targets: int = Field(default=100, ge=1, le=100)

@router.post("/strategy-discovery/matrix")
def strategy_discovery_matrix(request: MatrixRequest):
    targets = build_matrix(request.symbols, request.timeframes, request.max_targets)
    return {
        "contract": "sbt-research-matrix-v1",
        "mode": "free-deterministic-research",
        "targets": [target.__dict__ for target in targets],
        "target_count": len(targets),
        "limits": {"max_targets": request.max_targets},
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
        "next_stage": "fetch-provider-data-per-target-then-backtest"
    }
