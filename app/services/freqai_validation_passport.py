"""Validation Passport for FreqAI research evidence.

This layer never authorizes real-money trading. It converts FreqAI/backtest
evidence into a reproducible validation record and applies deterministic
research gates before SBT can progress to demo/paper.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class PassportThresholds:
    min_trades: int = 30
    max_drawdown_pct: float = 20.0
    min_prediction_coverage_pct: float = 70.0
    max_lookahead_bias_count: int = 0
    min_test_samples: int = 100
    require_dry_run: bool = True


def build_freqai_validation_passport(
    evidence: dict[str, Any],
    thresholds: PassportThresholds | None = None,
) -> dict[str, Any]:
    """Build a validation passport from externally produced FreqAI evidence.

    The evidence is descriptive input; no profitability claim is inferred.
    Real-money execution is always denied at this boundary.
    """
    t = thresholds or PassportThresholds()

    trades = int(evidence.get("closed_trades", evidence.get("trade_count", 0)) or 0)
    drawdown = float(evidence.get("max_drawdown_pct", 100.0) or 100.0)
    coverage = float(evidence.get("prediction_coverage_pct", 0.0) or 0.0)
    lookahead = int(evidence.get("lookahead_bias_count", 0) or 0)
    test_samples = int(evidence.get("test_samples", 0) or 0)
    dry_run = bool(evidence.get("dry_run", False))
    backtest_present = bool(evidence.get("backtest_present", False))
    metrics_present = bool(evidence.get("metrics_present", False))

    checks = {
        "data_present": bool(evidence.get("data_present", False)),
        "backtest_present": backtest_present,
        "metrics_present": metrics_present,
        "minimum_test_samples": test_samples >= t.min_test_samples,
        "minimum_trade_count": trades >= t.min_trades,
        "prediction_coverage": coverage >= t.min_prediction_coverage_pct,
        "drawdown_limit": drawdown <= t.max_drawdown_pct,
        "lookahead_clean": lookahead <= t.max_lookahead_bias_count,
        "dry_run": dry_run if t.require_dry_run else True,
    }

    research_valid = all(checks.values())
    next_stage = "demo" if research_valid else "research-rework"

    return {
        "passport_version": "1.0",
        "source": "freqtrade-freqai",
        "pipeline": [
            "data",
            "backtest",
            "freqai_predictions",
            "metrics",
            "validation",
            "risk_gate",
        ],
        "evidence": {
            "data_present": checks["data_present"],
            "backtest_present": backtest_present,
            "metrics_present": metrics_present,
            "trade_count": trades,
            "test_samples": test_samples,
            "prediction_coverage_pct": coverage,
            "max_drawdown_pct": drawdown,
            "lookahead_bias_count": lookahead,
            "dry_run": dry_run,
            "identifier": evidence.get("identifier"),
            "strategy": evidence.get("strategy"),
            "model": evidence.get("model"),
            "timerange": evidence.get("timerange"),
        },
        "checks": checks,
        "validation": {
            "research_valid": research_valid,
            "next_stage": next_stage,
        },
        "risk_gate": {
            "real_money": False,
            "live_trading_enabled": False,
            "broker_orders": 0,
            "demo_allowed": research_valid,
            "paper_allowed": research_valid,
            "live_allowed": False,
            "reason": "FreqAI evidence can advance research/demo validation only; real-money execution remains disabled.",
        },
    }
