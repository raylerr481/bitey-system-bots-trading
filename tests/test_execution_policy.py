from app.services.execution_policy import ExecutionPolicy


def test_live_is_always_blocked():
    decision, risk = ExecutionPolicy().authorize_order(
        platform="alpaca",
        mode="live",
        capital=10_000,
        notional=100,
        daily_pnl=0,
        permissions=["live_execute"],
    )
    assert decision.allowed is False
    assert decision.stage == "safety-gates"
    assert risk is None


def test_demo_requires_explicit_permission():
    decision, risk = ExecutionPolicy().authorize_order(
        platform="mt5",
        mode="demo",
        capital=10_000,
        notional=100,
        daily_pnl=0,
        permissions=[],
    )
    assert decision.allowed is False
    assert decision.stage == "permissions"
    assert risk is None


def test_risk_gate_is_mandatory():
    decision, risk = ExecutionPolicy().authorize_order(
        platform="alpaca",
        mode="paper",
        capital=10_000,
        notional=300,
        daily_pnl=0,
        permissions=["paper_execute"],
    )
    assert decision.allowed is False
    assert decision.stage == "risk-gate"
    assert risk is not None
    assert risk.allowed is False
