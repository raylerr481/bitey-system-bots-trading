from fastapi import APIRouter
from app.strategies.technical import TechnicalSignalRequest, technical_signal
from app.strategies.smc import SMCSignalRequest, smc_signal

router = APIRouter(prefix="/api/v1/strategy", tags=["strategy"])


@router.post("/signal")
def signal(request: TechnicalSignalRequest):
    return technical_signal(request)


@router.post("/smc")
def smc(request: SMCSignalRequest):
    return smc_signal(request)
