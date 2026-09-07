from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.brokers.registry import catalog, get_adapter

router = APIRouter(prefix="/api/v1/brokers", tags=["brokers"])


class BrokerOrder(BaseModel):
    broker: str = Field(min_length=1, max_length=30)
    symbol: str = Field(min_length=1, max_length=30)
    side: str = Field(pattern="^(buy|sell)$")
    quantity: float = Field(gt=0)


@router.get("/catalog")
def broker_catalog():
    return {
        "contract": "sbt-broker-adapter-v1",
        "live": False,
        "real_money": False,
        "broker_orders": 0,
        "brokers": catalog(),
    }


@router.get("/{broker}/account")
def broker_account(broker: str):
    try:
        return get_adapter(broker).account().__dict__
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.get("/{broker}/quote/{symbol}")
def broker_quote(broker: str, symbol: str):
    try:
        return get_adapter(broker).quote(symbol).__dict__
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@router.post("/paper-order")
def broker_paper_order(order: BrokerOrder):
    try:
        adapter = get_adapter(order.broker)
        capabilities = adapter.capabilities()
        if not capabilities.paper:
            raise ValueError(f"Broker {order.broker} has no paper-order capability")
        result = adapter.submit_order(order.symbol, order.side, order.quantity)
        return {"contract": "sbt-broker-adapter-v1", "execution": "paper", "live": False, "result": result}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
