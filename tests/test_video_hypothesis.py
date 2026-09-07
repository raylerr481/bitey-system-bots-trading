from app.bot_builder.hypothesis import TradingHypothesis, evaluate_video_hypothesis, expected_value_per_trade, expectancy_r_multiple


def test_video_numbers_are_explicit_and_not_guaranteed():
    hypothesis = TradingHypothesis()
    assert round(expected_value_per_trade(hypothesis), 6) == 0.007
    assert round(expectancy_r_multiple(hypothesis), 6) == 0.35

    result = evaluate_video_hypothesis(hypothesis)
    assert result["contract"] == "sbt-video-hypothesis-v1"
    assert result["metrics"]["gross_expected_monthly_pct"] == 0.07
    assert result["interpretation"]["is_prediction"] is False
    assert result["interpretation"]["requires_market_backtest"] is True
    assert result["safety"] == {"live": False, "real_money": False, "broker_orders": 0}


def test_costs_can_destroy_the_claimed_expectancy():
    hypothesis = TradingHypothesis(
        spread_cost_monthly_pct=0.04,
        slippage_cost_monthly_pct=0.02,
        swap_cost_monthly_pct=0.02,
    )
    result = evaluate_video_hypothesis(hypothesis)
    assert result["metrics"]["net_expected_monthly_pct_before_compounding"] < 0
    assert result["interpretation"]["costs_destroy_expectancy"] is True
