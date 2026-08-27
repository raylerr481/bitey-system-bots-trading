from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field
from typing import Literal


router = APIRouter(
    prefix="/api/v1/bot-groups",
    tags=["bot-groups"],
)


RiskLevel = Literal["low", "medium", "high"]


class BotGroup(BaseModel):
    id: str
    name: str
    description: str
    strategy: str
    market: str
    risk_level: RiskLevel
    minimum_capital_usd: float = Field(gt=0)
    target_profit_pct: float = Field(ge=0)
    probable_loss_pct: float = Field(ge=0)
    max_loss_pct: float = Field(ge=0)
    bots: list[str]


BOT_GROUPS = [
    BotGroup(
        id="conservative",
        name="Bitey Conservative",
        description=(
            "Grupo diseñado para usuarios que priorizan proteger el capital "
            "y aceptar ganancias potencialmente menores."
        ),
        strategy="SMA crossover + risk control",
        market="Forex",
        risk_level="low",
        minimum_capital_usd=10,
        target_profit_pct=2.0,
        probable_loss_pct=1.0,
        max_loss_pct=2.0,
        bots=[
            "trend-following",
            "risk-manager",
        ],
    ),
    BotGroup(
        id="balanced",
        name="Bitey Balanced",
        description=(
            "Grupo equilibrado entre crecimiento y control del riesgo."
        ),
        strategy="SMA crossover + momentum + risk control",
        market="Forex",
        risk_level="medium",
        minimum_capital_usd=25,
        target_profit_pct=5.0,
        probable_loss_pct=2.5,
        max_loss_pct=5.0,
        bots=[
            "trend-following",
            "momentum",
            "risk-manager",
        ],
    ),
    BotGroup(
        id="dynamic",
        name="Bitey Dynamic",
        description=(
            "Grupo orientado a buscar mayores oportunidades aceptando "
            "variaciones y pérdidas potenciales mayores."
        ),
        strategy="Trend + momentum + volatility",
        market="Forex",
        risk_level="high",
        minimum_capital_usd=50,
        target_profit_pct=10.0,
        probable_loss_pct=5.0,
        max_loss_pct=10.0,
        bots=[
            "trend-following",
            "momentum",
            "volatility",
            "risk-manager",
        ],
    ),
]


@router.get("")
def list_bot_groups():
    return {
        "count": len(BOT_GROUPS),
        "groups": [
            group.model_dump()
            for group in BOT_GROUPS
        ],
    }


@router.get("/{group_id}")
def get_bot_group(group_id: str):
    for group in BOT_GROUPS:
        if group.id == group_id:
            return group.model_dump()

    raise HTTPException(
        status_code=404,
        detail=f"Bot group '{group_id}' not found",
    )