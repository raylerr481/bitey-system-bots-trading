from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.core.models import DemoPortfolio, OrderIntent
from app.risk.engine import RiskEngine
from app.services.demo_engine import DemoEngine
from app.services.demo_loop import DemoTradingLoop
from app.strategies.technical import TechnicalSignalRequest

router = APIRouter(prefix="/api/v1/trading", tags=["trading"])

portfolio = DemoPortfolio()
risk = RiskEngine()
engine = DemoEngine(portfolio, risk)

demo_loop = DemoTradingLoop()


class DemoOrderRequest(BaseModel):
    symbol: str = Field(min_length=1, max_length=30)
    side: str
    quantity: float = Field(gt=0)
    price: float = Field(gt=0)


@router.get("/portfolio")
def get_portfolio():
    return portfolio.model_dump()


@router.post("/demo/order")
def demo_order(request: DemoOrderRequest):
    order = OrderIntent(symbol=request.symbol, side=request.side, quantity=request.quantity)
    return engine.simulate_order(order, request.price)


@router.post("/demo/run")
def demo_run(request: TechnicalSignalRequest, quantity: float = Field(default=1, gt=0)):
    """Run one strategy -> risk -> virtual execution cycle."""
    return demo_loop.run(request, quantity=quantity)


@router.get("/demo/portfolio")
def demo_portfolio():
    return demo_loop.snapshot()
