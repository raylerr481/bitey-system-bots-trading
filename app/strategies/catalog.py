"""Provider-neutral strategy catalog for Bitey SBT.

Strategies are research hypotheses, not profitability claims. Every strategy must
be validated per instrument, timeframe, costs, sample size and robustness tests.
"""

from __future__ import annotations

from dataclasses import dataclass, asdict


@dataclass(frozen=True)
class StrategyTemplate:
    strategy_id: str
    name: str
    family: str
    description: str
    entry_rules: tuple[str, ...]
    exit_rules: tuple[str, ...]
    indicators: tuple[str, ...]
    preferred_regimes: tuple[str, ...]
    default_risk_pct: float = 0.01
    supports_long: bool = True
    supports_short: bool = True

    def as_dict(self) -> dict:
        value = asdict(self)
        for key in ("entry_rules", "exit_rules", "indicators", "preferred_regimes"):
            value[key] = list(value[key])
        return value


STRATEGIES = (
    StrategyTemplate(
        "SBT-EMA-RSI-ATR-001", "EMA Cross + RSI + ATR", "trend-following",
        "Trend confirmation with momentum filter and volatility-based stop.",
        ("fast EMA crosses above slow EMA", "RSI confirms bullish momentum"),
        ("fast EMA crosses below slow EMA", "ATR stop or risk target"),
        ("EMA", "RSI", "ATR"), ("trending",),
    ),
    StrategyTemplate(
        "SBT-RCI-MR-001", "RCI Mean Reversion", "mean-reversion",
        "Buys oversold conditions and exits on overbought conditions; short side is a symmetric research hypothesis.",
        ("RCI below oversold threshold",),
        ("RCI above overbought threshold", "risk stop"),
        ("RCI", "ATR"), ("range-bound",),
    ),
    StrategyTemplate(
        "SBT-SMA-CROSS-001", "SMA Crossover", "trend-following",
        "Simple moving-average crossover baseline for transparent research and comparison.",
        ("fast SMA crosses above slow SMA",),
        ("fast SMA crosses below slow SMA",),
        ("SMA",), ("trending",),
    ),
    StrategyTemplate(
        "SBT-BB-MR-001", "Bollinger Mean Reversion", "mean-reversion",
        "Research template for reversion from volatility bands with a risk-defined exit.",
        ("price reaches lower band and confirmation passes",),
        ("price reaches middle/upper band", "risk stop"),
        ("Bollinger Bands", "ATR"), ("range-bound", "low-trend"),
    ),
    StrategyTemplate(
        "SBT-MACD-TREND-001", "MACD Trend", "trend-following",
        "MACD direction and signal crossover baseline with volatility risk control.",
        ("MACD crosses above signal",),
        ("MACD crosses below signal", "ATR stop"),
        ("MACD", "ATR"), ("trending",),
    ),
    StrategyTemplate(
        "SBT-BREAKOUT-ATR-001", "Volatility Breakout + ATR", "breakout",
        "Breakout of a rolling range with ATR-based risk control.",
        ("close breaks above rolling high",),
        ("close breaks below trailing threshold", "ATR stop"),
        ("Rolling High/Low", "ATR"), ("expanding-volatility", "trending"),
    ),
)


def list_strategies(family: str | None = None) -> list[dict]:
    items = STRATEGIES
    if family:
        items = tuple(s for s in items if s.family == family)
    return [s.as_dict() for s in items]


def get_strategy(strategy_id: str) -> StrategyTemplate | None:
    return next((s for s in STRATEGIES if s.strategy_id == strategy_id), None)
