from app.turtle import TurtleController


def test_turtle_baseline_is_classic_v122():
    baseline = TurtleController().baseline()
    assert baseline["contract"] == "classic-turtle-mt4-v1.22"
    assert baseline["system_1_entry_days"] == 20
    assert baseline["system_1_exit_days"] == 10
    assert baseline["system_2_entry_days"] == 55
    assert baseline["system_2_exit_days"] == 20
    assert baseline["atr_period"] == 20
    assert baseline["stop_n"] == 2.0
    assert baseline["pyramid_n"] == 0.5
    assert baseline["max_units"] == 4
    assert baseline["optimization_allowed"] is False


def test_turtle_detects_campaign_architecture_errors():
    result = TurtleController().diagnose({
        "issues": ["mixed_exit_systems", "pyramid_loses_campaign_identity", "dynamic_n"],
        "config": {},
    })
    assert result["status"] == "CORRECTION_READY"
    assert set(result["automatic_corrections"]) == {
        "TURTLE-C001", "TURTLE-C002", "TURTLE-C003"
    }


def test_turtle_blocks_parameter_drift():
    result = TurtleController().diagnose({
        "issues": [],
        "config": {"system_1_entry_days": 41},
    })
    assert result["status"] == "BLOCKED_CLASSIC_BASELINE"
    plan = TurtleController().correction_plan(result)
    assert plan["allowed"] is False


def test_turtle_validation_requires_all_gates():
    controller = TurtleController()
    rejected = controller.validate_result({
        "compile_errors": 1,
        "classic_parameters_unchanged": True,
        "backtest_completed": True,
        "risk_gate_passed": True,
        "live_orders": 0,
    })
    assert rejected["status"] == "REJECTED"
    assert rejected["apply_allowed"] is False

    approved = controller.validate_result({
        "compile_errors": 0,
        "classic_parameters_unchanged": True,
        "backtest_completed": True,
        "risk_gate_passed": True,
        "live_orders": 0,
    })
    assert approved["status"] == "APPROVED"
    assert approved["apply_allowed"] is True
