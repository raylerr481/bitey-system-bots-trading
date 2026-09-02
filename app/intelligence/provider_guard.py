from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


class AIProvider(str, Enum):
    BITEY = "bitey"
    CHATGPT = "chatgpt"
    CLAUDE = "claude"
    GEMINI = "gemini"
    DEEPSEEK = "deepseek"
    OTHER = "other"


class BillingOwner(str, Enum):
    BITEY = "bitey"
    USER = "user"
    UNKNOWN = "unknown"


class ConnectionMode(str, Enum):
    API = "api"
    MCP = "mcp"
    DIRECT_USER = "direct_user"
    OTHER = "other"


class ProviderPolicy(BaseModel):
    provider: AIProvider
    model: str = Field(min_length=1, max_length=120)
    connection_mode: ConnectionMode = ConnectionMode.API
    exclusive: bool = True
    allow_paid_external: bool = False
    ask_before_paid_call: bool = True
    background_usage: bool = False
    max_spend_per_operation: float | None = Field(default=None, ge=0)
    max_spend_per_period: float | None = Field(default=None, ge=0)
    billing_owner: BillingOwner = BillingOwner.UNKNOWN
    cost_known: bool = False
    consented: bool = False
    policy_version: str = "1.1"


class GuardDecision(BaseModel):
    allowed: bool
    reason: str
    provider: AIProvider
    paid_call: bool


def evaluate_provider_call(
    policy: ProviderPolicy,
    *,
    estimated_cost: float | None = None,
    background: bool = False,
    fallback_provider: AIProvider | None = None,
) -> GuardDecision:
    """Fail-closed authorization. This function never executes a provider."""
    paid_external = policy.provider not in {AIProvider.BITEY}

    if policy.exclusive and fallback_provider is not None:
        return GuardDecision(
            allowed=False,
            reason="Exclusive provider policy forbids fallback",
            provider=policy.provider,
            paid_call=paid_external,
        )

    if policy.provider == AIProvider.BITEY:
        return GuardDecision(
            allowed=True,
            reason="Bitey provider selected",
            provider=policy.provider,
            paid_call=False,
        )

    # DIRECT_USER means SBT prepares/exports the request for the user's own
    # product session; SBT does not consume an external API quota itself.
    if policy.connection_mode == ConnectionMode.DIRECT_USER:
        if not policy.consented:
            return GuardDecision(
                allowed=False,
                reason="User authorization is required",
                provider=policy.provider,
                paid_call=False,
            )
        return GuardDecision(
            allowed=True,
            reason="Direct user-controlled provider session",
            provider=policy.provider,
            paid_call=False,
        )

    if not policy.consented:
        return GuardDecision(
            allowed=False,
            reason="Provider consent is required",
            provider=policy.provider,
            paid_call=paid_external,
        )
    if policy.billing_owner != BillingOwner.USER:
        return GuardDecision(
            allowed=False,
            reason="External billing owner must be the user",
            provider=policy.provider,
            paid_call=paid_external,
        )
    if background and not policy.background_usage:
        return GuardDecision(
            allowed=False,
            reason="Background external AI usage is disabled",
            provider=policy.provider,
            paid_call=paid_external,
        )
    if not policy.allow_paid_external:
        return GuardDecision(
            allowed=False,
            reason="Paid external AI is not authorized",
            provider=policy.provider,
            paid_call=True,
        )
    if estimated_cost is None and not policy.cost_known:
        return GuardDecision(
            allowed=False,
            reason="External cost is unknown; fail closed",
            provider=policy.provider,
            paid_call=True,
        )
    if estimated_cost is not None and policy.max_spend_per_operation is not None:
        if estimated_cost > policy.max_spend_per_operation:
            return GuardDecision(
                allowed=False,
                reason="Operation exceeds user spending limit",
                provider=policy.provider,
                paid_call=True,
            )

    return GuardDecision(
        allowed=True,
        reason="External provider authorized by user policy",
        provider=policy.provider,
        paid_call=True,
    )
