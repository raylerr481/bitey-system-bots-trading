from __future__ import annotations

from typing import Any

from fastapi import APIRouter, Query

from app.api import mt4
from app.storage import live_trades

router = APIRouter(prefix="/api/v1", tags=["adaptive-cycle"])


def _finite(value: Any) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number


def _parameter_candidates() -> list[dict[str, Any]]:
    candidates = []
    for sl_atr in (1.20, 1.30, 1.50, 1.80):
        for tp_r in (1.50, 2.00, 2.50):
            rr = tp_r
            candidates.append({
                "sl_atr": sl_atr,
                "tp_r": tp_r,
                "rr": rr,
                "status": "PROPOSAL_ONLY",
                "promotion": "REQUIRES_BACKTEST_WFO_OOS_ROBUSTNESS",
            })
    return candidates


def build_cycle(symbol: str, limit: int) -> dict[str, Any]:
    trades = live_trades.list_recent(limit)
    scoped = [t for t in trades if str(t.get("symbol") or "").upper() == symbol.upper()]

    r_values = [_finite(t.get("r_multiple")) for t in scoped]
    r_values = [v for v in r_values if v is not None]
    wins = sum(1 for t in scoped if _finite(t.get("pnl")) is not None and float(t.get("pnl")) > 0)
    losses = sum(1 for t in scoped if _finite(t.get("pnl")) is not None and float(t.get("pnl")) < 0)
    ev_r = sum(r_values) / len(r_values) if r_values else None
    positive = ev_r is not None and ev_r > 0 and len(r_values) >= 2

    latest = mt4._latest or {}
    current = {
        "symbol": symbol,
        "timeframe": latest.get("timeframe") or (scoped[0].get("timeframe") if scoped else "UNKNOWN"),
        "strategy": latest.get("strategy") or latest.get("best_strategy") or "TURTLE_CLASSIC",
        "regime": latest.get("regime") or "UNKNOWN",
        "mode": latest.get("mode") or "UNKNOWN",
        "operational_capital_usd": 500.0,
        "execution_authority": "MT4",
        "q_learning": "ADVISORY_ONLY",
        "risk_gate": "AUTHORITATIVE",
    }

    if not scoped:
        process = [
            "WAITING_FOR_MT4_CLOSE",
            "RECORD_OUTCOME",
            "UPDATE_Q_LEARNING",
            "MARKET_STUDY",
            "BOUNDED_PARAMETER_STUDY",
            "EXPECTED_VALUE_CHECK",
            "RISK_GATE",
            "RENEW_BOT_CYCLE",
        ]
        next_state = "WAITING_FOR_MT4_CLOSE"
    else:
        process = [
            "TRADE_CLOSED",
            "OUTCOME_RECORDED",
            "Q_LEARNING_UPDATED_OR_RETRY",
            "MARKET_STUDY",
            "PARAMETER_STUDY",
            "EXPECTED_VALUE_CHECK",
            "RISK_GATE",
            "BOT_CYCLE_RENEWED",
        ]
        next_state = "BOUNDED_PARAMETER_STUDY" if positive else "COLLECT_MORE_CLOSED_TRADE_EVIDENCE"

    return {
        "ok": True,
        "symbol": symbol,
        "current_state": current,
        "evidence": {
            "closed_trades": len(scoped),
            "wins": wins,
            "losses": losses,
            "r_multiple_observations": len(r_values),
            "r_multiples": r_values[-50:],
            "expected_value_r": ev_r,
            "positive_observed_ev": positive,
            "latest_close": scoped[0] if scoped else None,
        },
        "parameter_study": {
            "status": "STUDY" if positive else "COLLECT",
            "candidates": _parameter_candidates() if positive else [],
            "promotion_rule": "PROPOSAL_ONLY; requires independent evidence before EA change",
        },
        "process": process,
        "next_research_state": next_state,
        "safety": {
            "mt4_execution_authority": True,
            "q_learning_execution": False,
            "risk_gate_bypass": False,
            "auto_demo_real_switch": False,
            "sbt_operational_capital_usd": 500.0,
            "risk_escalation_to_recover_losses": False,
        },
    }


@router.get("/adaptive-cycle")
def adaptive_cycle(
    symbol: str = Query(default="EURUSD", min_length=1, max_length=32),
    limit: int = Query(default=200, ge=1, le=5000),
):
    return build_cycle(symbol.upper(), limit)
