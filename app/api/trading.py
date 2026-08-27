from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.core.models import OrderIntent
from app.services.demo_engine import DemoEngine
from app.services.demo_state import get_demo_state
from app.strategies.technical import TechnicalSignalRequest

router = APIRouter(prefix="/api/v1/trading", tags=["trading"])


class DemoOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    side: str
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)


@router.get("/portfolio")
def get_portfolio():
    return get_demo_state().snapshot()


@router.post("/demo/order")
def demo_order(request: DemoOrderRequest):
    state = get_demo_state()
    order = OrderIntent(symbol=request.symbol, side=request.side, quantity=request.quantity)
    return state.engine.simulate_order(order, request.price)


@router.post("/demo/run")
def demo_run(request: TechnicalSignalRequest, quantity: float = 1.0):
    return get_demo_state().run(request, quantity=quantity)


@router.get("/demo/portfolio")
def demo_portfolio():
    return get_demo_state().snapshot()

