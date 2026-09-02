from __future__ import annotations

import os
from collections.abc import Awaitable, Callable
from typing import Any

import httpx
from mcp.server import MCPServer
from mcp.server.transport_security import TransportSecuritySettings
from starlette.types import ASGIApp, Receive, Scope, Send

from app.api.integrations import PERMISSIONS, PLATFORMS

MCP_TOKEN = os.getenv("SBT_MCP_TOKEN", "").strip()
MT5_BRIDGE_URL = os.getenv("MT5_BRIDGE_URL", "").rstrip("/")


class BearerGate:
    """Small ASGI auth gate; deliberately not BaseHTTPMiddleware."""

    def __init__(self, app: ASGIApp, token: str) -> None:
        self.app = app
        self.token = token

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        if not self.token:
            await _json_error(send, 503, "MCP authentication is not configured")
            return
        headers = {k.decode().lower(): v.decode() for k, v in scope.get("headers", [])}
        authorization = headers.get("authorization", "")
        if authorization != f"Bearer {self.token}":
            await _json_error(send, 401, "Unauthorized")
            return
        await self.app(scope, receive, send)


async def _json_error(send: Send, status: int, detail: str) -> None:
    body = (f'{{"detail":"{detail}"}}').encode()
    await send({"type": "http.response.start", "status": status, "headers": [(b"content-type", b"application/json"), (b"content-length", str(len(body)).encode())]})
    await send({"type": "http.response.body", "body": body})


mcp = MCPServer("Bitey SBT MCP")


@mcp.tool()
def sbt_system_status() -> dict[str, Any]:
    """Return SBT capabilities and the current execution boundary."""
    return {
        "module": "Bitey System Bots Trading",
        "mcp": True,
        "live_trading_enabled": False,
        "supported_modes": ["demo", "paper"],
        "execution_rule": "AI proposes; SBT permissions and Risk Gate decide.",
        "broker_credentials_exposed_to_ai": False,
    }


@mcp.tool()
def list_trading_platforms() -> list[dict[str, Any]]:
    """List supported trading platforms and their permitted modes."""
    return PLATFORMS


@mcp.tool()
def list_sbt_permissions() -> list[dict[str, Any]]:
    """List SBT permissions and their risk classes."""
    return PERMISSIONS


@mcp.tool()
def create_connection_plan(
    ai_provider: str,
    platform: str,
    mode: str = "demo",
    permissions: list[str] | None = None,
    automation: bool = False,
    ai_connection: str = "mcp",
) -> dict[str, Any]:
    """Validate an AI/platform/permission combination before any connector action."""
    permissions = permissions or []
    selected = next((p for p in PLATFORMS if p["id"] == platform), None)
    if mode == "live" or "live_execute" in permissions:
        return {"allowed": False, "stage": "safety-gates", "reason": "Real-money execution is disabled."}
    if not selected:
        return {"allowed": False, "stage": "platform-selection", "reason": "Unsupported platform"}
    if automation and not any(p in permissions for p in ("demo_execute", "paper_execute")):
        return {"allowed": False, "stage": "permissions", "reason": "Automation requires explicit demo or paper execution permission."}
    return {
        "allowed": True,
        "stage": "ready-for-connection",
        "plan": {
            "ai_provider": ai_provider,
            "ai_connection": ai_connection,
            "platform": selected,
            "mode": mode,
            "permissions": permissions,
            "automation": automation,
            "risk_gate": "mandatory",
        },
    }


@mcp.tool()
def risk_gate_status() -> dict[str, Any]:
    """Return the deterministic SBT execution boundary; live trading stays locked."""
    return {
        "demo": "available",
        "paper": "available",
        "live": "locked",
        "emergency_stop": "required",
        "fail_closed": True,
        "requirements_for_live": [
            "authenticated_user",
            "explicit_real_account",
            "risk_limits",
            "validated_strategy",
            "broker_health",
            "audit_trail",
            "final_confirmation",
        ],
    }


@mcp.tool()
async def mt5_status() -> dict[str, Any]:
    """Check the MT5 bridge without exposing broker credentials."""
    if not MT5_BRIDGE_URL:
        return {"provider": "metatrader5", "bridge_configured": False, "live_trading_enabled": False}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{MT5_BRIDGE_URL}/status")
            response.raise_for_status()
            data = response.json()
            data["live_trading_enabled"] = False
            return data
    except httpx.HTTPError as exc:
        return {"provider": "metatrader5", "bridge_configured": True, "reachable": False, "error": str(exc), "live_trading_enabled": False}


@mcp.tool()
async def mt5_quote(symbol: str) -> dict[str, Any]:
    """Read an MT5 market quote through the SBT bridge; this tool cannot place orders."""
    if not MT5_BRIDGE_URL:
        return {"allowed": False, "reason": "MT5 bridge is not configured"}
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            response = await client.get(f"{MT5_BRIDGE_URL}/quote/{symbol.upper()}")
            response.raise_for_status()
            return {"allowed": True, "symbol": symbol.upper(), "quote": response.json(), "execution": "read_only"}
    except httpx.HTTPError as exc:
        return {"allowed": False, "symbol": symbol.upper(), "reason": f"MT5 bridge unavailable: {exc}"}


def build_mcp_app() -> ASGIApp:
    """Build the protected Streamable HTTP app mounted by FastAPI at /mcp."""
    security = TransportSecuritySettings(
        allowed_hosts=[
            "127.0.0.1",
            "localhost",
            "bitey-system-bots-trading.raylerr481.workers.dev",
            "*.workers.dev",
        ],
        allowed_origins=[
            "https://bitey-system-bots-trading.raylerr481.workers.dev",
            "http://localhost",
            "http://127.0.0.1",
        ],
    )
    app = mcp.streamable_http_app(
        streamable_http_path="/",
        stateless_http=True,
        json_response=True,
        transport_security=security,
    )
    return BearerGate(app, MCP_TOKEN)
