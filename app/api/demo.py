"""Demo portfolio API for the mobile app."""
from fastapi import APIRouter
from app.core.models import DemoPortfolio

router = APIRouter(prefix="/api/v1/demo", tags=["demo"])
_demo_portfolio = DemoPortfolio(initial_capital=10_000, cash=10_000)

@router.get("/portfolio")
def demo_portfolio():
    return _demo_portfolio.model_dump()

@router.get("/status")
def demo_status():
    return {"mode": "demo", "real_money": False, "broker_orders": False, "description": "Simulación con capital ficticio."}
