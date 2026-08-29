from app.intelligence.market_intelligence import Direction, MarketIntelligenceEngine, NewsEvent


def test_hawkish_fed_event_builds_primary_secondary_and_tertiary_impacts():
    engine = MarketIntelligenceEngine()
    result = engine.analyze(NewsEvent(
        headline="Fed signals higher rates",
        importance=90,
        source_quality=95,
        tags={"fed", "hawkish"},
    ))
    primary_assets = {item["asset"] for item in result["primary_impacts"]}
    domino = result["domino_effects"]
    secondary_assets = {item["asset"] for item in domino if item["layer"] == 2}
    tertiary_assets = {item["asset"] for item in domino if item["layer"] == 3}

    assert {"USD", "EUR/USD", "NASDAQ", "GOLD"}.issubset(primary_assets)
    assert {"USD/JPY", "USD/BRL"}.issubset(secondary_assets)
    assert "JPY" in tertiary_assets or "BRL" in tertiary_assets
    assert result["probable_market_horizons"] == ["0-5m", "5-30m", "30m-4h", "1-3d", "1-4w"]
    assert result["execution_allowed"] is False
    assert result["next_gate"] == "strategy_confirmation_and_risk_engine"


def test_conflicting_tags_produce_neutral_bias_and_wait():
    engine = MarketIntelligenceEngine()
    event = NewsEvent(
        headline="Conflicting monetary signals",
        tags={"hawkish", "dovish"},
    )
    impacts = engine.impacts(event)
    usd = next(item for item in impacts if item.asset == "USD")
    assert usd.direction is Direction.NEUTRAL
    opportunities = engine.opportunities(event)
    usd_opp = next(item for item in opportunities if item.asset == "USD")
    assert usd_opp.action == "wait"


def test_confirmation_can_raise_opportunity_score_without_executing():
    engine = MarketIntelligenceEngine()
    result = engine.analyze(
        NewsEvent(headline="Fed event", importance=85, tags={"fed"}),
        confirmed_assets=["USD"],
    )
    usd = next(item for item in result["opportunities"] if item["asset"] == "USD")
    assert usd["score"] <= 100
    assert usd["action"] == "watch-confirmed"
    assert result["execution_allowed"] is False
