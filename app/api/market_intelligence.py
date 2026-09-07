from __future__ import annotations

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.market_intelligence import analyze_market

router = APIRouter(prefix="/api/v1/sbt/market-intelligence", tags=["market-intelligence"])


class MarketIntelligenceRequest(BaseModel):
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    timeframe: str = Field(default="M5", min_length=2, max_length=8)
    candles: list[dict] = Field(default_factory=list, min_length=0, max_length=500)
    capital: float = Field(default=1000, gt=0)
    language: str = Field(default="es", min_length=2, max_length=5)
    event: str = Field(default="market_structure", min_length=1, max_length=120)
    evidence: list[dict] = Field(default_factory=list, max_length=50)


@router.post("/analyze")
def market_intelligence(request: MarketIntelligenceRequest):
    result = analyze_market(request.candles, request.symbol.upper(), request.timeframe.upper(), request.event)
    result["capital"] = request.capital
    result["language"] = request.language
    result["evidence_count"] = len(request.evidence)
    return result
