from __future__ import annotations

from typing import Any
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.market_sdk.registry import build_provider
from app.market_sdk import ProviderError
from app.quant.nonlinear_patterns import mine_nonlinear_patterns
from app.storage import research_experiments

router = APIRouter(prefix="/api/v1/research/nonlinear-patterns", tags=["nonlinear-patterns"])

class PatternMiningRequest(BaseModel):
    bars: list[dict[str, Any]] = Field(min_length=120, max_length=5000)
    window: int = Field(default=16, ge=8, le=64)
    horizon: int = Field(default=8, ge=1, le=32)
    neighbors: int = Field(default=12, ge=5, le=50)
    min_support: int = Field(default=8, ge=3, le=200)

def _experiment_id(symbol: str, timeframe: str) -> str:
    return f"INTRADAY-{symbol.upper()}-ENSEMBLE-{timeframe.upper()}"

def _feature_candidates(result: dict[str, Any]) -> list[dict[str, Any]]:
    out=[]
    for p in result.get("top_positive_patterns", []):
        out.append({
            "feature_id": f"NONLINEAR::{p['pattern']}",
            "type": "interaction_regime",
            "definition": p["pattern"],
            "source_metrics": p,
            "execution": "CANDIDATE_ONLY",
        })
    motif=result.get("latest_shape_motif") or {}
    out.append({
        "feature_id":"NONLINEAR::LATEST_SHAPE_MOTIF",
        "type":"nearest_neighbor_shape",
        "definition":{"window":motif.get("window"),"neighbors":motif.get("neighbors")},
        "source_metrics":motif,
        "execution":"CANDIDATE_ONLY",
    })
    return out

def _register(symbol: str, timeframe: str, result: dict[str, Any], source: str):
    eid=_experiment_id(symbol,timeframe)
    features=_feature_candidates(result)
    row={
      "experiment_id":eid,"symbol":symbol.upper(),"strategy":"ENSEMBLE",
      "strategy_timeframe":timeframe.upper(),"chart_timeframe":timeframe.upper(),
      "stage":"FEATURE_DISCOVERED","source":"BITEY_SBT",
      "hypothesis":{"baseline":"ENSEMBLE","augmentation":"nonlinear pattern features","research_only":True},
      "feature_candidates":features,"baseline_evidence":{},"enhanced_evidence":{},
      "validation":{"wfo":None,"oos":None,"robustness":None},
      "evolution_status":{"eligible":False,"reason":"BACKTEST_COST_WFO_OOS_ROBUSTNESS_REQUIRED"},
      "metadata":{"source":source,"mt4_status":"WAITING_FOR_RESEARCH_ORDER"}
    }
    try:
        return eid,features,research_experiments.upsert(row)
    except Exception:
        return eid,features,{"persisted":False,"reason":"SUPABASE_WRITE_FAILED"}

@router.get("/catalog")
def catalog():
    return {"contract":"sbt-nonlinear-pattern-mining-v1","methods":["nonlinear momentum-volatility-location interactions","nearest-neighbor shape motifs","lookahead-free forward-return attribution"],"research":["nonlinear regime representation","symbolic/pattern discovery","multivariate regime detection"],"safety":{"research_only":True,"execution_enabled":False,"real_money":False}}

@router.post("/mine")
def mine(request: PatternMiningRequest):
    result=mine_nonlinear_patterns(**request.model_dump())
    return result

@router.get("/{symbol}")
async def mine_market(symbol: str, timeframe: str=Query(default="M15",min_length=2,max_length=4), limit:int=Query(default=500,ge=120,le=500), window:int=Query(default=16,ge=8,le=64), horizon:int=Query(default=8,ge=1,le=32)):
    symbol=symbol.upper(); timeframe=timeframe.upper()
    provider=build_provider()
    try:
        rows=await provider.candles(symbol,timeframe,limit)
    except (ProviderError,ValueError) as exc:
        raise HTTPException(status_code=502,detail=str(exc)) from exc
    result=mine_nonlinear_patterns([row.as_dict() for row in rows],window=window,horizon=horizon)
    eid,features,persistence=_register(symbol,timeframe,result,provider.name)
    result.update({"symbol":symbol,"timeframe":timeframe,"experiment_id":eid,"source":provider.name,"feature_candidates":features,"experiment_persistence":persistence,"ensemble_target":{"strategy":"ENSEMBLE","baseline":"UNCHANGED","candidate_features":"VALIDATION_GATED","automatic_execution":False}})
    return result
