from __future__ import annotations

from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.engine import build_bot
from app.bot_builder.spec import BotSpecification
from app.bot_builder.validation import stress_test, virtual_validation
from app.risk.engine import RiskEngine


def run_pipeline(spec: BotSpecification, prices: list[float]) -> dict:
    backtest = run_spec_backtest(spec, prices)
    stress = stress_test(spec, prices)

    last_price = float(prices[-1])
    risk_notional = spec.initial_capital * spec.risk.max_position_pct
    risk_engine = RiskEngine(
        max_position_pct=spec.risk.max_position_pct,
        max_daily_loss_pct=spec.risk.risk_pct,
        allowed_symbols={spec.symbol.upper()},
    )
    decision = risk_engine.approve(
        capital=spec.initial_capital,
        notional=risk_notional,
        daily_pnl=0.0,
        symbol=spec.symbol.upper(),
    )
    risk = {
        "contract": "sbt-risk-gate-v1",
        "authoritative": True,
        "approved": decision.allowed,
        "reason": decision.reason,
        "capital": spec.initial_capital,
        "notional": risk_notional,
        "reference_price": last_price,
        "risk_pct": spec.risk.risk_pct,
        "max_position_pct": spec.risk.max_position_pct,
        "live": False,
        "real_money": False,
        "broker_orders": 0,
    }

    virtual = virtual_validation(spec)
    validated = bool(
        stress["passed"]
        and risk["approved"]
        and virtual["live"] is False
        and virtual["real_money"] is False
        and virtual["broker_orders"] == 0
    )
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
