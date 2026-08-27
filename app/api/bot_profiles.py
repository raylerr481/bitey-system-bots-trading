"""User-friendly bot-group profiles and live-trading safety gates.

Profiles expose simple explanations first and professional trading details on
request. They are descriptive configuration presets; they do not promise
returns or guarantee a maximum loss in all market conditions.
"""

from typing import Any

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

router = APIRouter(prefix="/api/v1/bot-profiles", tags=["bot-profiles"])


class RiskProfile(BaseModel):
    level: str
    max_position_pct: float = Field(gt=0, le=1)
    max_loss_pct_per_trade: float = Field(gt=0, le=1)
    max_daily_loss_pct: float = Field(gt=0, le=1)
    description: str


class BotProfile(BaseModel):
    id: str
    name: str
    short_description: str
    beginner_explanation: str
    professional_explanation: str
    markets: list[str]
    strategy: list[str]
    risk: RiskProfile
    estimated_scenarios: dict[str, str]
    suitable_for: str


PROFILES: list[BotProfile] = [
    BotProfile(
        id="conservative-eurusd",
        name="Conservador EUR/USD",
        short_description="Busca movimientos pequeños priorizando control de exposición.",
        beginner_explanation=(
            "Si asignas $10, el sistema puede ganar o perder una cantidad pequeña; "
            "el objetivo es limitar la exposición, no prometer una ganancia."
        ),
        professional_explanation=(
            "Perfil de baja exposición para EUR/USD. Usa señales de tendencia y "
            "límites de posición/pérdida configurables. Los escenarios son estimaciones "
            "históricas o de simulación y no constituyen una previsión."
        ),
        markets=["EUR/USD"],
        strategy=["sma-crossover-v1", "risk-controls"],
        risk=RiskProfile(
            level="low",
            max_position_pct=0.01,
            max_loss_pct_per_trade=0.02,
            max_daily_loss_pct=0.01,
            description="Baja exposición; diseñado para pruebas y usuarios principiantes.",
        ),
        estimated_scenarios={
            "favorable": "+$0.20 por cada $10 asignados (ejemplo ilustrativo)",
            "neutral": "$0.00 (ejemplo ilustrativo)",
            "unfavorable": "-$0.10 por cada $10 asignados (ejemplo ilustrativo)",
            "configured_limit": "hasta -$0.20 por cada $10, antes de costes/slippage/gaps",
        },
        suitable_for="Aprendizaje, demo y primeras pruebas de estrategia.",
    ),
    BotProfile(
        id="balanced-eurusd",
        name="Equilibrado EUR/USD",
        short_description="Equilibra exposición y oportunidad de rendimiento.",
        beginner_explanation="Acepta más variación de resultados que el perfil conservador para buscar movimientos mayores.",
        professional_explanation="Perfil intermedio con mayor exposición por posición y tolerancia de pérdida diaria superior al perfil conservador.",
        markets=["EUR/USD"],
        strategy=["sma-crossover-v1", "risk-controls"],
        risk=RiskProfile(
            level="medium",
            max_position_pct=0.02,
            max_loss_pct_per_trade=0.03,
            max_daily_loss_pct=0.02,
            description="Exposición intermedia con límites explícitos.",
        ),
        estimated_scenarios={
            "favorable": "Mayor potencial que conservador, sin garantía",
            "neutral": "Resultado cercano a cero posible",
            "unfavorable": "Pérdidas superiores al perfil conservador posibles",
            "configured_limit": "El límite se calcula sobre el capital asignado, sujeto a ejecución real",
        },
        suitable_for="Usuarios que ya probaron el sistema en demo/paper.",
    ),
    BotProfile(
        id="aggressive-eurusd",
        name="Agresivo EUR/USD",
        short_description="Busca movimientos mayores aceptando una variación y pérdida potencial mayores.",
        beginner_explanation="Puede ganar más en un movimiento favorable, pero también puede perder una parte importante del capital asignado.",
        professional_explanation="Perfil de alta exposición. Requiere validación en demo/paper y parámetros de riesgo estrictos antes de cualquier uso real.",
        markets=["EUR/USD"],
        strategy=["sma-crossover-v1", "risk-controls"],
        risk=RiskProfile(
            level="high",
            max_position_pct=0.05,
            max_loss_pct_per_trade=0.05,
            max_daily_loss_pct=0.03,
            description="Alta exposición y alta variabilidad; no recomendado para principiantes.",
        ),
        estimated_scenarios={
            "favorable": "Potencial superior, sin garantía",
            "neutral": "Resultado cercano a cero posible",
            "unfavorable": "Pérdidas relevantes posibles",
            "configured_limit": "Los límites son controles de ejecución, no una garantía contra gaps o slippage",
        },
        suitable_for="Usuarios avanzados tras validación prolongada en demo/paper.",
    ),
]


@router.get("")
def list_profiles() -> list[dict[str, Any]]:
    return [profile.model_dump() for profile in PROFILES]


@router.get("/{profile_id}")
def get_profile(profile_id: str) -> dict[str, Any]:
    profile = next((item for item in PROFILES if item.id == profile_id), None)
    if profile is None:
        raise HTTPException(status_code=404, detail="Bot profile not found")
    return profile.model_dump()


@router.get("/{profile_id}/risk-preview")
def risk_preview(profile_id: str, capital: float = Field(default=10, gt=0)) -> dict[str, Any]:
    profile = next((item for item in PROFILES if item.id == profile_id), None)
    if profile is None:
        raise HTTPException(status_code=404, detail="Bot profile not found")
    risk = profile.risk
    return {
        "profile_id": profile.id,
        "capital": capital,
        "max_position_value": round(capital * risk.max_position_pct, 8),
        "configured_loss_per_trade": round(capital * risk.max_loss_pct_per_trade, 8),
        "configured_daily_loss": round(capital * risk.max_daily_loss_pct, 8),
        "warning": "Estos límites son controles configurados; mercado, slippage y gaps pueden producir pérdidas mayores.",
    }


@router.get("/live/activation-status")
def live_activation_status() -> dict[str, Any]:
    return {
        "available": False,
        "enabled": False,
        "stage": "safety-preparation",
        "required": [
            "authenticated_user",
            "broker_account_connection",
            "explicit_real_account_selection",
            "capital_limit",
            "per_trade_loss_limit",
            "daily_loss_limit",
            "preflight_risk_validation",
            "audit_log",
            "emergency_stop",
            "explicit_final_confirmation",
        ],
        "message": "El botón de dinero real puede mostrarse como una función preparada, pero la ejecución real permanece bloqueada en esta versión.",
    }
