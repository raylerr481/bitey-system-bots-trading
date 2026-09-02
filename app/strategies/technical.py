from pydantic import BaseModel, Field


class TechnicalSignalRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=12)
    prices: list[float] = Field(min_length=30)
    fast_window: int = Field(default=10, ge=2, le=50)
    slow_window: int = Field(default=30, ge=5, le=200)


def technical_signal(request: TechnicalSignalRequest) -> dict:
    prices = request.prices
    fast = sum(prices[-request.fast_window:]) / request.fast_window
    slow = sum(prices[-request.slow_window:]) / request.slow_window
    if fast > slow:
        action = "buy"
    elif fast < slow:
        action = "sell"
    else:
        action = "hold"
    gap = abs(fast - slow) / slow if slow else 0
    confidence = min(0.99, 0.5 + gap * 10)
    return {
        "symbol": request.symbol.upper(),
        "action": action,
        "confidence": round(confidence, 4),
        "fast_sma": round(fast, 6),
        "slow_sma": round(slow, 6),
        "strategy": "sma-crossover-v1",
    }


def _ema(values: list[float], period: int) -> float:
    if len(values) < period:
        raise ValueError("Not enough prices for EMA")
    value = sum(values[:period]) / period
    alpha = 2 / (period + 1)
    for price in values[period:]:
        value = alpha * price + (1 - alpha) * value
    return value


def _rsi(values: list[float], period: int = 14) -> float:
    if len(values) < period + 1:
        raise ValueError("Not enough prices for RSI")
    changes = [values[i] - values[i - 1] for i in range(1, len(values))]
    recent = changes[-period:]
    gains = sum(max(change, 0) for change in recent) / period
    losses = sum(max(-change, 0) for change in recent) / period
    if losses == 0:
        return 100.0
    return 100 - (100 / (1 + gains / losses))


def _atr_from_closes(values: list[float], period: int = 14) -> float:
    if len(values) < period + 1:
        raise ValueError("Not enough prices for ATR")
    ranges = [abs(values[i] - values[i - 1]) for i in range(1, len(values))]
    return sum(ranges[-period:]) / period


class EmaRsiAtrRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=12)
    prices: list[float] = Field(min_length=30)
    ema_fast: int = Field(default=9, ge=2, le=50)
    ema_slow: int = Field(default=21, ge=5, le=100)
    rsi_period: int = Field(default=14, ge=2, le=50)
    atr_period: int = Field(default=14, ge=2, le=50)
    rsi_buy_max: float = Field(default=70, gt=50, lt=100)
    rsi_sell_min: float = Field(default=30, gt=0, lt=50)


def ema_rsi_atr_signal(request: EmaRsiAtrRequest) -> dict:
    prices = request.prices
    fast = _ema(prices, request.ema_fast)
    slow = _ema(prices, request.ema_slow)
    rsi = _rsi(prices, request.rsi_period)
    atr = _atr_from_closes(prices, request.atr_period)
    if fast > slow and rsi < request.rsi_buy_max:
        action = "buy"
    elif fast < slow and rsi > request.rsi_sell_min:
        action = "sell"
    else:
        action = "hold"
    spread = abs(fast - slow) / slow if slow else 0
    confidence = min(0.99, 0.5 + spread * 12)
    return {
        "symbol": request.symbol.upper(),
        "action": action,
        "confidence": round(confidence, 4),
        "ema_fast": round(fast, 6),
        "ema_slow": round(slow, 6),
        "rsi": round(rsi, 4),
        "atr": round(atr, 6),
        "strategy": "ema-rsi-atr-v1",
    }
