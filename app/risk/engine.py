from dataclasses import dataclass
from enum import Enum


@dataclass(frozen=True)
class RiskDecision:
    allowed: bool
    reason: str


class RiskEngine:
    def __init__(
        self,
        max_position_pct: float = 0.02,
        max_daily_loss_pct: float = 0.01,
        allowed_symbols: set[str] | None = None,
        max_quantity: float | None = None,
    ):
        self.max_position_pct = max_position_pct
        self.max_daily_loss_pct = max_daily_loss_pct
        self.allowed_symbols = allowed_symbols
        self.max_quantity = max_quantity

    def approve(
        self,
        capital: float,
        notional: float,
        daily_pnl: float,
        symbol: str | None = None,
        side: Enum | None = None,
        quantity: float | None = None,
    ) -> RiskDecision:
        if capital <= 0:
            return RiskDecision(False, "Capital must be positive")
        if notional <= 0:
            return RiskDecision(False, "Notional must be positive")
        if self.allowed_symbols is not None and symbol not in self.allowed_symbols:
            return RiskDecision(False, "Symbol is not allowed")
        if self.max_quantity is not None and quantity is not None and quantity > self.max_quantity:
            return RiskDecision(False, "Quantity exceeds maximum allowed")
        if notional > capital * self.max_position_pct:
            return RiskDecision(False, "Position exceeds maximum position size")
        if daily_pnl < -(capital * self.max_daily_loss_pct):
            return RiskDecision(False, "Daily loss limit reached")
        return RiskDecision(True, "Approved")
