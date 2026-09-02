from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


@dataclass(frozen=True)
class EventAnalysis:
    event_id: str
    headline: str
    sector: str
    assets: tuple[str, ...]
    impact: str
    bias: str
    volatility_score: float
    opportunity_score: float
    risk_score: float
    horizon: str
    conflicts: tuple[str, ...]
    alert_level: str
    rationale: tuple[str, ...]


# These are research taxonomies, not investment recommendations.
EVENT_PROFILES = {
    "earnings": ("equities", 0.65, "short_term"),
    "merger_acquisition": ("equities", 0.80, "short_term"),
    "rate_decision": ("macro", 0.90, "short_term"),
    "inflation": ("macro", 0.85, "short_term"),
    "employment": ("macro", 0.75, "short_term"),
    "commodity_supply": ("commodities", 0.80, "days_weeks"),
    "geopolitical": ("macro", 0.95, "hours_days"),
    "regulation": ("sector", 0.70, "days_weeks"),
    "contract": ("equities", 0.55, "days_weeks"),
    "technology": ("technology", 0.65, "days_weeks"),
}

POSITIVE_TERMS = {
    "beat", "growth", "record", "approval", "contract", "acquisition",
    "investment", "expansion", "demand", "production", "upgrade",
    "lower inflation", "rate cut", "stimulus", "strong guidance",
}
NEGATIVE_TERMS = {
    "miss", "loss", "downgrade", "recession", "sanction", "war",
    "default", "bankruptcy", "lawsuit", "recall", "supply disruption",
    "higher inflation", "rate hike", "weak guidance", "unemployment",
}


def _direction(text: str) -> float:
    normalized = text.lower()
    positive = sum(1 for term in POSITIVE_TERMS if term in normalized)
    negative = sum(1 for term in NEGATIVE_TERMS if term in normalized)
    return max(-1.0, min(1.0, (positive - negative) / max(1, positive + negative)))


def analyze_event(
    *,
    event_id: str,
    headline: str,
    event_type: str,
    sector: str,
    assets: list[str],
    source: str | None = None,
) -> EventAnalysis:
    profile_sector, base_vol, horizon = EVENT_PROFILES.get(event_type, (sector or "unknown", 0.50, "unknown"))
    text = f"{headline} {sector} {source or ''}"
    direction = _direction(text)
    opportunity = max(0.0, min(1.0, 0.50 + direction * 0.35))
    risk = max(0.0, min(1.0, base_vol * 0.70 + (0.25 if abs(direction) < 0.20 else 0.0)))
    volatility = max(0.0, min(1.0, base_vol + abs(direction) * 0.10))

    conflicts: list[str] = []
    rationale: list[str] = [f"Event class: {event_type}", f"Expected horizon: {horizon}"]
    if direction > 0.20:
        bias = "favorable"
        rationale.append("Headline contains positive market-relevant signals; confirmation is required.")
    elif direction < -0.20:
        bias = "adverse"
        rationale.append("Headline contains adverse market-relevant signals.")
    else:
        bias = "mixed"
        conflicts.append("Fundamental/news direction is not sufficiently clear from headline text.")
        rationale.append("Signal is ambiguous; avoid treating the event as a directional trade signal.")

    if base_vol >= 0.85:
        conflicts.append("High-event-risk regime: price gaps and rapid repricing are possible.")
    if len(assets) > 1:
        conflicts.append("Cross-asset transmission may create correlated exposure.")

    alert_level = "critical" if risk >= 0.85 else "high" if max(opportunity, risk, volatility) >= 0.70 else "medium" if max(opportunity, risk, volatility) >= 0.45 else "low"
    return EventAnalysis(
        event_id=event_id,
        headline=headline,
        sector=profile_sector,
        assets=tuple(assets),
        impact="high" if base_vol >= 0.75 else "medium" if base_vol >= 0.50 else "low",
        bias=bias,
        volatility_score=round(volatility, 3),
        opportunity_score=round(opportunity, 3),
        risk_score=round(risk, 3),
        horizon=horizon,
        conflicts=tuple(conflicts),
        alert_level=alert_level,
        rationale=tuple(rationale),
    )


def alert_matches(analysis: EventAnalysis, *, min_opportunity: float, max_risk: float) -> bool:
    return analysis.opportunity_score >= min_opportunity and analysis.risk_score <= max_risk and analysis.bias == "favorable"


def news_engine_status() -> dict:
    return {
        "enabled": True,
        "purpose": "research and market-event alerts",
        "event_classes": sorted(EVENT_PROFILES),
        "real_time_source_connected": False,
        "execution_authority": False,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "disclaimer": "News signals are research indicators, not guaranteed investment advice.",
    }
