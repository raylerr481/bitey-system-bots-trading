from pydantic import BaseModel, Field


class RiskDecisionRequest(BaseModel):
    equity: float = Field(gt=0)
    cash: float = Field(ge=0)
    price: float = Field(gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=0.20)
    max_daily_loss_pct: float = Field(default=0.01, gt=0, le=0.10)
    daily_pnl: float = 0.0


def risk_decision(request: RiskDecisionRequest) -> dict:
    daily_loss_limit = request.equity * request.max_daily_loss_pct
    if request.daily_pnl <= -daily_loss_limit:
        return {"allowed": False, "reason": "daily_loss_limit_reached", "max_quantity": 0}

    max_notional = request.equity * request.max_position_pct
    max_quantity = int(min(request.cash, max_notional) // request.price)
    if max_quantity <= 0:
        return {"allowed": False, "reason": "insufficient_risk_budget", "max_quantity": 0}

    return {
        "allowed": True,
        "reason": "within_limits",
        "max_quantity": max_quantity,
        "max_notional": round(max_quantity * request.price, 2),
        "daily_loss_limit": round(daily_loss_limit, 2),
    }
