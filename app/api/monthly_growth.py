"""Monthly compound-growth API for Bitey SBT.

Preview is side-effect free by default. Persistence and Q-learning submission
must be explicitly requested by the caller. No endpoint in this module creates
broker orders.
"""
from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

import httpx
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.core.monthly_growth import MonthlyCompoundGrowthEngine
from app.storage import monthly_growth as growth_store

router = APIRouter(prefix="/api/v1/monthly-growth", tags=["monthly-growth"])

BITEY_Q_LEARNING_URL = os.getenv(
    "BITEY_Q_LEARNING_URL",
    "https://bitey-ia-suprabrain.onrender.com/api/v1/q-learning/experience",
).rstrip("/")


class MonthlyGrowthRequest(BaseModel):
    month_start: datetime
    trades: list[dict[str, Any]] = Field(default_factory=list)
    opening_capital_usd: float | None = Field(default=None, gt=0)
    environment: str = Field(default="DEMO", pattern=r"^(DEMO|REAL|PAPER)$")
    scope_key: str = Field(default="traderwill-mt4", min_length=1, max_length=120)
    risk_gate: dict[str, Any] = Field(default_factory=dict)
    persist: bool = False
    send_to_q_learning: bool = False


@router.post("/preview")
async def preview_month(request: MonthlyGrowthRequest):
    """Calculate one month without persistence, learning side effects, or orders."""
    engine = MonthlyCompoundGrowthEngine()
    result = engine.build_month(
        month_start=request.month_start,
        trades=request.trades,
        opening_capital_usd=request.opening_capital_usd,
        environment=request.environment,
        scope_key=request.scope_key,
        risk_gate=request.risk_gate,
    )
    payload = result.to_dict()

    persistence = {"persisted": False, "reason": "PREVIEW_ONLY"}
    q_learning = {"sent": False, "reason": "PREVIEW_ONLY"}

    if request.persist:
        persistence = growth_store.save(payload)

    if request.send_to_q_learning:
        q_learning = await _send_q_learning(result)

    return {
        "ok": True,
        "mode": "preview",
        "result": payload,
        "persistence": persistence,
        "q_learning": q_learning,
        "execution": {
            "broker_orders": 0,
            "new_trade_created": False,
            "risk_gate_authoritative": True,
        },
    }


async def _send_q_learning(result) -> dict[str, Any]:
    context = {
        "current_intent_domain": "trading",
        "source": "bitey_sbt_monthly_growth",
        "domain_context": {
            "task_type": "monthly_compound_growth",
            "workflow": "monthly_performance",
            "environment": result.environment,
            "scope_key": result.scope_key,
        },
        "sbt": {
            "operational_capital_usd": result.capital_end_usd,
            "initial_operational_capital_usd": result.initial_capital_usd,
            "risk_gate": "authoritative",
            "martingale": False,
        },
    }
    body = {
        "state_context": context,
        "next_context": context,
        "action": "MONTHLY_COMPOUND_GROWTH",
        "reward": result.q_learning_reward,
        "pnl_usd": result.net_pnl_usd,
        "drawdown_pct": result.max_drawdown_pct,
        "risk_used_pct": result.risk_gate.get("risk_pct"),
        "source": "bitey_sbt_monthly_growth",
        "outcome": "SUCCESS" if result.net_pnl_usd > 0 else "FAILURE" if result.net_pnl_usd < 0 else "NEUTRAL",
        "symbol": "EURUSD",
        "timeframe": "H1",
        "risk_gate_allowed": True,
        "operational_capital_usd": result.capital_end_usd,
    }
    try:
        async with httpx.AsyncClient(timeout=8) as client:
            response = await client.post(BITEY_Q_LEARNING_URL, json=body)
        return {
            "sent": response.status_code < 400,
            "status": response.status_code,
            "reward": result.q_learning_reward,
        }
    except Exception as exc:
        return {"sent": False, "reason": type(exc).__name__}


@router.get("/recent")
def recent_months(limit: int = 24):
    items = growth_store.list_recent(limit)
    return {
        "items": items,
        "count": len(items),
        "persistent_store": bool(items),
    }
