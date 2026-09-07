from __future__ import annotations
from app.bot_builder.backtest import run_spec_backtest
from app.bot_builder.spec import BotSpecification
from app.services.virtual_validation import run_virtual_validation


def stress_test(spec: BotSpecification, prices: list[float]) -> dict:
    scenarios = [prices, prices[:: -1], [p * 1.01 for p in prices], [p * 0.99 for p in prices]]
    results = []
    for scenario in scenarios:
        try:
            result = run_spec_backtest(spec, scenario)
            results.append({"status":"completed","final_equity":result.get("final_equity"),"trades":result.get("trades")})
        except ValueError as exc:
            results.append({"status":"rejected","reason":str(exc)})
    return {"contract":"sbt-stress-v1","scenarios":results,"passed":all(r["status"] == "completed" for r in results)}


def virtual_validation(spec: BotSpecification) -> dict:
    result = run_virtual_validation()
    return {"contract":"sbt-bot-validation-v1","bot_contract":spec.contract,"validation":result,"live":False,"real_money":False,"broker_orders":0}
