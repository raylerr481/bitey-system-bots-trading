from pydantic import BaseModel, Field
from typing import Literal


RiskLevel = Literal["low", "medium", "high"]


class BotGroup(BaseModel):
    id: str
    name: str

    description_simple: str
    description_professional: str

    risk_level: RiskLevel

    strategies: list[str]
    symbols: list[str]
    timeframes: list[str]

    minimum_capital: float = Field(gt=0)

    max_position_pct: float = Field(
        gt=0,
        le=1,
    )

    max_daily_loss_pct: float = Field(
        gt=0,
        le=1,
    )

    max_exposure_pct: float = Field(
        gt=0,
        le=1,
    )
