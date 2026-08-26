# Bitey System Bots Trading

**Bitey System Bots Trading** is an independent specialized trading module of **Bitey IA / Supracerebro**.

It is separate from JobIA and Bitey Trainer, with its own trading engine, strategies, risk controls, simulation and execution architecture. Its mobile application is **Bitey SBT App** (`bitey-system-bots-trading-app`).

## Objective

Research, build, test, evaluate and operate algorithmic trading systems with a controlled progression:

**Research → Backtest → Demo → Paper Trading → Micro-capital → Controlled scaling**

No profit is guaranteed or assumed. Real-money operation is disabled until explicit safety and validation gates are satisfied.

## Relationship with Bitey IA

Bitey IA is the general Supracerebro. Trading is a specialized module that can consume authorized Bitey IA services and return authorized results, metrics and knowledge that can enrich the ecosystem. It does not replace or restrict Bitey IA.

```text
BITEY IA / SUPRACEREBRO
          │
          └── Bitey System Bots Trading
                    │
               Bitey SBT App
```

Bitey Trainer/JobIA is a separate module/product and is not a dependency of the trading engine.

## Safety progression

1. Research.
2. Historical backtesting with fees/slippage.
3. Demo with virtual capital.
4. Paper trading with live market data and simulated execution.
5. Micro-capital only after predefined validation gates and explicit activation.
6. Controlled scaling only while objective performance, reliability and risk limits remain valid.

Failure of safety criteria should reduce exposure or return the system to demo/paper mode.

## Architecture

- `core/` — portfolios, positions, orders and trading state.
- `strategies/` — deterministic strategy/signal contracts.
- `risk/` — mandatory pre-trade and portfolio controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters; paper first.
- `api/` — FastAPI service for Bitey IA and Bitey SBT App.
- `tests/` — unit, integration, simulation and safety tests.

AI may assist with research, comparison, experiment design, anomaly detection, analysis and reporting, but cannot bypass hard risk controls.

## Design principles

- Same signal → risk → execution architecture across simulation and future live modes.
- Strategies never send orders directly.
- Risk controls cannot be bypassed by AI or strategies.
- Hard limits are outside the AI decision layer.
- Events and decisions are auditable.
- Live execution is disabled by default.
- Fail closed when required data, credentials, risk state or execution dependencies are unavailable.

## Initial milestone

A safe demo/paper trading engine with authentication, audit trail, monitoring and validated risk controls. No live broker/exchange connection until the required gates pass.

## Disclaimer

Trading financial assets involves risk, including loss of capital. No bot, strategy or AI system guarantees profits. This software is initially for research, simulation and controlled testing.
