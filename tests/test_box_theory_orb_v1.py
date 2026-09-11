from datetime import datetime
from zoneinfo import ZoneInfo

from strategies.box_theory_orb_v1 import Bar, StrategyConfig, generate_signal


def ts(minute: int) -> int:
    value = datetime(2026, 9, 10, 9, minute, tzinfo=ZoneInfo("America/New_York"))
    return int(value.timestamp())


def test_box_theory_long_signal_uses_ny_opening_range_and_2_to_1_target() -> None:
    bars = [
        Bar(ts(30), 99.5, 100.0, 99.0, 99.7),
        Bar(ts(31), 99.7, 100.0, 99.2, 99.8),
        Bar(ts(32), 99.8, 100.0, 99.1, 99.9),
        Bar(ts(33), 99.9, 100.0, 99.3, 99.8),
        Bar(ts(34), 99.8, 100.0, 99.2, 99.9),
        Bar(ts(35), 99.9, 102.0, 99.7, 101.5),
        # Counter-trend bearish candle; its upper wick defines a type-1 box.
        Bar(ts(36), 101.6, 102.2, 100.8, 101.1),
        # Strong continuation impulse.
        Bar(ts(37), 101.1, 103.4, 100.9, 103.2),
        # Pullback contacts the box and closes above it.
        Bar(ts(38), 103.0, 103.1, 101.5, 102.6),
        # Entry is the next candle's open.
        Bar(ts(39), 102.7, 103.0, 102.5, 102.9),
    ]

    signal = generate_signal(
        bars,
        config=StrategyConfig(require_m5_confirmation=False, reward_risk=2.0),
    )

    assert signal is not None
    assert signal.side == "long"
    assert signal.timestamp == ts(39)
    assert signal.entry == 102.7
    assert signal.stop_loss < signal.box_low
    assert signal.take_profit > signal.entry
    assert abs((signal.take_profit - signal.entry) / (signal.entry - signal.stop_loss) - 2.0) < 1e-9
    assert signal.opening_range_high == 100.0
    assert signal.opening_range_low == 99.0


def test_no_signal_before_opening_range_breakout() -> None:
    bars = [
        Bar(ts(30), 99.5, 100.0, 99.0, 99.7),
        Bar(ts(31), 99.7, 100.0, 99.2, 99.8),
        Bar(ts(32), 99.8, 100.0, 99.1, 99.9),
        Bar(ts(33), 99.9, 100.0, 99.3, 99.8),
        Bar(ts(34), 99.8, 100.0, 99.2, 99.9),
    ]

    assert generate_signal(bars, config=StrategyConfig(require_m5_confirmation=False)) is None
