from __future__ import annotations
from .generators import generate_code
from .spec import BotSpecification


def build_bot(spec: BotSpecification) -> dict:
    return {
        "contract": "sbt-bot-v1",
        "specification": spec.model_dump(),
        "language": spec.language,
        "code": generate_code(spec),
        "execution": "research-demo-paper",
        "live": False,
        "real_money": False,
        "broker_orders": 0,
        "next_steps": ["backtest", "stress-test", "risk-gate", "virtual-validation"],
    }
