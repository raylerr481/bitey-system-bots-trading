# Bitey System Bots Trading (Bitey SBT)

**Bitey SBT** is the specialized trading intelligence, research and execution-control platform of the **Bitey IA ecosystem**.

It is being developed as an **original Bitey product**, with an independent web platform and mobile channel. The product may learn from proven market patterns and publicly observable product capabilities in AI-assisted trading, but it must not reproduce another company's code, copywriting, branding, artwork, proprietary workflows or distinctive interface.

## Product principle: original Bitey, proven dynamics

Bitey SBT can implement broad, non-exclusive trading-product dynamics such as:

- strategy creation;
- historical simulation/backtesting;
- robustness and out-of-sample validation;
- comparison of strategies or AI-generated proposals;
- simulated/demo and paper trading;
- bot publishing and discovery;
- monitoring and performance measurement.

These are **market-level concepts**, not a blueprint for copying any particular competitor.

Bitey SBT must create its own:

- information architecture;
- navigation and page hierarchy;
- terminology;
- visual identity;
- UI components and layouts;
- copywriting;
- prompts and orchestration;
- scoring methodology;
- data contracts;
- backend architecture;
- bot lifecycle implementation;
- safety model.

No competitor code, assets, screenshots, text or proprietary implementation may be incorporated into this repository.

## Product vision

Bitey SBT is an independent **AI Trading Laboratory** where a trader can move from an idea to evidence before exposing capital to a strategy.

The core lifecycle is:

**Research → Design → Simulate → Stress-test → Validate → Demo → Paper → Publish/Deploy → Monitor → Re-evaluate**

The platform is designed around evidence, reproducibility and risk control rather than promises of profit.

## Bitey SBT architecture

```text
                         BITEY IA
                    GENERAL INTELLIGENCE
                            │
                  authorized API contracts
                            │
                            ▼
                 ┌─────────────────────┐
                 │      BITEY SBT      │
                 │ specialized trading │
                 │     intelligence     │
                 └──────────┬──────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
   Research Core       Bot Laboratory       Risk Engine
        │                   │                   │
        └───────────────────┼───────────────────┘
                            ▼
                 Simulation / Validation
                            │
                 ┌──────────┴──────────┐
                 ▼                     ▼
               Demo                  Paper
                 │                     │
                 └──────────┬──────────┘
                            ▼
                    Registry / Deploy
                            │
                            ▼
                       Monitoring
```

The future web platform is independent from `bitey-web`. The mobile app is independent in presentation but consumes the same controlled SBT APIs. Bitey SBT is not BiteFixes and must not share private enterprise trading data with BiteFixes.

## Original product areas

### 1. Bitey Research Lab

A research workspace for market questions, hypotheses, news/event context, technical context and experiment design.

### 2. Bitey Bot Lab

A strategy workspace where a trader can define or modify a deterministic trading system.

A bot can specify:

- market/instrument;
- timeframe;
- entry and exit conditions;
- indicators;
- regime filters;
- stop loss / take profit rules;
- position sizing;
- capital allocation;
- maximum exposure;
- execution mode;
- hard risk limits.

Bitey IA can help translate natural language into a structured strategy specification, explain decisions and propose experiments. The executable strategy and Risk Engine remain deterministic and authoritative.

### 3. Bitey Model Workshop

Users may select supported AI providers/models, including Bitey Trading Intelligence and external models such as ChatGPT or Claude when the required integration is available.

The models are **advisors/proposers**, not execution authorities.

The same hypothesis can be submitted to multiple models under controlled conditions:

```text
Same hypothesis
      │
 ┌────┼─────┐
 ▼    ▼     ▼
Bitey Model A Model B
 │      │      │
 └──────┼──────┘
        ▼
 Same data + costs + period
        ▼
 Same simulation engine
        ▼
 Same risk rules
        ▼
 Comparable evidence
```

Provider-specific credentials remain server-side. No model is allowed to bypass the SBT risk and validation contracts.

### 4. SBT Evaluation

Bitey SBT should not declare a strategy superior because it has the largest historical return.

The platform will build its own **SBT Evaluation Score** from transparent components where statistically meaningful, including:

- net return;
- maximum drawdown;
- profit factor;
- risk-adjusted return;
- win rate;
- trade count;
- exposure;
- volatility;
- consecutive losses;
- out-of-sample performance;
- parameter sensitivity;
- stability across periods/regimes;
- demo/paper consistency;
- execution quality;
- validation freshness.

The exact weighting must be versioned and documented. A score is an evaluation aid, not a prediction of future profit.

### 5. SBT Strategy Registry

Instead of copying another platform's marketplace implementation, Bitey SBT uses an original **Strategy Registry** concept.

Each published strategy has an identity and version history:

```text
Strategy ID
 ├── owner / author
 ├── version
 ├── AI/model provenance
 ├── market + timeframe
 ├── strategy specification
 ├── backtest evidence
 ├── robustness evidence
 ├── demo/paper evidence
 ├── risk classification
 ├── SBT Evaluation Score
 ├── validation timestamp
 └── publication status
```

Backtest, demo, paper and live evidence must always be clearly separated.

## Bot lifecycle

```text
DRAFT
  ↓
SIMULATED
  ↓
ROBUSTNESS CHECK
  ↓
VALIDATED
  ↓
DEMO
  ↓
PAPER
  ↓
PUBLISHED
  ↓
DEPLOYED
  ↓
MONITORED
  ↓
REVALIDATED / SUSPENDED
```

A strategy can move backwards in the lifecycle when evidence becomes stale, behavior changes or a safety condition is triggered.

## Initial bot groups

The existing `/api/v1/bot-profiles` profiles remain the seed for the product:

- **Conservador EUR/USD**
- **Equilibrado EUR/USD**
- **Agresivo EUR/USD**

They expose beginner and professional explanations, markets/strategies, risk level, position limits, configured loss limits and risk previews. They should be upgraded into versioned SBT strategies rather than discarded.

## Intelligence model

Bitey Trading Intelligence can assist with:

- market research;
- news and event analysis;
- affected-asset analysis;
- domino/event-chain analysis;
- time-horizon analysis;
- technical context;
- strategy hypothesis generation;
- experiment design;
- backtest interpretation;
- anomaly detection;
- strategy comparison;
- risk explanations;
- performance reports.

Example:

```text
Event / News
    ↓
Affected assets
    ↓
Possible domino effects
    ↓
Time horizon
    ↓
Technical confirmation
    ↓
Hypothesis
    ↓
Simulation
    ↓
Robustness
    ↓
Risk validation
    ↓
Demo / Paper
```

This is research intelligence, not a guarantee or automatic trading instruction.

## Risk and execution boundary

The fundamental rule is:

> **AI can propose. The deterministic SBT engine and Risk Engine decide whether an action is technically and financially permitted.**

Real-money execution remains gated by:

1. authenticated user;
2. explicit real-account selection;
3. broker/exchange connection;
4. maximum capital allocation;
5. per-trade loss limit;
6. daily loss limit;
7. pre-trade validation;
8. audit trail;
9. emergency stop;
10. explicit final confirmation;
11. strategy validation status;
12. execution and broker health checks.

The system must fail closed when a mandatory safety dependency is unavailable.

## Current MT5 boundary

MetaTrader 5 is currently a **read-only market-data/demo bridge**. The present milestone does not send real broker orders.

Future live connectors must remain behind the same strategy, validation, Risk Engine, audit and emergency-stop gates.

## Participation model for Bitey-branded strategies

The commercial concept remains a possible **0.1% participation on verified realized net profit** when another trader uses an eligible Bitey-branded strategy.

The intended calculation is based on realized results attributable to the strategy after explicitly defined costs and adjustments. It does not apply to backtest returns or unrealized gains.

Before any real-money implementation, the commercial definition, accounting treatment, taxation, jurisdictional requirements, broker rules and applicable financial regulations must be reviewed and versioned. This mechanism is not a profit guarantee.

## Independent web product

The future Cloudflare web application is a separate frontend/product from `bitey-web`.

It will have its own:

- domain/subdomain;
- frontend codebase;
- navigation;
- visual identity;
- authentication UX;
- SBT dashboards;
- bot laboratory;
- registry;
- research tools;
- trading views.

It connects to this backend through explicit versioned APIs. It must never become a copy of another platform's frontend.

## Mobile app

`bitey-system-bots-trading-app` is the mobile channel for Bitey SBT. It must consume the same SBT contracts and never duplicate the trading engine.

## Repository architecture

- `core/` — trading state and domain primitives.
- `strategies/` — deterministic strategy contracts.
- `risk/` — mandatory risk controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters.
- `api/` — SBT API contracts.
- `tests/` — unit, integration, simulation and safety tests.
- `docs/` — product and architecture specifications.

## Intellectual-property guardrail

Every future feature must pass this design test:

**What problem are we solving?**
→ implement the general capability if useful.

**Are we copying a particular expression of that capability?**
→ redesign it from first principles for Bitey.

Never import competitor code, assets, text, logos, screenshots or proprietary implementation details.

The objective is to build a product that can stand on its own as **Bitey SBT**, not as a clone.

## Disclaimer

Trading financial assets involves substantial risk, including loss of capital. Backtests, simulations, demo results and paper results do not guarantee future performance. Slippage, gaps, liquidity, execution failures and market-regime changes can materially alter results.

Real-money trading remains disabled until the required technical, operational, legal and regulatory controls are validated.
