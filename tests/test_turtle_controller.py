from app.turtle.controller import TurtleController


def test_controller_exposes_live_turtle_state():
    controller = TurtleController()
    state = controller.observe({
        "status": "RUNNING",
        "mode": "DEMO",
        "symbol": "EURUSD",
        "timeframe": "H1",
        "regime": "TREND",
        "signal": "BUY",
        "risk_pct": 0.25,
    })
    assert state["controller"] == "Turtle Controller"
    assert state["next_action"] == "CHECK_RISK_GATE"
    assert state["risk_gate_authoritative"] is True


def test_controller_halts_on_drawdown_gate():
    controller = TurtleController(max_drawdown_pct=5.0)
    state = controller.observe({"status": "RUNNING", "drawdown_pct": 5.1})
    assert state["next_action"] == "PAUSE_RISK"


def test_learning_requires_evidence():
    controller = TurtleController(min_trades_for_learning=3)
    controller.record_trade(-1)
    controller.record_trade(2)
    result = controller.evaluate_learning({"profit_factor": 2})
    assert result["status"] == "INSUFFICIENT_DATA"


def test_learning_proposes_backtest_not_live_change():
    controller = TurtleController(min_trades_for_learning=2)
    controller.record_trade(1)
    controller.record_trade(2)
    result = controller.evaluate_learning({
        "profit_factor": 1.2,
        "expectancy": 0.3,
        "drawdown_pct": 2,
    })
    assert result["status"] == "PROPOSAL_PENDING"
    assert result["proposal"]["action"] == "BACKTEST_BEFORE_CHANGE"
    assert controller.status()["live_parameter_change"] is False


def test_degraded_performance_requests_pause_and_revalidation():
    controller = TurtleController(min_trades_for_learning=1)
    controller.record_trade(-3)
    result = controller.evaluate_learning({
        "profit_factor": 0.8,
        "expectancy": -0.2,
        "drawdown_pct": 4,
    })
    assert result["proposal"]["action"] == "PAUSE_AND_REVALIDATE"
