from app.services.paper_trading import PaperConfig, simulate_signal


def test_paper_long_calculates_risk_and_never_sends_broker_order():
    result = simulate_signal(
        {"action": "LONG", "entry": 100, "stop": 98, "target": 104},
        PaperConfig(initial_capital=10000, risk_per_trade=0.005, max_position_pct=0.02),
    )
    assert result["status"] == "SIMULATED"
    assert result["mode"] == "paper"
    assert result["real_money"] is False
    assert result["broker_order_sent"] is False
    assert result["risk_reward"] == 2.0


def test_paper_rejects_invalid_short_levels():
    result = simulate_signal({"action": "SHORT", "entry": 100, "stop": 98, "target": 104})
    assert result["status"] == "REJECTED"
    assert result["reason"] == "invalid_short_levels"


def test_position_cap_limits_notional():
    result = simulate_signal(
        {"action": "LONG", "entry": 100, "stop": 99.9, "target": 101},
        PaperConfig(initial_capital=10000, risk_per_trade=0.02, max_position_pct=0.02),
    )
    assert result["status"] == "SIMULATED"
    assert result["notional"] <= 200.0 + 1e-8
