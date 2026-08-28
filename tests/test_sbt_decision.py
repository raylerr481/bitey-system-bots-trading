from app.services.sbt_decision import evaluate_opportunity


def test_insufficient_evidence_is_watch():
    result = evaluate_opportunity(
        capital=1000,
        score=90,
        evidence_count=1,
        independent_sources=1,
        market_confirmation=0.90,
    )
    assert result.decision == "WATCH"


def test_strong_confirmed_opportunity_passes_gate():
    result = evaluate_opportunity(
        capital=1000,
        score=80,
        evidence_count=5,
        independent_sources=3,
        market_confirmation=0.80,
        direction="short",
    )
    assert result.decision == "SHORT"
    assert result.risk.max_loss == 10
    assert result.risk.reward_target == 20


def test_weak_confirmation_is_watch():
    result = evaluate_opportunity(
        capital=1000,
        score=90,
        evidence_count=5,
        independent_sources=3,
        market_confirmation=0.40,
    )
    assert result.decision == "WATCH"
