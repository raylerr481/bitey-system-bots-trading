# Bitey System Bots Trading

**Bitey System Bots Trading** is an independent specialized trading module of **Bitey IA / Supracerebro**. Its mobile application is **Bitey SBT App** (`bitey-system-bots-trading-app`).

## Product objective

Research, test and operate algorithmic trading systems through a controlled progression:

**Research → Backtest → Demo → Paper Trading → Micro-capital → Controlled scaling**

The product is designed for both beginners and advanced users. A beginner sees a plain-language explanation such as: **“If you assign $10, this profile is configured to risk about $0.20 per trade.”** The professional view exposes market, strategy, position and risk parameters. These are estimates/configured controls, not profit guarantees or guaranteed maximum losses under every market condition.

## Bot groups

The backend now exposes `/api/v1/bot-profiles` with initial profiles:

- **Conservador EUR/USD** — low exposure, intended for learning and validation.
- **Equilibrado EUR/USD** — intermediate exposure after demo/paper validation.
- **Agresivo EUR/USD** — high exposure and variability; for advanced users only.

Each profile contains:

- Simple beginner explanation.
- Professional/technical explanation.
- Markets and strategies.
- Risk level.
- Maximum position percentage.
- Configured loss per trade.
- Configured daily loss.
- Illustrative favorable/neutral/unfavorable scenarios.
- Risk preview for a selected capital amount.

## Real-money transition

The application is being prepared with an **“Activar dinero real”** control, but real execution remains disabled in this milestone. The backend exposes a safety-preparation status and requires, before future activation:

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

The system must fail closed when a required safety dependency is unavailable. Broker credentials must never be stored in the mobile application.

## MetaTrader 5

MT5 is currently integrated as a **read-only market-data/demo bridge**. The bridge can provide account information, quotes and candles while the trading engine uses virtual execution. A future real connector must be isolated behind the same risk and audit gates; the current milestone does not send real broker orders.

## Architecture

- `core/` — portfolios, positions, orders and trading state.
- `strategies/` — deterministic strategy/signal contracts.
- `risk/` — mandatory pre-trade and portfolio controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters; paper first.
- `api/` — FastAPI API for Bitey IA and Bitey SBT App.
- `tests/` — unit, integration, simulation and safety tests.

AI may assist with research, comparison, experiment design, anomaly detection, analysis and reporting, but cannot bypass hard risk controls.

## Mobile app UX

Bitey SBT App provides:

- Bot-group selection.
- Beginner/professional explanation toggle.
- Capital/risk preview.
- Demo/paper monitoring.
- Prepared real-money activation flow, currently disabled.

## Safety

No bot, strategy or AI system guarantees profits. A configured loss limit is a risk-control target, not a promise: market gaps, slippage, liquidity and execution conditions can produce larger losses. Real-money trading remains disabled until the full safety architecture is validated.
