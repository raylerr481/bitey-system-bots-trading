from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

from app.services.sbt_risk import OpportunityRisk, build_opportunity_risk

Decision = Literal["LONG", "SHORT", "WATCH", "NO_TRADE"]


@dataclass(frozen=True)
class DecisionResult:
    decision: Decision
    score: float
    reason: str
    risk: OpportunityRisk


def evaluate_opportunity(
    *,
    capital: float,
    score: float,
    evidence_count: int,
    independent_sources: int,
    market_confirmation: float,
    direction: Literal["long", "short"] = "long",
) -> DecisionResult:
    """Gate an SBT idea without executing an order.

    Scores are decision thresholds, not guaranteed win probabilities.
    """
    risk = build_opportunity_risk(capital)

    if evidence_count < 2 or independent_sources < 2:
        return DecisionResult("WATCH", score, "Insufficient independent evidence.", risk)
    if market_confirmation < 0.60:
        return DecisionResult("WATCH", score, "Market confirmation is below threshold.", risk)
    if score < 70:
        return DecisionResult("NO_TRADE", score, "Opportunity score is below threshold.", risk)

    return DecisionResult(direction.upper(), score, "Evidence and market confirmation passed the gate.", risk)
