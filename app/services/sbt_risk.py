from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class OpportunityRisk:
    capital: float
    risk_pct: float
    max_loss: float
    reward_target: float
    risk_reward: float
    position_budget: float


def build_opportunity_risk(
    capital: float,
    *,
    risk_pct: float = 0.01,
    risk_reward: float = 2.0,
    position_pct: float = 0.02,
) -> OpportunityRisk:
    """Calculate a bounded planning envelope; never submits an order."""
    if capital <= 0:
        raise ValueError("capital must be greater than zero")
    if not 0 < risk_pct <= 0.02:
        raise ValueError("risk_pct must be between 0 and 2%")
    if risk_reward < 1:
        raise ValueError("risk_reward must be at least 1")
    if not 0 < position_pct <= 0.50:
        raise ValueError("position_pct must be between 0 and 50%")

    max_loss = round(capital * risk_pct, 2)
    position_budget = round(capital * position_pct, 2)
    reward_target = round(max_loss * risk_reward, 2)
    return OpportunityRisk(
        capital=round(capital, 2),
        risk_pct=risk_pct,
        max_loss=max_loss,
        reward_target=reward_target,
        risk_reward=risk_reward,
        position_budget=position_budget,
    )
