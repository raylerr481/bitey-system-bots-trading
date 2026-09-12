from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.bot_builder.spec import BotSpecification
from app.strategy_discovery.blocks import INDICATORS, OPERATORS
from app.strategy_discovery.engine import discover, evolve
from app.strategy_discovery.generator import complexity_of, mutate
from app.strategy_discovery.models import DiscoveryRequest, EvolutionRequest
from app.bot_builder.backtest import run_spec_backtest
from app.strategy_discovery.fitness import fitness, metrics_from_result

router = APIRouter(prefix="/api/v1/strategy-discovery", tags=["strategy-discovery"])


@router.get("/catalog")
def catalog():
    return {
        "contract": "sbt-strategy-discovery-v1",
        "mode": "free-deterministic-research",
        "building_blocks": [name for name, _ in INDICATORS],
        "operators": list(OPERATORS),
        "pipeline": ["generate", "backtest", "filter", "rank", "evolve", "oos", "cost-stress", "monte-carlo", "walk-forward", "multi-market", "multi-timeframe", "portfolio", "risk-gate"],
        "limits": {"max_candidates": 1000, "max_conditions": 6, "max_generations": 10},
        "ai_role": "proposal-only; deterministic SBT engines perform validation",
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


class DiscoveryPricesRequest(DiscoveryRequest):
    prices: list[float] = Field(min_length=30, max_length=10000)


@router.post("/generate")
def generate(request: DiscoveryPricesRequest):
    return discover(request, request.prices).model_dump()


class EvolutionPricesRequest(EvolutionRequest):
    prices: list[float] = Field(min_length=60, max_length=10000)


@router.post("/evolve")
def evolve_endpoint(request: EvolutionPricesRequest):
    return evolve(request, request.prices).model_dump()


class ImproveRequest(BaseModel):
    specification: BotSpecification
    prices: list[float] = Field(min_length=60, max_length=10000)
    iterations: int = Field(default=20, ge=1, le=100)
    seed: int = Field(default=42, ge=0)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)


@router.post("/improve")
def improve(request: ImproveRequest):
    import random
    rng = random.Random(request.seed)
    current = request.specification
    best_result = run_spec_backtest(current, request.prices, request.fee_pct)
    best_metrics = metrics_from_result(best_result, complexity_of(current))
    best_score = fitness(best_metrics)
    history = []
    for _ in range(request.iterations):
        proposal = mutate(current, rng, 6, 1)
        result = run_spec_backtest(proposal, request.prices, request.fee_pct)
        metrics = metrics_from_result(result, complexity_of(proposal))
        score = fitness(metrics)
        history.append({"score": score, "metrics": metrics, "strategy_name": proposal.name})
        if score > best_score:
            current, best_score, best_metrics = proposal, score, metrics
    return {
        "contract": "sbt-strategy-improver-v1",
        "accepted": True,
        "iterations": request.iterations,
        "best": {"score": best_score, "metrics": best_metrics, "specification": current.model_dump()},
        "history": sorted(history, key=lambda x: x["score"], reverse=True)[:20],
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
