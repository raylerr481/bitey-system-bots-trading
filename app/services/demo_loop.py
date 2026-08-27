from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.strategies.technical import TechnicalSignalRequest, technical_signal
from app.services.demo_engine import DemoEngine


class DemoTradingLoop:
    """Runs one deterministic strategy -> risk -> virtual execution cycle."""

    def __init__(self, initial_capital: float = 10_000, max_position_pct: float = 0.02,
                 max_daily_loss_pct: float = 0.01):
        self.portfolio = DemoPortfolio(initial_capital=initial_capital, cash=initial_capital)
        self.risk = RiskEngine(max_position_pct, max_daily_loss_pct)
        self.engine = DemoEngine(self.portfolio, self.risk)

    def run(self, request: TechnicalSignalRequest, quantity: float = 1) -> dict:
        signal = technical_signal(request)
        price = request.prices[-1]

        result = {
            "mode": "demo",
            "signal": signal,
            "price": price,
            "executed": False,
            "portfolio": self.portfolio.model_dump(),
        }

        if signal["action"] == "hold":
            result["reason"] = "Strategy returned hold"
            return result

        side = Side.BUY if signal["action"] == "buy" else Side.SELL
        order = OrderIntent(symbol=signal["symbol"], side=side, quantity=quantity)
        execution = self.engine.simulate_order(order, price)
        result["execution"] = execution
        result["executed"] = execution.get("executed", False)
        result["portfolio"] = self.portfolio.model_dump()
        return result

    def snapshot(self) -> dict:
        return self.portfolio.model_dump()
