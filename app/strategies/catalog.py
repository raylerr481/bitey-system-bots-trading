"""Provider-neutral strategy library for Bitey SBT.

Catalog entries are research hypotheses. Published/public sources are references,
not profitability claims. Every candidate must pass costs, walk-forward, OOS and
robustness validation before any production consideration.
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
    source_type: str = "internal"
    source_reference: str = ""
    validation_status: str = "UNVALIDATED"
    default_risk_pct: float = 0.01
    supports_long: bool = True
    supports_short: bool = True

    def as_dict(self) -> dict:
        value = asdict(self)
        for key in ("entry_rules","exit_rules","indicators","preferred_regimes"):
            value[key] = list(value[key])
        return value

STRATEGIES = (
    StrategyTemplate("SBT-TURTLE-S1-001","Turtle S1 20/10","trend-following",
        "Classic Donchian breakout with volatility-based sizing, 2N stop and campaign logic.",
        ("close breaks above 20-day high","close breaks below 20-day low"),
        ("close breaks below 10-day low","2N protective stop"),
        ("Donchian","ATR/N"),("trending","expanding-volatility"),
        "published","Richard Dennis / William Eckhardt Turtle rules","REFERENCE",0.005),
    StrategyTemplate("SBT-TURTLE-S2-001","Turtle S2 55/20","trend-following",
        "Slower classic Turtle breakout for longer trends.",
        ("close breaks above 55-day high","close breaks below 55-day low"),
        ("close breaks below 20-day low","2N protective stop"),
        ("Donchian","ATR/N"),("trending",),
        "published","Richard Dennis / William Eckhardt Turtle rules","REFERENCE",0.005),
    StrategyTemplate("SBT-DONCHIAN-001","Donchian Breakout","breakout",
        "Rolling-channel breakout baseline derived from the same family as Turtle entries.",
        ("close breaks above rolling high","close breaks below rolling low"),
        ("opposite channel break","ATR stop"),
        ("Donchian","ATR"),("trending","expanding-volatility"),
        "published","Donchian channel / Turtle family","UNVALIDATED"),
    StrategyTemplate("SBT-TSMOM-001","Time-Series Momentum","momentum",
        "Directional momentum based on the sign of trailing returns.",
        ("trailing return is positive","trailing return is negative"),
        ("signal reverses","risk stop"),
        ("ROC","ATR"),("trending",),
        "published","Moskowitz, Ooi & Pedersen (2012)","UNVALIDATED"),
    StrategyTemplate("SBT-MA-CROSS-001","Dual Moving Average","trend-following",
        "Transparent fast/slow moving-average trend baseline.",
        ("fast MA crosses above slow MA","fast MA crosses below slow MA"),
        ("opposite crossover","ATR stop"),
        ("SMA/EMA","ATR"),("trending",),
        "published","Classical moving-average trend following","UNVALIDATED"),
    StrategyTemplate("SBT-ADX-TREND-001","ADX Trend Filter","trend-following",
        "Directional trend entry gated by minimum ADX strength.",
        ("ADX above threshold","+DI above -DI","price above trend MA"),
        ("ADX weakens","trend MA exit"),
        ("ADX","DI","EMA","ATR"),("trending",),
        "published","Classical ADX trend methodology","UNVALIDATED"),
    StrategyTemplate("SBT-DUAL-THRUST-001","Dual Thrust Breakout","breakout",
        "Range-expansion breakout using rolling range and configurable thresholds.",
        ("price breaks upper thrust band","price breaks lower thrust band"),
        ("opposite band","ATR stop"),
        ("rolling range","ATR"),("expanding-volatility","trending"),
        "published","Dual Thrust family","UNVALIDATED"),
    StrategyTemplate("SBT-EMA-RSI-ATR-001","EMA Cross + RSI + ATR","trend-following",
        "Trend confirmation with momentum filter and volatility-based stop.",
        ("fast EMA crosses above slow EMA","RSI confirms bullish momentum"),
        ("fast EMA crosses below slow EMA","ATR stop or risk target"),
        ("EMA","RSI","ATR"),("trending",),
        "internal","Bitey SBT baseline","UNVALIDATED"),
    StrategyTemplate("SBT-RCI-MR-001","RCI Mean Reversion","mean-reversion",
        "Oversold/overbought reversion hypothesis with risk-defined exit.",
        ("RCI below oversold threshold",),("RCI above overbought threshold","risk stop"),
        ("RCI","ATR"),("range-bound",),
        "internal","Bitey SBT baseline","UNVALIDATED"),
    StrategyTemplate("SBT-BB-MR-001","Bollinger Mean Reversion","mean-reversion",
        "Reversion from volatility bands with trend/risk filter.",
        ("price reaches lower band and confirmation passes",),
        ("price reaches middle/upper band","risk stop"),
        ("Bollinger Bands","ATR"),("range-bound","low-trend"),
        "published","Bollinger-band mean reversion family","UNVALIDATED"),
    StrategyTemplate("SBT-MACD-TREND-001","MACD Trend","trend-following",
        "MACD directional crossover baseline with volatility control.",
        ("MACD crosses above signal",),("MACD crosses below signal","ATR stop"),
        ("MACD","ATR"),("trending",),
        "internal","Bitey SBT baseline","UNVALIDATED"),
    StrategyTemplate("SBT-BREAKOUT-ATR-001","Volatility Breakout + ATR","breakout",
        "Rolling range breakout with ATR risk control.",
        ("close breaks above rolling high",),("close breaks below trailing threshold","ATR stop"),
        ("Rolling High/Low","ATR"),("expanding-volatility","trending"),
        "internal","Bitey SBT baseline","UNVALIDATED"),
    StrategyTemplate("SBT-ROC-BREAKOUT-001","ROC Breakout","momentum",
        "Breakout confirmed by accelerating rate of change.",
        ("ROC accelerates into price breakout",),("ROC turns negative","ATR stop"),
        ("ROC","Donchian","ATR"),("trending","expanding-volatility"),
        "published","ROC breakout strategy family","UNVALIDATED"),
    StrategyTemplate("SBT-ZSCORE-MR-001","Z-Score Mean Reversion","mean-reversion",
        "Statistical deviation from a rolling mean with volatility-aware exits.",
        ("z-score below entry threshold",),("z-score returns toward zero","risk stop"),
        ("Z-score","ATR"),("range-bound","low-trend"),
        "published","Classical statistical mean reversion","UNVALIDATED"),
    StrategyTemplate("SBT-VOL-TARGET-001","Volatility Target Overlay","risk-overlay",
        "Position sizing overlay that scales exposure inversely with realized volatility.",
        ("base strategy signal accepted",),("base strategy exits",),
        ("Realized Volatility","ATR"),("all",),
        "published","Volatility-managed strategy family","UNVALIDATED",0.005),
)

def list_strategies(family: str | None = None, status: str | None = None) -> list[dict]:
    items=STRATEGIES
    if family: items=tuple(s for s in items if s.family == family)
    if status: items=tuple(s for s in items if s.validation_status == status.upper())
    return [s.as_dict() for s in items]

def get_strategy(strategy_id: str) -> StrategyTemplate | None:
    return next((s for s in STRATEGIES if s.strategy_id == strategy_id), None)
