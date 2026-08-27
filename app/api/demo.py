from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.demo_loop import DemoTradingLoop
from app.strategies.technical import TechnicalSignalRequest

router = APIRouter(prefix="/api/v1/demo", tags=["demo"])

_loop = DemoTradingLoop()


class DemoRunRequest(TechnicalSignalRequest):
    quantity: float = Field(default=1, gt=0)


@router.post("/run")
def run_demo(request: DemoRunRequest):
    return _loop.run(request, request.quantity)


@router.get("/portfolio")
def portfolio():
    return _loop.snapshot()
