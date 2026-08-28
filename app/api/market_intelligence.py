from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.market_intelligence import Evidence, engine

router = APIRouter(
    prefix="/api/v1/sbt/market-intelligence",
    tags=["sbt-market-intelligence"],
)


class EvidenceRequest(BaseModel):
    source: str
    source_type: str = "news"
    title: str
    reliability: float = Field(default=0.5, ge=0, le=1)
    impact: float = Field(default=0.5, ge=0, le=1)
    direction: Literal["long", "short", "neutral", "watch"] = "neutral"


class AnalysisRequest(BaseModel):
    capital: float = Field(gt=0)
    language: Literal["es", "pt", "en"] = "es"
    event: str = "energy_supply_risk"
    evidence: list[EvidenceRequest] = Field(default_factory=list)


@router.get("/languages")
def languages():
    return {"supported": ["es", "pt", "en"], "default": "es"}


@router.post("/analyze")
def analyze(request: AnalysisRequest):
    evidence = [Evidence(**item.model_dump()) for item in request.evidence]
    return engine.analyze(
        capital=request.capital,
        language=request.language,
        event=request.event,
        evidence=evidence,
    )
