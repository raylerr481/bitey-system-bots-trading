from __future__ import annotations

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.registries.ai_provider_registry import get_ai_provider, validate_ai_connection
from app.registries.platform_connector_registry import get_platform, list_platforms

router = APIRouter(prefix="/api/v1/integrations", tags=["integrations"])

Permission = Literal[
    "read_market",
    "read_account",
    "research",
    "strategy_write",
    "demo_execute",
    "paper_execute",
    "live_execute",
    "admin",
]

PERMISSIONS = [
    {"id": "read_market", "label": "Leer mercado", "risk": "low"},
    {"id": "read_account", "label": "Leer cuenta/portfolio", "risk": "low"},
    {"id": "research", "label": "Investigar y analizar", "risk": "low"},
    {"id": "strategy_write", "label": "Crear/modificar estrategias", "risk": "medium"},
    {"id": "demo_execute", "label": "Ejecutar Demo", "risk": "medium"},
    {"id": "paper_execute", "label": "Ejecutar Paper", "risk": "medium"},
    {"id": "live_execute", "label": "Ejecutar dinero real", "risk": "critical"},
]


class ConnectionPlan(BaseModel):
    ai_provider: str = Field(min_length=1, max_length=80)
    ai_connection: Literal["api", "mcp", "direct_user", "other"] = "mcp"
    platform: str = Field(min_length=1, max_length=80)
    mode: Literal["demo", "paper", "live"] = "demo"
    permissions: list[Permission] = Field(default_factory=list)
    automation: bool = False


@router.get("/platforms")
def platforms():
    # Compatibility endpoint: the canonical platform definitions live in the registry.
    return {"platforms": list_platforms()}


@router.get("/permissions")
def permissions():
    return {"permissions": PERMISSIONS, "live_default": False}


@router.post("/plan")
def plan(request: ConnectionPlan):
    provider = get_ai_provider(request.ai_provider)
    if not provider:
        return {"allowed": False, "stage": "ai-selection", "reason": "Unsupported AI provider"}

    ai_validation = validate_ai_connection(request.ai_provider, request.ai_connection)
    if not ai_validation["valid"]:
        return {"allowed": False, "stage": "ai-connection", "reason": ai_validation["reason"]}

    platform = get_platform(request.platform)
    live_requested = request.mode == "live" or "live_execute" in request.permissions

    if live_requested:
        return {
            "allowed": False,
            "stage": "safety-gates",
            "reason": "Real-money execution is not enabled in the current milestone.",
            "next": [
                "authenticated_user",
                "explicit_real_account",
                "risk_limits",
                "strategy_validation",
                "broker_health",
                "audit_trail",
                "final_confirmation",
            ],
        }

    if not platform:
        return {"allowed": False, "stage": "platform-selection", "reason": "Unsupported platform"}

    if request.mode not in platform.modes:
        return {
            "allowed": False,
            "stage": "platform-selection",
            "reason": "Execution mode is not supported by this platform",
        }

    if request.automation and not any(
        permission in request.permissions for permission in ["demo_execute", "paper_execute"]
    ):
        return {
            "allowed": False,
            "stage": "permissions",
            "reason": "Automation requires an explicit execution permission.",
        }

    return {
        "allowed": True,
        "stage": "ready-for-connection",
        "plan": {
            "ai_provider": request.ai_provider,
            "ai_connection": request.ai_connection,
            "platform": platform.__dict__,
            "mode": request.mode,
            "permissions": request.permissions,
            "automation": request.automation,
            "risk_gate": "mandatory",
            "user_controls_external_costs": True,
        },
    }
