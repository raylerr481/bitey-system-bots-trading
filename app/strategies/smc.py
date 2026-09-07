from pydantic import BaseModel, Field


class OHLC(BaseModel):
    open: float = Field(gt=0)
    high: float = Field(gt=0)
    low: float = Field(gt=0)
    close: float = Field(gt=0)


class SMCSignalRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=12)
    candles: list[OHLC] = Field(min_length=20)
    swing_window: int = Field(default=2, ge=1, le=5)


def _swings(candles: list[OHLC], window: int) -> tuple[list[tuple[int, float]], list[tuple[int, float]]]:
    highs: list[tuple[int, float]] = []
    lows: list[tuple[int, float]] = []
    for i in range(window, len(candles) - window):
        high = candles[i].high
        low = candles[i].low
        if high > max(c.high for c in candles[i - window:i]) and high >= max(c.high for c in candles[i + 1:i + window + 1]):
            highs.append((i, high))
        if low < min(c.low for c in candles[i - window:i]) and low <= min(c.low for c in candles[i + 1:i + window + 1]):
            lows.append((i, low))
    return highs, lows


def _fvg(candles: list[OHLC]) -> list[dict]:
    gaps: list[dict] = []
    for i in range(2, len(candles)):
        left, middle, right = candles[i - 2], candles[i - 1], candles[i]
        if right.low > left.high:
            gaps.append({"index": i, "type": "bullish", "low": left.high, "high": right.low})
        elif right.high < left.low:
            gaps.append({"index": i, "type": "bearish", "low": right.high, "high": left.low})
    return gaps


def _order_blocks(candles: list[OHLC], swing_highs: list[tuple[int, float]], swing_lows: list[tuple[int, float]]) -> list[dict]:
    blocks: list[dict] = []
    for index, _ in swing_highs[-3:]:
        if index > 0 and candles[index].close < candles[index].open:
            blocks.append({"index": index, "type": "bearish", "low": candles[index].low, "high": candles[index].high})
    for index, _ in swing_lows[-3:]:
        if index > 0 and candles[index].close > candles[index].open:
            blocks.append({"index": index, "type": "bullish", "low": candles[index].low, "high": candles[index].high})
    return blocks[-6:]


def smc_signal(request: SMCSignalRequest) -> dict:
    candles = request.candles
    highs, lows = _swings(candles, request.swing_window)
    last_close = candles[-1].close
    previous_high = highs[-1][1] if highs else None
    previous_low = lows[-1][1] if lows else None

    bos = None
    if previous_high is not None and last_close > previous_high:
        bos = "bullish"
    elif previous_low is not None and last_close < previous_low:
        bos = "bearish"

    choch = None
    if len(highs) >= 2 and len(lows) >= 2:
        higher_high = highs[-1][1] > highs[-2][1]
        higher_low = lows[-1][1] > lows[-2][1]
        lower_high = highs[-1][1] < highs[-2][1]
        lower_low = lows[-1][1] < lows[-2][1]
        if higher_high and higher_low:
            choch = "bullish_structure"
        elif lower_high and lower_low:
            choch = "bearish_structure"

    liquidity_sweep = None
    if previous_high is not None and candles[-1].high > previous_high and last_close < previous_high:
        liquidity_sweep = "buy_side"
    elif previous_low is not None and candles[-1].low < previous_low and last_close > previous_low:
        liquidity_sweep = "sell_side"

    fvgs = _fvg(candles)
    blocks = _order_blocks(candles, highs, lows)

    action = "hold"
    reasons: list[str] = []
    if liquidity_sweep == "sell_side" and (bos == "bullish" or choch == "bullish_structure"):
        action = "buy"
        reasons.append("sell-side liquidity sweep with bullish structure")
    elif liquidity_sweep == "buy_side" and (bos == "bearish" or choch == "bearish_structure"):
        action = "sell"
        reasons.append("buy-side liquidity sweep with bearish structure")
    elif bos == "bullish":
        action = "buy"
        reasons.append("bullish break of structure")
    elif bos == "bearish":
        action = "sell"
        reasons.append("bearish break of structure")

    if any(g["type"] == "bullish" for g in fvgs[-3:]) and action == "buy":
        reasons.append("recent bullish fair value gap")
    if any(g["type"] == "bearish" for g in fvgs[-3:]) and action == "sell":
        reasons.append("recent bearish fair value gap")

    confidence = 0.5
    confidence += 0.15 if bos else 0
    confidence += 0.15 if choch else 0
    confidence += 0.10 if liquidity_sweep else 0
    confidence += 0.10 if fvgs else 0
    confidence = min(0.95, confidence)

    return {
        "symbol": request.symbol.upper(),
        "action": action,
        "confidence": round(confidence, 4),
        "strategy": "smc-v1",
        "structure": {"bos": bos, "choch": choch},
        "liquidity": {"sweep": liquidity_sweep, "previous_high": previous_high, "previous_low": previous_low},
        "fair_value_gaps": fvgs[-6:],
        "order_blocks": blocks,
        "swing_highs": highs[-6:],
        "swing_lows": lows[-6:],
        "reasons": reasons,
        "research_only": True,
        "live": False,
        "real_money": False,
    }
