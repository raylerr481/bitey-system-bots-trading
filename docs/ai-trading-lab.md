# Bitey AI Trading Lab

Bitey SBT now defines an AI-assisted trading laboratory inspired by the general workflow of multi-source analysis, deterministic indicators, AI review, risk sizing, execution, position management and evidence-based learning.

## Core rule

AI may research, classify, explain and propose. Deterministic SBT controls decide whether a trade or strategy change is permitted.

## Pipeline

```text
Market Data
  -> Universal Market Gateway
  -> Data Engine
  -> Indicator Engine
  -> Market Intelligence
  -> Filter & Control
  -> Bitey AI Analyst
  -> Risk Gate
  -> Execution Engine
  -> Position Manager
  -> Evidence Store
  -> Learning Lab
```

## Modes

- `research`: no execution; generate hypotheses and analysis.
- `simulation`: historical deterministic execution with explicit fees and slippage.
- `demo`: broker/terminal demo execution only.
- `paper`: virtual live execution using live market data.
- `live`: disabled by default and subject to the existing real-money gate.

## AI analyst contract

The analyst receives normalized market facts, indicators, market regime, approved news/event context and current risk state. It returns a structured proposal:

- direction: `LONG`, `SHORT`, or `WAIT`
- confidence: 0-100
- rationale
- proposed entry/stop/target
- proposed risk class
- evidence references

The analyst cannot directly place orders or change risk limits.

## Adaptive aggression

The user-facing aggression level is a policy input, not a direct leverage command. Risk Gate can reduce exposure when drawdown, volatility, liquidity, correlation, spread, execution health or daily loss limits require it.

Suggested baseline profiles:

| Level | Target risk/trade | Maximum leverage |
|---|---:|---:|
| 1 | 0.10% | 1x |
| 3 | 0.25% | 1x |
| 5 | 0.50% | 2x |
| 7 | 0.75% | 2x |
| 10 | 1.00% | 3x |

These are policy defaults for simulation/research and are not authorization for live trading.

## Learning loop

SBT must never promote an AI observation directly into production behavior.

```text
Observation
  -> Hypothesis
  -> Backtest
  -> Walk-forward test
  -> Paper/demo evidence
  -> Statistical validation
  -> Risk review
  -> ACCEPT or REJECT
  -> Versioned Strategy Registry entry
```

Accepted hypotheses become a new strategy version with provenance. Rejected hypotheses remain recorded so the system does not repeatedly rediscover failed ideas.

## Benchmark discipline

Every experiment should compare the strategy against an appropriate benchmark, including buy-and-hold where meaningful, while reporting:

- total and annualized return
- maximum drawdown
- Sharpe and Sortino where statistically meaningful
- profit factor
- expectancy and R-multiple distribution
- win/loss rate
- trade count
- exposure
- fees and estimated slippage
- out-of-sample performance
- parameter sensitivity
- regime stability

Seven-day or low-trade results must be labelled insufficient evidence.

## Asset universe

The system may evaluate a configurable set of instruments rather than assuming a fixed number. Eligibility is determined by liquidity, spread, volatility, market-data quality and correlation/exposure constraints.

## Safety boundary

No live order is enabled by this laboratory feature. Existing SBT Risk Gate, explicit permissions, audit trail and emergency-stop requirements remain authoritative.
