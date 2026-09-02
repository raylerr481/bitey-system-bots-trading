from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Literal

ConnectionMode = Literal["api", "mcp", "direct_user", "other"]


@dataclass(frozen=True)
class AIProviderDefinition:
    id: str
    name: str
    connection_modes: tuple[ConnectionMode, ...]
    external_billing: bool = True
    enabled: bool = True


AI_PROVIDERS: tuple[AIProviderDefinition, ...] = (
    AIProviderDefinition("bitey", "Bitey Trading Intelligence", ("api",), external_billing=False),
    AIProviderDefinition("chatgpt", "ChatGPT / OpenAI", ("api", "direct_user", "mcp")),
    AIProviderDefinition("claude", "Claude / Anthropic", ("api", "mcp", "direct_user")),
    AIProviderDefinition("gemini", "Gemini / Google", ("api", "direct_user")),
    AIProviderDefinition("deepseek", "DeepSeek", ("api", "direct_user")),
    AIProviderDefinition("codex", "Codex", ("mcp", "direct_user")),
    AIProviderDefinition("other", "Other supported provider/client", ("api", "mcp", "direct_user", "other")),
)


def list_ai_providers() -> list[dict]:
    return [asdict(provider) for provider in AI_PROVIDERS if provider.enabled]


def get_ai_provider(provider_id: str) -> AIProviderDefinition | None:
    return next((p for p in AI_PROVIDERS if p.id == provider_id and p.enabled), None)


def validate_ai_connection(provider_id: str, connection_mode: ConnectionMode) -> dict:
    provider = get_ai_provider(provider_id)
    if not provider:
        return {"valid": False, "reason": "Unsupported AI provider"}
    if connection_mode not in provider.connection_modes:
        return {"valid": False, "reason": "Connection mode is not supported by this provider"}
    return {"valid": True, "provider": asdict(provider), "connection_mode": connection_mode}
