from __future__ import annotations

from dataclasses import dataclass
import math
import random
import statistics


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
            "Reject if the confidence interval for expectancy remains at or below zero.",
            "Reject if stress/walk-forward performance is unstable beyond configured tolerance.",
        ],
        "evidence_protocol": {
            "minimum_trades": 100,
            "minimum_oos_trades": 30,
            "minimum_bootstrap_samples": 2000,
            "approval_rule": "OOS expectancy > 0, profit factor > 1, bootstrap 95% lower bound > 0, and positive stress scenarios.",
            "note": "Thresholds are a conservative default research protocol, not a guarantee of profitability.",
        },
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


def _profit_factor(rs: list[float]) -> float:
    gains = sum(x for x in rs if x > 0)
    losses = -sum(x for x in rs if x < 0)
    return math.inf if losses == 0 and gains > 0 else (gains / losses if losses else 0.0)


def _max_drawdown(rs: list[float]) -> float:
    equity = peak = 1.0
    max_dd = 0.0
    for r in rs:
        equity *= max(0.000001, 1.0 + r)
        peak = max(peak, equity)
        max_dd = max(max_dd, (peak - equity) / peak)
    return max_dd


def _bootstrap_lower_bound(rs: list[float], samples: int = 2000, seed: int = 1001) -> float:
    if not rs:
        return 0.0
    rng = random.Random(seed)
    means = []
    n = len(rs)
    for _ in range(samples):
        means.append(sum(rs[rng.randrange(n)] for _ in range(n)) / n)
    means.sort()
    return means[max(0, int(0.025 * len(means)) - 1)]


def evaluate_ar001_evidence(
    r_multiples: list[float],
    oos_start: int | None = None,
    stress_results: list[float] | None = None,
    risk_sizing_ok: bool = True,
    bootstrap_samples: int = 2000,
) -> dict:
    """Classify AR-001 from supplied, already-computed trade outcomes.

    The function deliberately does not fabricate market data. `r_multiples` must
    represent realized trade results after fees/slippage in units of initial
    trade risk (R). If data are missing or the sample is too small, the result is
    EVIDENCE_INSUFFICIENT rather than a positive claim.
    """
    if not r_multiples:
        return _evidence_result("EVIDENCE_INSUFFICIENT", ["No trade outcomes supplied."], {})
    if any(not math.isfinite(x) for x in r_multiples):
        raise ValueError("r_multiples must contain finite numbers")

    n = len(r_multiples)
    split = oos_start if oos_start is not None else max(1, n // 2)
    if split <= 0 or split >= n:
        raise ValueError("oos_start must leave both in-sample and out-of-sample observations")
    oos = r_multiples[split:]
    expectancy = statistics.fmean(oos)
    pf = _profit_factor(oos)
    lower = _bootstrap_lower_bound(oos, samples=max(2000, bootstrap_samples), seed=1001)
    dd = _max_drawdown(oos)
    stress = stress_results or []
    positive_stress = bool(stress) and all(x > 0 for x in stress)

    failures: list[str] = []
    if not risk_sizing_ok:
        failures.append("Aggregate stop risk exceeds the configured risk budget.")
    if n < 100:
        failures.append("Minimum sample of 100 trades not reached.")
    if len(oos) < 30:
        failures.append("Minimum out-of-sample sample of 30 trades not reached.")
    if expectancy <= 0:
        failures.append("Out-of-sample expectancy is not positive.")
    if pf <= 1.0:
        failures.append("Out-of-sample profit factor is not above 1.")
    if lower <= 0:
        failures.append("Bootstrap 95% lower bound of expectancy is not above zero.")
    if not positive_stress:
        failures.append("Stress evidence is missing or not positive in every supplied scenario.")

    if failures:
        status = "REJECTED" if n >= 100 and len(oos) >= 30 and (expectancy <= 0 or pf <= 1.0 or lower <= 0 or not risk_sizing_ok) else "EVIDENCE_INSUFFICIENT"
    else:
        status = "APPROVED"

    return _evidence_result(status, failures, {
        "sample_size": n,
        "oos_sample_size": len(oos),
        "oos_expectancy_R": expectancy,
        "oos_profit_factor": pf,
        "oos_max_drawdown_pct": dd * 100.0,
        "bootstrap_95_lower_bound_R": lower,
        "stress_scenarios": len(stress),
        "positive_stress": positive_stress,
        "oos_start": split,
    })


def _evidence_result(status: str, reasons: list[str], metrics: dict) -> dict:
    return {
        "contract": "sbt-ar001-evidence-v1",
        "hypothesis_id": "AR-001",
        "status": status,
        "reasons": reasons,
        "metrics": metrics,
        "interpretation": "APPROVED means the supplied dataset passed the default evidence protocol; it does not prove future profitability.",
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
