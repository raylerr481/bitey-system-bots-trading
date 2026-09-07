from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.quant.regime_lab import catalog as regime_catalog, run_regime_lab

router = APIRouter(prefix="/api/v1/quant/regime-lab", tags=["regime-lab"])

class RegimeLabRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=100, max_length=100000)
    strategy_id: str = "AR-001"
    states: int | str = "auto"
    window: int = Field(default=20, ge=5, le=500)
    seed: int = Field(default=7, ge=0, le=1000000)
    initial_capital: float = Field(default=10000, gt=0)
    risk_pct: float = Field(default=0.01, gt=0, le=0.05)
    fee_bps: float = Field(default=1.0, ge=0, le=1000)
    slippage_bps: float = Field(default=1.0, ge=0, le=1000)
    direction: str = Field(default="long", pattern="^(long|short)$")
    oos_start: int | None = Field(default=None, ge=1)
    bootstrap_samples: int = Field(default=2000, ge=2000, le=100000)

@router.get("/catalog")
def get_catalog():
    return regime_catalog()

@router.post("/run")
def run(request: RegimeLabRequest):
    return run_regime_lab(**request.model_dump())
