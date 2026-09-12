from __future__ import annotations

import os
import httpx
from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field
from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine

router = APIRouter(prefix="/api/v1/trading", tags=["trading"])
portfolio = DemoPortfolio(initial_capital=10_000, cash=10_000)
risk = RiskEngine(allowed_symbols={"EURUSD"})
engine = DemoEngine(portfolio, risk)

SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")
REQUIRED_LIVE_DOC_TYPES = {"terms", "privacy", "risk_disclosure"}


class DemoOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    side: Side
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)


@router.get("/portfolio")
def get_portfolio():
    return portfolio.model_dump()


@router.post("/demo/order")
def demo_order(request: DemoOrderRequest):
    order = OrderIntent(symbol=request.symbol, side=request.side, quantity=request.quantity)
    return engine.simulate_order(order, request.price)


async def _live_identity(authorization: str | None) -> tuple[str, set[str]]:
    """Validate a Supabase session and verify all active SBT legal acceptances."""
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Real-money trading requires a registered account")
    if not SUPABASE_URL or not SUPABASE_ANON_KEY:
        raise HTTPException(status_code=503, detail="Account verification is not configured")

    token = authorization.split(" ", 1)[1].strip()
    headers = {"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15) as client:
        user_response = await client.get(f"{SUPABASE_URL}/auth/v1/user", headers=headers)
        if user_response.status_code >= 400:
            raise HTTPException(status_code=401, detail="Valid registered account required")
        user = user_response.json()
        user_id = user.get("id")
        if not user_id:
            raise HTTPException(status_code=401, detail="Valid registered account required")
        docs_response = await client.get(
            f"{SUPABASE_URL}/rest/v1/user_legal_acceptances",
            headers={**headers, "Accept": "application/json"},
            params={"select": "document_id,legal_documents!inner(document_type,product,active)", "user_id": f"eq.{user_id}", "product": "eq.sbt"},
        )
    if docs_response.status_code >= 400:
        raise HTTPException(status_code=403, detail="Legal acceptance status could not be verified")
    accepted = set()
    for row in docs_response.json() or []:
        doc = row.get("legal_documents") or {}
        if doc.get("product") == "sbt" and doc.get("active") is True and doc.get("document_type") in REQUIRED_LIVE_DOC_TYPES:
            accepted.add(doc["document_type"])
    return user_id, accepted


@router.get("/live/eligibility")
async def live_eligibility(authorization: str | None = Header(default=None)):
    """Hard gate for future real-money trading; this milestone never enables live orders."""
    _, accepted = await _live_identity(authorization)
    missing = sorted(REQUIRED_LIVE_DOC_TYPES - accepted)
    if missing:
        return {"eligible": False, "registered": True, "legal_accepted": False, "missing_legal": missing, "live_enabled": False}
    return {"eligible": False, "registered": True, "legal_accepted": True, "missing_legal": [], "live_enabled": False, "reason": "Live trading remains disabled until the live execution milestone is explicitly enabled."}
