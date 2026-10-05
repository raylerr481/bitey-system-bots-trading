from __future__ import annotations

from collections import defaultdict
from datetime import datetime, timezone
from statistics import mean, median
from typing import Any

from fastapi import APIRouter

from app.api.mt4 import _latest, _history, _backtests

router = APIRouter(prefix="/api/v1/performance", tags=["performance"])


def _number(value: Any) -> float | None:
    try:
        return float(value) if value is not None else None
    except (TypeError, ValueError):
        return None


def _timestamp(row: dict[str, Any]) -> datetime | None:
    raw = row.get("timestamp")
    if not raw:
        return None
    try:
        dt = datetime.fromisoformat(str(raw).replace("Z", "+00:00"))
        return dt.replace(tzinfo=timezone.utc) if dt.tzinfo is None else dt
    except (TypeError, ValueError):
        return None


def _selected(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    if not rows:
        return []
    latest = rows[-1]
    bot = latest.get("bot") or {}
    key = (
        bot.get("magic"),
        bot.get("name") or latest.get("source"),
        latest.get("symbol"),
        latest.get("timeframe"),
    )
    selected = []
    for row in rows:
        rb = row.get("bot") or {}
        rkey = (
            rb.get("magic"),
            rb.get("name") or row.get("source"),
            row.get("symbol"),
            row.get("timeframe"),
        )
        if rkey == key:
            selected.append(row)
    return selected


def _equity(row: dict[str, Any]) -> float | None:
    account = row.get("account") or {}
    return _number(account.get("equity", account.get("balance")))


def _initial_capital(rows: list[dict[str, Any]]) -> float | None:
    for row in rows:
        account = row.get("account") or {}
        value = _number(account.get("initial_balance", account.get("initial_capital")))
        if value is not None and value > 0:
            return value
    for row in rows:
        value = _number((row.get("account") or {}).get("balance"))
        if value is not None and value > 0:
            return value
    return None


def _max_drawdown(equities: list[float]) -> float | None:
    if not equities:
        return None
    peak = equities[0]
    max_dd = 0.0
    for value in equities:
        peak = max(peak, value)
        if peak > 0:
            max_dd = max(max_dd, (peak - value) / peak)
    return max_dd


def _monthly(rows: list[dict[str, Any]], capital: float | None) -> list[dict[str, Any]]:
    points = [(dt, eq) for row in rows if (dt := _timestamp(row)) is not None and (eq := _equity(row)) is not None]
    points.sort(key=lambda x: x[0])
    buckets: dict[str, list[tuple[datetime, float]]] = defaultdict(list)
    for dt, eq in points:
        buckets[dt.strftime("%Y-%m")].append((dt, eq))
    result = []
    previous_end = capital
    for month in sorted(buckets):
        series = buckets[month]
        start = previous_end if previous_end is not None else series[0][1]
        end = series[-1][1]
        ret = (end - start) / start if start and start > 0 else None
        result.append({"month": month, "start_equity": start, "end_equity": end, "return": ret})
        previous_end = end
    return result


def _metric_fallback(rows: list[dict[str, Any]]) -> dict[str, Any]:
    if not rows:
        return {}
    m = rows[-1].get("metrics") or {}
    a = rows[-1].get("account") or {}
    def first(*keys: str):
        for key in keys:
            if key in m:
                return m[key]
            if key in a:
                return a[key]
        return None
    return {
        "trades": first("trades", "total_trades", "trade_count"),
        "wins": first("wins", "winning_trades"),
        "losses": first("losses", "losing_trades"),
        "profit_factor": first("profit_factor", "pf"),
        "expectancy": first("expectancy", "expected_profit"),
        "net_pnl": first("net_pnl", "net_profit", "profit", "pnl"),
        "max_drawdown": first("max_drawdown", "drawdown", "dd_pct"),
    }


@router.get("/selected-bot")
def selected_bot_performance():
    rows = _selected(_history)
    capital = _initial_capital(rows)
    current = _equity(rows[-1]) if rows else None
    monthly = _monthly(rows, capital)
    returns = [m["return"] for m in monthly if m["return"] is not None]
    positive = sum(1 for r in returns if r > 0)
    ge5 = sum(1 for r in returns if r >= 0.05)
    ge10 = sum(1 for r in returns if r >= 0.10)
    negative = sum(1 for r in returns if r < 0)
    fallback = _metric_fallback(rows)

    observed_return = ((current - capital) / capital) if capital and current is not None else None
    drawdown = _max_drawdown([eq for row in rows if (eq := _equity(row)) is not None])
    dd_fallback = _number(fallback.get("max_drawdown"))
    if drawdown is None:
        drawdown = dd_fallback / 100 if dd_fallback is not None and dd_fallback > 1 else dd_fallback

    evidence_count = len(rows)
    monthly_evidence = len(returns)
    sufficient_months = monthly_evidence >= 6
    probability_positive = positive / monthly_evidence if monthly_evidence else None
    probability_ge5 = ge5 / monthly_evidence if monthly_evidence else None
    probability_ge10 = ge10 / monthly_evidence if monthly_evidence else None

    status = "INSUFFICIENT_EVIDENCE"
    if monthly_evidence >= 12:
        status = "ROBUSTER_MONTHLY_EVIDENCE"
    elif monthly_evidence >= 6:
        status = "PRELIMINARY_MONTHLY_EVIDENCE"
    elif evidence_count >= 30:
        status = "TRADE_TELEMETRY_ONLY"

    target_progress = None
    if observed_return is not None:
        target_progress = max(0.0, min(100.0, observed_return / 0.10 * 100.0))

    return {
        "contract": "bitey-sbt-performance-v1",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "bot": (_latest or {}).get("bot") or {"name": (_latest or {}).get("source")},
        "market": {"symbol": (_latest or {}).get("symbol"), "timeframe": (_latest or {}).get("timeframe"), "regime": (_latest or {}).get("regime")},
        "environment": ((_latest or {}).get("account") or {}).get("mode") or (_latest or {}).get("mode") or "UNKNOWN",
        "reference_capital": capital,
        "current_equity": current,
        "net_return": observed_return,
        "target": {"return": 0.10, "amount": capital * 1.10 if capital else None, "progress_pct": target_progress, "guaranteed": False},
        "trade_metrics": {
            "trades": fallback.get("trades"),
            "wins": fallback.get("wins"),
            "losses": fallback.get("losses"),
            "profit_factor": _number(fallback.get("profit_factor")),
            "expectancy": _number(fallback.get("expectancy")),
            "net_pnl": _number(fallback.get("net_pnl")),
        },
        "risk": {"max_drawdown": drawdown},
        "monthly": {
            "months_observed": monthly_evidence,
            "positive_months": positive,
            "negative_months": negative,
            "probability_positive": probability_positive,
            "probability_ge_5pct": probability_ge5,
            "probability_ge_10pct": probability_ge10,
            "mean_return": mean(returns) if returns else None,
            "median_return": median(returns) if returns else None,
            "best_return": max(returns) if returns else None,
            "worst_return": min(returns) if returns else None,
            "series": monthly[-24:],
        },
        "evidence": {
            "snapshots": evidence_count,
            "backtests": len(_backtests),
            "sufficient_for_probability": sufficient_months,
            "status": status,
            "note": "Las probabilidades mensuales solo se calculan cuando existen meses observables; no se rellenan con estimaciones inventadas.",
        },
    }


@router.get("/monthly-probability")
def monthly_probability():
    report = selected_bot_performance()
    monthly = report["monthly"]
    return {
        "contract": "bitey-sbt-monthly-probability-v1",
        "status": report["evidence"]["status"],
        "sufficient_evidence": report["evidence"]["sufficient_for_probability"],
        "months_observed": monthly["months_observed"],
        "probability_positive_month": monthly["probability_positive"],
        "probability_month_ge_5pct": monthly["probability_ge_5pct"],
        "probability_month_ge_10pct": monthly["probability_ge_10pct"],
        "mean_monthly_return": monthly["mean_return"],
        "median_monthly_return": monthly["median_return"],
        "best_month": monthly["best_return"],
        "worst_month": monthly["worst_return"],
        "series": monthly["series"],
    }
