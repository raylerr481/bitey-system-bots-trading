from core.ai_trading_lab import (
    AIProposal,
    Direction,
    LabMode,
    LearningStatus,
    MarketState,
    RiskProfile,
    learning_promotion,
    validate_proposal,
)


def market(**overrides):
    values = dict(
        symbol="BTCUSDT",
        price=64000,
        volatility_pct=3,
        spread_pct=0.05,
    )
    values.update(overrides)
    return MarketState(**values)


def test_live_is_fail_closed():
    decision = validate_proposal(
        AIProposal(Direction.LONG, 90, 64000, 63500, 65000),
        market(),
        RiskProfile(),
        LabMode.LIVE,
    )
    assert not decision.allowed


def test_valid_paper_proposal_passes():
    decision = validate_proposal(
        AIProposal(Direction.LONG, 80, 64000, 63500, 65000),
        market(),
        RiskProfile(aggression=7),
        LabMode.PAPER,
    )
    assert decision.allowed
    assert decision.effective_risk_pct == 0.75


def test_high_volatility_reduces_effective_risk():
    decision = validate_proposal(
        AIProposal(Direction.LONG, 80, 64000, 63500, 65000),
        market(volatility_pct=12),
        RiskProfile(aggression=7),
        LabMode.PAPER,
    )
    assert decision.allowed
    assert decision.effective_risk_pct == 0.375


def test_insufficient_evidence_stays_in_testing():
    assert learning_promotion(
        sample_count=35,
        out_of_sample_return_pct=12,
        max_drawdown_pct=6,
        paper_consistency=True,
    ) == LearningStatus.TESTING


def test_validated_learning_requires_out_of_sample_and_paper_evidence():
    assert learning_promotion(
        sample_count=250,
        out_of_sample_return_pct=8,
        max_drawdown_pct=9,
        paper_consistency=True,
    ) == LearningStatus.VALIDATED


def test_negative_out_of_sample_is_rejected():
    assert learning_promotion(
        sample_count=250,
        out_of_sample_return_pct=-2,
        max_drawdown_pct=9,
        paper_consistency=True,
    ) == LearningStatus.REJECTED
