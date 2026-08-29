from dataclasses import dataclass


@dataclass(frozen=True)
class Opportunity:
    asset: str
    direction: str
    score: float
    status: str
    horizon: str
    rationale: list[str]


class OpportunityScorer:
    """Ranks market opportunities without authorizing trade execution."""

    def score(
        self,
        asset: str,
        direction: str,
        confirmation: str,
        importance: int,
        source_quality: int,
        horizon: str = "30m-4h",
        risk_level: str = "medium",
        reward_risk: float | None = None,
    ) -> Opportunity:
        score = 0.0
        rationale: list[str] = []

        if confirmation == "CONFIRMED":
            score += 35
            rationale.append("market confirms the expected direction")
        elif confirmation == "DIVERGENCE":
            score -= 25
            rationale.append("market diverges from the expected direction")
        elif confirmation == "EXTENDED":
            score -= 10
            rationale.append("move may already be extended")
        else:
            rationale.append("market confirmation is incomplete")

        score += min(max(importance, 0), 100) * 0.25
        score += min(max(source_quality, 0), 100) * 0.15

        if reward_risk is not None:
            if reward_risk >= 3:
                score += 15
                rationale.append("reward/risk is favorable")
            elif reward_risk < 1:
                score -= 20
                rationale.append("reward/risk is unfavorable")

        if risk_level.lower() == "high":
            score -= 15
            rationale.append("high risk reduces the opportunity score")
        elif risk_level.lower() == "low":
            score += 5

        score = round(max(0.0, min(100.0, score)), 2)

        if confirmation == "DIVERGENCE" or score < 40:
            status = "WAIT"
        elif score >= 70:
            status = "WATCH-CONFIRMED"
        else:
            status = "WATCH"

        return Opportunity(asset, direction, score, status, horizon, rationale)
