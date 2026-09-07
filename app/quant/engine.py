"""Pure, dependency-free quantitative indicators and risk statistics.

This module performs arithmetic only. It never places broker orders and is safe to
reuse from research, backtest, market-intelligence and strategy layers.
"""
from __future__ import annotations

from math import sqrt
from statistics import mean, pstdev


def _check(values: list[float], minimum: int = 1) -> None:
    if len(values) < minimum:
        raise ValueError(f"Need at least {minimum} observations")
    if any(not isinstance(v, (int, float)) for v in values):
        raise ValueError("All observations must be numeric")


def sma(values: list[float], period: int) -> float:
    _check(values, period)
    return mean(values[-period:])


def ema(values: list[float], period: int) -> float:
    _check(values, period)
    value = mean(values[:period])
    alpha = 2.0 / (period + 1.0)
    for price in values[period:]:
        value = alpha * price + (1.0 - alpha) * value
    return value


def returns(values: list[float]) -> list[float]:
    _check(values, 2)
    return [(values[i] / values[i - 1]) - 1.0 for i in range(1, len(values)) if values[i - 1] != 0]


def volatility(values: list[float], annualization: float = 1.0) -> float:
    r = returns(values)
    return pstdev(r) * sqrt(annualization) if len(r) > 1 else 0.0


def rsi(values: list[float], period: int = 14) -> float:
    _check(values, period + 1)
    changes = [values[i] - values[i - 1] for i in range(1, len(values))]
    recent = changes[-period:]
    gains = sum(max(c, 0.0) for c in recent) / period
    losses = sum(max(-c, 0.0) for c in recent) / period
    if losses == 0:
        return 100.0 if gains > 0 else 50.0
    return 100.0 - (100.0 / (1.0 + gains / losses))


def atr(high: list[float], low: list[float], close: list[float], period: int = 14) -> float:
    _check(high, period + 1); _check(low, period + 1); _check(close, period + 1)
    if not (len(high) == len(low) == len(close)):
        raise ValueError("OHLC series must have equal length")
    tr = [max(high[i] - low[i], abs(high[i] - close[i - 1]), abs(low[i] - close[i - 1])) for i in range(1, len(close))]
    return mean(tr[-period:])


def bollinger(values: list[float], period: int = 20, deviations: float = 2.0) -> dict[str, float]:
    _check(values, period)
    window = values[-period:]
    mid = mean(window)
    sd = pstdev(window)
    return {"middle": mid, "upper": mid + deviations * sd, "lower": mid - deviations * sd, "bandwidth": (2 * deviations * sd / mid) if mid else 0.0}


def macd(values: list[float], fast: int = 12, slow: int = 26, signal: int = 9) -> dict[str, float]:
    _check(values, slow + signal)
    fast_line = ema(values, fast)
    slow_line = ema(values, slow)
    macd_line = fast_line - slow_line
    # Build a MACD history so the signal line is calculated from the same formula.
    history: list[float] = []
    start = slow
    for i in range(start, len(values) + 1):
        history.append(ema(values[:i], fast) - ema(values[:i], slow))
    signal_line = ema(history, signal)
    return {"macd": macd_line, "signal": signal_line, "histogram": macd_line - signal_line}


def drawdown(equity: list[float]) -> float:
    _check(equity)
    peak = equity[0]
    worst = 0.0
    for value in equity:
        peak = max(peak, value)
        if peak:
            worst = min(worst, (value / peak) - 1.0)
    return worst


def sharpe(returns_series: list[float], risk_free: float = 0.0) -> float:
    _check(returns_series, 2)
    excess = [r - risk_free for r in returns_series]
    sd = pstdev(excess)
    return mean(excess) / sd if sd else 0.0


def sortino(returns_series: list[float], target: float = 0.0) -> float:
    _check(returns_series, 2)
    excess = [r - target for r in returns_series]
    downside = [min(r, 0.0) for r in excess]
    dd = sqrt(sum(r * r for r in downside) / len(downside))
    return mean(excess) / dd if dd else 0.0


def position_size(capital: float, risk_pct: float, entry: float, stop: float) -> float:
    if capital <= 0 or not 0 < risk_pct <= 1 or entry <= 0 or stop <= 0 or entry == stop:
        raise ValueError("Invalid position-sizing parameters")
    risk_cash = capital * risk_pct
    return risk_cash / abs(entry - stop)


class QuantEngine:
    """Public facade with stable names for API and strategy integration."""

    @staticmethod
    def indicators(close: list[float], period: int = 14) -> dict:
        result = {"sma": sma(close, period), "ema": ema(close, period), "rsi": rsi(close, period)}
        result["returns"] = returns(close)
        result["volatility"] = volatility(close)
        result["bollinger"] = bollinger(close, max(2, min(20, len(close))))
        return result

    @staticmethod
    def ohlc_indicators(high: list[float], low: list[float], close: list[float], period: int = 14) -> dict:
        return {"atr": atr(high, low, close, period), "close": close[-1]}

    @staticmethod
    def risk_stats(equity: list[float]) -> dict:
        r = returns(equity) if len(equity) > 1 else []
        return {"max_drawdown": drawdown(equity), "sharpe": sharpe(r) if len(r) > 1 else 0.0, "sortino": sortino(r) if len(r) > 1 else 0.0}
