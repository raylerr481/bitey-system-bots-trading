"""AR-002: falsifiable liquidity / order-flow hypothesis from Alex Ruiz video."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class AR002Spec:
    hypothesis_id: str = "AR-002"
    source: str = "Alex Ruiz"
    video_id: str = "EXA50PIskF4"
    swing_left: int = 2
    swing_right: int = 2
    equal_tolerance_atr: float = 0.10
    sweep_buffer_atr: float = 0.05
    acceptance_bars: int = 2
    vwap_anchor: str = "session"
    value_area_pct: float = 0.70
    live: bool = False
    real_money: bool = False
    broker_orders: int = 0


def ar002_spec() -> dict[str, Any]:
    s = AR002Spec()
    return {
        "hypothesis_id": s.hypothesis_id,
        "source": s.source,
        "video_id": s.video_id,
        "claim": "After price interacts with an objectively detected liquidity pool, rejection/sweep behavior should contain predictive information about reversal versus continuation after costs.",
        "status": "UNTESTED",
        "parameters": {
            "swing_left": s.swing_left,
            "swing_right": s.swing_right,
            "equal_tolerance_atr": s.equal_tolerance_atr,
            "sweep_buffer_atr": s.sweep_buffer_atr,
            "acceptance_bars": s.acceptance_bars,
            "vwap_anchor": s.vwap_anchor,
            "value_area_pct": s.value_area_pct,
        },
        "testable_components": [
            "buy-side/sell-side liquidity around confirmed swing highs/lows",
            "equal highs/lows as clustered liquidity",
            "liquidity sweep versus continuation (acceptance)",
            "explicit gaps and three-candle fair-value gaps",
            "VWAP distance and reversion/continuation",
            "volume-profile high/low-volume proxies when volume is available",
        ],
        "orderflow_limitations": [
            "True bid/ask depth, footprint imbalance and heatmap persistence require L2/order-book or tick/order-flow data.",
            "OHLCV-only mode uses observable price/volume proxies and must not be labeled as true order flow.",
        ],
        "falsification": [
            "Reject if sweep/rejection has no statistically useful out-of-sample edge after fees and slippage.",
            "Reject if continuation and rejection cannot be separated better than a defined baseline.",
            "Reject if the effect disappears across instruments, regimes or walk-forward windows.",
        ],
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def _atr(bars: list[dict[str, float]], period: int = 14) -> list[float]:
    out: list[float] = [0.0] * len(bars)
    trs: list[float] = []
    prev_close: float | None = None
    for i, b in enumerate(bars):
        h, l, c = b["high"], b["low"], b["close"]
        tr = max(h - l, abs(h - prev_close), abs(l - prev_close)) if prev_close is not None else h - l
        trs.append(tr)
        if i + 1 >= period:
            out[i] = sum(trs[i + 1 - period : i + 1]) / period
        prev_close = c
    return out


def _is_swing_high(bars: list[dict[str, float]], i: int, left: int, right: int) -> bool:
    if i < left or i + right >= len(bars):
        return False
    x = bars[i]["high"]
    return all(x > bars[j]["high"] for j in range(i - left, i)) and all(x >= bars[j]["high"] for j in range(i + 1, i + right + 1))


def _is_swing_low(bars: list[dict[str, float]], i: int, left: int, right: int) -> bool:
    if i < left or i + right >= len(bars):
        return False
    x = bars[i]["low"]
    return all(x < bars[j]["low"] for j in range(i - left, i)) and all(x <= bars[j]["low"] for j in range(i + 1, i + right + 1))


def detect_liquidity_events(bars: list[dict[str, float]], *, left: int = 2, right: int = 2, equal_tolerance_atr: float = 0.10, sweep_buffer_atr: float = 0.05) -> list[dict[str, Any]]:
    """Detect price/volume liquidity proxies without pretending to have L2 data."""
    if len(bars) < max(10, left + right + 2):
        return []
    atr = _atr(bars)
    highs: list[tuple[int, float]] = []
    lows: list[tuple[int, float]] = []
    events: list[dict[str, Any]] = []
    for i in range(len(bars)):
        if _is_swing_high(bars, i, left, right):
            highs.append((i, bars[i]["high"]))
            events.append({"index": i, "type": "buy_side_liquidity", "price": bars[i]["high"], "source": "swing_high"})
            if len(highs) >= 2 and atr[i] > 0 and abs(highs[-1][1] - highs[-2][1]) <= atr[i] * equal_tolerance_atr:
                events.append({"index": i, "type": "equal_highs", "price": (highs[-1][1] + highs[-2][1]) / 2, "source": "clustered_swings"})
        if _is_swing_low(bars, i, left, right):
            lows.append((i, bars[i]["low"]))
            events.append({"index": i, "type": "sell_side_liquidity", "price": bars[i]["low"], "source": "swing_low"})
            if len(lows) >= 2 and atr[i] > 0 and abs(lows[-1][1] - lows[-2][1]) <= atr[i] * equal_tolerance_atr:
                events.append({"index": i, "type": "equal_lows", "price": (lows[-1][1] + lows[-2][1]) / 2, "source": "clustered_swings"})
        if atr[i] > 0 and highs:
            level = highs[-1][1]
            if bars[i]["high"] > level + atr[i] * sweep_buffer_atr and bars[i]["close"] < level:
                events.append({"index": i, "type": "buy_side_sweep_rejection", "price": level, "source": "high_sweep_close_back_below"})
        if atr[i] > 0 and lows:
            level = lows[-1][1]
            if bars[i]["low"] < level - atr[i] * sweep_buffer_atr and bars[i]["close"] > level:
                events.append({"index": i, "type": "sell_side_sweep_rejection", "price": level, "source": "low_sweep_close_back_above"})
        if i >= 2:
            if bars[i - 2]["high"] < bars[i]["low"]:
                events.append({"index": i, "type": "bullish_fvg", "low": bars[i - 2]["high"], "high": bars[i]["low"], "source": "three_candle_gap"})
            if bars[i - 2]["low"] > bars[i]["high"]:
                events.append({"index": i, "type": "bearish_fvg", "low": bars[i]["high"], "high": bars[i - 2]["low"], "source": "three_candle_gap"})
    return events


def liquidity_signal_backtest(bars: list[dict[str, float]], horizon: int = 5) -> dict[str, Any]:
    """Event study: measure forward returns after sweep rejection events.

    This is deliberately not a broker/trading executor. It is an evidence engine.
    """
    events = detect_liquidity_events(bars)
    samples: list[dict[str, Any]] = []
    for e in events:
        i = int(e["index"])
        if e["type"] not in {"buy_side_sweep_rejection", "sell_side_sweep_rejection"} or i + horizon >= len(bars):
            continue
        entry = bars[i]["close"]
        exit_price = bars[i + horizon]["close"]
        direction = -1 if e["type"].startswith("buy_side") else 1
        ret = direction * (exit_price - entry) / entry if entry else 0.0
        samples.append({"index": i, "type": e["type"], "entry": entry, "exit": exit_price, "horizon": horizon, "directional_return": ret})
    n = len(samples)
    mean = sum(x["directional_return"] for x in samples) / n if n else 0.0
    wins = sum(1 for x in samples if x["directional_return"] > 0)
    return {
        "contract": "sbt-ar002-event-study-v1",
        "hypothesis_id": "AR-002",
        "events_tested": n,
        "win_rate": wins / n if n else None,
        "mean_forward_return": mean if n else None,
        "samples": samples,
        "evidence_status": "INSUFFICIENT_EVIDENCE" if n < 30 else ("POSITIVE_PRELIMINARY" if mean > 0 else "NO_EDGE_DETECTED"),
        "data_mode": "OHLCV_proxy",
        "requires_cost_model": True,
        "requires_out_of_sample": True,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
