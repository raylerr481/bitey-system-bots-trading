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
    periods = {i.name: i.period for i in spec.indicators}
    def signal(prices, i):
        if i < max(periods.values(), default=2):
            return "hold"
        values = {}
        for name, period in periods.items():
            if name in {"sma", "ema", "rsi"}:
                values[name] = _value(list(prices[:i+1]), name, period)
        def matches(rule):
            left = values.get(rule.indicator)
            right = values.get(str(rule.value)) if isinstance(rule.value, str) else float(rule.value)
            if left is None or right is None: return False
            return {">": left > right, ">=": left >= right, "<": left < right, "<=": left <= right}.get(rule.operator, False)
        if spec.entry_rules and all(matches(r) for r in spec.entry_rules): return "buy"
        if spec.exit_rules and all(matches(r) for r in spec.exit_rules): return "sell"
        return "hold"
    return signal


def run_spec_backtest(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001):
    result = run_backtest(prices, build_signal(spec), initial_capital=spec.initial_capital, fee_pct=fee_pct)
    return {"contract":"sbt-backtest-v2", "strategy_contract":spec.contract, "strategy_name":spec.name, **result.__dict__}
