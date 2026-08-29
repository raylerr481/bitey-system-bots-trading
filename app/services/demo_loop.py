from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.strategies.technical import TechnicalSignalRequest, technical_signal
from app.services.demo_engine import DemoEngine
from app.intelligence.market_intelligence import MarketIntelligenceEngine, NewsEvent


class DemoTradingLoop:
    """Runs deterministic strategy -> risk -> virtual execution cycles.

    Market Intelligence is an optional upstream gate. It can propose a
    direction, but it never executes an order and never bypasses Strategy or
    the Risk Engine.
    """

    def __init__(self, initial_capital: float = 10_000, max_position_pct: float = 0.02,
                 max_daily_loss_pct: float = 0.01):
        self.portfolio = DemoPortfolio(initial_capital=initial_capital, cash=initial_capital)
        self.risk = RiskEngine(max_position_pct, max_daily_loss_pct)
        self.engine = DemoEngine(self.portfolio, self.risk)
        self.intelligence = MarketIntelligenceEngine()

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

    @staticmethod
    def _normalize_symbol(symbol: str) -> str:
        return symbol.upper().replace("/", "").replace("-", "")

    def run_with_intelligence(
        self,
        request: TechnicalSignalRequest,
        event: NewsEvent,
        confirmed_assets: tuple[str, ...] = (),
        quantity: float = 1,
    ) -> dict:
        """Run Demo only when Intelligence confirms a matching opportunity.

        The news analysis is advisory. Strategy must agree with the direction,
        and the normal DemoEngine/RiskEngine path remains the final execution gate.
        """
        analysis = self.intelligence.analyze(event, confirmed_assets)
        symbol = self._normalize_symbol(request.symbol)
        candidates = [
            item for item in analysis["opportunities"]
            if self._normalize_symbol(item["asset"]) == symbol
        ]
        opportunity = max(candidates, key=lambda item: item["score"], default=None)

        base = {
            "mode": "demo",
            "executed": False,
            "intelligence": analysis,
            "portfolio": self.portfolio.model_dump(),
        }

        if opportunity is None:
            base["reason"] = "No intelligence opportunity for requested symbol"
            return base

        if opportunity["action"] != "watch-confirmed":
            base["reason"] = "Intelligence opportunity is not confirmed"
            return base

        signal = technical_signal(request)
        base["signal"] = signal
        base["price"] = request.prices[-1]

        expected_action = "buy" if opportunity["direction"] == "bullish" else "sell"
        if signal["action"] != expected_action:
            base["reason"] = "Strategy contradicts intelligence direction"
            return base

        side = Side.BUY if signal["action"] == "buy" else Side.SELL
        order = OrderIntent(symbol=signal["symbol"], side=side, quantity=quantity)
        execution = self.engine.simulate_order(order, request.prices[-1])
        base["execution"] = execution
        base["executed"] = execution.get("executed", False)
        base["portfolio"] = self.portfolio.model_dump()
        return base

    def snapshot(self) -> dict:
        return self.portfolio.model_dump()
