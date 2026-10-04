"""Deterministic Classic Turtle Trading strategy for Bitey SBT.

Rules implemented from the canonical Turtle-style breakout specification:
- System 1 entry: 20-period breakout; optional one-time skip after a winning S1 trade.
- System 2 entry: 55-period breakout.
- N: 20-period ATR.
- Initial stop: 2N.
- Pyramiding: add one unit every 0.5N, up to 4 units total.
- Long and short symmetry.
- Unit sizing is supplied by the caller so broker/account risk remains outside this module.

This module generates signals only. It does not place broker orders.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal, Sequence

Side = Literal["long", "short"]

@dataclass(frozen=True)
class Bar:
    timestamp: int
    open: float
    high: float
    low: float
    close: float

@dataclass(frozen=True)
class TurtleConfig:
    entry_period_s1: int = 20
    exit_period_s1: int = 10
    entry_period_s2: int = 55
    exit_period_s2: int = 20
    atr_period: int = 20
    stop_n: float = 2.0
    add_n: float = 0.5
    max_units: int = 4
    skip_s1_after_winner: bool = True

@dataclass(frozen=True)
class TurtleSignal:
    system: Literal["S1", "S2"]
    side: Side
    timestamp: int
    entry: float
    n: float
    stop_loss: float
    unit_index: int
    reason: str

@dataclass(frozen=True)
class TurtleExit:
    system: Literal["S1", "S2"]
    side: Side
    timestamp: int
    price: float
    reason: str

def true_range(current: Bar, previous: Bar) -> float:
    return max(current.high - current.low, abs(current.high - previous.close), abs(current.low - previous.close))

def atr(bars: Sequence[Bar], period: int) -> float | None:
    if len(bars) < period + 1:
        return None
    trs = [true_range(bars[i], bars[i - 1]) for i in range(len(bars) - period, len(bars))]
    return sum(trs) / len(trs)

def breakout_levels(bars: Sequence[Bar], period: int) -> tuple[float, float] | None:
    if len(bars) < period + 1:
        return None
    sample = bars[-period - 1 : -1]
    return max(b.high for b in sample), min(b.low for b in sample)

def generate_entry(bars: Sequence[Bar], config: TurtleConfig | None = None, *, s1_eligible: bool = True, side_filter: Side | None = None, unit_index: int = 1) -> TurtleSignal | None:
    """Evaluate the latest completed bar for a Turtle breakout without look-ahead."""
    config = config or TurtleConfig()
    if unit_index < 1 or unit_index > config.max_units:
        return None
    n = atr(bars, config.atr_period)
    if n is None or n <= 0 or len(bars) < 2:
        return None
    candidates = []
    if s1_eligible:
        candidates.append(("S1", config.entry_period_s1))
    candidates.append(("S2", config.entry_period_s2))
    latest = bars[-1]
    for system, period in candidates:
        levels = breakout_levels(bars, period)
        if levels is None:
            continue
        high, low = levels
        if latest.high >= high and side_filter in (None, "long"):
            return TurtleSignal(system, "long", latest.timestamp, high, n, high - config.stop_n * n, unit_index, f"{system} {period}-bar upside breakout")
        if latest.low <= low and side_filter in (None, "short"):
            return TurtleSignal(system, "short", latest.timestamp, low, n, low + config.stop_n * n, unit_index, f"{system} {period}-bar downside breakout")
    return None

def add_unit_price(entry_price: float, side: Side, n: float, unit_index: int, config: TurtleConfig | None = None) -> float | None:
    config = config or TurtleConfig()
    if unit_index < 1 or unit_index >= config.max_units:
        return None
    distance = config.add_n * n
    return entry_price + distance if side == "long" else entry_price - distance

def exit_levels(bars: Sequence[Bar], system: Literal["S1", "S2"], config: TurtleConfig | None = None) -> tuple[float, float] | None:
    config = config or TurtleConfig()
    period = config.exit_period_s1 if system == "S1" else config.exit_period_s2
    return breakout_levels(bars, period)

def generate_exit(bars: Sequence[Bar], *, side: Side, system: Literal["S1", "S2"], config: TurtleConfig | None = None) -> TurtleExit | None:
    levels = exit_levels(bars, system, config)
    if levels is None:
        return None
    high, low = levels
    latest = bars[-1]
    if side == "long" and latest.low <= low:
        return TurtleExit(system, side, latest.timestamp, low, "downside exit-channel break")
    if side == "short" and latest.high >= high:
        return TurtleExit(system, side, latest.timestamp, high, "upside exit-channel break")
    return None
