from dataclasses import dataclass

from app.risk.engine import RiskEngine


@dataclass(frozen=True)
class Opportunity:
    asset: str
    direction: str
    score: float
    status: str
    horizon: str
    rationale: list[str]
    risk_allowed: bool = False
    risk_reason: str = "Risk Engine not evaluated"


class OpportunityScorer:
    """Ranks opportunities and optionally gates them through RiskEngine."""

    def score(self, asset: str, direction: str, confirmation: str, importance: int,
              source_quality: int, horizon: str = "30m-4h", risk_level: str = "medium",
              reward_risk: float | None = None, capital: float | None = None,
              notional: float | None = None, daily_pnl: float = 0.0,
              risk_engine: RiskEngine | None = None) -> Opportunity:
        score = 0.0
        rationale: list[str] = []
        if confirmation == "CONFIRMED":
            score += 35; rationale.append("market confirms expected direction")
        elif confirmation == "DIVERGENCE":
            score -= 25; rationale.append("market diverges from expected direction")
        elif confirmation == "EXTENDED":
            score -= 10; rationale.append("move may already be extended")
        else:
            rationale.append("market confirmation is incomplete")
        score += min(max(importance, 0), 100) * 0.25
        score += min(max(source_quality, 0), 100) * 0.15
        if reward_risk is not None:
            if reward_risk >= 3:
                score += 15; rationale.append("reward/risk is favorable")
            elif reward_risk < 1:
                score -= 20; rationale.append("reward/risk is unfavorable")
        if risk_level.lower() == "high":
            score -= 15; rationale.append("high risk reduces opportunity score")
        elif risk_level.lower() == "low":
            score += 5
        score = round(max(0.0, min(100.0, score)), 2)
        if confirmation == "DIVERGENCE" or score < 40:
            status = "WAIT"
        elif score >= 70:
            status = "WATCH-CONFIRMED"
        else:
            status = "WATCH"

        risk_allowed = False
        risk_reason = "Risk Engine not evaluated"
        if risk_engine is not None and capital is not None and notional is not None:
            decision = risk_engine.approve(capital, notional, daily_pnl)
            risk_allowed = decision.allowed and status == "WATCH-CONFIRMED"
            risk_reason = decision.reason
            if not decision.allowed:
                status = "WAIT"
                rationale.append(f"risk gate: {decision.reason}")

        return Opportunity(asset, direction, score, status, horizon, rationale,
                           risk_allowed, risk_reason)
