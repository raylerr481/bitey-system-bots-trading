from __future__ import annotations

from math import isfinite
from statistics import mean


def _closes(candles: list[dict]) -> list[float]:
    return [float(c["close"]) for c in candles if isfinite(float(c.get("close", float("nan"))))]


def _ema(values: list[float], period: int) -> float | None:
    if len(values) < period:
        return None
    value = mean(values[:period])
    alpha = 2 / (period + 1)
    for price in values[period:]:
        value = alpha * price + (1 - alpha) * value
    return value


def _rsi(values: list[float], period: int = 14) -> float | None:
    if len(values) < period + 1:
        return None
    gains: list[float] = []
    losses: list[float] = []
    for previous, current in zip(values[-period - 1:-1], values[-period:]):
        delta = current - previous
        gains.append(max(delta, 0.0))
        losses.append(max(-delta, 0.0))
    avg_gain = mean(gains)
    avg_loss = mean(losses)
    if avg_loss == 0:
        return 100.0 if avg_gain > 0 else 50.0
    rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))


def _atr(candles: list[dict], period: int = 14) -> float | None:
    if len(candles) < period + 1:
        return None
    true_ranges: list[float] = []
    previous_close = float(candles[-period - 1]["close"])
    for candle in candles[-period:]:
        high = float(candle["high"])
        low = float(candle["low"])
        close = float(candle["close"])
        true_ranges.append(max(high - low, abs(high - previous_close), abs(low - previous_close)))
        previous_close = close
    return mean(true_ranges)


def analyze_market(candles: list[dict], symbol: str, timeframe: str, event: str = "market_structure") -> dict:
    if len(candles) < 35:
        return {
            "status": "insufficient_data",
            "symbol": symbol,
            "timeframe": timeframe,
            "bias": "NEUTRAL",
            "confidence": None,
            "volatility": None,
            "reason": "At least 35 OHLC candles are required for the baseline EMA/RSI/ATR analysis.",
            "research_only": True,
            "live": False,
            "real_money": False,
        }

    closes = _closes(candles)
    ema_fast = _ema(closes, 9)
    ema_slow = _ema(closes, 21)
    rsi = _rsi(closes, 14)
    atr = _atr(candles, 14)
    last = closes[-1]

    ema_bias = "BULLISH" if ema_fast and ema_slow and ema_fast > ema_slow else "BEARISH" if ema_fast and ema_slow and ema_fast < ema_slow else "NEUTRAL"
    rsi_state = "OVERBOUGHT" if rsi is not None and rsi >= 70 else "OVERSOLD" if rsi is not None and rsi <= 30 else "NEUTRAL"
    momentum_bias = "BULLISH" if rsi is not None and rsi > 55 else "BEARISH" if rsi is not None and rsi < 45 else "NEUTRAL"

    votes = [ema_bias, momentum_bias]
    bullish = votes.count("BULLISH")
    bearish = votes.count("BEARISH")
    bias = "BULLISH" if bullish > bearish else "BEARISH" if bearish > bullish else "NEUTRAL"

    contradictions: list[dict] = []
    if ema_bias != "NEUTRAL" and momentum_bias != "NEUTRAL" and ema_bias != momentum_bias:
        contradictions.append({"type": "technical_momentum", "severity": "high", "message": "EMA structure and RSI momentum disagree."})
    if bias == "BULLISH" and rsi_state == "OVERBOUGHT":
        contradictions.append({"type": "extension", "severity": "medium", "message": "Bullish structure is extended by overbought RSI."})
    if bias == "BEARISH" and rsi_state == "OVERSOLD":
        contradictions.append({"type": "extension", "severity": "medium", "message": "Bearish structure is extended by oversold RSI."})

    confidence = 0.50
    if ema_bias == bias and bias != "NEUTRAL":
        confidence += 0.18
    if momentum_bias == bias and bias != "NEUTRAL":
        confidence += 0.15
    confidence -= 0.15 * sum(1 for item in contradictions if item["severity"] == "high")
    confidence -= 0.07 * sum(1 for item in contradictions if item["severity"] == "medium")
    confidence = round(max(0.0, min(0.95, confidence)), 3)

    ranges = [float(c["high"]) - float(c["low"]) for c in candles[-14:]]
    average_range = mean(ranges)
    volatility_regime = "HIGH" if atr and average_range and atr > average_range * 1.15 else "LOW" if atr and average_range and atr < average_range * 0.85 else "NORMAL"

    return {
        "status": "analyzed",
        "symbol": symbol,
        "timeframe": timeframe,
        "event": event,
        "last_price": last,
        "bias": bias,
        "confidence": confidence,
        "technical": {
            "ema": {"fast_period": 9, "slow_period": 21, "fast": ema_fast, "slow": ema_slow, "bias": ema_bias},
            "rsi": {"period": 14, "value": round(rsi, 3) if rsi is not None else None, "state": rsi_state, "bias": momentum_bias},
            "atr": {"period": 14, "value": round(atr, 6) if atr is not None else None, "regime": volatility_regime},
        },
        "contradiction_detector": {"status": "WATCH" if contradictions else "CLEAR", "count": len(contradictions), "items": contradictions},
        "time_engine": {"status": "READY", "timeframe": timeframe, "horizon": "intraday" if timeframe in {"M1", "M5", "M15", "M30", "H1"} else "swing"},
        "domino_state": {"status": "READY", "state": "technical_context_only", "downstream_order_impact": "blocked"},
        "hypothesis": {"bias": bias, "confidence": confidence, "action": "WATCH" if contradictions or confidence < 0.60 else "EXPERIMENT", "order_allowed": False},
        "research_only": True,
        "live": False,
        "real_money": False,
        "risk_gate_authoritative": True,
    }
