from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.intelligence.market_intelligence import MarketIntelligenceEngine, NewsEvent
from app.intelligence.market_confirmation import MarketConfirmation

router = APIRouter(prefix="/api/v1/intelligence", tags=["market-intelligence"])
engine = MarketIntelligenceEngine()
confirmation = MarketConfirmation()


class NewsAnalysisRequest(BaseModel):
    headline: str = Field(min_length=3, max_length=1000)
    source_quality: int = Field(default=70, ge=0, le=100)
    importance: int = Field(default=50, ge=0, le=100)
    tags: list[str] = Field(default_factory=list, max_length=30)
    confirmed_assets: list[str] = Field(default_factory=list, max_length=50)
    market_observations: dict[str, float] = Field(default_factory=dict, max_length=50)


@router.post("/news/analyze")
def analyze_news(request: NewsAnalysisRequest):
    event = NewsEvent(
        headline=request.headline,
        source_quality=request.source_quality,
        importance=request.importance,
        tags={tag.strip().lower() for tag in request.tags if tag.strip()},
    )
    analysis = engine.analyze(event, request.confirmed_assets)
    analysis["market_confirmation"] = confirmation.evaluate(
        analysis.get("primary_impacts", []),
        request.market_observations,
    )
    analysis["execution"] = "analysis-only"
    analysis["execution_allowed"] = False
    return analysis


@router.get("/health")
def intelligence_health():
    return {
        "status": "ok",
        "module": "market-intelligence",
        "execution": "analysis-only",
        "execution_allowed": False,
        "risk_engine_required": True,
        "market_confirmation": True,
    }
