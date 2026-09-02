from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.core.models import DemoPortfolio, OrderIntent, Side
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine

router = APIRouter(prefix="/api/v1/trading", tags=["trading"])
portfolio = DemoPortfolio(initial_capital=10_000, cash=10_000)
risk = RiskEngine(allowed_symbols={"EURUSD"})
engine = DemoEngine(portfolio, risk)


class DemoOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    side: Side
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)


@router.get("/portfolio")
def get_portfolio():
    return portfolio.model_dump()


@router.post("/demo/order")
def demo_order(request: DemoOrderRequest):
    order = OrderIntent(symbol=request.symbol, side=request.side, quantity=request.quantity)
    return engine.simulate_order(order, request.price)
