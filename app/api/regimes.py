from fastapi import APIRouter
from pydantic import BaseModel, Field
from app.quant.hmm import analyze_regimes

router = APIRouter(prefix="/api/v1/quant/regimes", tags=["quant-regimes"])

class HMMRequest(BaseModel):
    bars: list[dict[str, float]] = Field(min_length=40, max_length=100000)
    states: int | str = "auto"
    window: int = Field(default=20, ge=5, le=500)
    seed: int = Field(default=7, ge=0, le=1000000)

@router.post("/hmm")
def hmm(request: HMMRequest):
    return analyze_regimes(request.bars, request.states, request.window, request.seed)
