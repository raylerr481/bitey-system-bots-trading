"""Regression tests for SBT market timeframe normalization."""

from __future__ import annotations

from app.api.market import _bucket, _timeframe_seconds


def test_m1_is_a_first_class_timeframe() -> None:
    assert _timeframe_seconds("M1") == 60
    assert _timeframe_seconds("m1") == 60


def test_m1_buckets_ticks_to_minute_boundary() -> None:
    assert _bucket(1_725_000_089, 60) == 1_725_000_060


def test_all_supported_stream_timeframes_have_positive_intervals() -> None:
    for timeframe in ("M1", "M5", "M15", "M30", "H1", "H4", "D1", "W1"):
        assert _timeframe_seconds(timeframe) > 0


def test_unknown_timeframe_fails_closed() -> None:
    try:
        _timeframe_seconds("M2")
    except ValueError as exc:
        assert "Unsupported timeframe" in str(exc)
    else:
        raise AssertionError("Unsupported timeframe was accepted")
