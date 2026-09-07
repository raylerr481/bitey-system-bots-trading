from __future__ import annotations
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.validation import stress_test, virtual_validation


def run_pipeline(spec: BotSpecification, prices: list[float]) -> dict:
    backtest = run_spec_backtest(spec, prices)
    stress = stress_test(spec, prices)
    risk = {
        "authoritative": True,
        "approved": spec.risk.risk_pct <= 0.05 and spec.risk.max_position_pct <= 1.0,
        "risk_pct": spec.risk.risk_pct,
        "max_position_pct": spec.risk.max_position_pct,
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }
    virtual = virtual_validation(spec)
    validated = bool(stress["passed"] and risk["approved"] and virtual["live"] is False)
    generated = build_bot(spec) if validated else None
    return {
        "contract": "sbt-bot-pipeline-v1",
        "status": "validated" if validated else "rejected",
        "backtest": backtest,
        "stress_test": stress,
        "risk_gate": risk,
        "virtual_validation": virtual,
        "generated": generated,
        "safety": {"live": False, "real_money": False, "broker_orders": 0},
    }
