from app.services.virtual_validation import run_virtual_validation


def test_virtual_validation_is_deterministic():
    first = run_virtual_validation()
    second = run_virtual_validation()

    assert first == second


def test_virtual_validation_is_virtual_and_closed():
    result = run_virtual_validation()

    assert result["validation"] == "deterministic-virtual-v2"
    assert result["fixture"] == "synthetic-deterministic-not-market-history"
    assert result["real_money"] is False
    assert result["broker_orders"] == 0
    assert result["live_trading_enabled"] is False
    assert result["final_virtual_cash"] >= 0
    assert result["closed_trades"] == len(result["trades"])
    assert result["wins"] + result["losses"] + result["flats"] == result["closed_trades"]


def test_virtual_trade_accounting_matches_realized_pnl():
    result = run_virtual_validation()

    trade_pnl = 0.0
    for trade in result["trades"]:
        assert trade["entry_index"] < trade["exit_index"]
        assert trade["quantity"] > 0
        expected_pnl = (trade["exit_price"] - trade["entry_price"]) * trade["quantity"]
        assert round(expected_pnl, 6) == trade["pnl"]
        assert trade["outcome"] in {"win", "loss", "flat"}
        trade_pnl += trade["pnl"]

    assert round(trade_pnl, 6) == result["realized_pnl"]
    assert round(result["final_virtual_cash"] - result["initial_capital"], 6) == result["realized_pnl"]


def test_virtual_validation_risk_limits_are_recorded():
    result = run_virtual_validation()

    assert result["risk_limits"] == {
        "max_position_pct": 2.0,
        "max_daily_loss_pct": 1.0,
    }
    assert result["symbol"] == "EURUSD"
    assert result["strategy"] == "ema-rsi-atr-v1"
