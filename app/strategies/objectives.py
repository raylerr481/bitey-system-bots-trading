"""Machine-readable objective and risk policy for Bitey SBT strategy research.

This policy defines how Bitey IA/SBT ranks candidate strategies. It is not a
profit guarantee and it does not authorize broker execution or environment
switching.
"""

TRADING_OBJECTIVE = {
    "name": "sustainable_return_under_risk_control",
    "primary_goal": "maximize_expected_sustainable_return_subject_to_risk_and_robustness",
    "minimum_reference_return": 0.10,
    "minimum_reference_label": "+10%",
    "reference_is_guarantee": False,
    "timeframe_selection": "evidence_driven",
}

MAXIMIZE_METRICS = (
    "expected_return",
    "profit_factor",
    "expectancy",
    "positive_month_probability",
    "robustness",
    "oos_quality",
)

MINIMIZE_METRICS = (
    "max_drawdown",
    "negative_month_probability",
    "loss_magnitude",
    "cost_drag",
    "parameter_sensitivity",
    "overfit_risk",
)

HARD_SAFETY_RULES = {
    "risk_increase": False,
    "disable_stop": False,
    "increase_max_drawdown": False,
    "bypass_risk_gate": False,
    "automatic_demo_to_real": False,
    "automatic_real_to_demo": False,
    "automatic_broker_switch": False,
    "unvalidated_production_change": False,
}

VALIDATION_GATES = (
    "historical_backtest",
    "realistic_costs",
    "walk_forward",
    "out_of_sample",
    "robustness",
    "demo_or_shadow_observation",
    "risk_gate",
)

DECISION_ORDER = (
    "observe",
    "analyze",
    "form_hypothesis",
    "select_strategy_and_timeframe",
    "backtest",
    "cost_adjust",
    "walk_forward",
    "out_of_sample",
    "robustness",
    "compare_risk_adjusted_results",
    "validate",
    "apply_allowlisted_change",
    "monitor",
    "report",
    "re_evaluate",
)


def score_priority(metrics: dict) -> float:
    """Return a simple ranking score; callers must still enforce hard gates.

    This is deliberately conservative: drawdown and negative-month probability
    subtract from the return-oriented score. It is a ranking aid, not a
    production risk engine.
    """
    expected_return = float(metrics.get("expected_return", 0.0))
    profit_factor = float(metrics.get("profit_factor", 0.0))
    expectancy = float(metrics.get("expectancy", 0.0))
    positive_month_probability = float(metrics.get("positive_month_probability", 0.0))
    robustness = float(metrics.get("robustness", 0.0))
    max_drawdown = float(metrics.get("max_drawdown", 0.0))
    negative_month_probability = float(metrics.get("negative_month_probability", 0.0))
    cost_drag = float(metrics.get("cost_drag", 0.0))

    return (
        4.0 * expected_return
        + 0.8 * max(profit_factor - 1.0, 0.0)
        + 1.0 * expectancy
        + 1.5 * positive_month_probability
        + 1.5 * robustness
        - 4.0 * max_drawdown
        - 1.5 * negative_month_probability
        - 1.0 * cost_drag
    )
