from fastapi import APIRouter, HTTPException

from app.strategies.catalog import get_strategy, list_strategies

router = APIRouter(prefix="/api/v1/strategies", tags=["strategies"])


@router.get("")
def strategies(family: str | None = None):
    return {
        "contract": "sbt-strategy-catalog-v1",
        "mode": "research-templates",
        "strategies": list_strategies(family),
        "validation_required": True,
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }


@router.get("/{strategy_id}")
def strategy(strategy_id: str):
    item = get_strategy(strategy_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Strategy template not found")
    return {
        "contract": "sbt-strategy-v1",
        "strategy": item.as_dict(),
        "validation_required": True,
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }
