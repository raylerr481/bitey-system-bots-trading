from __future__ import annotations

from dataclasses import asdict, dataclass
from enum import Enum

from app.intelligence.market_intelligence import Direction, Opportunity


class ConfirmationState(str, Enum):
    CONFIRMED = "confirmed"
    DIVERGENCE = "divergence"
    EXTENDED = "extended"
    WAIT = "wait"


@dataclass(frozen=True)
class MarketObservation:
    asset: str
    price_change_pct: float
    expected_direction: Direction
    volatility_pct: float = 0.0
    momentum_score: int = 50


@dataclass(frozen=True)
class ConfirmationResult:
    asset: str
    state: ConfirmationState
    observed_direction: Direction
    expected_direction: Direction
    confirmation_score: int
    thesis: str
    next_action: str
    execution_allowed: bool = False


def _observed_direction(change_pct: float) -> Direction:
    if change_pct > 0:
        return Direction.BULLISH
    if change_pct < 0:
        return Direction.BEARISH
    return Direction.NEUTRAL


def confirm_opportunity(opportunity: Opportunity, observation: MarketObservation) -> ConfirmationResult:
    """Compare an intelligence hypothesis with read-only market observation.

    This is a gate for analysis only. It never authorizes an order.
    """
    observed = _observed_direction(observation.price_change_pct)
    expected = opportunity.direction

    if expected is Direction.NEUTRAL or observed is Direction.NEUTRAL:
        state = ConfirmationState.WAIT
        score = 35
        action = "wait"
        thesis = "Price direction is insufficient to confirm the intelligence hypothesis."
    elif observed is expected:
        # A very large move can mean the thesis is already extended; wait for a
        # pullback/retest instead of chasing the event.
        if abs(observation.price_change_pct) >= 2.5 or observation.volatility_pct >= 4.0:
            state = ConfirmationState.EXTENDED
            score = 65
            action = "wait-for-pullback"
            thesis = "Price confirms direction, but the move/volatility is extended."
        else:
            state = ConfirmationState.CONFIRMED
            score = min(100, 65 + max(0, min(35, observation.momentum_score // 3)))
            action = "watch-confirmed"
            thesis = "Observed price direction confirms the intelligence hypothesis."
    else:
        state = ConfirmationState.DIVERGENCE
        score = 20
        action = "wait-and-investigate-reversal"
        thesis = "Observed price direction contradicts the intelligence hypothesis."

    return ConfirmationResult(
        asset=observation.asset,
        state=state,
        observed_direction=observed,
        expected_direction=expected,
        confirmation_score=score,
        thesis=thesis,
        next_action=action,
        execution_allowed=False,
    )


def confirm_many(opportunities: list[Opportunity], observations: list[MarketObservation]) -> list[dict]:
    by_asset = {item.asset.upper(): item for item in observations}
    results = []
    for opportunity in opportunities:
        observation = by_asset.get(opportunity.asset.upper())
        if observation is None:
            continue
        results.append(asdict(confirm_opportunity(opportunity, observation)))
    return results
