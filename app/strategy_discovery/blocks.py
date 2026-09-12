from __future__ import annotations

INDICATORS = (
    ("sma", (5, 10, 20, 50)),
    ("ema", (5, 9, 12, 21, 50)),
    ("rsi", (7, 14, 21)),
    ("rci", (9, 14, 20)),
    ("macd", (8, 12, 20)),
    ("bollinger", (10, 20, 30)),
    ("rolling_high", (10, 20, 50)),
    ("rolling_low", (10, 20, 50)),
)

OPERATORS = (">", ">=", "<", "<=", "cross_above", "cross_below")


def indicator_refs() -> list[tuple[str, int]]:
    return [(name, period) for name, periods in INDICATORS for period in periods]


def complexity(indicators: int, rules: int) -> int:
    return indicators + rules
