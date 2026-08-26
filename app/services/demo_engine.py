from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine

class DemoEngine:
    def __init__(self, portfolio: DemoPortfolio, risk: RiskEngine):
        self.portfolio = portfolio
        self.risk = risk

    def simulate_order(self, order: OrderIntent, price: float):
        if price <= 0:
            return {"executed": False, "reason": "Price must be positive"}
        notional = order.quantity * price
        decision = self.risk.approve(self.portfolio.cash, notional, self.portfolio.realized_pnl)
        if not decision.allowed:
            return {"executed": False, "reason": decision.reason}
        if order.side is Side.BUY:
            if notional > self.portfolio.cash:
                return {"executed": False, "reason": "Insufficient virtual cash"}
            self.portfolio.cash -= notional
        else:
            self.portfolio.cash += notional
        return {"executed": True, "mode": "demo", "symbol": order.symbol, "side": order.side.value, "quantity": order.quantity, "price": price, "notional": notional}
