"""Deterministic ABC EMA50 scalping strategy for Bitey SBT.

Source concept: user-provided trading-video transcript.
This module converts subjective chart language into explicit, testable rules.
It is research/demo/paper only and does not place broker orders.
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
class StrategyConfig:
    ema_period: int = 50
    pivot_left: int = 2
    pivot_right: int = 2
    zone_tolerance_pct: float = 0.0010
    min_zone_touches: int = 2
    deceleration_bars: int = 3
    deceleration_body_ratio_max: float = 0.45
    deceleration_wick_ratio_min: float = 0.30
    structure_lookback: int = 20
    pullback_tolerance_pct: float = 0.0010
    stop_buffer_pct: float = 0.0005


@dataclass(frozen=True)
class Signal:
    side: Side
    timestamp: int
    entry: float
    stop_loss: float
    reference_target: float | None
    reason: str


def ema(values: Sequence[float], period: int) -> list[float | None]:
    if period <= 0:
        raise ValueError("ema_period must be positive")
    out: list[float | None] = [None] * len(values)
    if len(values) < period:
        return out
    seed = sum(values[:period]) / period
    out[period - 1] = seed
    multiplier = 2.0 / (period + 1)
    previous = seed
    for index in range(period, len(values)):
        previous = (values[index] - previous) * multiplier + previous
        out[index] = previous
    return out


def _body_ratio(bar: Bar) -> float:
    span = max(bar.high - bar.low, 1e-12)
    return abs(bar.close - bar.open) / span


def _wick_ratio(bar: Bar) -> float:
    span = max(bar.high - bar.low, 1e-12)
    upper = bar.high - max(bar.open, bar.close)
    lower = min(bar.open, bar.close) - bar.low
    return max(upper, lower) / span


def is_decelerating(bars: Sequence[Bar], config: StrategyConfig) -> bool:
    """Approximate transcript's deceleration without subjective interpretation.

    A run qualifies when recent bodies/ranges lose force and the candles show
    meaningful wicks. This is intentionally configurable for robustness tests.
    """
    n = config.deceleration_bars
    if len(bars) < n + 1:
        return False
    recent = list(bars[-n:])
    previous = list(bars[-(n + 1) : -n])
    recent_ranges = [max(b.high - b.low, 1e-12) for b in recent]
    previous_range = max(previous[-1].high - previous[-1].low, 1e-12)
    shrinking = recent_ranges[-1] <= previous_range
    indecision = all(
        _body_ratio(b) <= config.deceleration_body_ratio_max
        and _wick_ratio(b) >= config.deceleration_wick_ratio_min
        for b in recent
    )
    return shrinking and indecision


def _pivots(bars: Sequence[Bar], left: int, right: int) -> tuple[list[float], list[float]]:
    highs: list[float] = []
    lows: list[float] = []
    for i in range(left, len(bars) - right):
        window = bars[i - left : i + right + 1]
        high = bars[i].high
        low = bars[i].low
        if high == max(b.high for b in window):
            highs.append(high)
        if low == min(b.low for b in window):
            lows.append(low)
    return highs, lows


def _zone(values: Sequence[float], tolerance_pct: float, min_touches: int) -> float | None:
    if not values:
        return None
    # Cluster the latest pivots into a price zone. A zone is valid only when
    # at least the configured number of pivots overlap the tolerance band.
    for candidate in reversed(values):
        touches = sum(abs(value - candidate) / max(candidate, 1e-12) <= tolerance_pct for value in values)
        if touches >= min_touches:
            return sum(value for value in values if abs(value - candidate) / max(candidate, 1e-12) <= tolerance_pct) / touches
    return None


def h1_bias(bars: Sequence[Bar], config: StrategyConfig) -> Side | None:
    """Return directional bias after zone rejection + deceleration.

    Resistance + deceleration => short bias.
    Support + deceleration => long bias.
    """
    if len(bars) < max(config.ema_period, config.pivot_left + config.pivot_right + 5):
        return None
    highs, lows = _pivots(bars, config.pivot_left, config.pivot_right)
    resistance = _zone(highs, config.zone_tolerance_pct, config.min_zone_touches)
    support = _zone(lows, config.zone_tolerance_pct, config.min_zone_touches)
    recent = bars[-config.deceleration_bars :]
    price = bars[-1].close
    if resistance is not None and abs(price - resistance) / max(resistance, 1e-12) <= config.zone_tolerance_pct * 2 and is_decelerating(bars, config):
        return "short"
    if support is not None and abs(price - support) / max(support, 1e-12) <= config.zone_tolerance_pct * 2 and is_decelerating(bars, config):
        return "long"
    return None


def _structure_change(bars: Sequence[Bar], side: Side, config: StrategyConfig) -> bool:
    """Detect a deterministic HH/HL -> LH/LL or inverse transition."""
    if len(bars) < config.structure_lookback:
        return False
    sample = bars[-config.structure_lookback :]
    highs, lows = _pivots(sample, config.pivot_left, config.pivot_right)
    if len(highs) < 2 or len(lows) < 2:
        return False
    if side == "short":
        return highs[-1] < highs[-2] and lows[-1] < lows[-2]
    return highs[-1] > highs[-2] and lows[-1] > lows[-2]


def _pullback_to_ema(bars: Sequence[Bar], side: Side, config: StrategyConfig) -> bool:
    closes = [b.close for b in bars]
    values = ema(closes, config.ema_period)
    if not values or values[-1] is None:
        return False
    current_ema = float(values[-1])
    bar = bars[-1]
    tolerance = current_ema * config.pullback_tolerance_pct
    touched = bar.low <= current_ema + tolerance and bar.high >= current_ema - tolerance
    if not touched:
        return False
    if side == "short":
        return bar.close <= current_ema + tolerance
    return bar.close >= current_ema - tolerance


def m1_trigger(bars: Sequence[Bar], side: Side, config: StrategyConfig) -> bool:
    closes = [b.close for b in bars]
    values = ema(closes, config.ema_period)
    if len(values) < 2 or values[-1] is None or values[-2] is None:
        return False
    previous_close = closes[-2]
    current_close = closes[-1]
    previous_ema = float(values[-2])
    current_ema = float(values[-1])
    if side == "short":
        return previous_close >= previous_ema and current_close < current_ema
    return previous_close <= previous_ema and current_close > current_ema


def generate_signal(
    h1_bars: Sequence[Bar],
    m5_bars: Sequence[Bar],
    m1_bars: Sequence[Bar],
    config: StrategyConfig | None = None,
) -> Signal | None:
    """Generate one deterministic signal after all three timeframes align."""
    config = config or StrategyConfig()
    side = h1_bias(h1_bars, config)
    if side is None:
        return None
    if not _structure_change(m5_bars, side, config):
        return None
    if not _pullback_to_ema(m5_bars, side, config):
        return None
    if not m1_trigger(m1_bars, side, config):
        return None

    entry = m1_bars[-1].close
    m5_high = max(bar.high for bar in m5_bars[-config.structure_lookback :])
    m5_low = min(bar.low for bar in m5_bars[-config.structure_lookback :])
    if side == "short":
        stop_loss = m5_high * (1 + config.stop_buffer_pct)
        reference_target = m5_low
        reason = "H1 resistance+deceleration; M5 bearish structure change+EMA50 pullback; M1 EMA50 bearish break"
    else:
        stop_loss = m5_low * (1 - config.stop_buffer_pct)
        reference_target = m5_high
        reason = "H1 support+deceleration; M5 bullish structure change+EMA50 pullback; M1 EMA50 bullish break"
    return Signal(side, m1_bars[-1].timestamp, entry, stop_loss, reference_target, reason)
