from __future__ import annotations

from datetime import datetime, timezone
from typing import Literal
from uuid import uuid4

from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/financial", tags=["financial-hub"])

# Phase 1 is a non-custodial control/readiness layer.
# No bank credentials, Pix keys, wallet secrets, or real-money transfers are stored here.
_LEDGER = {
    "currency": "BRL",
    "available_balance": 0.0,
    "pending_deposits": 0.0,
    "pending_withdrawals": 0.0,
    "transactions": [],
}


class DepositRequest(BaseModel):
    amount: float = Field(gt=0, le=1_000_000)
    method: Literal["PIX", "PIX_CHARGE", "OPEN_FINANCE"] = "PIX"
    description: str = Field(default="Deposit request", max_length=200)


class WithdrawalRequest(BaseModel):
    amount: float = Field(gt=0, le=1_000_000)
    method: Literal["PIX", "BANK_TRANSFER"] = "PIX"
    destination_label: str = Field(default="", max_length=120)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _tx(kind: str, amount: float, method: str, status: str, **extra):
    item = {
        "id": "fin_" + uuid4().hex[:16],
        "kind": kind,
        "amount": round(amount, 2),
        "currency": "BRL",
        "method": method,
        "status": status,
        "created_at": _now(),
        **extra,
    }
    _LEDGER["transactions"].insert(0, item)
    _LEDGER["transactions"] = _LEDGER["transactions"][:50]
    return item


@router.get("/status")
def financial_status():
    return {
        "hub": "Bitey Financial Hub",
        "mode": "READINESS_ONLY",
        "custody": False,
        "real_money_enabled": False,
        "pix": {"available": True, "connected": False, "action": "PREPARE_ONLY"},
        "pix_charge": {"available": True, "connected": False, "action": "PREPARE_ONLY"},
        "open_finance": {"available": True, "connected": False, "action": "AUTHORIZATION_REQUIRED"},
        "withdrawals": {"available": True, "connected": False, "action": "REQUEST_ONLY"},
        "broker_funding": {"enabled": False},
        "balance": {
            "currency": _LEDGER["currency"],
            "available": _LEDGER["available_balance"],
            "pending_deposits": _LEDGER["pending_deposits"],
            "pending_withdrawals": _LEDGER["pending_withdrawals"],
        },
        "transactions": _LEDGER["transactions"][:20],
        "security": {
            "bank_credentials_stored": False,
            "broker_password_stored": False,
            "manual_confirmation_required": True,
            "financial_risk_gate": True,
        },
    }


@router.post("/deposits")
def create_deposit(request: DepositRequest):
    item = _tx(
        "DEPOSIT",
        request.amount,
        request.method,
        "PENDING_PROVIDER",
        description=request.description,
        provider_connected=False,
        next_step="Connect an authorized payment/Open Finance provider before settlement.",
    )
    _LEDGER["pending_deposits"] += request.amount
    return {
        "accepted": True,
        "settled": False,
        "money_moved": False,
        "transaction": item,
        "message": "Deposit request prepared. No real-money movement occurs in the current readiness phase.",
    }


@router.post("/withdrawals")
def create_withdrawal(request: WithdrawalRequest):
    if request.amount > _LEDGER["available_balance"]:
        return {
            "accepted": False,
            "settled": False,
            "money_moved": False,
            "reason": "INSUFFICIENT_AVAILABLE_BALANCE",
        }
    item = _tx(
        "WITHDRAWAL",
        request.amount,
        request.method,
        "PENDING_REVIEW",
        destination_label=request.destination_label,
        provider_connected=False,
        next_step="Authenticate and connect an authorized financial provider before settlement.",
    )
    _LEDGER["pending_withdrawals"] += request.amount
    return {
        "accepted": True,
        "settled": False,
        "money_moved": False,
        "transaction": item,
        "message": "Withdrawal request prepared. No real-money movement occurs in the current readiness phase.",
    }
