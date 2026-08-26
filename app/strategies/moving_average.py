from .base import MarketSnapshot, Signal, Strategy

class MovingAverageStrategy(Strategy):
    name = "moving-average-demo"

    def evaluate(self, snapshot: MarketSnapshot) -> Signal:
        # Placeholder deterministic signal contract. Historical series will be
        # added by the backtest engine before any live execution is considered.
        return Signal(symbol=snapshot.symbol, action="hold", confidence=1.0)
