from __future__ import annotations

from dataclasses import dataclass

from app.registries.platform_connector_registry import get_platform, validate_platform_mode
from app.risk.engine import RiskEngine, RiskDecision


@dataclass(frozen=True)
class ExecutionDecision:
    allowed: bool
    stage: str
    reason: str


class ExecutionPolicy:
    """Single execution boundary used before any automated trading action."""

    def __init__(self, risk_engine: RiskEngine | None = None) -> None:
        self.risk_engine = risk_engine or RiskEngine()

    def validate_mode(self, platform: str, mode: str) -> ExecutionDecision:
        result = validate_platform_mode(platform, mode)
        if not result.get("valid"):
            return ExecutionDecision(False, "platform", result.get("reason", "Invalid platform/mode"))
        if mode == "live":
            return ExecutionDecision(False, "safety-gates", "Live trading is locked")
        return ExecutionDecision(True, "mode", "Mode accepted")

    def authorize_order(
        self,
        platform: str,
        mode: str,
        capital: float,
        notional: float,
        daily_pnl: float,
        permissions: list[str],
    ) -> tuple[ExecutionDecision, RiskDecision | None]:
        mode_decision = self.validate_mode(platform, mode)
        if not mode_decision.allowed:
            return mode_decision, None

        required = "demo_execute" if mode == "demo" else "paper_execute"
        if required not in permissions:
            return ExecutionDecision(False, "permissions", f"Missing explicit permission: {required}"), None

        risk = self.risk_engine.approve(capital, notional, daily_pnl)
        if not risk.allowed:
            return ExecutionDecision(False, "risk-gate", risk.reason), risk

        return ExecutionDecision(True, "execution", "Order authorized for safe mode"), risk
