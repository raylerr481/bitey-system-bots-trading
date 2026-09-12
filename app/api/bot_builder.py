from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.strategy_discovery.matrix import build_matrix

router = APIRouter(prefix="/api/v1/bot-builder", tags=["bot-builder"])

class MatrixRequest(BaseModel):
    symbols: list[str] = Field(min_length=1, max_length=100)
    timeframes: list[str] = Field(min_length=1, max_length=20)
    max_targets: int = Field(default=100, ge=1, le=100)

@router.post("/strategy-discovery/matrix")
def strategy_discovery_matrix(request: MatrixRequest):
    targets = build_matrix(request.symbols, request.timeframes, request.max_targets)
    return {
        "contract": "sbt-research-matrix-v1",
        "mode": "free-deterministic-research",
        "targets": [target.__dict__ for target in targets],
        "target_count": len(targets),
        "limits": {"max_targets": request.max_targets},
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
        "next_stage": "fetch-provider-data-per-target-then-backtest"
    }
