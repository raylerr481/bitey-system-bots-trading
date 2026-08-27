from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.services.demo_state import get_demo_state
from app.strategies.technical import TechnicalSignalRequest

router = APIRouter(prefix="/api/v1/demo", tags=["demo"])


class DemoRunRequest(TechnicalSignalRequest):
    quantity: float = Field(default=1, gt=0)


@router.post("/run")
def run_demo(request: DemoRunRequest):
    return get_demo_state().run(request, request.quantity)


@router.get("/portfolio")
def portfolio():
    return get_demo_state().snapshot()
