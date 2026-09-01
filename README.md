# Bitey System Bots Trading

**Bitey System Bots Trading (Bitey SBT)** is the specialized algorithmic-trading intelligence and trading-platform backend of the **Bitey IA ecosystem**.

It is designed to become the engine behind an independent web platform, hosted separately from the general Bitey IA Web, where traders can **create, test, compare, validate, publish, discover and operate trading bots**.

The platform uses the intelligence of Bitey IA for trading research and analysis, while keeping the trading engine, execution controls, risk system, bot lifecycle and trading data isolated inside this specialized product.

> **Important:** the platform is original to Bitey IA. It may use familiar market-product dynamics such as strategy creation, backtesting, comparison, deployment and community discovery, but it does **not** copy TradingKit or any other product's code, branding, interface, text, proprietary implementation or visual identity.

## Product vision

Bitey SBT is intended to evolve into an independent **Bitey trading laboratory and bot ecosystem**.

A trader should be able to move through a controlled lifecycle:

**Idea → Build → Backtest → Compare → Validate → Demo → Paper → Publish/Deploy → Monitor → Scale carefully**

The objective is not to promise profits. The objective is to provide transparent infrastructure for discovering whether a trading system has evidence of an edge before exposing capital to it.

## Independent web platform

A future Bitey SBT web platform will be hosted independently in the owner's Cloudflare environment and will have its own product identity, frontend, API, authentication, trading data and deployment lifecycle.

Conceptually:

```text
BITEY IA / SUPRACEREBRO
        │
        │ authorized trading intelligence
        ▼
┌──────────────────────────────────────────┐
│ BITEY SYSTEM BOTS TRADING                │
│                                          │
│  Bitey Trading Intelligence              │
│  Bot Builder                             │
│  Strategy Lab                            │
│  Backtesting                             │
│  Optimization / Comparison               │
│  Demo & Paper Trading                    │
│  Risk Engine                             │
│  Bot Registry / Marketplace              │
│  Performance & Monitoring                │
│  Broker / Exchange Connectors             │
└──────────────────────┬───────────────────┘
                       │
                       ▼
              Independent Web Platform
                   on Cloudflare
```

The trading platform must **not depend on `bitey-web` as its frontend** and must not become part of BiteFixes. It can consume authorized Bitey IA intelligence through explicit APIs/contracts.

## Bitey Bot Lab

The central creation experience will be the **Bitey Bot Lab**: a workspace where a trader can create or modify a bot without starting from an empty project.

A bot can define:

- Market/instrument.
- Timeframes.
- Entry conditions.
- Exit conditions.
- Stop loss and take profit logic.
- Position sizing.
- Technical indicators.
- Market regime filters.
- News/event filters where supported.
- Maximum concurrent positions.
- Per-trade and daily risk limits.
- Capital allocation.
- Execution mode.

Bitey IA can help translate a trader's idea into a deterministic strategy specification, explain the logic, identify contradictions, suggest experiments and analyze results. The final executable strategy remains subject to the deterministic strategy and risk contracts.

## Strategy validation

Every bot intended for publication or deployment should pass progressively stronger validation.

### 1. Backtest

Run the strategy against historical data with explicit assumptions for fees, spread and slippage where data permits.

### 2. Robustness testing

Evaluate the strategy across different periods, market conditions, parameters and instruments where appropriate. Detect overfitting, look-ahead bias and unstable parameter regions.

### 3. Comparison

Compare multiple versions of a strategy using the same historical conditions and rank them by transparent metrics rather than by a single headline return.

### 4. Demo

Run the bot against a simulated account and observe its actual signal lifecycle.

### 5. Paper trading

Use live market data without placing real-money orders. The code path should remain as close as practical to the future execution path.

### 6. Controlled real deployment

Real trading remains gated by authentication, broker/account connection, capital limits, risk controls, auditability and an emergency stop.

## Bot Registry and Bitey Marketplace

The future platform will include a public/private **Bitey Bot Registry** where validated bots can be discovered.

Bots may have two principal origins:

### Bitey-built bots

Bots created and maintained under the Bitey brand. These can become official platform strategies when they meet the required validation criteria.

### Trader-created bots

Authorized traders can create, test and publish their own bots. Publication should require transparent metadata, validation results, risk information and clear ownership/attribution.

A published bot should expose evidence such as:

- Strategy description.
- Market and timeframe.
- Backtest period.
- Number of trades.
- Return metrics.
- Drawdown.
- Win rate.
- Profit factor where meaningful.
- Sharpe/Sortino where appropriate.
- Fees/slippage assumptions.
- Demo/paper history when available.
- Validation status.
- Risk classification.
- Bot version.
- Last validation date.

Historical performance is evidence about the past, not a guarantee of future performance.

## Bitey bot earnings / creator participation

Bitey SBT is designed around a transparent participation model for bots carrying the Bitey ecosystem's brand and made available to other traders.

When a **Bitey-branded bot is actually used by another trader and produces verified realized net profit**, the platform may allocate **0.1% of the applicable realized net profit to the platform/brand owner**, subject to the final commercial, accounting and legal model implemented by the service.

The intended principle is:

```text
Trader uses validated Bitey bot
          ↓
Bot operates on trader's own account
          ↓
Performance is recorded
          ↓
Realized result is calculated
          ↓
Eligible net profit is verified
          ↓
0.1% participation is calculated
```

The platform must never represent this mechanism as a promise of profit. It is a **usage/performance participation model**, not a guarantee, and its final implementation must account for fees, refunds/adjustments, losses, chargebacks, taxation, jurisdiction and applicable financial regulations.

The exact commercial definition of **eligible net profit** must be versioned before real-money operation. A sensible initial definition is based on realized P&L attributable to the bot after explicitly defined trading costs, rather than unrealized gains.

## Trader control

The trader remains the owner/controller of the connected trading account and capital.

The platform should not take custody of customer funds merely to operate a bot. Broker/exchange credentials must be protected and should be stored only in an appropriate server-side secret mechanism or delegated connection system; they must never be embedded in the mobile application or browser frontend.

The trader chooses:

- Which bot to use.
- Which account to connect.
- Capital allocation.
- Risk envelope.
- Demo/paper/live mode when available.
- Whether to stop or disconnect the bot.

## Bitey Trading Intelligence

Bitey IA becomes a specialized intelligence layer for trading.

It can assist with:

- Market research.
- News and event analysis.
- Asset-impact analysis.
- Event-chain/domino analysis.
- Technical-context analysis.
- Strategy hypothesis generation.
- Experiment design.
- Backtest interpretation.
- Anomaly detection.
- Strategy comparison.
- Risk explanations.
- Performance reports.
- Natural-language explanations for beginners and professionals.

Example intelligence flow:

```text
News / Market Event
        ↓
Affected Asset
        ↓
Possible Domino Effects
        ↓
Time Horizon
        ↓
Technical Confirmation
        ↓
Strategy Hypothesis
        ↓
Backtest
        ↓
Robustness / Comparison
        ↓
Risk Validation
        ↓
Demo / Paper
        ↓
Possible Deployment
```

Bitey IA can propose and explain. **The deterministic trading engine and Risk Engine control execution.** AI must never bypass hard risk controls.

## Initial bot groups

The backend currently exposes `/api/v1/bot-profiles` with initial profiles:

- **Conservador EUR/USD** — low exposure, intended for learning and validation.
- **Equilibrado EUR/USD** — intermediate exposure after demo/paper validation.
- **Agresivo EUR/USD** — high exposure and variability; advanced users only.

Each profile contains:

- Beginner explanation.
- Professional/technical explanation.
- Markets and strategies.
- Risk level.
- Maximum position percentage.
- Configured loss per trade.
- Configured daily loss.
- Illustrative favorable/neutral/unfavorable scenarios.
- Risk preview for a selected capital amount.

These existing profiles are the seed of the future Bitey Bot Registry and should be reused and upgraded rather than discarded.

## Bot lifecycle

```text
DRAFT
  ↓
BACKTESTED
  ↓
ROBUSTNESS_CHECKED
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
```

A bot can be returned to testing or suspended when its validation status becomes stale, its behavior changes, or a safety condition is triggered.

## Performance is more than profit

The platform should not rank bots only by ROI.

Ranking and validation should consider, as applicable:

- Net return.
- Maximum drawdown.
- Risk-adjusted return.
- Win rate.
- Profit factor.
- Trade count.
- Exposure.
- Volatility.
- Consecutive losses.
- Stability across periods.
- Out-of-sample behavior.
- Paper/demo consistency.
- Execution quality.
- Strategy age and validation freshness.

A bot with lower return and substantially lower drawdown may be more suitable than a high-return/high-risk bot.

## Real-money transition

The application is being prepared with an **“Activar dinero real”** control, but real execution remains disabled until the complete safety architecture is validated.

Before future activation, the system requires at minimum:

1. Authenticated user.
2. Broker/account connection.
3. Explicit selection of a real account.
4. Maximum capital allocation.
5. Per-trade loss limit.
6. Daily loss limit.
7. Pre-trade risk validation.
8. Audit trail.
9. Emergency stop.
10. Explicit final confirmation.
11. Strategy validation status.
12. Execution health checks.
13. Broker/exchange health checks.
14. Ability to suspend the bot immediately.

The system must fail closed when a required safety dependency is unavailable.

## MetaTrader 5

MT5 is currently integrated as a **read-only market-data/demo bridge**. The bridge can provide account information, quotes and candles while the trading engine uses virtual execution.

A future real connector must remain behind the same strategy, risk, audit and emergency-stop gates. The current milestone does not send real broker orders.

## Architecture

- `core/` — portfolios, positions, orders and trading state.
- `strategies/` — deterministic strategy/signal contracts.
- `risk/` — mandatory pre-trade and portfolio controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters; paper first.
- `api/` — FastAPI API for the trading platform, Bitey IA and Bitey SBT App.
- `tests/` — unit, integration, simulation and safety tests.

Future platform services should be designed as explicit contracts so the independent web product can evolve without coupling itself to the general Bitey IA Web frontend.

## Independent product identity

The future site should feel like **Bitey IA's own trading product**, not a clone of another trading platform.

Design principles:

- Original Bitey visual language.
- Clear distinction between beginner and professional views.
- Data-first dashboards.
- Explainable bot logic.
- Transparent validation.
- Risk visible before profit.
- Strong bot identity/versioning.
- No black-box claims.
- No copied layouts, copywriting, logos or proprietary workflows.

The product can learn from the broad dynamics of successful trading platforms — build, test, compare, discover, deploy and monitor — while creating its own information architecture, UX, terminology and brand expression.

## Mobile app

**Bitey SBT App** (`bitey-system-bots-trading-app`) is the mobile channel for the specialized trading product.

The future independent web platform and mobile application should consume the same controlled SBT APIs and contracts rather than duplicating the trading engine.

## Safety and financial disclaimer

No bot, strategy or AI system guarantees profits. Historical backtests and paper/demo results do not guarantee future performance. Market gaps, slippage, liquidity, execution failures and regime changes can produce losses larger than configured estimates.

Real-money trading must remain disabled until the complete technical, operational, legal and regulatory requirements for the target jurisdictions and brokers have been validated.
