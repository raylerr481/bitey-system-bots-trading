from __future__ import annotations

from collections import Counter
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from fastapi import APIRouter
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/learning", tags=["learning"])

_MAX_EVENTS = 2000
_EVENTS: list[dict[str, Any]] = []
_ALLOWED_DOMAINS = {"general", "trading", "turtle", "weather", "finance", "programming", "research", "local_search"}
_ALLOWED_OUTCOMES = {"UNKNOWN", "VERIFIED", "REJECTED", "SUCCESS", "FAILURE", "NEEDS_REVIEW"}


class LearningExperience(BaseModel):
    source: str = Field(default="bitey_ia", min_length=1, max_length=80)
    conversation_id: str | None = Field(default=None, max_length=160)
    message: str = Field(min_length=1, max_length=4000)
    response: str = Field(default="", max_length=8000)
    domain: str = Field(default="general", max_length=40)
    intent: str = Field(default="unknown", max_length=120)
    selected_tools: list[str] = Field(default_factory=list, max_length=20)
    evidence_class: str = Field(default="NO_EVIDENCE", max_length=80)
    evidence_verified: bool = False
    outcome: str = Field(default="UNKNOWN", max_length=30)
    feedback: str | None = Field(default=None, max_length=1000)
    context: dict[str, Any] = Field(default_factory=dict)
    result_summary: dict[str, Any] = Field(default_factory=dict)


def _sanitize(value: Any, depth: int = 0) -> Any:
    if depth > 3:
        return "[truncated]"
    if isinstance(value, str):
        return value[:4000]
    if isinstance(value, (int, float, bool)) or value is None:
        return value
    if isinstance(value, list):
        return [_sanitize(item, depth + 1) for item in value[:30]]
    if isinstance(value, dict):
        # Do not retain credentials, authorization headers, tokens or secrets.
        blocked = {"authorization", "token", "access_token", "api_key", "secret", "password", "cookie"}
        return {
            str(key): _sanitize(item, depth + 1)
            for key, item in list(value.items())[:50]
            if str(key).casefold() not in blocked
        }
    return str(value)[:4000]


def record_experience(payload: LearningExperience) -> dict[str, Any]:
    domain = payload.domain.casefold()
    outcome = payload.outcome.upper()
    if domain not in _ALLOWED_DOMAINS:
        domain = "general"
    if outcome not in _ALLOWED_OUTCOMES:
        outcome = "UNKNOWN"

    event = {
        "id": str(uuid4()),
        "created_at": datetime.now(timezone.utc).isoformat(),
        "source": payload.source,
        "conversation_id": payload.conversation_id,
        "message": payload.message,
        "response": payload.response,
        "domain": domain,
        "intent": payload.intent,
        "selected_tools": list(dict.fromkeys(payload.selected_tools))[:20],
        "evidence_class": payload.evidence_class,
        "evidence_verified": bool(payload.evidence_verified),
        "outcome": outcome,
        "feedback": payload.feedback,
        "context": _sanitize(payload.context),
        "result_summary": _sanitize(payload.result_summary),
        # Training policy: only verified/explicitly reviewed experiences become
        # eligible for future learning datasets.
        "training_eligible": bool(payload.evidence_verified or outcome in {"VERIFIED", "SUCCESS", "FAILURE", "REJECTED", "NEEDS_REVIEW"}),
        "training_policy": "verified_or_reviewed_only",
    }
    _EVENTS.append(event)
    if len(_EVENTS) > _MAX_EVENTS:
        del _EVENTS[:-_MAX_EVENTS]
    return event


@router.post("/experience")
def create_experience(payload: LearningExperience):
    event = record_experience(payload)
    return {"ok": True, "event": event, "stored": len(_EVENTS), "persistence": "runtime_memory"}


@router.get("/status")
def learning_status():
    eligible = sum(1 for item in _EVENTS if item.get("training_eligible"))
    return {
        "ok": True,
        "events": len(_EVENTS),
        "training_eligible": eligible,
        "domains": dict(Counter(str(item.get("domain") or "general") for item in _EVENTS)),
        "outcomes": dict(Counter(str(item.get("outcome") or "UNKNOWN") for item in _EVENTS)),
        "policy": "verified_or_reviewed_only",
        "execution_learning": "observation_only",
        "live_parameter_learning": False,
        "persistence": "runtime_memory",
    }


@router.get("/recent")
def recent_experiences(limit: int = 20):
    limit = max(1, min(int(limit), 100))
    return {"ok": True, "events": _EVENTS[-limit:], "count": min(limit, len(_EVENTS))}


@router.post("/feedback/{event_id}")
def feedback(event_id: str, outcome: str = "NEEDS_REVIEW", feedback: str = ""):
    normalized = outcome.upper()
    if normalized not in _ALLOWED_OUTCOMES:
        normalized = "NEEDS_REVIEW"
    for event in reversed(_EVENTS):
        if event["id"] == event_id:
            event["outcome"] = normalized
            event["feedback"] = feedback[:1000]
            event["training_eligible"] = True
            return {"ok": True, "event": event}
    return {"ok": False, "reason": "experience_not_found"}
