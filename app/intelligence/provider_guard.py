from __future__ import annotations

from enum import Enum
from pydantic import BaseModel, Field


class AIProvider(str, Enum):
    BITEY = "bitey"
    CHATGPT = "chatgpt"
    CLAUDE = "claude"
    OTHER = "other"


class BillingOwner(str, Enum):
    BITEY = "bitey"
    USER = "user"
    UNKNOWN = "unknown"


class ProviderPolicy(BaseModel):
    provider: AIProvider
    model: str = Field(min_length=1, max_length=120)
    exclusive: bool = True
    allow_paid_external: bool = False
    ask_before_paid_call: bool = True
    background_usage: bool = False
    max_spend_per_operation: float | None = Field(default=None, ge=0)
    max_spend_per_period: float | None = Field(default=None, ge=0)
    billing_owner: BillingOwner = BillingOwner.UNKNOWN
    cost_known: bool = False
    consented: bool = False
    policy_version: str = "1.0"


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
    """Fail-closed authorization for AI-provider calls.

    This guard never performs a provider call. It only decides whether a
    separately implemented adapter is authorized to do so.
    """
    paid_external = policy.provider in {AIProvider.CHATGPT, AIProvider.CLAUDE, AIProvider.OTHER}

    if policy.provider == AIProvider.BITEY:
        if fallback_provider is not None and policy.exclusive:
            return GuardDecision(False, "Exclusive provider policy forbids fallback", policy.provider, False)
        return GuardDecision(True, "Bitey provider selected", policy.provider, False)

    if policy.exclusive and fallback_provider is not None:
        return GuardDecision(False, "Exclusive provider policy forbids fallback", policy.provider, paid_external)

    if not policy.consented:
        return GuardDecision(False, "Provider consent is required", policy.provider, paid_external)

    if policy.billing_owner != BillingOwner.USER:
        return GuardDecision(False, "External billing owner must be the user", policy.provider, paid_external)

    if background and not policy.background_usage:
        return GuardDecision(False, "Background external AI usage is disabled", policy.provider, paid_external)

    if paid_external and not policy.allow_paid_external:
        return GuardDecision(False, "Paid external AI is not authorized", policy.provider, True)

    if estimated_cost is None and paid_external and not policy.cost_known:
        return GuardDecision(False, "External cost is unknown; fail closed", policy.provider, True)

    if estimated_cost is not None and policy.max_spend_per_operation is not None:
        if estimated_cost > policy.max_spend_per_operation:
            return GuardDecision(False, "Operation exceeds user spending limit", policy.provider, paid_external)

    return GuardDecision(True, "External provider authorized by user policy", policy.provider, paid_external)
