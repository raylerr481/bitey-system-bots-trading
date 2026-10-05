from fastapi import APIRouter, HTTPException
from app.strategies.catalog import get_strategy, list_strategies
from app.strategies.factory import build_strategy_bot

router=APIRouter(prefix="/api/v1/strategies",tags=["strategies"])

@router.get("")
def strategies(family: str|None=None, status: str|None=None):
    items=list_strategies(family, status)
    return {"contract":"sbt-strategy-library-v2","mode":"research-library","count":len(items),
            "strategies":items,"validation_required":True,"production_auto_apply":False}

@router.get("/families")
def families():
    items=list_strategies()
    return {"families":sorted({s["family"] for s in items}),
            "count":len(items),
            "strategy_count":len(items),
            "rule":"catalog entries are candidates, never profitability guarantees"}

@router.get("/{strategy_id}")
def strategy(strategy_id:str):
    item=get_strategy(strategy_id)
    if item is None: raise HTTPException(status_code=404,detail="Strategy template not found")
    return {"contract":"sbt-strategy-v2","strategy":item.as_dict(),
            "validation_required":True,"production_auto_apply":False}

@router.get("/{strategy_id}/bot")
def strategy_bot(strategy_id:str,symbol:str="EURUSD",timeframe:str="M5",language:str="python"):
    if get_strategy(strategy_id) is None: raise HTTPException(status_code=404,detail="Strategy template not found")
    try: bot=build_strategy_bot(strategy_id,symbol=symbol,timeframe=timeframe,language=language)
    except ValueError as exc: raise HTTPException(status_code=422,detail=str(exc)) from exc
    return {"contract":"sbt-strategy-bot-v2","strategy_id":strategy_id,
            "specification":bot.model_dump(),"execution":"research-only",
            "validation_required":True,"production_auto_apply":False}
