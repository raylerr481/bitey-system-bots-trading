from __future__ import annotations

from statistics import mean, pstdev

from app.bot_builder.spec import BotSpecification
from app.quant.engine import bollinger, ema, macd, rsi, sma
from app.services.backtest import run_backtest


def _rci(prices: list[float], period: int) -> float:
    """Rank Correlation Index (RCI), scaled to [-100, 100]."""
    if len(prices) < period:
        raise ValueError(f"Need at least {period} observations for RCI")
    window = prices[-period:]
    price_ranks = {i: rank for rank, i in enumerate(sorted(range(period), key=lambda j: (window[j], j)), 1)}
    d2 = 0.0
    for time_rank, index in enumerate(range(period), 1):
        d = price_ranks[index] - time_rank
        d2 += d * d
    return (1.0 - (6.0 * d2) / (period * (period * period - 1.0))) * 100.0


def _value(prices: list[float], indicator: str, period: int) -> float:
    name = indicator.lower()
    if name == "sma": return sma(prices, period)
    if name == "ema": return ema(prices, period)
    if name == "rsi": return rsi(prices, period)
    if name == "rci": return _rci(prices, period)
    if name == "macd": return macd(prices, fast=period, slow=max(period + 14, 26), signal=9)["macd"]
    if name == "bollinger": return bollinger(prices, period)["middle"]
    if name == "rolling_high": return max(prices[-period:])
    if name == "rolling_low": return min(prices[-period:])
    if name == "atr": return 0.0
    raise ValueError(f"Unsupported backtest indicator: {indicator}")


def build_signal(spec: BotSpecification):
    indicators = [(i.name, i.period) for i in spec.indicators]
    max_period = max((p for _, p in indicators), default=2)

    def snapshot(prices, i):
        history = list(prices[:i + 1])
        values = {"close": float(history[-1])}
        for name, period in indicators:
            key = f"{name}_{period}"
            if name == "bollinger":
                band = bollinger(history, period)
                values[f"{key}_middle"] = band["middle"]
                values[f"{key}_upper"] = band["upper"]
                values[f"{key}_lower"] = band["lower"]
                values[key] = band["middle"]
            else:
                values[key] = _value(history, name, period)
        return values

    def signal(prices, i):
        if i < max_period:
            return "hold"
        current = snapshot(prices, i)
        previous = snapshot(prices, i - 1) if i > max_period else {}

        def value(values, ref):
            return values.get(ref) if isinstance(ref, str) else float(ref)

        def matches(rule):
            left = current.get(rule.indicator)
            right = value(current, rule.value)
            if left is None or right is None:
                return False
            if rule.operator == ">": return left > right
            if rule.operator == ">=": return left >= right
            if rule.operator == "<": return left < right
            if rule.operator == "<=": return left <= right
            prev_left = previous.get(rule.indicator)
            prev_right = value(previous, rule.value)
            if prev_left is None or prev_right is None:
                return False
            if rule.operator == "cross_above": return prev_left <= prev_right and left > right
            if rule.operator == "cross_below": return prev_left >= prev_right and left < right
            return False

        if spec.entry_rules and all(matches(r) for r in spec.entry_rules): return "buy"
        if spec.exit_rules and all(matches(r) for r in spec.exit_rules): return "sell"
        return "hold"
    return signal


def run_spec_backtest(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001):
    result = run_backtest(prices, build_signal(spec), initial_capital=spec.initial_capital, fee_pct=fee_pct)
    return {"contract":"sbt-backtest-v2", "strategy_contract":spec.contract, "strategy_name":spec.name, **result.__dict__}
