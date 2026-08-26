from dataclasses import dataclass

@dataclass(frozen=True)
class RiskDecision:
    allowed: bool
    reason: str

class RiskEngine:
    def __init__(self, max_position_pct: float = 0.02, max_daily_loss_pct: float = 0.01):
        self.max_position_pct = max_position_pct
        self.max_daily_loss_pct = max_daily_loss_pct

    def approve(self, capital: float, notional: float, daily_pnl: float) -> RiskDecision:
        if capital <= 0:
            return RiskDecision(False, "Capital must be positive")
        if notional > capital * self.max_position_pct:
            return RiskDecision(False, "Position exceeds maximum position size")
        if daily_pnl < -(capital * self.max_daily_loss_pct):
            return RiskDecision(False, "Daily loss limit reached")
        return RiskDecision(True, "Approved")
