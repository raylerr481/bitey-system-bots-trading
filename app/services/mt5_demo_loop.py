"""Read-only MT5 market data -> strategy -> Demo execution adapter."""

from app.services.mt5_market_data import MT5MarketData
from app.services.demo_state import get_demo_state
from app.strategies.technical import TechnicalSignalRequest


class MT5DemoLoop:
    def __init__(self, market_data: MT5MarketData):
        self.market_data = market_data

    async def run(
        self,
        symbol: str,
        timeframe: str = "M5",
        count: int = 30,
        fast_window: int = 10,
        slow_window: int = 30,
        quantity: float = 1,
    ) -> dict:
        prices = await self.market_data.candles(symbol, timeframe, count)
        if len(prices) < slow_window:
            return {
                "mode": "demo",
                "provider": "metatrader5",
                "executed": False,
                "reason": f"Not enough candles: {len(prices)} < {slow_window}",
                "prices_count": len(prices),
            }

        request = TechnicalSignalRequest(
            symbol=symbol.upper(),
            prices=prices,
            fast_window=fast_window,
            slow_window=slow_window,
        )
        result = get_demo_state().run(request, quantity=quantity)
        result["provider"] = "metatrader5"
        result["timeframe"] = timeframe.upper()
        result["prices_count"] = len(prices)
        return result
