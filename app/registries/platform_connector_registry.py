from __future__ import annotations

from dataclasses import asdict, dataclass


@dataclass(frozen=True)
class PlatformDefinition:
    id: str
    name: str
    modes: tuple[str, ...]
    transports: tuple[str, ...]
    live_enabled: bool = False
    read_only: bool = False


PLATFORMS: tuple[PlatformDefinition, ...] = (
    PlatformDefinition("mt5", "MetaTrader 5", ("demo",), ("bridge", "api"), read_only=True),
    PlatformDefinition("tradingview", "TradingView", ("webhook", "paper"), ("webhook",), read_only=True),
    PlatformDefinition("alpaca", "Alpaca", ("paper",), ("api", "sdk")),
)


def list_platforms() -> list[dict]:
    return [asdict(platform) for platform in PLATFORMS]


def get_platform(platform_id: str) -> PlatformDefinition | None:
    return next((p for p in PLATFORMS if p.id == platform_id), None)


def validate_platform_mode(platform_id: str, mode: str) -> dict:
    platform = get_platform(platform_id)
    if not platform:
        return {"valid": False, "reason": "Unsupported trading platform"}
    if mode not in platform.modes:
        return {"valid": False, "reason": "Execution mode is not supported by this platform"}
    if mode == "live" and not platform.live_enabled:
        return {"valid": False, "reason": "Live trading is locked"}
    return {"valid": True, "platform": asdict(platform), "mode": mode}
