from app.core.models import DemoPortfolio, OrderIntent, Side, VirtualPosition
from app.risk.engine import RiskEngine


class DemoEngine:
    def __init__(self, portfolio: DemoPortfolio, risk: RiskEngine):
        self.portfolio = portfolio
        self.risk = risk

    def simulate_order(self, order: OrderIntent, price: float):
        if price <= 0:
            return {"executed": False, "reason": "Price must be positive"}
        notional = order.quantity * price
        decision = self.risk.approve(
            self.portfolio.initial_capital,
            notional,
            self.portfolio.realized_pnl,
            symbol=order.symbol,
            side=order.side,
        )
        if not decision.allowed:
            return {"executed": False, "reason": decision.reason}

        position = next((p for p in self.portfolio.positions if p.symbol == order.symbol), None)
        if order.side is Side.BUY:
            if notional > self.portfolio.cash:
                return {"executed": False, "reason": "Insufficient virtual cash"}
            self.portfolio.cash -= notional
            if position is None:
                self.portfolio.positions.append(
                    VirtualPosition(symbol=order.symbol, quantity=order.quantity, average_price=price)
                )
            else:
                total_qty = position.quantity + order.quantity
                position.average_price = ((position.quantity * position.average_price) + notional) / total_qty
                position.quantity = total_qty
        else:
            if position is None or order.quantity > position.quantity:
                return {"executed": False, "reason": "Insufficient virtual position"}
            self.portfolio.cash += notional
            pnl = (price - position.average_price) * order.quantity
            self.portfolio.realized_pnl += pnl
            position.quantity -= order.quantity
            if position.quantity == 0:
                self.portfolio.positions.remove(position)

        return {
            "executed": True,
            "mode": "demo",
            "real_money": False,
            "broker_order": False,
            "symbol": order.symbol,
            "side": order.side.value,
            "quantity": order.quantity,
            "price": price,
            "notional": notional,
            "realized_pnl": self.portfolio.realized_pnl,
            "virtual_cash": self.portfolio.cash,
        }
