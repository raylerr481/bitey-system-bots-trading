"""Bitey SBT Evolution Engine — evidence ledger and experiment selector.

This module does not place broker orders or change MT4 environment. It turns
available telemetry/backtests into a reproducible experiment queue and keeps
versioned evolution records.
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from fastapi import APIRouter
from pydantic import BaseModel, Field

from app.api.mt4 import _latest, _history, _backtests
from app.strategies.objectives import TRADING_OBJECTIVE, score_priority

router = APIRouter(prefix="/api/v1/evolution", tags=["evolution"])
_records: list[dict[str, Any]] = []
_EXPERIMENTS = [
    {"strategy_id": "SBT-TURTLE-S1-001", "label": "Turtle S1", "timeframes": ["M5","M15","M30","H1","H4","D1"]},
    {"strategy_id": "SBT-TURTLE-S2-001", "label": "Turtle S2", "timeframes": ["M5","M15","M30","H1","H4","D1"]},
]

def _now() -> str:
    return datetime.now(timezone.utc).isoformat()

def _number(v: Any) -> float | None:
    try: return float(v) if v is not None else None
    except (TypeError, ValueError): return None

def _flatten(row: dict[str, Any]) -> dict[str, Any]:
    m = row.get("metrics") or row.get("results") or row
    return {
        "monthly_net_return": _number(m.get("monthly_net_return", m.get("monthly_return"))),
        "expected_return": _number(m.get("expected_return", m.get("expectancy"))),
        "profit_factor": _number(m.get("profit_factor", m.get("pf"))),
        "expectancy": _number(m.get("expectancy")),
        "max_drawdown": _number(m.get("max_drawdown", m.get("drawdown"))),
        "positive_month_probability": _number(m.get("positive_month_probability")),
        "negative_month_probability": _number(m.get("negative_month_probability")),
        "robustness": _number(m.get("robustness")),
        "oos_quality": _number(m.get("oos_quality")),
        "cost_drag": _number(m.get("cost_drag")),
    }

def _backtest_candidates() -> list[dict[str, Any]]:
    candidates=[]
    for row in _backtests:
        data=_flatten(row)
        if data["monthly_net_return"] is None and data["expected_return"] is None:
            continue
        bot=row.get("bot") or {}
        candidates.append({
            "strategy_id": bot.get("strategy") or row.get("strategy_id") or row.get("strategy"),
            "symbol": row.get("symbol") or bot.get("symbol"),
            "timeframe": row.get("timeframe") or bot.get("timeframe"),
            "version": bot.get("version") or row.get("version"),
            "metrics": data,
            "score": score_priority({k:v for k,v in data.items() if v is not None}),
            "source": "backtest",
        })
    return candidates

@router.get("/status")
def status():
    return {
        "contract":"sbt-evolution-v1",
        "objective":TRADING_OBJECTIVE,
        "environment":((_latest or {}).get("account") or {}).get("mode") or "UNKNOWN",
        "records":len(_records),
        "telemetry_snapshots":len(_history),
        "backtests":len(_backtests),
        "best_observed_candidate":best_candidate(),
        "next_experiments":next_experiments(),
        "turtle_matrix": turtle_matrix(),
    }

@router.get("/experiments")
def next_experiments():
    existing={(r.get("strategy_id"),r.get("timeframe")) for r in _records}
    current=(_latest or {}).get("symbol") or "EURUSD"
    items=[]
    for spec in _EXPERIMENTS:
        for tf in spec["timeframes"]:
            if (spec["strategy_id"],tf) in existing: continue
            items.append({
                "strategy_id":spec["strategy_id"], "label":spec["label"],
                "symbol":current, "timeframe":tf, "status":"READY_FOR_BACKTEST",
                "reason":"Comparar beneficio neto mensual bajo las mismas condiciones."
            })
    return {"contract":"sbt-evolution-experiment-queue-v1","objective":"monthly_net_return","items":items}

def _turtle_matrix_rows() -> list[dict[str, Any]]:
    rows = []
    for spec in _EXPERIMENTS:
        for tf in spec["timeframes"]:
            matches = [x for x in _backtest_candidates()
                       if x["strategy_id"] == spec["strategy_id"] and x["timeframe"] == tf]
            best = max(matches, key=lambda x: x["score"]) if matches else None
            rows.append({
                "strategy_id": spec["strategy_id"],
                "label": spec["label"],
                "symbol": best.get("symbol") if best else ((_latest or {}).get("symbol") or "EURUSD"),
                "timeframe": tf,
                "status": "EVIDENCE_AVAILABLE" if best else "UNTESTED",
                "best_candidate": best,
                "evidence_count": len(matches),
            })
    return rows

@router.get("/turtle-matrix")
def turtle_matrix():
    rows = _turtle_matrix_rows()
    tested = [r for r in rows if r["best_candidate"]]
    ranked = sorted(tested, key=lambda r: r["best_candidate"]["score"], reverse=True)
    return {
        "contract": "sbt-turtle-timeframe-matrix-v1",
        "objective": "maximize_monthly_profit_subject_to_risk_and_robustness",
        "symbol": ((_latest or {}).get("symbol") or "EURUSD"),
        "systems": ["SBT-TURTLE-S1-001", "SBT-TURTLE-S2-001"],
        "timeframes": ["M5","M15","M30","H1","H4","D1"],
        "tested_count": len(tested),
        "total_combinations": len(rows),
        "winner": ranked[0] if ranked else None,
        "ranking": ranked,
        "matrix": rows,
        "note": "UNTESTED means SBT has no comparable MT4 backtest evidence for that exact Turtle/timeframe combination. No winner is inferred from external evidence."
    }

@router.get("/compare")
def compare():
    candidates=_backtest_candidates()
    candidates.sort(key=lambda x:x["score"],reverse=True)
    return {
        "contract":"sbt-evolution-comparator-v1",
        "objective":"monthly_net_return",
        "evidence_count":len(candidates),
        "status":"EVIDENCE_AVAILABLE" if candidates else "NO_COMPARABLE_BACKTEST_EVIDENCE",
        "ranking":candidates[:20],
        "note":"Ranking is based only on supplied backtest evidence. Missing metrics are not invented."
    }

@router.get("/best")
def best_candidate():
    candidates=_backtest_candidates()
    if not candidates:
        return None
    return max(candidates,key=lambda x:x["score"])

class EvolutionRecord(BaseModel):
    bot_id: str
    strategy_id: str
    symbol: str
    timeframe: str
    previous_version: str | None = None
    new_version: str
    reason: str
    status: str = "PROPOSED"
    evidence: dict[str, Any] = Field(default_factory=dict)
    rollback_target: str | None = None

@router.post("/record")
def record_evolution(record: EvolutionRecord):
    item=record.model_dump()
    item.update({"timestamp":_now(),"environment":((_latest or {}).get("account") or {}).get("mode") or "UNKNOWN"})
    _records.append(item)
    return {"accepted":True,"record":item,"count":len(_records)}

@router.get("/records")
def records():
    return {"contract":"sbt-evolution-ledger-v1","items":list(reversed(_records[-100:])),"count":len(_records)}

@router.get("/report")
def report():
    best=best_candidate()
    return {
        "contract":"sbt-evolution-report-v1",
        "generated_at":_now(),
        "objective":"maximize_monthly_profit_subject_to_risk_and_robustness",
        "current_bot":(_latest or {}).get("bot"),
        "environment":((_latest or {}).get("account") or {}).get("mode") or "UNKNOWN",
        "best_validated_candidate":best,
        "evolution_records":list(reversed(_records[-20:])),
        "next_action": "RUN_TURTLE_BACKTEST_MATRIX" if not turtle_matrix()["winner"] else "VALIDATE_TOP_TURTLE_WITH_WFO_OOS_ROBUSTNESS",
        "email_ready":True,
        "email_recipient":"raylerr481@gmail.com",
        "note":"Este informe no envía correo todavía; requiere un conector de email autorizado."
    }
