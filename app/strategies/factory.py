"""Build reusable BotSpecification objects from the SBT strategy catalog."""

from __future__ import annotations

from app.bot_builder.spec import BotSpecification, IndicatorSpec, RiskSpec, RuleSpec
from app.strategies.catalog import get_strategy


def build_strategy_bot(strategy_id: str, symbol: str = "EURUSD", timeframe: str = "M5", language: str = "python") -> BotSpecification:
    """Create a deterministic research bot with symbol/timeframe injected."""
    strategy = get_strategy(strategy_id)
    if strategy is None:
        raise ValueError(f"Strategy template not found: {strategy_id}")

    risk = RiskSpec(risk_pct=strategy.default_risk_pct, stop_type="atr", stop_value=2.0)
    base = {"name": strategy.name, "symbol": symbol, "timeframe": timeframe, "language": language, "risk": risk}

    if strategy_id == "SBT-EMA-RSI-ATR-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="ema", period=9), IndicatorSpec(name="ema", period=21), IndicatorSpec(name="rsi", period=14), IndicatorSpec(name="atr", period=14)], entry_rules=[RuleSpec(indicator="ema_9", operator="cross_above", value="ema_21"), RuleSpec(indicator="rsi_14", operator=">", value=50)], exit_rules=[RuleSpec(indicator="ema_9", operator="cross_below", value="ema_21")])
    if strategy_id == "SBT-RCI-MR-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="rci", period=14), IndicatorSpec(name="atr", period=14)], entry_rules=[RuleSpec(indicator="rci_14", operator="<", value=-70)], exit_rules=[RuleSpec(indicator="rci_14", operator=">", value=70)])
    if strategy_id == "SBT-SMA-CROSS-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="sma", period=10), IndicatorSpec(name="sma", period=20)], entry_rules=[RuleSpec(indicator="sma_10", operator="cross_above", value="sma_20")], exit_rules=[RuleSpec(indicator="sma_10", operator="cross_below", value="sma_20")])
    if strategy_id == "SBT-BB-MR-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="bollinger", period=20), IndicatorSpec(name="atr", period=14)], entry_rules=[RuleSpec(indicator="bollinger_20_lower", operator="<", value="close")], exit_rules=[RuleSpec(indicator="bollinger_20_middle", operator="cross_above", value="close")])
    if strategy_id == "SBT-MACD-TREND-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="macd", period=12), IndicatorSpec(name="atr", period=14)], entry_rules=[RuleSpec(indicator="macd_12", operator="cross_above", value=0)], exit_rules=[RuleSpec(indicator="macd_12", operator="cross_below", value=0)])
    if strategy_id == "SBT-BREAKOUT-ATR-001":
        return BotSpecification(**base, indicators=[IndicatorSpec(name="rolling_high", period=20), IndicatorSpec(name="rolling_low", period=20), IndicatorSpec(name="atr", period=14)], entry_rules=[RuleSpec(indicator="close", operator="cross_above", value="rolling_high_20")], exit_rules=[RuleSpec(indicator="close", operator="cross_below", value="rolling_low_20")])
    raise ValueError(f"No factory mapping for strategy: {strategy_id}")
