from __future__ import annotations
import os
import httpx
from fastapi import APIRouter, HTTPException, Header
from pydantic import BaseModel, EmailStr, Field

router = APIRouter(prefix="/api/v1/auth", tags=["auth"])
SUPABASE_URL = os.getenv("SUPABASE_URL", "").rstrip("/")
SUPABASE_ANON_KEY = os.getenv("SUPABASE_ANON_KEY", "")

class SignUpRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=100)
class SignInRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=1, max_length=128)

def _headers() -> dict[str, str]:
    if not SUPABASE_ANON_KEY:
        raise HTTPException(status_code=503, detail="Supabase Auth is not configured")
    return {"apikey": SUPABASE_ANON_KEY, "Content-Type": "application/json"}

def _bearer(authorization: str | None) -> str:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Authenticated account required")
    return authorization.split(" ", 1)[1].strip()

async def _user(token: str) -> dict:
    headers = {"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15) as client:
        r = await client.get(f"{SUPABASE_URL}/auth/v1/user", headers=headers)
    if r.status_code >= 400:
        raise HTTPException(status_code=401, detail="Invalid or expired account session")
    return r.json()

@router.post("/signup")
async def signup(request: SignUpRequest):
    headers = _headers()
    payload = {"email": str(request.email), "password": request.password, "data": {"display_name": request.display_name} if request.display_name else {}}
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f"{SUPABASE_URL}/auth/v1/signup", headers=headers, json=payload)
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.json())
    return response.json()

@router.post("/signin")
async def signin(request: SignInRequest):
    headers = _headers()
    payload = {"email": str(request.email), "password": request.password}
    async with httpx.AsyncClient(timeout=15) as client:
        response = await client.post(f"{SUPABASE_URL}/auth/v1/token?grant_type=password", headers=headers, json=payload)
    if response.status_code >= 400:
        raise HTTPException(status_code=response.status_code, detail=response.json())
    return response.json()

@router.get("/status")
def auth_status():
    return {"configured": bool(SUPABASE_URL and SUPABASE_ANON_KEY), "provider": "supabase_auth", "registration": "email_password", "registration_required_for_real_money": True}

@router.get("/real-money-gate")
async def real_money_gate(authorization: str | None = Header(default=None)):
    token = _bearer(authorization)
    user = await _user(token)
    uid = user.get("id")
    headers = {"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {token}"}
    async with httpx.AsyncClient(timeout=15) as client:
        docs = await client.get(f"{SUPABASE_URL}/rest/v1/legal_documents", headers=headers, params={"product":"eq.sbt", "active":"eq.true", "select":"id,document_type,version,title"})
        accepts = await client.get(f"{SUPABASE_URL}/rest/v1/user_legal_acceptances", headers=headers, params={"user_id":f"eq.{uid}", "product":"eq.sbt", "select":"document_id"})
    if docs.status_code >= 400 or accepts.status_code >= 400:
        raise HTTPException(status_code=503, detail="Unable to verify SBT legal requirements")
    required = {d["id"] for d in docs.json() if d.get("document_type") in {"terms", "privacy", "risk_disclosure"}}
    accepted = {a["document_id"] for a in accepts.json()}
    missing = sorted(required - accepted)
    return {"registered": True, "legal_required": True, "legal_complete": not missing, "missing_document_ids": missing, "risk_gate_required": True, "live": False, "real_money": False, "broker_orders": 0, "eligible": False, "reason": "Live/real-money trading remains disabled until production verification, broker authorization and Risk Gate infrastructure are implemented."}
