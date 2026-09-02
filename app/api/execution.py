from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.execution_policy import ExecutionPolicy

router = APIRouter(prefix="/api/v1/execution", tags=["execution"])
policy = ExecutionPolicy()


class ExecutionCheck(BaseModel):
    platform: str = Field(min_length=1, max_length=80)
    mode: str = Field(min_length=1, max_length=20)
    capital: float = Field(gt=0)
    notional: float = Field(ge=0)
    daily_pnl: float
    permissions: list[str] = []


@router.post("/authorize")
def authorize(request: ExecutionCheck):
    decision, risk = policy.authorize_order(
        platform=request.platform,
        mode=request.mode,
        capital=request.capital,
        notional=request.notional,
        daily_pnl=request.daily_pnl,
        permissions=request.permissions,
    )
    return {
        "allowed": decision.allowed,
        "stage": decision.stage,
        "reason": decision.reason,
        "risk": {"allowed": risk.allowed, "reason": risk.reason} if risk else None,
        "execution": "safe_mode_only" if decision.allowed else "blocked",
    }


@router.get("/status")
def execution_status():
    return {
        "demo": "available",
        "paper": "available",
        "live": "locked",
        "fail_closed": True,
        "risk_gate": "mandatory",
        "broker_credentials_exposed_to_ai": False,
    }
