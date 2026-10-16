from datetime import datetime, timezone, timedelta

from app.api.continuous_signals import Candle, SignalRequest, _evaluate


def candles_trending_up(count=80):
    rows = []
    start = datetime(2026, 1, 1, tzinfo=timezone.utc)
    price = 1.05
    for i in range(count):
        op = price
        close = price + 0.0004
        rows.append(Candle(
            time=(start + timedelta(hours=i)).isoformat(),
            open=op,
            high=close + 0.00005,
            low=op - 0.00005,
            close=close,
            volume=100,
        ))
        price = close
    return rows


def test_signal_engine_is_deterministic_and_never_sends_orders():
    req = SignalRequest(candles=candles_trending_up())
    first = _evaluate(req)
    second = _evaluate(req)
    assert first == second
    assert first["action"] in {"BUY", "SELL", "WAIT"}
    assert first["operating_capital_usd"] == 500
    assert first["hard_risk_cap_usd"] == 2
    assert first["broker_order_sent"] is False
    assert first["minimum_risk_reward"] >= 1.5


def test_daily_loss_gate_forces_wait():
    req = SignalRequest(candles=candles_trending_up(), daily_realized_pnl_usd=-10)
    result = _evaluate(req)
    assert result["action"] == "WAIT"
    assert "daily_loss_limit_reached" in result["reason_codes"]


def test_trade_count_and_open_position_gates_force_wait():
    candles = candles_trending_up()
    assert _evaluate(SignalRequest(candles=candles, trades_today=3))["action"] == "WAIT"
    assert _evaluate(SignalRequest(candles=candles, open_positions=1))["action"] == "WAIT"


def test_stale_data_never_generates_trade_signal():
    result = _evaluate(SignalRequest(candles=candles_trending_up(), data_fresh=False))
    assert result["action"] == "WAIT"
    assert "stale_market_data" in result["reason_codes"]
