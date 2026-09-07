from __future__ import annotations

from typing import Literal
from pydantic import BaseModel, Field, model_validator

Language = Literal["python", "mql5", "pine", "typescript"]

class IndicatorSpec(BaseModel):
    name: Literal["sma", "ema", "rsi", "atr", "macd", "bollinger"]
    period: int = Field(default=14, ge=2, le=200)

class RuleSpec(BaseModel):
    indicator: str
    operator: Literal[">", ">=", "<", "<=", "cross_above", "cross_below"]
    value: float | str

class RiskSpec(BaseModel):
    risk_pct: float = Field(default=0.01, gt=0, le=0.05)
    stop_type: Literal["fixed_pct", "atr"] = "atr"
    stop_value: float = Field(default=2.0, gt=0)
    max_position_pct: float = Field(default=0.02, gt=0, le=1)

class BotSpecification(BaseModel):
    contract: Literal["sbt-bot-v1"] = "sbt-bot-v1"
    name: str = Field(min_length=1, max_length=80)
    symbol: str = Field(default="EURUSD", min_length=1, max_length=32)
    timeframe: str = Field(default="M5", min_length=2, max_length=8)
    language: Language = "python"
    indicators: list[IndicatorSpec] = Field(default_factory=list, max_length=20)
    entry_rules: list[RuleSpec] = Field(default_factory=list, max_length=20)
    exit_rules: list[RuleSpec] = Field(default_factory=list, max_length=20)
    risk: RiskSpec = Field(default_factory=RiskSpec)
    initial_capital: float = Field(default=10_000, gt=0)
    live: Literal[False] = False
    real_money: Literal[False] = False
    broker_orders: Literal[0] = 0

    @model_validator(mode="after")
    def safety(self):
        if self.live or self.real_money or self.broker_orders != 0:
            raise ValueError("SBT Bot Builder is research/demo/paper only")
        return self
