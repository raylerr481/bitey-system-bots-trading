from fastapi import APIRouter, HTTPException

from app.strategies.catalog import get_strategy, list_strategies
from app.strategies.factory import build_strategy_bot

router = APIRouter(prefix="/api/v1/strategies", tags=["strategies"])


@router.get("")
def strategies(family: str | None = None):
    return {"contract":"sbt-strategy-catalog-v1", "mode":"research-templates", "strategies":list_strategies(family), "validation_required":True, "live":False, "real_money":False, "broker_orders":0}


@router.get("/{strategy_id}")
def strategy(strategy_id: str):
    item = get_strategy(strategy_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Strategy template not found")
    return {"contract":"sbt-strategy-v1", "strategy":item.as_dict(), "validation_required":True, "live":False, "real_money":False, "broker_orders":0}


@router.get("/{strategy_id}/bot")
def strategy_bot(strategy_id: str, symbol: str = "EURUSD", timeframe: str = "M5", language: str = "python"):
    """Instantiate a catalog strategy as a reusable research BotSpecification."""
    if get_strategy(strategy_id) is None:
        raise HTTPException(status_code=404, detail="Strategy template not found")
    try:
        bot = build_strategy_bot(strategy_id, symbol=symbol, timeframe=timeframe, language=language)
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc
    return {"contract":"sbt-strategy-bot-v1", "strategy_id":strategy_id, "specification":bot.model_dump(), "execution":"research-only", "validation_required":True, "live":False, "real_money":False, "broker_orders":0}
