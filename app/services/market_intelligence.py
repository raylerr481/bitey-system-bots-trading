from __future__ import annotations

from math import isfinite
from statistics import mean

from app.strategies.smc import OHLC, SMCSignalRequest, smc_signal


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
    gains, losses = [], []
    for previous, current in zip(values[-period - 1:-1], values[-period:]):
        delta = current - previous
        gains.append(max(delta, 0.0))
        losses.append(max(-delta, 0.0))
    avg_gain, avg_loss = mean(gains), mean(losses)
    if avg_loss == 0:
        return 100.0 if avg_gain > 0 else 50.0
    return 100 - (100 / (1 + avg_gain / avg_loss))


def _atr(candles: list[dict], period: int = 14) -> float | None:
    if len(candles) < period + 1:
        return None
    values = []
    previous_close = float(candles[-period - 1]["close"])
    for candle in candles[-period:]:
        high, low, close = float(candle["high"]), float(candle["low"]), float(candle["close"])
        values.append(max(high - low, abs(high - previous_close), abs(low - previous_close)))
        previous_close = close
    return mean(values)


def _time_context(timeframe: str) -> dict:
    contexts = {
        "M1": ("micro", "scalping", "minutes", "Microstructure and noise dominate; spread and execution quality matter most."),
        "M5": ("intraday", "scalping", "minutes", "Short-term momentum is important and spread sensitivity is elevated."),
        "M15": ("intraday", "intraday", "hours", "Intraday structure is more relevant than isolated micro moves."),
        "M30": ("intraday", "intraday", "hours", "Session context and intraday structure are relevant."),
        "H1": ("intraday", "intraday/swing", "hours to 1 day", "Session transitions and broader structure should be considered."),
        "H4": ("swing", "swing", "days", "Multi-session structure is more important than intraday noise."),
        "D1": ("swing", "position", "days to weeks", "Daily structure dominates short-term fluctuations."),
    }
    horizon, style, window, explanation = contexts.get(timeframe.upper(), ("unknown", "unknown", "unknown", "Timeframe is not mapped by the current Time Engine."))
    return {"status": "READY" if timeframe.upper() in contexts else "LIMITED", "timeframe": timeframe.upper(), "market_horizon": horizon, "strategy_context": style, "typical_horizon": window, "explanation": explanation}


def analyze_market(candles: list[dict], symbol: str, timeframe: str, event: str = "market_structure") -> dict:
    if len(candles) < 35:
        return {"status": "insufficient_data", "symbol": symbol, "timeframe": timeframe, "bias": "NEUTRAL", "confidence": None, "reason": "At least 35 OHLC candles are required for the baseline analysis.", "research_only": True, "live": False, "real_money": False}

    closes = _closes(candles)
    ema_fast, ema_slow = _ema(closes, 9), _ema(closes, 21)
    rsi, atr = _rsi(closes, 14), _atr(candles, 14)
    last = closes[-1]
    ema_bias = "BULLISH" if ema_fast > ema_slow else "BEARISH" if ema_fast < ema_slow else "NEUTRAL"
    rsi_state = "OVERBOUGHT" if rsi >= 70 else "OVERSOLD" if rsi <= 30 else "NEUTRAL"
    momentum_bias = "BULLISH" if rsi > 55 else "BEARISH" if rsi < 45 else "NEUTRAL"
    votes = [ema_bias, momentum_bias]
    bullish, bearish = votes.count("BULLISH"), votes.count("BEARISH")
    bias = "BULLISH" if bullish > bearish else "BEARISH" if bearish > bullish else "NEUTRAL"

    contradictions = []
    if ema_bias != "NEUTRAL" and momentum_bias != "NEUTRAL" and ema_bias != momentum_bias:
        contradictions.append({"type": "technical_momentum", "severity": "high", "title": "EMA vs RSI disagreement", "message": "Trend structure and momentum point in opposite directions.", "effect": "Reduce confidence and keep the hypothesis in WATCH state."})
    if bias == "BULLISH" and rsi_state == "OVERBOUGHT":
        contradictions.append({"type": "extension", "severity": "medium", "title": "Bullish extension", "message": "Bullish structure is extended by overbought momentum.", "effect": "Prefer observation or a retest instead of chasing price."})
    if bias == "BEARISH" and rsi_state == "OVERSOLD":
        contradictions.append({"type": "extension", "severity": "medium", "title": "Bearish extension", "message": "Bearish structure is extended by oversold momentum.", "effect": "Prefer observation or a retest instead of chasing price."})

    smc = None
    smc_error = None
    try:
        ohlc = [OHLC(open=float(c["open"]), high=float(c["high"]), low=float(c["low"]), close=float(c["close"])) for c in candles[-200:]]
        smc = smc_signal(SMCSignalRequest(symbol=symbol.upper(), candles=ohlc))
    except Exception as exc:
        smc_error = str(exc)
    smc_action = smc.get("action") if smc else "unavailable"
    smc_conflict = bool(smc and smc_action in {"buy", "sell"} and ((smc_action == "buy" and bias == "BEARISH") or (smc_action == "sell" and bias == "BULLISH")))
    if smc_conflict:
        contradictions.append({"type": "technical_smc", "severity": "high", "title": "EMA/RSI vs SMC disagreement", "message": f"EMA/RSI bias is {bias}, while SMC research points to {smc_action.upper()}.", "effect": "Do not promote the hypothesis until the structural disagreement is resolved."})

    confidence = 0.50
    if ema_bias == bias and bias != "NEUTRAL":
        confidence += 0.14
    if momentum_bias == bias and bias != "NEUTRAL":
        confidence += 0.12
    if smc and ((smc_action == "buy" and bias == "BULLISH") or (smc_action == "sell" and bias == "BEARISH")):
        confidence += 0.12
    confidence -= 0.15 * sum(item["severity"] == "high" for item in contradictions)
    confidence -= 0.07 * sum(item["severity"] == "medium" for item in contradictions)
    confidence = round(max(0.0, min(0.95, confidence)), 3)

    current_ranges = [float(c["high"]) - float(c["low"]) for c in candles[-14:]]
    previous_ranges = [float(c["high"]) - float(c["low"]) for c in candles[-28:-14]]
    current_avg, previous_avg = mean(current_ranges), mean(previous_ranges) if previous_ranges else mean(current_ranges)
    regime = "HIGH" if current_avg > previous_avg * 1.20 else "LOW" if current_avg < previous_avg * 0.80 else "NORMAL"
    time_engine = _time_context(timeframe)
    action = "WATCH" if contradictions or confidence < 0.60 else "EXPERIMENT"

    return {
        "status": "analyzed", "symbol": symbol, "timeframe": timeframe, "event": event, "last_price": last, "bias": bias, "confidence": confidence,
        "market_pulse": {"summary": f"{bias} bias; EMA={ema_bias}, RSI={momentum_bias}, volatility={regime}, confidence={confidence:.0%}.", "trend": ema_bias, "momentum": momentum_bias, "volatility": regime, "structure": "conflicted" if contradictions else "aligned"},
        "technical": {
            "ema": {"fast_period": 9, "slow_period": 21, "fast": round(ema_fast, 6), "slow": round(ema_slow, 6), "bias": ema_bias, "explanation": "EMA 9 reacts faster to recent price; EMA 21 provides the slower trend baseline. Their relationship is the trend component."},
            "rsi": {"period": 14, "value": round(rsi, 3), "state": rsi_state, "bias": momentum_bias, "explanation": "RSI measures momentum. 70+ is overbought and 30- oversold; 45/55 are the directional bands used by this model."},
            "atr": {"period": 14, "value": round(atr, 6), "regime": regime, "explanation": "ATR measures recent true range and is used as a volatility/risk input, not as a direction signal.", "current_avg_range": round(current_avg, 6), "previous_avg_range": round(previous_avg, 6)},
        },
        "smc": {"status": "READY" if smc else "UNAVAILABLE", "strategy": "smc-v1", "action": smc_action, "confidence": smc.get("confidence") if smc else None, "bos": smc.get("structure", {}).get("bos") if smc else None, "choch": smc.get("structure", {}).get("choch") if smc else None, "liquidity_sweep": smc.get("liquidity", {}).get("sweep") if smc else None, "fair_value_gaps": len(smc.get("fair_value_gaps", [])) if smc else 0, "order_blocks": len(smc.get("order_blocks", [])) if smc else 0, "explanation": "Deterministic SMC v1 research heuristic: structure breaks, CHOCH, liquidity sweeps, FVG and order blocks. It has no execution authority.", "error": smc_error},
        "contradiction_detector": {"status": "WATCH" if contradictions else "CLEAR", "count": len(contradictions), "items": contradictions, "explanation": "Compares independent evidence streams. Contradictions reduce confidence or block promotion; they never create an order."},
        "time_engine": time_engine,
        "domino_state": {"status": "READY", "state": "technical_context_only", "chain": ["market_data", "technical_context", "hypothesis", "experiment", "validation", "risk_gate"], "current_effect": "No downstream order impact is authorized from Market Intelligence alone.", "explanation": "Shows the controlled path from observation to validation without skipping the Risk Gate."},
        "hypothesis": {"bias": bias, "confidence": confidence, "action": action, "thesis": f"{bias} is supported by the available technical evidence and {'SMC structure.' if smc and not smc_conflict else 'requires further reconciliation/validation.'}", "evidence": ["EMA 9/21", "RSI 14", "ATR 14", "SMC v1", "volatility regime", "timeframe context"], "order_allowed": False},
        "research_only": True, "live": False, "real_money": False, "risk_gate_authoritative": True,
    }
