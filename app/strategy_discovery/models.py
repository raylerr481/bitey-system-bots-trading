from __future__ import annotations

from pydantic import BaseModel, Field
from app.bot_builder.spec import BotSpecification


class DiscoveryRequest(BaseModel):
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    timeframe: str = Field(default="M5", min_length=2, max_length=8)
    candidates: int = Field(default=250, ge=10, le=1000)
    seed: int = Field(default=42, ge=0)
    max_conditions: int = Field(default=4, ge=1, le=6)
    min_trades: int = Field(default=10, ge=0, le=10000)
    max_drawdown_pct: float = Field(default=35.0, ge=0, le=100)
    min_profit_factor: float = Field(default=0.0, ge=0, le=20)
    fee_pct: float = Field(default=0.001, ge=0, lt=0.1)
    initial_capital: float = Field(default=10000, gt=0)


class EvolutionRequest(DiscoveryRequest):
    population: int = Field(default=100, ge=10, le=500)
    generations: int = Field(default=5, ge=1, le=10)
    elite: int = Field(default=10, ge=1, le=50)


class StrategyCandidate(BaseModel):
    candidate_id: str
    generation: int = 0
    fitness: float = 0.0
    complexity: int = 0
    status: str = "generated"
    metrics: dict = Field(default_factory=dict)
    specification: BotSpecification


class DiscoveryResult(BaseModel):
    contract: str = "sbt-strategy-discovery-v1"
    mode: str = "deterministic-research"
    seed: int
    generated: int
    evaluated: int
    accepted: int
    candidates: list[StrategyCandidate]
    filters: dict
    safety: dict = Field(default_factory=lambda: {"live": False, "real_money": False, "broker_orders": 0})
    next_stage: str = "oos-robustness-monte-carlo-walk-forward"
