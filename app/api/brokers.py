from __future__ import annotations

import os
import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from app.brokers.registry import catalog, get_adapter

router = APIRouter(prefix="/api/v1/brokers", tags=["brokers"])

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
REQUIRED_LIVE_DOC_TYPES = {"terms", "privacy", "risk_disclosure"}


class BrokerOrder(BaseModel):
    broker: str = Field(min_length=1, max_length=30)
    symbol: str = Field(min_length=1, max_length=30)
    side: str = Field(pattern="^(buy|sell)$")
    quantity: float = Field(gt=0)


@router.get("/catalog")
def broker_catalog():
    return {
        "contract": "sbt-broker-adapter-v1",
        "live": False,
        "real_money": False,
        "broker_orders": 0,
        "brokers": catalog(),
    }


@router.get("/{broker}/account")
def broker_account(broker: str):
    try:
        return get_adapter(broker).account().__dict__
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.get("/{broker}/quote/{symbol}")
def broker_quote(broker: str, symbol: str):
    try:
        return get_adapter(broker).quote(symbol).__dict__
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/paper-order")
def broker_paper_order(order: BrokerOrder):
    try:
        adapter = get_adapter(order.broker)
        capabilities = adapter.capabilities()
        if not capabilities.paper:
            raise ValueError(f"Broker {order.broker} has no paper-order capability")
        result = adapter.submit_order(order.symbol, order.side, order.quantity)
        return {"contract": "sbt-broker-adapter-v1", "execution": "paper", "live": False, "real_money": False, "broker_orders": 0, "result": result}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


async def _require_live_gate(authorization: str | None) -> None:
    """Fail closed. Live execution is unreachable unless every prerequisite is satisfied."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Registered account required for real-money trading")
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        raise HTTPException(status_code=503, detail="Live trading infrastructure is not configured")

    token = authorization.split(" ", 1)[1].strip()
    headers = {"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15) as client:
        user_response = await client.get(f"{SUPABASE_URL}/auth/v1/user", headers=headers)
        if user_response.status_code >= 400 or not user_response.json().get("id"):
            raise HTTPException(status_code=401, detail="Valid registered account required")
        user_id = user_response.json()["id"]
        docs_response = await client.get(
            f"{SUPABASE_URL}/rest/v1/user_legal_acceptances",
            headers={**headers, "Accept": "application/json"},
            params={
                "select": "document_id,legal_documents!inner(document_type,product,active)",
                "user_id": f"eq.{user_id}",
                "product": "eq.sbt",
            },
        )
    if docs_response.status_code >= 400:
        raise HTTPException(status_code=403, detail="Legal acceptance status could not be verified")
    accepted = set()
    for row in docs_response.json() or []:
        doc = row.get("legal_documents") or {}
        if doc.get("product") == "sbt" and doc.get("active") is True and doc.get("document_type") in REQUIRED_LIVE_DOC_TYPES:
            accepted.add(doc["document_type"])
    missing = sorted(REQUIRED_LIVE_DOC_TYPES - accepted)
    if missing:
        raise HTTPException(status_code=403, detail={"reason": "legal_acceptance_required", "missing_legal": missing})

    # Infrastructure kill-switch: this milestone deliberately cannot execute live orders.
    raise HTTPException(status_code=423, detail={
        "reason": "live_trading_disabled",
        "live": False,
        "real_money": False,
        "broker_orders": 0,
        "next_stage": "verification -> broker_authorization -> risk_gate -> explicit_live_enablement",
    })


@router.post("/live-order")
async def broker_live_order(order: BrokerOrder, authorization: str | None = Header(default=None)):
    """Reserved live-order boundary. It always fails closed until the full live milestone is enabled."""
    await _require_live_gate(authorization)
    raise HTTPException(status_code=423, detail="Live trading is disabled")
