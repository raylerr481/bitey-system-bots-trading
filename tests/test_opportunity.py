from app.intelligence.opportunity import OpportunityScorer


def test_confirmed_high_quality_opportunity():
    result = OpportunityScorer().score(
        asset="EURUSD",
        direction="bearish",
        confirmation="CONFIRMED",
        importance=90,
        source_quality=95,
        reward_risk=3.5,
    )
    assert result.score >= 70
    assert result.status == "WATCH-CONFIRMED"


def test_divergence_forces_wait():
    result = OpportunityScorer().score(
        asset="EURUSD",
        direction="bearish",
        confirmation="DIVERGENCE",
        importance=90,
        source_quality=95,
        reward_risk=4.0,
    )
    assert result.status == "WAIT"


def test_high_risk_reduces_score():
    result = OpportunityScorer().score(
        asset="BTCUSD",
        direction="bearish",
        confirmation="CONFIRMED",
        importance=80,
        source_quality=80,
        risk_level="high",
    )
    assert result.score < 70
