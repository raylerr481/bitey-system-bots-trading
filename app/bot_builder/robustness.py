"""Deterministic robustness research for Bitey SBT.

This module stress-tests a strategy without placing orders or fabricating market
information. It reuses the canonical SBT backtest engine and reports research
statistics, not profitability guarantees.
"""

from __future__ import annotations

import random
from dataclasses import asdict
from statistics import mean, pstdev

from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.spec import BotSpecification


def _metrics(result: dict) -> dict:
    return {
        "return_pct": float(result.get("total_return_pct", 0.0)),
        "drawdown_pct": float(result.get("max_drawdown_pct", 0.0)),
        "trades": int(result.get("trades", 0)),
        "wins": int(result.get("wins", 0)),
        "losses": int(result.get("losses", 0)),
    }


def _score(metrics: list[dict]) -> float:
    if not metrics:
        return 0.0
    positive = sum(1 for m in metrics if m["return_pct"] > 0) / len(metrics)
    returns = [m["return_pct"] for m in metrics]
    dispersion = pstdev(returns) if len(returns) > 1 else 0.0
    avg_dd = mean(m["drawdown_pct"] for m in metrics)
    # Bounded research score: consistency matters more than one exceptional run.
    return max(0.0, min(100.0, positive * 60.0 + max(0.0, 25.0 - dispersion) + max(0.0, 15.0 - avg_dd * 0.25)))


def oos_test(spec: BotSpecification, prices: list[float], train_pct: float = 70.0, fee_pct: float = 0.001) -> dict:
    if len(prices) < 60:
        raise ValueError("at least 60 prices are required for OOS testing")
    if not 50 <= train_pct < 90:
        raise ValueError("train_pct must be between 50 and 90")
    split = max(30, min(len(prices) - 30, int(len(prices) * train_pct / 100)))
    train = _metrics(run_spec_backtest(spec, prices[:split], fee_pct))
    test = _metrics(run_spec_backtest(spec, prices[split:], fee_pct))
    return {
        "contract": "sbt-oos-v1",
        "train": {"start": 0, "end": split, **train},
        "out_of_sample": {"start": split, "end": len(prices), **test},
        "survives": test["return_pct"] > 0 and test["trades"] > 0,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def parameter_sensitivity(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001) -> dict:
    variants: list[dict] = []
    for delta in (-2, -1, 0, 1, 2):
        indicators = []
        valid = True
        for item in spec.indicators:
            period = item.period + delta
            if period < 2 or period > 200:
                valid = False
                break
            indicators.append(item.model_copy(update={"period": period}))
        if not valid:
            continue
        variant = spec.model_copy(update={"indicators": indicators})
        metrics = _metrics(run_spec_backtest(variant, prices, fee_pct))
        variants.append({"delta_period": delta, **metrics})
    returns = [v["return_pct"] for v in variants]
    return {
        "contract": "sbt-parameter-sensitivity-v1",
        "variants": variants,
        "stable_return_range_pct": round((max(returns) - min(returns)) if returns else 0.0, 6),
        "score": round(_score(variants), 4),
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def cost_stress(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001) -> dict:
    variants = []
    for multiplier in (0.5, 1.0, 1.5, 2.0, 3.0):
        metrics = _metrics(run_spec_backtest(spec, prices, fee_pct * multiplier))
        variants.append({"fee_multiplier": multiplier, **metrics})
    return {
        "contract": "sbt-cost-stress-v1",
        "variants": variants,
        "survives_3x_cost": variants[-1]["return_pct"] > 0 and variants[-1]["trades"] > 0,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def monte_carlo_paths(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001, samples: int = 200, seed: int = 42) -> dict:
    if len(prices) < 60:
        raise ValueError("at least 60 prices are required for Monte Carlo")
    if not 200 <= samples <= 2000:
        raise ValueError("samples must be between 200 and 2000")
    rng = random.Random(seed)
    base = [float(p) for p in prices]
    returns = [(base[i] / base[i - 1]) - 1.0 for i in range(1, len(base))]
    outcomes = []
    for _ in range(samples):
        path = [base[0]]
        for _ in returns:
            r = rng.choice(returns)
            path.append(path[-1] * (1.0 + r))
        outcomes.append(_metrics(run_spec_backtest(spec, path, fee_pct)))
    sorted_returns = sorted(o["return_pct"] for o in outcomes)
    q05 = sorted_returns[max(0, int(samples * 0.05) - 1)]
    return {
        "contract": "sbt-monte-carlo-v1",
        "samples": samples,
        "seed": seed,
        "return_mean_pct": round(mean(sorted_returns), 6),
        "return_p05_pct": round(q05, 6),
        "positive_rate_pct": round(sum(r > 0 for r in sorted_returns) / samples * 100, 4),
        "drawdown_mean_pct": round(mean(o["drawdown_pct"] for o in outcomes), 6),
        "survives_p05": q05 > 0,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def walk_forward(spec: BotSpecification, prices: list[float], train_size: int = 120, test_size: int = 60, step: int = 60, fee_pct: float = 0.001) -> dict:
    if train_size < 30 or test_size < 20 or step < 1:
        raise ValueError("invalid walk-forward window")
    if len(prices) < train_size + test_size:
        raise ValueError("insufficient prices for walk-forward")
    windows = []
    start = 0
    while start + train_size + test_size <= len(prices) and len(windows) < 50:
        train_result = _metrics(run_spec_backtest(spec, prices[start:start + train_size], fee_pct))
        test_start = start + train_size
        test_result = _metrics(run_spec_backtest(spec, prices[test_start:test_start + test_size], fee_pct))
        windows.append({"train_start": start, "train_end": test_start, "test_start": test_start, "test_end": test_start + test_size, "train": train_result, "out_of_sample": test_result})
        start += step
    oos = [w["out_of_sample"] for w in windows]
    return {
        "contract": "sbt-walk-forward-v1",
        "windows": windows,
        "oos_positive_windows_pct": round(sum(x["return_pct"] > 0 for x in oos) / len(oos) * 100, 4) if oos else 0.0,
        "oos_mean_return_pct": round(mean(x["return_pct"] for x in oos), 6) if oos else 0.0,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }


def robustness_report(spec: BotSpecification, prices: list[float], fee_pct: float = 0.001, monte_carlo_samples: int = 200) -> dict:
    sensitivity = parameter_sensitivity(spec, prices, fee_pct)
    costs = cost_stress(spec, prices, fee_pct)
    oos = oos_test(spec, prices, 70.0, fee_pct)
    mc = monte_carlo_paths(spec, prices, fee_pct, monte_carlo_samples)
    wf = walk_forward(spec, prices, fee_pct=fee_pct)
    checks = {
        "oos": bool(oos["survives"]),
        "parameter_sensitivity": sensitivity["score"] >= 60,
        "cost_stress": bool(costs["survives_3x_cost"]),
        "monte_carlo": bool(mc["survives_p05"]),
        "walk_forward": wf["oos_positive_windows_pct"] >= 50,
    }
    passed = sum(checks.values())
    return {
        "contract": "sbt-robustness-v1",
        "strategy": spec.model_dump(),
        "checks": checks,
        "passed_checks": passed,
        "total_checks": len(checks),
        "robustness_score": round(passed / len(checks) * 100, 2),
        "parameter_sensitivity": sensitivity,
        "cost_stress": costs,
        "oos": oos,
        "monte_carlo": mc,
        "walk_forward": wf,
        "decision": "research-pass" if passed >= 4 else "research-review",
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
        "note": "Robustness is evidence quality, not a guarantee of future profitability.",
    }
