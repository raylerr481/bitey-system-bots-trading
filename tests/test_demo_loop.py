from app.services.demo_loop import DemoTradingLoop
from app.strategies.technical import TechnicalSignalRequest


def test_demo_loop_hold_does_not_execute():
    loop = DemoTradingLoop()
    request = TechnicalSignalRequest(
        symbol="EURUSD",
        prices=[100.0] * 30,
        fast_window=10,
        slow_window=30,
    )

    result = loop.run(request, quantity=1)

    assert result["mode"] == "demo"
    assert result["signal"]["action"] == "hold"
    assert result["executed"] is False
    assert result["reason"] == "Strategy returned hold"
    assert result["portfolio"]["cash"] == 10_000


def test_demo_loop_buy_is_blocked_when_risk_limit_is_exceeded():
    loop = DemoTradingLoop()
    request = TechnicalSignalRequest(
        symbol="EURUSD",
        prices=[100.0] * 20 + [101.0] * 10,
        fast_window=10,
        slow_window=30,
    )

    result = loop.run(request, quantity=3)

    assert result["signal"]["action"] == "buy"
    assert result["executed"] is False
    assert result["execution"]["reason"] == "Position exceeds maximum position size"
    assert result["portfolio"]["positions"] == []


def test_demo_loop_buy_executes_inside_risk_limit():
    loop = DemoTradingLoop()
    request = TechnicalSignalRequest(
        symbol="EURUSD",
        prices=[100.0] * 20 + [101.0] * 10,
        fast_window=10,
        slow_window=30,
    )

    result = loop.run(request, quantity=1)

    assert result["signal"]["action"] == "buy"
    assert result["executed"] is True
    assert result["execution"]["mode"] == "demo"
    assert result["portfolio"]["positions"][0]["symbol"] == "EURUSD"
    assert result["portfolio"]["positions"][0]["quantity"] == 1
