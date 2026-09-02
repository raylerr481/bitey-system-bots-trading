from __future__ import annotations

from typing import Literal

from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.bot_prompt_generator import generate_bot_prompts
from app.services.news_intelligence import analyze_event, alert_matches, news_engine_status

router = APIRouter(prefix="/api/v1/news", tags=["news-intelligence"])


class NewsEvent(BaseModel):
    event_id: str = Field(min_length=1, max_length=120)
    headline: str = Field(min_length=5, max_length=1000)
    event_type: str = Field(min_length=2, max_length=60)
    sector: str = Field(default="unknown", max_length=80)
    assets: list[str] = Field(default_factory=list, max_length=50)
    source: str | None = Field(default=None, max_length=300)


class AlertRule(BaseModel):
    min_opportunity: float = Field(default=0.70, ge=0, le=1)
    max_risk: float = Field(default=0.65, ge=0, le=1)
    alert_level: Literal["medium", "high", "critical"] = "high"


class BotPromptRequest(BaseModel):
    event: NewsEvent
    market: str | None = Field(default=None, max_length=80)
    timeframe: str = Field(default="1h", min_length=1, max_length=20)


@router.get("/status")
def status():
    return news_engine_status()


@router.post("/analyze")
def analyze(event: NewsEvent):
    result = analyze_event(**event.model_dump())
    return result.__dict__


@router.post("/alert/check")
def check_alert(event: NewsEvent, rule: AlertRule = AlertRule()):
    result = analyze_event(**event.model_dump())
    matched = alert_matches(result, min_opportunity=rule.min_opportunity, max_risk=rule.max_risk)
    return {
        "alert": matched,
        "alert_level": result.alert_level,
        "analysis": result.__dict__,
        "action": "notify_user_for_review" if matched else "no_alert",
        "execution": "never_automatic_from_news",
    }


@router.post("/bot-prompts")
def bot_prompts(request: BotPromptRequest):
    analysis = analyze_event(**request.event.model_dump()).__dict__
    proposals = generate_bot_prompts(analysis, market=request.market, timeframe=request.timeframe)
    return {
        "event_analysis": analysis,
        "proposals": proposals,
        "execution": "never_automatic_from_news",
        "next_step": "backtest_then_stress_test_then_demo_or_paper",
    }
