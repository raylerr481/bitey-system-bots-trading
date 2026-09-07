import math

from app.quant.engine import QuantEngine, atr, ema, position_size, rsi


def test_ema_constant_series():
    assert ema([10.0] * 30, 9) == 10.0


def test_rsi_uptrend():
    assert rsi([float(i) for i in range(1, 31)], 14) == 100.0


def test_atr_uses_true_range():
    close = [10, 11, 12, 11, 12, 13, 12, 13, 14, 13, 14, 15, 14, 15, 16, 15]
    high = [c + 1 for c in close]
    low = [c - 1 for c in close]
    assert atr(high, low, close, 14) > 0


def test_position_size_risk_is_deterministic():
    assert math.isclose(position_size(10_000, 0.01, 100, 98), 50.0)


def test_engine_exposes_research_indicators():
    prices = [100 + math.sin(i / 3) for i in range(40)]
    result = QuantEngine.indicators(prices, 14)
    assert {"sma", "ema", "rsi", "returns", "volatility", "bollinger"} <= result.keys()


def test_risk_stats_are_present():
    equity = [10000, 10100, 10050, 10200, 10150, 10300]
    result = QuantEngine.risk_stats(equity)
    assert {"max_drawdown", "sharpe", "sortino"} <= result.keys()
