from app.core.models import DemoPortfolio, OrderIntent, Side, VirtualPosition
from app.risk.engine import RiskEngine


class DemoEngine:
    """Deterministic virtual execution engine.

    This engine never reaches a broker. It updates only virtual portfolio state.
    Risk controls are mandatory for new exposure; exits are validated against
    the virtual position itself.
    """

    def __init__(self, portfolio: DemoPortfolio, risk: RiskEngine):
        self.portfolio = portfolio
        self.risk = risk

    def simulate_order(self, order: OrderIntent, price: float) -> dict:
        symbol = order.symbol.strip().upper()
        if not symbol:
            return {"executed": False, "reason": "Symbol is required"}
        if price <= 0:
            return {"executed": False, "reason": "Price must be positive"}

        quantity = float(order.quantity)
        notional = quantity * price
        position = self._find_position(symbol)

        if order.side is Side.BUY:
            decision = self.risk.approve(
                self.portfolio.cash, notional, self.portfolio.realized_pnl
            )
            if not decision.allowed:
                return {"executed": False, "reason": decision.reason}
            if notional > self.portfolio.cash:
                return {"executed": False, "reason": "Insufficient virtual cash"}

            old_qty = position.quantity if position else 0.0
            old_avg = position.average_price if position else 0.0
            new_qty = old_qty + quantity
            new_avg = ((old_qty * old_avg) + notional) / new_qty

            self.portfolio.cash -= notional
            if position:
                position.quantity = new_qty
                position.average_price = new_avg
            else:
                self.portfolio.positions.append(
                    VirtualPosition(
                        symbol=symbol,
                        quantity=new_qty,
                        average_price=new_avg,
                    )
                )
        else:
            if position is None or position.quantity < quantity:
                return {"executed": False, "reason": "Insufficient virtual position"}

            realized = (price - position.average_price) * quantity
            self.portfolio.cash += notional
            self.portfolio.realized_pnl += realized
            position.quantity -= quantity

            if position.quantity == 0:
                self.portfolio.positions.remove(position)

        return {
            "executed": True,
            "mode": "demo",
            "symbol": symbol,
            "side": order.side.value,
            "quantity": quantity,
            "price": price,
            "notional": notional,
            "cash": self.portfolio.cash,
            "realized_pnl": self.portfolio.realized_pnl,
            "positions": [p.model_dump() for p in self.portfolio.positions],
        }

    def _find_position(self, symbol: str) -> VirtualPosition | None:
        return next(
            (position for position in self.portfolio.positions if position.symbol == symbol),
            None,
        )
