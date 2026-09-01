from __future__ import annotations

import os
import httpx
from fastapi import APIRouter, HTTPException
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
    return {"configured": bool(SUPABASE_URL and SUPABASE_ANON_KEY), "provider": "supabase_auth", "registration": "email_password"}
