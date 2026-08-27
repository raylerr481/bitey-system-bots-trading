from app.bot_groups.models import BotGroup


BOT_GROUPS = [
    BotGroup(
        id="conservative",
        name="Conservador",
        risk_level="low",
        description_simple=(
            "Pensado para comenzar con una exposición más pequeña "
            "y controles estrictos de riesgo."
        ),
        description_professional=(
            "Estrategia técnica con exposición limitada, control "
            "de pérdida diaria y gestión conservadora de posiciones."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M15"],
        minimum_capital=10,
        max_position_pct=0.01,
        max_daily_loss_pct=0.03,
        max_exposure_pct=0.10,
    ),

    BotGroup(
        id="balanced",
        name="Equilibrado",
        risk_level="medium",
        description_simple=(
            "Busca un equilibrio entre oportunidad y control del riesgo."
        ),
        description_professional=(
            "Combina señales técnicas con una exposición moderada "
            "y controles de pérdida."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M15"],
        minimum_capital=10,
        max_position_pct=0.02,
        max_daily_loss_pct=0.05,
        max_exposure_pct=0.20,
    ),

    BotGroup(
        id="growth",
        name="Crecimiento",
        risk_level="high",
        description_simple=(
            "Acepta mayores fluctuaciones buscando aprovechar "
            "movimientos más importantes del mercado."
        ),
        description_professional=(
            "Permite una exposición superior, manteniendo límites "
            "de pérdida y exposición total."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M15"],
        minimum_capital=10,
        max_position_pct=0.03,
        max_daily_loss_pct=0.07,
        max_exposure_pct=0.30,
    ),

    BotGroup(
        id="trend",
        name="Tendencia",
        risk_level="medium",
        description_simple=(
            "Busca movimientos claros de subida o bajada."
        ),
        description_professional=(
            "Grupo orientado a estrategias de seguimiento de tendencia "
            "mediante señales de medias móviles."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M15"],
        minimum_capital=10,
        max_position_pct=0.02,
        max_daily_loss_pct=0.05,
        max_exposure_pct=0.20,
    ),

    BotGroup(
        id="scalping",
        name="Scalping",
        risk_level="high",
        description_simple=(
            "Busca movimientos pequeños y operaciones de duración corta."
        ),
        description_professional=(
            "Diseñado para operaciones de corto plazo con elevada "
            "frecuencia y estrictos controles de exposición."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M5"],
        minimum_capital=10,
        max_position_pct=0.01,
        max_daily_loss_pct=0.05,
        max_exposure_pct=0.15,
    ),

    BotGroup(
        id="multi_strategy",
        name="Multi-Strategy",
        risk_level="medium",
        description_simple=(
            "Combina diferentes estrategias para no depender "
            "de una sola señal."
        ),
        description_professional=(
            "Arquitectura preparada para combinar múltiples motores "
            "de señales bajo un único Risk Engine."
        ),
        strategies=["sma-crossover-v1"],
        symbols=["EURUSD"],
        timeframes=["M15"],
        minimum_capital=10,
        max_position_pct=0.02,
        max_daily_loss_pct=0.05,
        max_exposure_pct=0.20,
    ),
]


def list_bot_groups() -> list[BotGroup]:
    return BOT_GROUPS


def get_bot_group(group_id: str) -> BotGroup | None:
    return next(
        (group for group in BOT_GROUPS if group.id == group_id),
        None,
    )
