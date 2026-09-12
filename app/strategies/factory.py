"""Build reusable BotSpecification objects from the SBT strategy catalog."""

from __future__ import annotations

from app.bot_builder.spec import BotSpecification, IndicatorSpec, RiskSpec, RuleSpec
from app.strategies.catalog import get_strategy


def build_strategy_bot(
    strategy_id: str,
    symbol: str = "EURUSD",
    timeframe: str = "M5",
    language: str = "python",
) -> BotSpecification:
    """Create a deterministic research bot from a registered strategy template.

    Symbol and timeframe are injected at build time, so the same template can be
    evaluated across supported instruments and timeframes when provider data exists.
    """
    strategy = get_strategy(strategy_id)
    if strategy is None:
        raise ValueError(f"Strategy template not found: {strategy_id}")

    common_risk = RiskSpec(risk_pct=strategy.default_risk_pct, stop_type="atr", stop_value=2.0)

    if strategy_id == "SBT-EMA-RSI-ATR-001":
        return BotSpecification(
            name=strategy.name,
            symbol=symbol,
            timeframe=timeframe,
            language=language,
            indicators=[IndicatorSpec(name="ema", period=9), IndicatorSpec(name="ema", period=21), IndicatorSpec(name="rsi", period=14), IndicatorSpec(name="atr", period=14)],
            entry_rules=[RuleSpec(indicator="ema_9", operator="cross_above", value="ema_21"), RuleSpec(indicator="rsi_14", operator=">", value=50)],
            exit_rules=[RuleSpec(indicator="ema_9", operator="cross_below", value="ema_21")],
            risk=common_risk,
        )

    if strategy_id == "SBT-SMA-CROSS-001":
        return BotSpecification(
            name=strategy.name,
            symbol=symbol,
            timeframe=timeframe,
            language=language,
            indicators=[IndicatorSpec(name="sma", period=10), IndicatorSpec(name="sma", period=20)],
            entry_rules=[RuleSpec(indicator="sma_10", operator="cross_above", value="sma_20")],
            exit_rules=[RuleSpec(indicator="sma_10", operator="cross_below", value="sma_20")],
            risk=common_risk,
        )

    if strategy_id == "SBT-MACD-TREND-001":
        return BotSpecification(
            name=strategy.name,
            symbol=symbol,
            timeframe=timeframe,
            language=language,
            indicators=[IndicatorSpec(name="macd", period=12), IndicatorSpec(name="atr", period=14)],
            entry_rules=[RuleSpec(indicator="macd_12", operator=">", value=0)],
            exit_rules=[RuleSpec(indicator="macd_12", operator="<", value=0)],
            risk=common_risk,
        )

    if strategy_id == "SBT-BB-MR-001":
        return BotSpecification(
            name=strategy.name,
            symbol=symbol,
            timeframe=timeframe,
            language=language,
            indicators=[IndicatorSpec(name="bollinger", period=20), IndicatorSpec(name="atr", period=14)],
            entry_rules=[RuleSpec(indicator="bollinger_20", operator="<", value=0)],
            exit_rules=[RuleSpec(indicator="bollinger_20", operator=">", value=0)],
            risk=common_risk,
        )

    if strategy_id == "SBT-BREAKOUT-ATR-001":
        raise ValueError("Breakout template requires rolling high/low indicators not yet implemented in the generic BotSpecification engine")

    if strategy_id == "SBT-RCI-MR-001":
        raise ValueError("RCI template requires the RCI indicator engine before generic BotSpecification execution")

    raise ValueError(f"No factory mapping for strategy: {strategy_id}")
