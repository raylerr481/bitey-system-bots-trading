from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.intelligence.market_intelligence import MarketIntelligenceEngine, NewsEvent
from app.intelligence.market_confirmation import MarketConfirmation
from app.intelligence.opportunity import OpportunityScorer
from app.risk.engine import RiskEngine

router = APIRouter(prefix="/api/v1/intelligence", tags=["market-intelligence"])
engine = MarketIntelligenceEngine()
confirmation = MarketConfirmation()
opportunity_scorer = OpportunityScorer()
risk_engine = RiskEngine()


class NewsAnalysisRequest(BaseModel):
    headline: str = Field(min_length=3, max_length=1000)
    source_quality: int = Field(default=70, ge=0, le=100)
    importance: int = Field(default=50, ge=0, le=100)
    tags: list[str] = Field(default_factory=list, max_length=30)
    confirmed_assets: list[str] = Field(default_factory=list, max_length=50)
    market_observations: dict[str, float] = Field(default_factory=dict, max_length=50)
    risk_level: str = Field(default="medium", pattern="^(low|medium|high)$")
    reward_risk: float | None = Field(default=None, ge=0, le=20)
    capital: float | None = Field(default=None, gt=0)
    notional: float | None = Field(default=None, ge=0)
    daily_pnl: float = 0.0


@router.post("/news/analyze")
def analyze_news(request: NewsAnalysisRequest):
    event = NewsEvent(
        headline=request.headline,
        source_quality=request.source_quality,
        importance=request.importance,
        tags={tag.strip().lower() for tag in request.tags if tag.strip()},
    )
    analysis = engine.analyze(event, request.confirmed_assets)
    market_confirmation = confirmation.evaluate(
        analysis.get("primary_impacts", []), request.market_observations
    )
    analysis["market_confirmation"] = market_confirmation

    opportunities = []
    for impact in analysis.get("primary_impacts", []):
        asset = impact.get("asset")
        direction = impact.get("direction", "neutral")
        if not asset or direction == "neutral":
            continue
        asset_confirmation = next(
            (item.get("status") for item in market_confirmation if item.get("asset") == asset),
            "WAIT",
        )
        opportunity = opportunity_scorer.score(
            asset=asset, direction=direction, confirmation=asset_confirmation,
            importance=request.importance, source_quality=request.source_quality,
            risk_level=request.risk_level, reward_risk=request.reward_risk,
            capital=request.capital, notional=request.notional,
            daily_pnl=request.daily_pnl, risk_engine=risk_engine,
        )
        opportunities.append(opportunity.__dict__)
    analysis["opportunities"] = sorted(opportunities, key=lambda item: item["score"], reverse=True)
    analysis["execution"] = "analysis-only"
    analysis["execution_allowed"] = False
    analysis["risk_engine_required"] = True
    return analysis


@router.get("/health")
def intelligence_health():
    return {
        "status": "ok", "module": "market-intelligence",
        "execution": "analysis-only", "execution_allowed": False,
        "risk_engine_required": True, "market_confirmation": True,
        "opportunity_scoring": True, "risk_gating": True,
    }
