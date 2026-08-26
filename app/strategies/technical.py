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
