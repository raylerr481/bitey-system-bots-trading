from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.market_sdk.registry import build_provider
from app.market_sdk import ProviderError
from app.quant.nonlinear_patterns import mine_nonlinear_patterns

router = APIRouter(prefix="/api/v1/research/nonlinear-patterns", tags=["nonlinear-patterns"])


class PatternMiningRequest(BaseModel):
    bars: list[dict[str, Any]] = Field(min_length=120, max_length=5000)
    window: int = Field(default=16, ge=8, le=64)
    horizon: int = Field(default=8, ge=1, le=32)
    neighbors: int = Field(default=12, ge=5, le=50)
    min_support: int = Field(default=8, ge=3, le=200)


@router.get("/catalog")
def catalog():
    return {
        "contract": "sbt-nonlinear-pattern-mining-v1",
        "methods": [
            "nonlinear momentum-volatility-location interactions",
            "nearest-neighbor shape motifs",
            "lookahead-free forward-return attribution",
        ],
        "research": [
            "nonlinear regime representation",
            "symbolic/pattern discovery",
            "multivariate regime detection",
        ],
        "safety": {"research_only": True, "execution_enabled": False, "real_money": False},
    }


@router.post("/mine")
def mine(request: PatternMiningRequest):
    return mine_nonlinear_patterns(**request.model_dump())


@router.get("/{symbol}")
async def mine_market(
    symbol: str,
    timeframe: str = Query(default="M15", min_length=2, max_length=4),
    limit: int = Query(default=500, ge=120, le=500),
    window: int = Query(default=16, ge=8, le=64),
    horizon: int = Query(default=8, ge=1, le=32),
):
    provider = build_provider()
    try:
        rows = await provider.candles(symbol.upper(), timeframe.upper(), limit)
    except (ProviderError, ValueError) as exc:
        raise HTTPException(status_code=502, detail=str(exc)) from exc
    result = mine_nonlinear_patterns(
        [row.as_dict() for row in rows],
        window=window,
        horizon=horizon,
    )
    result.update({
        "symbol": symbol.upper(),
        "timeframe": timeframe.upper(),
        "experiment_id": f"INTRADAY-{symbol.upper()}-ENSEMBLE-{timeframe.upper()}",
        "source": provider.name,
    })
    return result
