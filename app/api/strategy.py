from fastapi import APIRouter
from app.strategies.technical import TechnicalSignalRequest, technical_signal

router = APIRouter(prefix="/api/v1/strategy", tags=["strategy"])


@router.post("/signal")
def signal(request: TechnicalSignalRequest):
    return technical_signal(request)
