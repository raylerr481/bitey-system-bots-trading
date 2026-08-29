from app.intelligence.market_confirmation import (
    ConfirmationState,
    MarketObservation,
    confirm_opportunity,
)
from app.intelligence.market_intelligence import Direction, Opportunity, Horizon


def make_opportunity(direction=Direction.BULLISH):
    return Opportunity(
        asset="EUR/USD",
        direction=direction,
        score=80,
        horizon=Horizon.SHORT,
        action="watch",
        thesis="test",
        risk="normal",
        confirmation_required=True,
    )


def test_confirms_matching_price_direction():
    result = confirm_opportunity(
        make_opportunity(Direction.BULLISH),
        MarketObservation("EUR/USD", 0.35, Direction.BULLISH, 0.8, 80),
    )
    assert result.state is ConfirmationState.CONFIRMED
    assert result.execution_allowed is False


def test_detects_divergence():
    result = confirm_opportunity(
        make_opportunity(Direction.BULLISH),
        MarketObservation("EUR/USD", -0.40, Direction.BULLISH, 1.0, 60),
    )
    assert result.state is ConfirmationState.DIVERGENCE
    assert result.next_action == "wait-and-investigate-reversal"


def test_detects_extended_move():
    result = confirm_opportunity(
        make_opportunity(Direction.BEARISH),
        MarketObservation("EUR/USD", -3.0, Direction.BEARISH, 5.0, 90),
    )
    assert result.state is ConfirmationState.EXTENDED
    assert result.next_action == "wait-for-pullback"


def test_neutral_price_waits():
    result = confirm_opportunity(
        make_opportunity(Direction.BULLISH),
        MarketObservation("EUR/USD", 0.0, Direction.BULLISH),
    )
    assert result.state is ConfirmationState.WAIT
