# Bitey System Bots Trading

**Bitey System Bots Trading (SBT)** is an independent specialized trading module of **Bitey IA / Supracerebro**. Its mobile application is **Bitey SBT App** (`bitey-system-bots-trading-app`).

## Objective

Research, build, test, evaluate and operate algorithmic trading systems with a controlled progression:

**Research → Backtest → Demo → Paper Trading → Micro-capital → Controlled scaling**

No profit is guaranteed or assumed. Real-money operation is disabled until explicit safety and validation gates are satisfied.

## Market Intelligence Engine

SBT includes a deterministic, explainable foundation for **market intelligence**. The engine is designed to turn a market event or news item into a structured chain:

**News → Event → Primary asset → Domino effects → Correlations → Market regime → Opportunity → Strategy confirmation → Risk**

The analysis considers:

- affected markets and assets;
- bullish, bearish or conflicting directional bias;
- source quality and event importance;
- immediate, short-term, intraday, swing and macro horizons;
- secondary and tertiary effects across correlated assets;
- confirmation versus contradiction between news and price behavior;
- opportunity scoring and explicit `watch` / `wait` states;
- explainable thesis and risk context.

The current implementation is an analysis foundation, not a news-feed provider. External news ingestion, live correlation data, event calendars and richer market-regime models can be added without allowing intelligence to bypass risk controls.

### Effect-domino time model

SBT evaluates the likely persistence of an event across several horizons:

| Horizon | Purpose |
|---|---|
| `0-5m` | Initial market shock and spread/volatility reaction |
| `5-30m` | Confirmation or immediate reversal |
| `30m-4h` | Intraday propagation across related assets |
| `1-3d` | Repositioning and swing effects |
| `1-4w` | Persistent macro consequences when the thesis remains valid |

These are analysis horizons, not guarantees that an event will affect the market for a fixed duration.

### Opportunity principle

An identified opportunity is **not an automatic trade**. SBT must distinguish between:

- a directional hypothesis;
- a confirmed opportunity;
- a conflicting signal that requires waiting;
- an event that is already priced in;
- an opportunity whose risk is too high.

The Market Intelligence Engine does not place orders and currently returns `execution_allowed: false`. Strategy confirmation and the SBT Risk Engine remain mandatory before any execution path.

## Relationship with Bitey IA

Bitey IA is the general Supracerebro. Trading is a specialized module that can consume authorized Bitey IA services and return authorized results, metrics and knowledge that can enrich the ecosystem. It does not replace or restrict Bitey IA.

```text
BITEY IA / SUPRACEREBRO
          │
          └── Bitey System Bots Trading
                    │
          ┌─────────┼──────────┐
          │         │          │
       Market    Strategy    Risk
    Intelligence   Engine    Engine
          │         │          │
          └─────────┼──────────┘
                    │
             Demo / Paper
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
- `intelligence/` — news/event impact, domino analysis and opportunity scoring foundation.
- `strategies/` — deterministic strategy/signal contracts.
- `risk/` — mandatory pre-trade and portfolio controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters; paper first.
- `api/` — FastAPI service for Bitey IA and Bitey SBT App.
- `tests/` — unit, integration, simulation and safety tests.

AI may assist with research, comparison, experiment design, anomaly detection, analysis and reporting, but cannot bypass hard risk controls.

## Market intelligence API

`POST /api/v1/intelligence/news/analyze` accepts a headline, event importance, source quality, tags and optional market confirmation. It returns affected assets, directional bias, horizons, opportunity hypotheses and the mandatory next risk/strategy gate.

`GET /api/v1/intelligence/health` reports that the intelligence component is available in analysis-only mode.

## Design principles

- Same signal → risk → execution architecture across simulation and future live modes.
- Strategies never send orders directly.
- Market intelligence never sends orders directly.
- Risk controls cannot be bypassed by AI, intelligence or strategies.
- Hard limits are outside the AI decision layer.
- Events and decisions are auditable.
- Live execution is disabled by default.
- Fail closed when required data, credentials, risk state or execution dependencies are unavailable.
- A news signal can be wrong, delayed, already priced in or contradicted by market data; the system must be able to wait.

## Initial milestone

A safe demo/paper trading engine with authentication, audit trail, monitoring, validated risk controls and market-intelligence analysis. No live broker/exchange connection until the required gates pass.

## Disclaimer

Trading financial assets involves risk, including loss of capital. No bot, strategy or AI system guarantees profits. This software is initially for research, simulation and controlled testing.
