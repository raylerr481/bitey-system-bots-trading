"""Demo portfolio API for the mobile app."""
from fastapi import APIRouter
from app.api.trading import portfolio

router = APIRouter(prefix="/api/v1/demo", tags=["demo"])


@router.get("/portfolio")
def demo_portfolio():
    return portfolio.model_dump()


@router.get("/status")
def demo_status():
    return {
        "mode": "demo",
        "real_money": False,
        "broker_orders": False,
        "virtual_capital": portfolio.initial_capital,
        "description": "Simulación con capital ficticio; no envía órdenes al broker.",
    }
