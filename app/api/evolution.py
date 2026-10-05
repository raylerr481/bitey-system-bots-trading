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
from app.storage import backtest_evidence

router = APIRouter(prefix="/api/v1/evolution", tags=["evolution"])
_records: list[dict[str, Any]] = []
# Research-priority candidates are hypotheses, not claims of guaranteed profitability.
# Priority is based on published evidence for trend/momentum persistence and practical
# compatibility with MT4; all remain UNVALIDATED until SBT backtest/WFO/OOS passes.
_RESEARCH_PRIORITY = [
    {"strategy_id":"SBT-TSMOM-001","label":"Time-Series Momentum","priority":1,
     "evidence":"Moskowitz, Ooi & Pedersen (2012); AQR trend-following research",
     "reason":"Strong published evidence across currencies and other liquid futures/forwards."},
    {"strategy_id":"SBT-TURTLE-S1-001","label":"Turtle S1","priority":2,
     "evidence":"Classic Turtle rules; trend-following literature",
     "reason":"Transparent Donchian trend-following baseline."},
    {"strategy_id":"SBT-TURTLE-S2-001","label":"Turtle S2","priority":3,
     "evidence":"Classic Turtle rules; trend-following literature",
     "reason":"Slower breakout baseline for longer trends."},
    {"strategy_id":"SBT-DONCHIAN-001","label":"Donchian Breakout","priority":4,
     "evidence":"Donchian/Turtle breakout family",
     "reason":"Simple breakout baseline for controlled comparison."},
    {"strategy_id":"SBT-ADX-TREND-001","label":"ADX Trend Filter","priority":5,
     "evidence":"Classical trend-strength methodology",
     "reason":"Tests whether a trend-strength filter improves breakout/trend entries."},
    {"strategy_id":"SBT-DUAL-THRUST-001","label":"Dual Thrust Breakout","priority":6,
     "evidence":"Published breakout family",
     "reason":"Range-expansion alternative to Donchian entries."},
]

_TIMEFRAMES = ["M5","M15","M30","H1","H4","D1"]
_EXPERIMENTS = [
    {"strategy_id": x["strategy_id"], "label": x["label"], "priority": x["priority"], "timeframes": _TIMEFRAMES}
    for x in _RESEARCH_PRIORITY
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
        "trades": _number(m.get("trades", m.get("trade_count"))),
        "months": _number(m.get("months", m.get("months_tested"))),
    }

def _persistent_backtests() -> list[dict[str, Any]]:
    try:
        rows = backtest_evidence.list_recent(500)
    except Exception:
        rows = []
    if rows:
        normalized = []
        for row in rows:
            bot = {
                "strategy": row.get("strategy_id"),
                "version": row.get("strategy_version"),
                "id": row.get("bot_id"),
                "parameters": row.get("parameters") or {},
            }
            normalized.append({
                "symbol": row.get("symbol"),
                "timeframe": row.get("timeframe"),
                "bot": bot,
                "metrics": row.get("metrics") or {},
                "costs": row.get("costs") or {},
                "validation": row.get("validation") or {},
                "source": row.get("source"),
                "timestamp": row.get("created_at"),
            })
        return normalized
    return list(_backtests)

def _backtest_candidates() -> list[dict[str, Any]]:
    candidates=[]
    for row in _persistent_backtests():
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
        "backtests":len(_persistent_backtests()),
        "best_observed_candidate":best_candidate(),
        "next_experiments":next_experiments(),
        "research_matrix": research_matrix(),
    }

@router.get("/experiments")
def next_experiments():
    existing={(r.get("strategy_id"),r.get("timeframe")) for r in _records}
    tested={(x["strategy_id"],x["timeframe"]) for x in _backtest_candidates()}
    current=(_latest or {}).get("symbol") or "EURUSD"
    items=[]
    for spec in _EXPERIMENTS:
        for tf in spec["timeframes"]:
            if (spec["strategy_id"],tf) in existing: continue
            items.append({
                "strategy_id":spec["strategy_id"], "label":spec["label"],
                "symbol":current, "timeframe":tf, "status":"EVIDENCE_AVAILABLE" if (spec["strategy_id"],tf) in tested else "READY_FOR_BACKTEST",
                "reason":"Comparar beneficio neto mensual bajo las mismas condiciones." if (spec["strategy_id"],tf) not in tested else "Ya existe evidencia de backtest; falta validación WFO/OOS/robustez para promoción."
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

@router.get("/research-priority")
def research_priority():
    return {
        "contract":"sbt-research-priority-v1",
        "objective":"maximize_monthly_profit_subject_to_risk_and_robustness",
        "status":"RESEARCH_ONLY",
        "candidates":_RESEARCH_PRIORITY,
        "warning":"Published evidence supports strategy families, not guaranteed profitability for EURUSD/MT4. Every candidate must pass cost-aware backtest, WFO, OOS and robustness validation."
    }

@router.get("/research-matrix")
def research_matrix():
    rows = _turtle_matrix_rows()
    tested = [r for r in rows if r["best_candidate"]]
    eligible = []
    for r in tested:
        m = r["best_candidate"]["metrics"]
        # A candidate is not a winner merely because it has a backtest.
        # Require enough observations and validation evidence before promotion.
        if (m.get("trades") is not None and m["trades"] < 30):
            continue
        if (m.get("months") is not None and m["months"] < 6):
            continue
        if m.get("oos_quality") is None or m.get("robustness") is None:
            continue
        eligible.append(r)
    ranked = sorted(eligible, key=lambda r: r["best_candidate"]["score"], reverse=True)
    return {
        "contract": "sbt-research-timeframe-matrix-v1",
        "objective": "maximize_monthly_profit_subject_to_risk_and_robustness",
        "symbol": ((_latest or {}).get("symbol") or "EURUSD"),
        "systems": [x["strategy_id"] for x in _RESEARCH_PRIORITY],
        "timeframes": ["M5","M15","M30","H1","H4","D1"],
        "tested_count": len(tested),
        "eligible_count": len(eligible),
        "total_combinations": len(rows),
        "winner": ranked[0] if ranked else None,
        "ranking": ranked,
        "matrix": rows,
        "note": "UNTESTED means no comparable MT4 evidence. A candidate is only eligible for winner ranking when observation and WFO/OOS/robustness evidence are present; otherwise it remains a research candidate."
    }

@router.get("/mt4-selection")
def mt4_selection(limit: int = 6):
    """Select the next research candidates for the local MT4 Strategy Tester.

    This endpoint never starts MT4 and never changes DEMO/REAL. It only produces
    deterministic test jobs from the 36 strategy/timeframe matrix using persisted
    evidence and the monthly-profit objective.
    """
    limit = max(1, min(limit, 36))
    candidates = []
    evidence = _backtest_candidates()
    by_key = {}
    for row in evidence:
        key = (row["strategy_id"], row["timeframe"])
        by_key[key] = row if key not in by_key or row["score"] > by_key[key]["score"] else by_key[key]
    priority = {x["strategy_id"]: x["priority"] for x in _RESEARCH_PRIORITY}
    labels = {x["strategy_id"]: x["label"] for x in _RESEARCH_PRIORITY}
    for spec in _EXPERIMENTS:
        for tf in spec["timeframes"]:
            key = (spec["strategy_id"], tf)
            row = by_key.get(key)
            if row is None:
                state, reason = "READY_FOR_MT4_TEST", "Sin evidencia comparable; prioridad de investigación."
                score = 100.0 - priority[spec["strategy_id"]]
            else:
                m = row["metrics"]
                validated = m.get("oos_quality") is not None and m.get("robustness") is not None
                enough = (m.get("trades") is None or m["trades"] >= 30) and (m.get("months") is None or m["months"] >= 6)
                if validated and enough:
                    state, reason = "VALIDATED_EVIDENCE", "Ya supera el umbral de evidencia; no repetir salvo nueva hipótesis."
                    score = row["score"] - 1000.0
                else:
                    state, reason = "RETEST_WITH_VALIDATION", "Existe backtest, pero falta evidencia WFO/OOS/robustez suficiente."
                    score = row["score"] + (10.0 - priority[spec["strategy_id"]])
            candidates.append({
                "strategy_id": spec["strategy_id"],
                "label": labels[spec["strategy_id"]],
                "symbol": ((_latest or {}).get("symbol") or "EURUSD"),
                "timeframe": tf,
                "selection_score": round(score, 6),
                "state": state,
                "reason": reason,
                "objective": "monthly_net_return",
                "mt4_action": "RUN_STRATEGY_TESTER",
                "risk_mode": "DEMO_ONLY",
            })
    candidates.sort(key=lambda x: x["selection_score"], reverse=True)
    return {
        "contract": "sbt-mt4-selection-v1",
        "total_combinations": 36,
        "returned": min(limit, len(candidates)),
        "selection": candidates[:limit],
        "authority": "MT4 controls DEMO/REAL; SBT only selects research jobs.",
        "note": "Selection does not execute trades or change MT4 environment."
    }

@router.get("/pipeline")
def pipeline():
    """End-to-end Turtle research pipeline: MT4 -> Bitey IA -> Evolution Engine.

    This endpoint selects research only. It never changes MT4 mode and never
    starts a Strategy Tester run automatically.
    """
    snapshot = _latest or {}
    ai = snapshot.get("ai") or {}
    turtle = snapshot.get("turtle_controller") or snapshot.get("turtle") or {}
    bot = snapshot.get("bot") or {}
    action = str(ai.get("action") or "HOLD").upper()
    regime = str(ai.get("regime") or turtle.get("regime") or snapshot.get("regime") or "UNKNOWN").upper()
    next_test = str(ai.get("next_test") or "").upper()

    strategy_id = None
    timeframe = None
    if next_test:
        if "S1" in next_test:
            strategy_id = "SBT-TURTLE-S1-001"
        elif "S2" in next_test:
            strategy_id = "SBT-TURTLE-S2-001"
        for tf in _TIMEFRAMES:
            if next_test.endswith("_" + tf):
                timeframe = tf
                break

    selection = mt4_selection(limit=36)
    selected = None
    if strategy_id and timeframe:
        selected = next(
            (x for x in selection["selection"]
             if x["strategy_id"] == strategy_id and x["timeframe"] == timeframe),
            None,
        )

    if selected is None:
        selected = selection["selection"][0] if selection["selection"] else None

    return {
        "contract": "bitey-turtle-evolution-pipeline-v1",
        "status": "READY_FOR_RESEARCH" if selected else "WAITING_FOR_EVIDENCE",
        "phase": {
            "mt4": "TELEMETRY_RECEIVED" if snapshot else "WAITING_FOR_MT4",
            "bitey_ia": "DECISION_RECEIVED" if ai else "WAITING_FOR_BITEY_IA",
            "turtle": "ANALYZED" if turtle else "WAITING_FOR_TURTLE",
            "evolution": "SELECTION_READY" if selected else "NO_SELECTION",
        },
        "bot": bot,
        "symbol": snapshot.get("symbol"),
        "timeframe": snapshot.get("timeframe"),
        "mode": snapshot.get("mode") or (snapshot.get("account") or {}).get("mode"),
        "execution_enabled": bool(snapshot.get("execution_enabled", False)),
        "bitey_decision": {
            "action": action,
            "confidence": ai.get("confidence"),
            "risk_allowed": bool(ai.get("risk_allowed", False)),
            "strategy": ai.get("strategy"),
            "reason": ai.get("reason"),
            "source": ai.get("source"),
            "next_test": next_test or None,
            "validation_required": ai.get("validation_required", True),
        },
        "turtle_analysis": {
            "strategy": "S1" if "S1" in next_test else ("S2" if "S2" in next_test else turtle.get("strategy") or "TURTLE"),
            "regime": regime,
            "signal": turtle.get("signal") or "NONE",
            "status": turtle.get("status") or "UNKNOWN",
            "learning_status": turtle.get("learning_status") or "OBSERVING",
        },
        "next_backtest": selected,
        "evolution": {
            "status": "READY_FOR_MT4_TEST" if selected else "WAITING_FOR_EVIDENCE",
            "strategy_id": selected.get("strategy_id") if selected else strategy_id,
            "timeframe": selected.get("timeframe") if selected else timeframe,
            "objective": "maximum_monthly_net_profit",
            "mt4_action": "RUN_STRATEGY_TESTER" if selected else None,
        },
        "validation_pipeline": [
            "COST_AWARE_BACKTEST",
            "WFO",
            "OOS",
            "ROBUSTNESS",
            "MONTHLY_PROFITABILITY_ANALYSIS",
            "PERSIST_AS_EVIDENCE",
        ],
        "evidence_policy": {
            "class": "BACKTEST",
            "promotion_requires": ["trades>=30", "months>=6", "oos_quality", "robustness"],
            "source_of_truth": "Supabase backtest_evidence when configured",
        },
        "authority": "MT4 controls DEMO/REAL; Evolution Engine only selects research jobs.",
        "objective": "maximize_monthly_profit_subject_to_risk_and_robustness",
        "automatic_execution": False,
    }

class ResearchOrder(BaseModel):
    strategy_id: str
    strategy: str
    symbol: str
    timeframe: str
    action: str = "RUN_STRATEGY_TESTER"
    mode: str = "DEMO_ONLY"
    objective: str = "maximum_monthly_net_profit"
    validation_pipeline: list[str] = Field(default_factory=lambda: [
        "COST_AWARE_BACKTEST", "WFO", "OOS", "ROBUSTNESS",
        "MONTHLY_PROFITABILITY_ANALYSIS", "PERSIST_AS_EVIDENCE"
    ])
    source: str = "BITEY_IA_EVOLUTION"
    status: str = "READY_FOR_MT4_TEST"


@router.get("/research-order")
def research_order():
    """Return the single next MT4 research order selected by Bitey + Evolution.

    This is a research command, not a broker/trading command. It never changes
    MT4 DEMO/REAL and never starts MT4 automatically.
    """
    p = pipeline()
    selected = p.get("next_backtest") or {}
    if not selected:
        return {
            "contract": "sbt-mt4-research-order-v1",
            "status": "NO_ORDER",
            "order": None,
            "authority": "MT4 controls DEMO/REAL; user must start Strategy Tester.",
        }

    strategy_id = selected.get("strategy_id") or p.get("evolution", {}).get("strategy_id")
    label = selected.get("label") or strategy_id
    timeframe = selected.get("timeframe") or p.get("evolution", {}).get("timeframe")
    symbol = selected.get("symbol") or p.get("symbol") or "EURUSD"
    order = ResearchOrder(
        strategy_id=strategy_id,
        strategy=label,
        symbol=symbol,
        timeframe=timeframe,
        mode="DEMO_ONLY",
    ).model_dump()
    order["order_id"] = f"MT4-{strategy_id}-{symbol}-{timeframe}-{datetime.now(timezone.utc).strftime('%Y%m%d%H%M%S')}"
    order["instructions"] = [
        "Configure MT4 Strategy Tester with this symbol/timeframe.",
        "Run the selected Turtle strategy without changing DEMO/REAL automatically.",
        "Return the completed tester metrics to POST /api/v1/evolution/evidence.",
    ]
    order["bitey_decision"] = p.get("bitey_decision")
    order["turtle_analysis"] = p.get("turtle_analysis")
    order["evidence_policy"] = p.get("evidence_policy")
    return {
        "contract": "sbt-mt4-research-order-v1",
        "status": "READY_FOR_MT4_TEST",
        "order": order,
        "automatic_execution": False,
        "authority": "MT4 controls DEMO/REAL; this order only authorizes research/testing.",
    }


@router.post("/evidence")
def register_evidence(payload: dict[str, Any]):
    """Register a completed MT4 research result as persistent BACKTEST evidence.

    This endpoint does not promote a strategy or enable trading. Validation
    fields remain explicit so incomplete results cannot be mistaken for proof.
    """
    data=dict(payload)
    data["evidence_class"]="BACKTEST"
    data["source"]=data.get("source","MT4_STRATEGY_TESTER")
    validation=dict(data.get("validation") or {})
    validation.setdefault("wfo", None)
    validation.setdefault("oos", None)
    validation.setdefault("robustness", None)
    validation.setdefault("status", "UNVALIDATED")
    data["validation"]=validation
    try:
        persisted=backtest_evidence.save(data)
    except Exception as exc:
        persisted={"persisted":False,"reason":"SUPABASE_WRITE_FAILED","error":type(exc).__name__}
    return {
        "accepted": True,
        "evidence_class": "BACKTEST",
        "persisted": bool(persisted.get("persisted")),
        "persistence": persisted,
        "promotion_status": "UNVALIDATED",
        "next_validation": ["WFO","OOS","ROBUSTNESS"],
    }

@router.post("/evidence/evaluate")
def evaluate_evidence(payload: dict[str, Any]):
    """Classify MT4 research evidence without promoting or enabling trading."""
    data = dict(payload)
    metrics = dict(data.get("metrics") or {})
    validation = dict(data.get("validation") or {})
    trades = metrics.get("trades")
    months = metrics.get("months")
    checks = {
        "trades>=30": isinstance(trades, (int, float)) and trades >= 30,
        "months>=6": isinstance(months, (int, float)) and months >= 6,
        "wfo": bool(validation.get("wfo")),
        "oos": bool(validation.get("oos")),
        "robustness": bool(validation.get("robustness")),
    }
    if not checks["trades>=30"] or not checks["months>=6"]:
        status, next_action = "INSUFFICIENT_OBSERVATIONS", "EXTEND_BACKTEST_SAMPLE"
    elif not (checks["wfo"] and checks["oos"] and checks["robustness"]):
        status, next_action = "READY_FOR_VALIDATION", "RUN_WFO_OOS_ROBUSTNESS"
    else:
        status, next_action = "VALIDATED_EVIDENCE", "COMPARE_CANDIDATES"
    return {
        "contract": "sbt-evidence-evaluation-v1",
        "evidence_class": "BACKTEST",
        "status": status,
        "checks": checks,
        "metrics": metrics,
        "validation": validation,
        "next_action": next_action,
        "promotion_allowed": False,
        "trading_activation_allowed": False,
        "objective": "maximum_monthly_net_profit",
        "authority": "MT4 controls DEMO/REAL; evaluation cannot change mode, risk, or execution.",
    }


_INTRADAY_STRATEGIES = {
    "ORB": {"strategy_id": "SBT-INTRADAY-ORB-001", "label": "Opening Range Breakout"},
    "TREND_PULLBACK": {"strategy_id": "SBT-INTRADAY-TREND-PULLBACK-001", "label": "EMA ADX Trend Pullback"},
    "MEAN_REVERSION": {"strategy_id": "SBT-INTRADAY-MEAN-REVERSION-001", "label": "Bollinger RSI Mean Reversion"},
    "ENSEMBLE": {"strategy_id": "SBT-INTRADAY-ENSEMBLE-001", "label": "Regime Ensemble"},
}
_INTRADAY_TIMEFRAMES = ("M15", "M30", "H1")


def _intraday_family(strategy: Any) -> str | None:
    s = str(strategy or "").upper()
    if "ENSEMBLE" in s:
        return "ENSEMBLE"
    if "MEAN_REVERSION" in s or "MEAN-REVERSION" in s or "MEAN REVERSION" in s:
        return "MEAN_REVERSION"
    if "TREND_PULLBACK" in s or "TREND-PULLBACK" in s or "TREND PULLBACK" in s:
        return "TREND_PULLBACK"
    if "ORB" in s or "OPENING RANGE" in s:
        return "ORB"
    return None


def _intraday_candidates() -> list[dict[str, Any]]:
    """Normalize persisted MT4 evidence into the four Intraday Lab families."""
    candidates = []
    for row in _persistent_backtests():
        bot = row.get("bot") or {}
        family = _intraday_family(
            bot.get("strategy") or row.get("strategy_id") or row.get("strategy")
        )
        tf = str(row.get("timeframe") or bot.get("timeframe") or "").upper()
        if family not in _INTRADAY_STRATEGIES or tf not in _INTRADAY_TIMEFRAMES:
            continue

        metrics = _flatten(row)
        if metrics["monthly_net_return"] is None and metrics["expected_return"] is None:
            continue

        meta = _INTRADAY_STRATEGIES[family]
        candidates.append({
            "strategy_id": meta["strategy_id"],
            "strategy": family,
            "label": meta["label"],
            "symbol": row.get("symbol") or "EURUSD",
            "timeframe": tf,
            "version": bot.get("version") or row.get("version"),
            "metrics": metrics,
            "score": score_priority({k: v for k, v in metrics.items() if v is not None}),
            "validation": row.get("validation") or {},
            "costs": row.get("costs") or {},
            "source": row.get("source") or "MT4_STRATEGY_TESTER",
            "timestamp": row.get("timestamp"),
        })
    return candidates


def _intraday_gate(candidate: dict[str, Any]) -> dict[str, Any]:
    m = candidate["metrics"]
    v = candidate.get("validation") or {}
    trades_ok = isinstance(m.get("trades"), (int, float)) and m["trades"] >= 30
    months_ok = isinstance(m.get("months"), (int, float)) and m["months"] >= 6
    wfo_ok = bool(v.get("wfo")) or m.get("oos_quality") is not None
    oos_ok = bool(v.get("oos")) or m.get("oos_quality") is not None
    robust_ok = bool(v.get("robustness")) or m.get("robustness") is not None
    return {
        "trades>=30": trades_ok,
        "months>=6": months_ok,
        "wfo": wfo_ok,
        "oos": oos_ok,
        "robustness": robust_ok,
        "eligible": trades_ok and months_ok and wfo_ok and oos_ok and robust_ok,
    }


@router.get("/intraday-compare")
def intraday_compare(symbol: str = "EURUSD"):
    """Compare ORB, trend pullback, mean reversion and ensemble automatically.

    The endpoint only ranks persisted MT4 evidence. It does not invent missing
    metrics, start MT4, place orders, change risk, or switch DEMO/REAL.
    """
    symbol = symbol.upper()
    candidates = [
        x for x in _intraday_candidates()
        if str(x.get("symbol") or "").upper() == symbol
    ]

    grouped = {}
    for family, meta in _INTRADAY_STRATEGIES.items():
        for tf in _INTRADAY_TIMEFRAMES:
            matches = [
                x for x in candidates
                if x["strategy"] == family and x["timeframe"] == tf
            ]
            best = max(matches, key=lambda x: x["score"]) if matches else None
            grouped[f"{family}:{tf}"] = {
                "strategy_id": meta["strategy_id"],
                "strategy": family,
                "label": meta["label"],
                "symbol": symbol,
                "timeframe": tf,
                "status": "EVIDENCE_AVAILABLE" if best else "UNTESTED",
                "best_candidate": best,
                "gate": _intraday_gate(best) if best else {
                    "eligible": False,
                    "reason": "No persisted MT4 evidence yet."
                },
                "evidence_count": len(matches),
            }

    eligible = [
        x for x in grouped.values()
        if x["best_candidate"] is not None and x["gate"]["eligible"]
    ]
    eligible.sort(
        key=lambda x: x["best_candidate"]["score"],
        reverse=True,
    )

    family_best = {}
    for family, meta in _INTRADAY_STRATEGIES.items():
        family_rows = [
            x for x in eligible
            if x["strategy"] == family
        ]
        family_best[family] = max(
            family_rows,
            key=lambda x: x["best_candidate"]["score"]
        ) if family_rows else None

    return {
        "contract": "sbt-intraday-comparator-v1",
        "objective": "maximize_monthly_profit_subject_to_risk_and_robustness",
        "symbol": symbol,
        "strategies": list(_INTRADAY_STRATEGIES.keys()),
        "timeframes": list(_INTRADAY_TIMEFRAMES),
        "total_combinations": 12,
        "evidence_combinations": sum(
            1 for x in grouped.values() if x["status"] == "EVIDENCE_AVAILABLE"
        ),
        "eligible_combinations": len(eligible),
        "winner": eligible[0] if eligible else None,
        "best_by_strategy": family_best,
        "matrix": list(grouped.values()),
        "next_action": (
            "VALIDATE_WINNER_WITH_WFO_OOS_ROBUSTNESS"
            if eligible else
            "RUN_MT4_BACKTESTS_FOR_UNTESTED_OR_UNVALIDATED_COMBINATIONS"
        ),
        "automatic_execution": False,
        "authority": "MT4 controls DEMO/REAL; Evolution Engine only compares research evidence.",
    }


@router.get("/intraday-best")
def intraday_best(symbol: str = "EURUSD"):
    result = intraday_compare(symbol=symbol)
    return {
        "contract": "sbt-intraday-best-v1",
        "symbol": result["symbol"],
        "winner": result["winner"],
        "status": "VALIDATED_CANDIDATE" if result["winner"] else "INSUFFICIENT_EVIDENCE",
        "automatic_execution": False,
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
        "next_action": "RUN_RESEARCH_PRIORITY_MATRIX" if not research_matrix()["winner"] else "VALIDATE_TOP_TURTLE_WITH_WFO_OOS_ROBUSTNESS",
        "email_ready":True,
        "email_recipient":"raylerr481@gmail.com",
        "note":"Este informe no envía correo todavía; requiere un conector de email autorizado."
    }
