"""Deterministic Box Theory + New York opening-range strategy for Bitey SBT.

Source concept: user-provided trading-video transcript.
The transcript's discretionary language is converted into explicit parameters so the
strategy can be backtested and stress-tested. It is research/demo/paper only.
It does not place broker orders.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Literal, Sequence
from zoneinfo import ZoneInfo

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
    timezone: str = "America/New_York"
    opening_hour: int = 9
    opening_minute: int = 30
    opening_range_minutes: int = 5
    breakout_buffer_pct: float = 0.0001
    impulse_body_ratio_min: float = 0.60
    impulse_range_multiple: float = 1.20
    max_box_age_bars: int = 120
    wick_to_body_type1: float = 0.50
    wick_to_body_type2: float = 0.15
    confirmation_body_ratio_min: float = 0.50
    stop_buffer_pct: float = 0.0002
    reward_risk: float = 2.0
    require_m5_confirmation: bool = True


@dataclass(frozen=True)
class Box:
    side: Side
    source_timestamp: int
    low: float
    high: float
    candle_type: int


@dataclass(frozen=True)
class Signal:
    side: Side
    timestamp: int
    entry: float
    stop_loss: float
    take_profit: float
    box_low: float
    box_high: float
    opening_range_high: float
    opening_range_low: float
    reason: str


def _body(bar: Bar) -> float:
    return abs(bar.close - bar.open)


def _range(bar: Bar) -> float:
    return max(bar.high - bar.low, 1e-12)


def _body_ratio(bar: Bar) -> float:
    return _body(bar) / _range(bar)


def _upper_wick(bar: Bar) -> float:
    return max(0.0, bar.high - max(bar.open, bar.close))


def _lower_wick(bar: Bar) -> float:
    return max(0.0, min(bar.open, bar.close) - bar.low)


def _ny_time(timestamp: int, timezone: str) -> datetime:
    return datetime.fromtimestamp(timestamp, tz=ZoneInfo("UTC")).astimezone(ZoneInfo(timezone))


def _opening_range(bars: Sequence[Bar], config: StrategyConfig) -> tuple[float, float] | None:
    """Return the high/low of the first N one-minute bars of the NY session."""
    target = [
        bar
        for bar in bars
        if (
            _ny_time(bar.timestamp, config.timezone).hour == config.opening_hour
            and config.opening_minute
            <= _ny_time(bar.timestamp, config.timezone).minute
            < config.opening_minute + config.opening_range_minutes
        )
    ]
    if len(target) < config.opening_range_minutes:
        return None
    return max(bar.high for bar in target), min(bar.low for bar in target)


def _session_bias(bars: Sequence[Bar], config: StrategyConfig) -> tuple[Side, float, float, int] | None:
    opening = _opening_range(bars, config)
    if opening is None:
        return None
    range_high, range_low = opening
    for index, bar in enumerate(bars):
        local = _ny_time(bar.timestamp, config.timezone)
        if local.hour < config.opening_hour or (
            local.hour == config.opening_hour
            and local.minute < config.opening_minute + config.opening_range_minutes
        ):
            continue
        if bar.close > range_high * (1.0 + config.breakout_buffer_pct):
            return "long", range_high, range_low, index
        if bar.close < range_low * (1.0 - config.breakout_buffer_pct):
            return "short", range_high, range_low, index
    return None


def _average_range(bars: Sequence[Bar], end_index: int, lookback: int = 10) -> float:
    sample = bars[max(0, end_index - lookback):end_index]
    if not sample:
        return 0.0
    return sum(_range(bar) for bar in sample) / len(sample)


def _is_impulse(bar: Bar, previous_average_range: float, side: Side, config: StrategyConfig) -> bool:
    if _body_ratio(bar) < config.impulse_body_ratio_min:
        return False
    if previous_average_range > 0 and _range(bar) < previous_average_range * config.impulse_range_multiple:
        return False
    return (side == "long" and bar.close > bar.open) or (side == "short" and bar.close < bar.open)


def _build_box(candle: Bar, side: Side, config: StrategyConfig) -> Box:
    """Mirror the transcript's three box types around the trend direction."""
    body = max(_body(candle), 1e-12)
    if side == "long":
        wick = _upper_wick(candle)
        body_low, body_high = sorted((candle.open, candle.close))
        ratio = wick / body
        if ratio >= config.wick_to_body_type1:
            low, high, candle_type = body_high, candle.high, 1
        elif ratio >= config.wick_to_body_type2:
            low, high, candle_type = body_low, candle.high, 2
        else:
            low, high, candle_type = candle.low, candle.high, 3
    else:
        wick = _lower_wick(candle)
        body_low, body_high = sorted((candle.open, candle.close))
        ratio = wick / body
        if ratio >= config.wick_to_body_type1:
            low, high, candle_type = candle.low, body_low, 1
        elif ratio >= config.wick_to_body_type2:
            low, high, candle_type = candle.low, body_high, 2
        else:
            low, high, candle_type = candle.low, candle.high, 3
    return Box(side, candle.timestamp, min(low, high), max(low, high), candle_type)


def _latest_countertrend_box(
    bars: Sequence[Bar],
    side: Side,
    breakout_index: int,
    config: StrategyConfig,
) -> Box | None:
    """Find the latest opposite candle before a qualifying impulse."""
    start = max(1, breakout_index - config.max_box_age_bars)
    for index in range(breakout_index, start - 1, -1):
        candle = bars[index]
        previous_average = _average_range(bars, index)
        if not _is_impulse(candle, previous_average, side, config):
            continue
        for candidate_index in range(index - 1, start - 1, -1):
            candidate = bars[candidate_index]
            if side == "long" and candidate.close < candidate.open:
                return _build_box(candidate, side, config)
            if side == "short" and candidate.close > candidate.open:
                return _build_box(candidate, side, config)
    return None


def _m5_bias(
    m5_bars: Sequence[Bar],
    side: Side,
    range_high: float,
    range_low: float,
    config: StrategyConfig,
) -> bool:
    if not config.require_m5_confirmation:
        return True
    for bar in m5_bars:
        local = _ny_time(bar.timestamp, config.timezone)
        if local.hour < config.opening_hour or (
            local.hour == config.opening_hour
            and local.minute < config.opening_minute + config.opening_range_minutes
        ):
            continue
        if side == "long" and bar.close > range_high * (1.0 + config.breakout_buffer_pct):
            return True
        if side == "short" and bar.close < range_low * (1.0 - config.breakout_buffer_pct):
            return True
    return False


def _confirmation(bar: Bar, side: Side, box: Box, config: StrategyConfig) -> bool:
    if _body_ratio(bar) < config.confirmation_body_ratio_min:
        return False
    if side == "long":
        return bar.close > box.high and bar.close > bar.open
    return bar.close < box.low and bar.close < bar.open


def generate_signal(
    m1_bars: Sequence[Bar],
    m5_bars: Sequence[Bar] | None = None,
    config: StrategyConfig | None = None,
) -> Signal | None:
    """Generate one confirmed Box Theory signal after NY opening-range direction.

    Entry is the open of the candle after a confirmation candle. The box must
    first be contacted by price. A reward/risk of at least 2:1 is required.
    This function is deterministic and contains no broker execution.
    """
    config = config or StrategyConfig()
    if len(m1_bars) < 20:
        return None

    bias = _session_bias(m1_bars, config)
    if bias is None:
        return None
    side, range_high, range_low, breakout_index = bias

    if m5_bars is not None and not _m5_bias(m5_bars, side, range_high, range_low, config):
        return None

    box = _latest_countertrend_box(m1_bars, side, breakout_index, config)
    if box is None:
        return None

    contacted = False
    for index in range(breakout_index + 1, len(m1_bars) - 1):
        bar = m1_bars[index]
        if bar.high >= box.low and bar.low <= box.high:
            contacted = True
        if not contacted:
            continue
        if not _confirmation(bar, side, box, config):
            continue

        entry = m1_bars[index + 1].open
        if side == "long":
            stop = box.low * (1.0 - config.stop_buffer_pct)
            risk = entry - stop
            if risk <= 0:
                return None
            target = entry + risk * config.reward_risk
        else:
            stop = box.high * (1.0 + config.stop_buffer_pct)
            risk = stop - entry
            if risk <= 0:
                return None
            target = entry - risk * config.reward_risk

        return Signal(
            side=side,
            timestamp=m1_bars[index + 1].timestamp,
            entry=entry,
            stop_loss=stop,
            take_profit=target,
            box_low=box.low,
            box_high=box.high,
            opening_range_high=range_high,
            opening_range_low=range_low,
            reason=(
                "NY opening-range breakout + counter-trend candle box + box contact + "
                "confirmed continuation + minimum 2:1 reward/risk"
            ),
        )
    return None
