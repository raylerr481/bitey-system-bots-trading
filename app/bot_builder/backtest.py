from __future__ import annotations

from app.bot_builder.spec import BotSpecification
from app.quant.engine import ema, rsi, sma
from app.services.backtest import run_backtest


def _value(prices: list[float], indicator: str, period: int) -> float:
    name = indicator.lower()
    if name == "sma": return sma(prices, period)
    if name == "ema": return ema(prices, period)
    if name == "rsi": return rsi(prices, period)
    raise ValueError(f"Unsupported backtest indicator: {indicator}")


def build_signal(spec: BotSpecification):
    indicators = [(i.name, i.period) for i in spec.indicators]
    max_period = max((p for _, p in indicators), default=2)

    def signal(prices, i):
        if i < max_period:
            return "hold"
        history = list(prices[:i+1])
        prior_history = list(prices[:i])
        current, previous = {}, {}
        for name, period in indicators:
            if name in {"sma", "ema", "rsi"}:
                key = f"{name}_{period}"
                current[key] = _value(history, name, period)
                previous[key] = _value(prior_history, name, period) if len(prior_history) > period else None

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
