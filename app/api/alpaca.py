from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.core.settings import WEBHOOK_TOKEN
from app.services.alpaca_paper import account, market_order

router = APIRouter(prefix="/api/v1/alpaca", tags=["alpaca-paper"])


class PaperOrder(BaseModel):
    symbol: str = Field(min_length=1, max_length=12)
    side: str
    quantity: float = Field(gt=0)


@router.get("/account")
def get_account():
    try:
        return account()
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc))


@router.post("/order")
def place_order(order: PaperOrder):
    try:
        return market_order(order.symbol, order.side.lower(), order.quantity)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/webhook")
def tradingview_webhook(order: PaperOrder, token: str = ""):
    if not WEBHOOK_TOKEN or token != WEBHOOK_TOKEN:
        raise HTTPException(status_code=401, detail="Invalid webhook token")
    return place_order(order)
