from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine


def make_engine():
    portfolio = DemoPortfolio(initial_capital=10_000, cash=10_000)
    return portfolio, DemoEngine(portfolio, RiskEngine())


def test_buy_creates_virtual_position():
    portfolio, engine = make_engine()
    result = engine.simulate_order(
        OrderIntent(symbol="eurusd", side=Side.BUY, quantity=1), 100
    )

    assert result["executed"] is True
    assert portfolio.cash == 9_900
    assert portfolio.positions[0].symbol == "EURUSD"
    assert portfolio.positions[0].quantity == 1
    assert portfolio.positions[0].average_price == 100


def test_second_buy_updates_average_price():
    portfolio, engine = make_engine()
    engine.simulate_order(OrderIntent(symbol="EURUSD", side=Side.BUY, quantity=1), 100)
    result = engine.simulate_order(
        OrderIntent(symbol="EURUSD", side=Side.BUY, quantity=1), 200
    )

    assert result["executed"] is True
    assert portfolio.positions[0].quantity == 2
    assert portfolio.positions[0].average_price == 150
    assert portfolio.cash == 9_700


def test_sell_requires_existing_position():
    portfolio, engine = make_engine()
    result = engine.simulate_order(
        OrderIntent(symbol="EURUSD", side=Side.SELL, quantity=1), 100
    )

    assert result["executed"] is False
    assert result["reason"] == "Insufficient virtual position"
    assert portfolio.cash == 10_000


def test_sell_realizes_pnl_and_closes_position():
    portfolio, engine = make_engine()
    engine.simulate_order(OrderIntent(symbol="EURUSD", side=Side.BUY, quantity=1), 100)
    result = engine.simulate_order(
        OrderIntent(symbol="EURUSD", side=Side.SELL, quantity=1), 120
    )

    assert result["executed"] is True
    assert portfolio.cash == 10_020
    assert portfolio.realized_pnl == 20
    assert portfolio.positions == []


def test_risk_blocks_oversized_buy():
    portfolio, engine = make_engine()
    result = engine.simulate_order(
        OrderIntent(symbol="EURUSD", side=Side.BUY, quantity=3), 100
    )

    assert result["executed"] is False
    assert result["reason"] == "Position exceeds maximum position size"
    assert portfolio.cash == 10_000
    assert portfolio.positions == []
