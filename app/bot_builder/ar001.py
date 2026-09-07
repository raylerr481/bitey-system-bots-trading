from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class AR001Spec:
    hypothesis_id: str = "AR-001"
    source: str = "Alex Ruiz"
    video_id: str = "QY7Kchg9nEU"
    risk_pct: float = 0.01
    allocation: tuple[float, float, float] = (0.25, 0.40, 0.35)
    atr_period: int = 14
    atr_multipliers: tuple[float, float, float] = (0.0, 2.0, 3.0)
    stop_type: str = "common_stop"
    live: bool = False
    real_money: bool = False
    broker_orders: int = 0


def ar001_spec() -> dict:
    s = AR001Spec()
    return {
        "hypothesis_id": s.hypothesis_id,
        "source": s.source,
        "video_id": s.video_id,
        "claim": "A staged 25/40/35 entry in a predefined zone, spaced with ATR, can improve the average entry without exceeding a fixed aggregate stop risk.",
        "status": "UNTESTED",
        "parameters": {
            "risk_pct": s.risk_pct,
            "allocation": list(s.allocation),
            "atr_period": s.atr_period,
            "atr_multipliers": list(s.atr_multipliers),
            "stop_type": s.stop_type,
        },
        "falsification": [
            "Reject if aggregate stop loss exceeds the configured risk budget.",
            "Reject if out-of-sample expectancy is not positive after fees and slippage.",
            "Reject if stress/walk-forward performance is unstable beyond configured tolerance.",
        ],
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def size_staged_entries(capital: float, risk_pct: float, entries: list[float], stop: float, weights: list[float] | None = None, point_value: float = 1.0) -> dict:
    if capital <= 0 or risk_pct <= 0 or risk_pct > 0.05:
        raise ValueError("capital/risk_pct outside allowed range")
    if len(entries) != 3:
        raise ValueError("AR-001 requires exactly three staged entries")
    if stop <= 0 or point_value <= 0:
        raise ValueError("stop and point_value must be positive")
    weights = weights or [0.25, 0.40, 0.35]
    if len(weights) != 3 or abs(sum(weights) - 1.0) > 1e-9 or any(w <= 0 for w in weights):
        raise ValueError("weights must be positive and sum to 1")
    budget = capital * risk_pct
    rows = []
    for entry, weight in zip(entries, weights):
        distance = abs(entry - stop)
        if distance == 0:
            raise ValueError("entry cannot equal stop")
        risk_budget = budget * weight
        quantity = risk_budget / (distance * point_value)
        rows.append({"entry": entry, "weight": weight, "risk_budget": risk_budget, "distance_to_stop": distance, "quantity": quantity, "stop_loss": quantity * distance * point_value})
    total_risk = sum(r["stop_loss"] for r in rows)
    weighted_average = sum(r["entry"] * r["quantity"] for r in rows) / sum(r["quantity"] for r in rows)
    return {"contract": "sbt-ar001-sizing-v1", "hypothesis_id": "AR-001", "risk_budget": budget, "entries": rows, "total_stop_risk": total_risk, "risk_within_budget": total_risk <= budget * (1 + 1e-9), "weighted_average_entry": weighted_average, "safety": {"live": False, "real_money": False, "broker_orders": 0}}
