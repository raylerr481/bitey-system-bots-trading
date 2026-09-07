from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/capabilities", tags=["capabilities"])

class DelegationRequest(BaseModel):
    contract: str = "sbt-v1"
    capability: str = "sbt"
    message: str = Field(min_length=1, max_length=12000)
    conversation_id: str | None = None
    source: str = "bitey-web"
    mode: str = "research-only"

@router.post("/delegate")
def delegate(request: DelegationRequest):
    if request.contract != "sbt-v1" or request.capability != "sbt":
        raise HTTPException(status_code=400, detail="Invalid SBT delegation contract")
    return {
        "contract": "sbt-v1",
        "capability": "sbt",
        "delegated": True,
        "delegation_status": "accepted",
        "specialization": "trading-intelligence",
        "message": request.message,
        "conversation_id": request.conversation_id,
        "source": request.source,
        "mode": "research-only",
        "execution": {"live": False, "paper": False, "demo": False, "risk_gate_authoritative": True},
        "next_capabilities": ["strategy", "backtesting", "validation", "risk-controls", "market-data"],
        "note": "SBT accepted the delegated capability. Trading actions remain subject to SBT permissions and Risk Gate.",
    }
