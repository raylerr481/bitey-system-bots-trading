"""Deterministic strategy candidate generation for Bitey SBT.

This is an original, dependency-free research generator. It creates bounded
candidate specifications from a small strategy grammar so later engines can
rank, mutate and evolve them. It never places orders and never fabricates
market data.
"""

from __future__ import annotations

from itertools import combinations

from app.bot_builder.spec import BotSpecification, IndicatorSpec, RiskSpec, RuleSpec


FAST_PERIODS = (5, 9, 12, 20)
SLOW_PERIODS = (21, 34, 50)
RSI_PERIODS = (7, 14, 21)
RSI_THRESHOLDS = (45.0, 50.0, 55.0)
STOP_ATR = (1.5, 2.0, 3.0)


def _candidate(symbol: str, timeframe: str, fast: int, slow: int, rsi_period: int,
               threshold: float, stop_atr: float, direction: str, index: int) -> BotSpecification:
    cross = "cross_above" if direction == "long" else "cross_below"
    exit_cross = "cross_below" if direction == "long" else "cross_above"
    rsi_op = ">" if direction == "long" else "<"
    name = f"GEN-{index:04d} {direction.upper()} EMA{fast}/{slow} RSI{rsi_period}"
    return BotSpecification(
        name=name,
        symbol=symbol,
        timeframe=timeframe,
        language="python",
        indicators=[
            IndicatorSpec(name="ema", period=fast),
            IndicatorSpec(name="ema", period=slow),
            IndicatorSpec(name="rsi", period=rsi_period),
        ],
        entry_rules=[
            RuleSpec(indicator=f"ema_{fast}", operator=cross, value=f"ema_{slow}"),
            RuleSpec(indicator=f"rsi_{rsi_period}", operator=rsi_op, value=threshold),
        ],
        exit_rules=[
            RuleSpec(indicator=f"ema_{fast}", operator=exit_cross, value=f"ema_{slow}"),
        ],
        risk=RiskSpec(risk_pct=0.01, stop_type="atr", stop_value=stop_atr, max_position_pct=0.02),
        initial_capital=10_000,
        live=False,
        real_money=False,
        broker_orders=0,
    )


def generate_candidates(symbol: str, timeframe: str, max_candidates: int = 100,
                         directions: tuple[str, ...] = ("long", "short")) -> list[BotSpecification]:
    """Generate a bounded, reproducible candidate population."""
    if max_candidates < 1:
        raise ValueError("max_candidates must be positive")
    if max_candidates > 5000:
        raise ValueError("max_candidates cannot exceed 5000")
    if not symbol or not timeframe:
        raise ValueError("symbol and timeframe are required")
    if any(d not in {"long", "short"} for d in directions):
        raise ValueError("directions must contain only long/short")

    out: list[BotSpecification] = []
    idx = 1
    for fast, slow in combinations(FAST_PERIODS, 2):
        if fast >= slow or slow not in SLOW_PERIODS and slow <= fast:
            continue
        for rsi_period in RSI_PERIODS:
            for threshold in RSI_THRESHOLDS:
                for stop in STOP_ATR:
                    for direction in directions:
                        out.append(_candidate(symbol, timeframe, fast, slow, rsi_period, threshold, stop, direction, idx))
                        idx += 1
                        if len(out) >= max_candidates:
                            return out
    return out
