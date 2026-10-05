# Bitey SBT — Strategy and Bot Evolution Plan

## Purpose

Define the permanent decision policy for selecting, improving and validating
trading strategies and bots.

Bitey IA is expected to observe, analyze, decide, propose and, when a validated
allowlisted change path exists, apply improvements. Bitey SBT is the
deterministic research, validation, risk-control and audit layer.

The primary objective is:

**maximize net profit per month, subject to strict risk, cost and robustness constraints.**

Monthly profit is the optimization target. Risk controls are hard constraints,
not a reason to abandon the monthly-profit objective. The system should search
for the highest monthly result that remains statistically credible and robust.

The +10% monthly reference is a validation target/benchmark, never a promise
or a required monthly outcome.

## Strategy selection

Candidate strategies and timeframes are evidence-driven. No timeframe is
declared superior before comparable evidence exists.

Candidate timeframes:

- M5
- M15
- M30
- H1
- H4
- D1

The system should compare strategy + symbol + timeframe combinations using the
same assumptions for spread, commission, slippage and sample periods.

## Monthly-profit optimization

Bitey should optimize the expected **net monthly return** first. It should
compare strategies, symbols and timeframes specifically for their monthly
profit potential, while rejecting candidates that achieve it through
unacceptable drawdown, excessive risk, unrealistic costs or overfitting.

The system should report best month, median month, mean month, probability of
a positive month, probability of reaching +5% and +10%, worst month and
maximum drawdown.

## Ranking priorities

Bitey should prefer candidates that combine:

1. positive expected return;
2. lower maximum drawdown;
3. positive expectancy;
4. higher profit factor;
5. higher probability of positive months;
6. lower probability/severity of negative months;
7. stronger walk-forward and out-of-sample behavior;
8. robustness across parameters and regimes;
9. lower cost drag;
10. lower sensitivity to small parameter changes.

Maximum monthly profit is the primary objective, but it is constrained by
the safety gates. A +20% historical month does not justify a strategy if the
result depends on excessive drawdown or overfitting.

## Required validation pipeline

Every candidate follows:

**Strategy → Bot → Backtest → Realistic Costs → WFO → OOS → Robustness →
Demo/Shadow → Risk Gate → Monitor → Report → Re-evaluate**

No unvalidated strategy is eligible for production application.

## Risk rules

Bitey/SBT must never:

- increase risk to recover losses;
- increase lot size as a recovery mechanism;
- disable or weaken stops;
- increase the permitted maximum drawdown;
- bypass Risk Gate;
- silently change broker/account;
- automatically switch DEMO/PAPER/REAL;
- apply an unvalidated production change.

The trader's MT4 account connection is the authority for environment state.
Bitey can detect and report REAL, but it does not switch into REAL.

## Preventive behavior

When evidence indicates deterioration, Bitey may investigate protective
actions such as:

- tightening entry filters;
- reducing new-entry frequency;
- reducing position size;
- blocking new entries;
- pausing new entries;
- preserving existing protective stops.

Any application must pass the change gate and produce an audit record.

## Evolution model

Each bot must have versioned evolution records:

- bot identifier;
- strategy identifier;
- symbol;
- timeframe;
- previous version;
- new version;
- parameter changes;
- reason for change;
- market/regime context;
- backtest evidence;
- WFO evidence;
- OOS evidence;
- robustness evidence;
- drawdown;
- expectancy;
- profit factor;
- monthly performance statistics;
- DEMO/shadow result;
- application status;
- rollback target;
- current next decision.

## Reporting

After a meaningful evolution decision or applied change, Bitey should create
an evolution report containing the complete evidence chain and deliver it to
the configured user email.

Default report recipient:

**raylerr481@gmail.com**

Suggested subject:

**Bitey IA — Informe de evolución | {bot} | {old_version} → {new_version} | {environment}**

Reports must clearly distinguish:

- historical evidence;
- simulated evidence;
- DEMO/shadow evidence;
- REAL monitoring evidence.

A report must never present a target, forecast or backtest as a guaranteed
profit.

## Implementation roadmap

### Phase 1 — Research intelligence
- Strategy Library
- evidence-driven timeframe selection
- regime analysis
- generic strategy backtesting
- realistic cost model

### Phase 2 — Validation intelligence
- WFO
- OOS
- robustness
- performance comparator
- monthly probability engine using closed-trade data where available

### Phase 3 — Evolution engine
- version registry
- hypothesis/decision ledger
- change proposals
- Bot Change Gate
- Guardian integration
- rollback records

### Phase 4 — Controlled application
- authenticated MT4 command protocol
- command expiry/idempotency
- acknowledgement and result telemetry
- DEMO application first
- REAL protective allowlist only
- never change account environment

### Phase 5 — Reporting and learning
- evolution reports
- email delivery
- report history
- automatic re-evaluation
- next-best experiment selection

## Definition of success

The system is successful when it can repeatedly demonstrate that a bot change
was:

**needed → hypothesized → tested → validated → risk-checked → applied through
a controlled path → observed → measured → reported**

rather than merely claiming that a backtest looked profitable.
