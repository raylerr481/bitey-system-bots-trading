from __future__ import annotations

import random
from app.bot_builder.backtest import run_spec_backtest
from app.strategy_discovery.fitness import fitness, metrics_from_result
from app.strategy_discovery.generator import candidate_id, complexity_of, crossover, generate_population, mutate
from app.strategy_discovery.models import DiscoveryRequest, DiscoveryResult, EvolutionRequest, StrategyCandidate


def _evaluate(specs, prices, fee_pct, seed, min_trades, max_dd, min_pf, generation=0):
    out = []
    for spec in specs:
        try:
            result = run_spec_backtest(spec, prices, fee_pct)
            metrics = metrics_from_result(result, complexity_of(spec))
            fit = fitness(metrics)
            accepted = (
                metrics["closed_trades"] >= min_trades
                and metrics["max_drawdown_pct"] <= max_dd
                and metrics["profit_factor"] >= min_pf
            )
            out.append(StrategyCandidate(
                candidate_id=candidate_id(spec, seed), generation=generation, fitness=fit,
                complexity=metrics["complexity"], status="accepted" if accepted else "filtered",
                metrics=metrics, specification=spec,
            ))
        except (ValueError, TypeError, ZeroDivisionError) as exc:
            out.append(StrategyCandidate(
                candidate_id=candidate_id(spec, seed), generation=generation, fitness=-1_000_000,
                complexity=complexity_of(spec), status="error", metrics={"error": str(exc)}, specification=spec,
            ))
    return out


def discover(request: DiscoveryRequest, prices: list[float]) -> DiscoveryResult:
    if len(prices) < 30:
        raise ValueError("at least 30 prices are required")
    specs = generate_population(request.symbol, request.timeframe, request.candidates, request.seed, request.max_conditions)
    evaluated = _evaluate(specs, prices, request.fee_pct, request.seed, request.min_trades, request.max_drawdown_pct, request.min_profit_factor)
    accepted = [c for c in evaluated if c.status == "accepted"]
    evaluated.sort(key=lambda c: c.fitness, reverse=True)
    return DiscoveryResult(
        seed=request.seed, generated=len(specs), evaluated=len(evaluated), accepted=len(accepted),
        candidates=evaluated[:100], filters={"min_trades":request.min_trades,"max_drawdown_pct":request.max_drawdown_pct,"min_profit_factor":request.min_profit_factor,"fee_pct":request.fee_pct},
    )


def evolve(request: EvolutionRequest, prices: list[float]) -> DiscoveryResult:
    if len(prices) < 60:
        raise ValueError("at least 60 prices are required for evolution")
    rng = random.Random(request.seed)
    population = generate_population(request.symbol, request.timeframe, request.population, request.seed, request.max_conditions)
    all_best = []
    for generation in range(request.generations):
        evaluated = _evaluate(population, prices, request.fee_pct, request.seed + generation, request.min_trades, request.max_drawdown_pct, request.min_profit_factor, generation)
        evaluated.sort(key=lambda c: c.fitness, reverse=True)
        all_best.extend(evaluated[:request.elite])
        elites = [c.specification for c in evaluated[:request.elite]]
        next_population = list(elites)
        while len(next_population) < request.population:
            if len(elites) > 1 and rng.random() < 0.35:
                child = crossover(rng.choice(elites), rng.choice(elites), rng, generation + 1)
            else:
                child = mutate(rng.choice(elites), rng, request.max_conditions, generation + 1)
            next_population.append(child)
        population = next_population
    all_best.sort(key=lambda c: c.fitness, reverse=True)
    accepted = [c for c in all_best if c.status == "accepted"]
    unique = {}
    for c in all_best:
        unique[c.candidate_id] = c
    final = list(unique.values())[:100]
    return DiscoveryResult(
        seed=request.seed, generated=request.population * request.generations, evaluated=len(all_best), accepted=len(accepted),
        candidates=final, filters={"population":request.population,"generations":request.generations,"elite":request.elite,"min_trades":request.min_trades,"max_drawdown_pct":request.max_drawdown_pct,"min_profit_factor":request.min_profit_factor,"fee_pct":request.fee_pct},
    )
