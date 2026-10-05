from __future__ import annotations
from datetime import datetime, timezone
from typing import Any
from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field
from app.storage import research_experiments

router=APIRouter(prefix="/api/v1/experiments",tags=["experiments"])

def now(): return datetime.now(timezone.utc).isoformat()

def _base(e):
    return {
      "research":{"status":e.get("stage","DISCOVERED"),"experiment_id":e.get("experiment_id"),"hypothesis":e.get("hypothesis") or {},"feature_candidates":e.get("feature_candidates") or []},
      "mt4":{"status":e.get("metadata",{}).get("mt4_status","WAITING_FOR_MT4"),"strategy_timeframe":e.get("strategy_timeframe"),"chart_timeframe":e.get("chart_timeframe")},
      "evidence":{"status":e.get("stage"),"baseline":e.get("baseline_evidence") or {},"enhanced":e.get("enhanced_evidence") or {}},
      "evolution":e.get("evolution_status") or {"eligible":False},
      "validation":e.get("validation") or {"wfo":None,"oos":None,"robustness":None},
    }

class ExperimentCreate(BaseModel):
    experiment_id:str=Field(min_length=5,max_length=160)
    symbol:str
    strategy:str="ENSEMBLE"
    strategy_timeframe:str="M15"
    chart_timeframe:str|None=None
    parent_experiment_id:str|None=None
    hypothesis:dict[str,Any]=Field(default_factory=dict)
    feature_candidates:list[dict[str,Any]]=Field(default_factory=list)
    metadata:dict[str,Any]=Field(default_factory=dict)

@router.post("")
def create_experiment(p:ExperimentCreate):
    row=p.model_dump()
    row.update({"stage":"DISCOVERED","source":"BITEY_SBT","baseline_evidence":{},"enhanced_evidence":{},"validation":{"wfo":None,"oos":None,"robustness":None},"evolution_status":{"eligible":False,"reason":"VALIDATION_REQUIRED"}})
    try: out=research_experiments.upsert(row)
    except Exception as exc: raise HTTPException(503,"experiment persistence failed") from exc
    return {"contract":"sbt-experiment-lineage-v1","experiment_id":p.experiment_id,"persisted":out.get("persisted",False),"experiment":row}

@router.get("")
def list_experiments(limit:int=Query(50,ge=1,le=200)):
    items=research_experiments.list_recent(limit)
    return {"contract":"sbt-experiment-lineage-v1","items":items,"count":len(items)}

@router.get("/{experiment_id}")
def get_experiment(experiment_id:str):
    try:e=research_experiments.get(experiment_id)
    except Exception as exc:raise HTTPException(503,"experiment store unavailable") from exc
    if not e:raise HTTPException(404,"experiment_id not found")
    return {"contract":"sbt-experiment-timeline-v1","experiment_id":experiment_id,"timeline":_base(e),"raw":e}

@router.get("/{experiment_id}/mt4-order")
def mt4_order(experiment_id:str):
    e=research_experiments.get(experiment_id)
    if not e:raise HTTPException(404,"experiment_id not found")
    if e.get("strategy")!="ENSEMBLE" or e.get("strategy_timeframe")!="M15":
        raise HTTPException(409,"This gated feature workflow is defined for ENSEMBLE M15")
    order={"order_id":"EXP-"+experiment_id+"-"+datetime.now(timezone.utc).strftime("%Y%m%d%H%M%S"),"experiment_id":experiment_id,"symbol":e["symbol"],"strategy":"ENSEMBLE","strategy_timeframe":"M15","chart_timeframe":e.get("chart_timeframe") or "M15","action":"RUN_STRATEGY_TESTER","mode":"DEMO_ONLY","feature_candidates":e.get("feature_candidates") or [],"baseline_required":True,"costs_required":True,"validation_pipeline":["COST_AWARE_BACKTEST","WFO","OOS","ROBUSTNESS"],"automatic_execution":False,"authority":"MT4 controls DEMO/REAL"}
    meta=dict(e.get("metadata") or {});meta.update({"mt4_status":"ORDER_READY","mt4_order_id":order["order_id"],"mt4_last_seen":now()});e.update({"metadata":meta,"stage":"MT4_ORDER_READY","updated_at":now()})
    research_experiments.upsert(e)
    return {"contract":"sbt-experiment-mt4-order-v1","order":order}

@router.post("/{experiment_id}/mt4")
def mark_mt4(experiment_id:str,payload:dict[str,Any]):
    e=research_experiments.get(experiment_id)
    if not e:raise HTTPException(404,"experiment_id not found")
    meta=dict(e.get("metadata") or {});meta.update({"mt4_status":payload.get("status","TELEMETRY_BOUND"),"mt4_order_id":payload.get("order_id"),"mt4_last_seen":now()})
    e.update({"metadata":meta,"stage":"MT4_LINKED","updated_at":now()})
    return research_experiments.upsert(e)

@router.post("/{experiment_id}/evidence")
def attach_evidence(experiment_id:str,payload:dict[str,Any]):
    e=research_experiments.get(experiment_id)
    if not e:raise HTTPException(404,"experiment_id not found")
    kind=str(payload.get("kind","enhanced")).lower();key="baseline_evidence" if kind=="baseline" else "enhanced_evidence"
    e[key]=payload;e["stage"]="EVIDENCE_COLLECTED";e["updated_at"]=now()
    return research_experiments.upsert(e)

@router.post("/{experiment_id}/validation")
def attach_validation(experiment_id:str,payload:dict[str,Any]):
    e=research_experiments.get(experiment_id)
    if not e:raise HTTPException(404,"experiment_id not found")
    v=dict(e.get("validation") or {});v.update(payload);e["validation"]=v
    e["stage"]="VALIDATED" if all(bool(v.get(k)) for k in ("wfo","oos","robustness")) else "VALIDATION_PENDING"
    m=(e.get("enhanced_evidence") or {}).get("metrics") or {}
    enough=isinstance(m.get("trades"),(int,float)) and m["trades"]>=30 and isinstance(m.get("months"),(int,float)) and m["months"]>=6
    eligible=enough and all(bool(v.get(k)) for k in ("wfo","oos","robustness"))
    e["evolution_status"]={"eligible":eligible,"reason":"ALL_GATES_PASSED" if eligible else "BACKTEST_COST_WFO_OOS_ROBUSTNESS_REQUIRED","experiment_id":experiment_id}
    e["updated_at"]=now()
    return research_experiments.upsert(e)

@router.get("/{experiment_id}/evolution-candidate")
def evolution_candidate(experiment_id:str):
    e=research_experiments.get(experiment_id)
    if not e:raise HTTPException(404,"experiment_id not found")
    v=e.get("validation") or {};m=(e.get("enhanced_evidence") or {}).get("metrics") or {}
    checks={"trades>=30":isinstance(m.get("trades"),(int,float)) and m["trades"]>=30,"months>=6":isinstance(m.get("months"),(int,float)) and m["months"]>=6,"wfo":bool(v.get("wfo")),"oos":bool(v.get("oos")),"robustness":bool(v.get("robustness"))}
    eligible=all(checks.values())
    return {"contract":"sbt-evolution-candidate-gate-v1","experiment_id":experiment_id,"eligible":eligible,"checks":checks,"candidate":{"strategy":"ENSEMBLE","timeframe":e.get("strategy_timeframe"),"feature_candidates":e.get("feature_candidates") or []} if eligible else None,"reason":"ALL_GATES_PASSED" if eligible else "NOT_ELIGIBLE"}
