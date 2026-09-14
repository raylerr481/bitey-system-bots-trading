"""Deterministic safety contracts for Bitey AI Trading Lab.

This module does not execute broker orders. It validates AI proposals and
controls promotion of learning hypotheses into versioned strategy evidence.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import Optional


class Direction(str, Enum):
    LONG = "LONG"
    SHORT = "SHORT"
    WAIT = "WAIT"


class LabMode(str, Enum):
    RESEARCH = "research"
    SIMULATION = "simulation"
    DEMO = "demo"
    PAPER = "paper"
    LIVE = "live"


class LearningStatus(str, Enum):
    HYPOTHESIS = "hypothesis"
    TESTING = "testing"
    VALIDATED = "validated"
    REJECTED = "rejected"


@dataclass(frozen=True)
class RiskProfile:
    aggression: int = 5
    max_drawdown_pct: float = 10.0
    daily_loss_limit_pct: float = 2.0
    max_exposure_pct: float = 25.0

    def risk_per_trade_pct(self) -> float:
        table = {1: 0.10, 2: 0.15, 3: 0.25, 4: 0.35, 5: 0.50,
                 6: 0.60, 7: 0.75, 8: 0.85, 9: 0.95, 10: 1.00}
        return table[max(1, min(10, self.aggression))]


@dataclass(frozen=True)
class MarketState:
    symbol: str
    price: float
    volatility_pct: float
    spread_pct: float
    liquidity_ok: bool = True
    data_fresh: bool = True
    correlation_exposure_pct: float = 0.0
    current_drawdown_pct: float = 0.0
    daily_loss_pct: float = 0.0


@dataclass(frozen=True)
class AIProposal:
    direction: Direction
    confidence: int
    entry: Optional[float] = None
    stop_loss: Optional[float] = None
    take_profit: Optional[float] = None
    rationale: str = ""
    evidence: tuple[str, ...] = field(default_factory=tuple)


@dataclass(frozen=True)
class GateDecision:
    allowed: bool
    reason: str
    effective_risk_pct: float = 0.0


def validate_proposal(
    proposal: AIProposal,
    market: MarketState,
    risk: RiskProfile,
    mode: LabMode,
) -> GateDecision:
    """Apply deterministic controls to an AI proposal."""
    if mode == LabMode.LIVE:
        return GateDecision(False, "live execution is disabled by the AI Trading Lab")
    if not market.data_fresh:
        return GateDecision(False, "market data is stale")
    if not market.liquidity_ok:
        return GateDecision(False, "liquidity gate failed")
    if market.current_drawdown_pct >= risk.max_drawdown_pct:
        return GateDecision(False, "maximum drawdown gate failed")
    if market.daily_loss_pct >= risk.daily_loss_limit_pct:
        return GateDecision(False, "daily loss gate failed")
    if market.spread_pct > 0.50:
        return GateDecision(False, "spread gate failed")
    if proposal.direction == Direction.WAIT:
        return GateDecision(False, "AI proposal is WAIT")
    if not 0 <= proposal.confidence <= 100:
        return GateDecision(False, "invalid confidence")
    if proposal.confidence < 60:
        return GateDecision(False, "minimum AI confidence not reached")
    if proposal.entry is None or proposal.stop_loss is None:
        return GateDecision(False, "entry and stop loss are required")
    if proposal.direction == Direction.LONG and proposal.stop_loss >= proposal.entry:
        return GateDecision(False, "invalid LONG stop loss")
    if proposal.direction == Direction.SHORT and proposal.stop_loss <= proposal.entry:
        return GateDecision(False, "invalid SHORT stop loss")

    effective = risk.risk_per_trade_pct()
    if market.volatility_pct > 8.0:
        effective *= 0.50
    if market.correlation_exposure_pct > risk.max_exposure_pct:
        return GateDecision(False, "correlation exposure gate failed")
    return GateDecision(True, "proposal passed deterministic SBT gates", effective)


def learning_promotion(
    *,
    sample_count: int,
    out_of_sample_return_pct: float,
    max_drawdown_pct: float,
    paper_consistency: bool,
) -> LearningStatus:
    """Require evidence before an AI-generated hypothesis becomes validated."""
    if sample_count < 100:
        return LearningStatus.TESTING
    if out_of_sample_return_pct <= 0:
        return LearningStatus.REJECTED
    if max_drawdown_pct <= 0 or max_drawdown_pct > 20:
        return LearningStatus.REJECTED
    if not paper_consistency:
        return LearningStatus.TESTING
    return LearningStatus.VALIDATED
