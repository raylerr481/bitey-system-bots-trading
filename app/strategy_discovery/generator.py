from __future__ import annotations

import random
import uuid
from app.bot_builder.spec import BotSpecification, IndicatorSpec, RuleSpec, RiskSpec
from app.strategy_discovery.blocks import INDICATORS, OPERATORS, complexity


def _indicator_key(name: str, period: int) -> str:
    return f"{name}_{period}"


def _reference_value(rng: random.Random, indicator_name: str, period: int, refs: list[str]) -> float | str:
    key = _indicator_key(indicator_name, period)
    if indicator_name == "rsi":
        return rng.choice((30.0, 40.0, 50.0, 60.0, 70.0))
    if indicator_name == "rci":
        return rng.choice((-70.0, -50.0, 0.0, 50.0, 70.0))
    if indicator_name == "macd":
        return 0.0
    if indicator_name in {"rolling_high", "rolling_low"}:
        return "close"
    if rng.random() < 0.55:
        return rng.choice(refs) if refs else "close"
    return "close"


def generate_candidate(symbol: str, timeframe: str, rng: random.Random, max_conditions: int, index: int, generation: int = 0) -> BotSpecification:
    selected = rng.sample(INDICATORS, k=rng.randint(1, min(4, len(INDICATORS))))
    indicators = [IndicatorSpec(name=name, period=rng.choice(periods)) for name, periods in selected]
    refs = [_indicator_key(i.name, i.period) for i in indicators]
    refs += ["close"]
    rule_count = rng.randint(1, max_conditions)
    entry: list[RuleSpec] = []
    exit_rules: list[RuleSpec] = []
    for n in range(rule_count):
        ind = rng.choice(indicators)
        key = _indicator_key(ind.name, ind.period)
        op = rng.choice(OPERATORS)
        value = _reference_value(rng, ind.name, ind.period, refs)
        rule = RuleSpec(indicator=key, operator=op, value=value)
        (entry if n < max(1, rule_count - 1) else exit_rules).append(rule)
    if not exit_rules:
        exit_rules.append(RuleSpec(indicator="close", operator="cross_below", value=refs[0]))
    return BotSpecification(
        name=f"SBT-DISC-{generation:02d}-{index:04d}",
        symbol=symbol.upper(), timeframe=timeframe.upper(), language="python",
        indicators=indicators, entry_rules=entry, exit_rules=exit_rules,
        risk=RiskSpec(risk_pct=0.01, stop_type="atr", stop_value=2.0, max_position_pct=0.02),
        initial_capital=10000,
    )


def generate_population(symbol: str, timeframe: str, count: int, seed: int, max_conditions: int, generation: int = 0) -> list[BotSpecification]:
    rng = random.Random(seed)
    return [generate_candidate(symbol, timeframe, rng, max_conditions, i, generation) for i in range(count)]


def candidate_id(spec: BotSpecification, seed: int) -> str:
    return uuid.uuid5(uuid.NAMESPACE_URL, f"sbt:{seed}:{spec.model_dump_json()}").hex[:16]


def mutate(spec: BotSpecification, rng: random.Random, max_conditions: int, generation: int) -> BotSpecification:
    data = spec.model_dump()
    if data["indicators"] and rng.random() < 0.7:
        idx = rng.randrange(len(data["indicators"]))
        name = data["indicators"][idx]["name"]
        choices = dict(INDICATORS)[name]
        data["indicators"][idx]["period"] = rng.choice(choices)
    if data["entry_rules"] and rng.random() < 0.7:
        idx = rng.randrange(len(data["entry_rules"]))
        data["entry_rules"][idx]["operator"] = rng.choice(OPERATORS)
    if data["exit_rules"] and rng.random() < 0.7:
        idx = rng.randrange(len(data["exit_rules"]))
        data["exit_rules"][idx]["operator"] = rng.choice(OPERATORS)
    if rng.random() < 0.25 and len(data["entry_rules"]) < max_conditions:
        ind = rng.choice(data["indicators"])
        data["entry_rules"].append({"indicator": _indicator_key(ind["name"], ind["period"]), "operator": rng.choice(OPERATORS), "value": "close"})
    data["name"] = f"SBT-EVO-{generation:02d}-{rng.randrange(100000):05d}"
    return BotSpecification.model_validate(data)


def crossover(a: BotSpecification, b: BotSpecification, rng: random.Random, generation: int) -> BotSpecification:
    indicators = a.indicators[: max(1, len(a.indicators) // 2)] + b.indicators[max(0, len(b.indicators) // 2):]
    entry = a.entry_rules[:1] + b.entry_rules[:1]
    exit_rules = a.exit_rules[:1] + b.exit_rules[:1]
    return BotSpecification(
        name=f"SBT-CROSS-{generation:02d}-{rng.randrange(100000):05d}", symbol=a.symbol,
        timeframe=a.timeframe, language="python", indicators=indicators[:6],
        entry_rules=entry[:4], exit_rules=exit_rules[:4], risk=a.risk,
        initial_capital=a.initial_capital,
    )


def complexity_of(spec: BotSpecification) -> int:
    return complexity(len(spec.indicators), len(spec.entry_rules) + len(spec.exit_rules))
