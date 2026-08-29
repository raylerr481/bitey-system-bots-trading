from app.intelligence.market_intelligence import NewsEvent
from app.services.demo_loop import DemoTradingLoop
from app.strategies.technical import TechnicalSignalRequest


def _buy_request(symbol="EURUSD"):
    return TechnicalSignalRequest(
        symbol=symbol,
        prices=[100.0] * 20 + [101.0] * 10,
        fast_window=10,
        slow_window=30,
    )


def _dovish_event():
    return NewsEvent(
        headline="Fed signals a dovish policy path",
        source_quality=95,
        importance=90,
        tags={"fed", "dovish"},
    )


def test_confirmed_news_can_reach_demo_after_strategy_and_risk():
    loop = DemoTradingLoop()
    result = loop.run_with_intelligence(
        _buy_request(),
        _dovish_event(),
        confirmed_assets=("EURUSD",),
        quantity=1,
    )

    assert result["intelligence"]["execution_allowed"] is False
    assert result["intelligence"]["opportunities"]
    assert result["signal"]["action"] == "buy"
    assert result["executed"] is True
    assert result["execution"]["mode"] == "demo"


def test_unconfirmed_news_stops_before_demo_execution():
    loop = DemoTradingLoop()
    result = loop.run_with_intelligence(_buy_request(), _dovish_event(), quantity=1)

    assert result["executed"] is False
    assert result["reason"] == "Intelligence opportunity is not confirmed"
    assert "execution" not in result
    assert result["portfolio"]["positions"] == []


def test_strategy_contradiction_stops_before_demo_execution():
    loop = DemoTradingLoop()
    request = TechnicalSignalRequest(
        symbol="EURUSD",
        prices=[101.0] * 20 + [100.0] * 10,
        fast_window=10,
        slow_window=30,
    )

    result = loop.run_with_intelligence(
        request,
        _dovish_event(),
        confirmed_assets=("EURUSD",),
        quantity=1,
    )

    assert result["executed"] is False
    assert result["reason"] == "Strategy contradicts intelligence direction"
    assert "execution" not in result
    assert result["portfolio"]["positions"] == []


def test_risk_gate_still_blocks_intelligence_approved_demo_trade():
    loop = DemoTradingLoop()
    result = loop.run_with_intelligence(
        _buy_request(),
        _dovish_event(),
        confirmed_assets=("EURUSD",),
        quantity=3,
    )

    assert result["executed"] is False
    assert result["execution"]["reason"] == "Position exceeds maximum position size"
    assert result["portfolio"]["positions"] == []
