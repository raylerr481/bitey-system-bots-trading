from datetime import datetime, timezone
from enum import Enum
from pydantic import BaseModel, Field


class DominoState(str, Enum):
    NEW = "new"
    SHOCK = "shock"
    CONFIRMING = "confirming"
    CONFIRMED = "confirmed"
    EXTENDED = "extended"
    EXPIRED = "expired"
    REJECTED = "rejected"


class MarketObservation(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    timeframe: str = Field(min_length=1, max_length=10)
    price: float = Field(gt=0)
    trend_score: float | None = Field(default=None, ge=-1, le=1)
    momentum_score: float | None = Field(default=None, ge=-1, le=1)
    volatility_score: float | None = Field(default=None, ge=0, le=1)
    structure_score: float | None = Field(default=None, ge=-1, le=1)
    volume_score: float | None = Field(default=None, ge=-1, le=1)
    timestamp: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))


class ConfirmationResult(BaseModel):
    symbol: str
    confirmed: bool
    score: float = Field(ge=0, le=1)
    threshold: float = Field(ge=0, le=1)
    reasons: list[str] = Field(default_factory=list)
    missing_evidence: list[str] = Field(default_factory=list)
