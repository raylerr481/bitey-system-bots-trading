# Bitey System Bots Trading (Bitey SBT)

**Bitey SBT** is the specialized trading intelligence, research, automation and execution-control platform of the **Bitey IA ecosystem**.

It is an original Bitey product with an independent web platform and mobile channel. It may implement broad market capabilities found in AI-assisted trading products, but must not copy another company's code, branding, artwork, text, screenshots, proprietary workflows or distinctive implementation.

## Product vision

Bitey SBT is an **AI Trading Laboratory and guided trading workspace** where the user chooses how they want to work, connects their own AI and trading platform when desired, and can progress from an idea to evidence before exposing capital.

The core lifecycle is:

**Research → Design → Simulate → Stress-test → Validate → Demo → Paper → Publish/Deploy → Monitor → Re-evaluate**

The platform is evidence-driven and risk-controlled. It does not promise profits.

## User chooses the AI and trading platform

Bitey SBT is **model-agnostic and platform-agnostic**. The user is not required to use Bitey Trading Intelligence.

The web application must let the user independently choose:

### AI

- Bitey Trading Intelligence
- ChatGPT/OpenAI, when an approved integration is available
- Claude/Anthropic, when an approved integration is available
- Codex or another supported MCP-compatible client, where supported
- DeepSeek or another supported provider/client
- another compatible AI/MCP client

The user can select one provider exclusively. If the user chooses **"only this AI"**, SBT must not silently call another AI as a fallback.

### Trading platform / broker / tool

Examples include:

- MetaTrader 5
- TradingView
- Alpaca
- other supported broker, exchange or trading-tool connectors

The selected AI and selected trading platform are independent choices. A user may therefore choose combinations such as:

```text
ChatGPT + MetaTrader 5
Claude + TradingView
Codex + TradingView
DeepSeek + Alpaca
Bitey IA + MetaTrader 5
```

New combinations should be enabled through versioned connector contracts rather than hard-coded assumptions about one vendor.

## MCP integration model

**Model Context Protocol (MCP)** is an integration layer for allowing a compatible AI client to discover and call controlled Bitey SBT tools. MCP is not itself a broker API and does not replace broker/exchange APIs, SDKs, webhooks or terminal bridges.

The preferred architecture is:

```text
Selected AI / MCP Client
          │
          ▼
     SBT MCP Layer
          │
   Tool permissions
          │
          ▼
     Bitey SBT Core
     ┌────┼─────────────┐
     ▼    ▼             ▼
 Research Bot Lab   Risk Gate
     │    │             │
     └────┼─────────────┘
          ▼
 Execution / Data Connectors
     ┌────┼──────────────┐
     ▼    ▼              ▼
    MT5 TradingView    Alpaca
```

The AI never receives unrestricted authority merely because it is connected through MCP. Every tool invocation is checked against authentication, connector permissions, mode, strategy state and deterministic risk controls.

### MCP capability classes

Tools should be explicitly classified, for example:

- **READ** — market data, account state, positions, bot status and reports;
- **RESEARCH** — news/event analysis, experiments and research tasks;
- **DESIGN** — create or modify a strategy draft;
- **SIMULATION** — backtest and robustness tests;
- **VALIDATION** — request or evaluate validation evidence;
- **DEMO** — start, stop or manage demo execution;
- **PAPER** — manage paper execution;
- **LIVE** — real-money actions, disabled by default and subject to the full real-money gate.

Permissions are user-controlled and revocable. The SBT Risk Gate remains authoritative regardless of which AI initiated a request.

## Guided implementation by the SBT web application

The independent SBT web application is not only a dashboard. It acts as a **guided implementation assistant**.

A typical flow is:

1. **Choose AI** — select Bitey or the user's external AI/MCP client.
2. **Choose platform** — select MT5, TradingView, Alpaca or another supported connector.
3. **Choose objective** — research, create bot, backtest, optimize, demo, paper or real trading.
4. **Connect accounts/tools** — follow platform-specific setup instructions.
5. **Verify connectivity** — test permissions, market data and account state.
6. **Define strategy** — convert natural language into a deterministic strategy specification.
7. **Simulate** — run historical tests under explicit costs/slippage assumptions.
8. **Stress-test** — test periods, parameters, regimes and out-of-sample behavior.
9. **Validate** — generate a versioned Validation Passport.
10. **Demo/Paper** — observe behavior without real capital.
11. **Request automation** — the user chooses how much work SBT may perform automatically.
12. **Monitor and re-evaluate** — continuously record evidence and suspend/revalidate when required conditions fail.

The user may choose to perform the steps manually or authorize SBT to perform eligible steps automatically. Automation never removes the Risk Gate or explicit permissions.

## User-owned external services and costs

Bitey SBT does **not** assume costs belonging to external services selected by the user.

The user remains responsible for applicable:

- AI subscriptions, API usage, tokens or credits;
- TradingView subscriptions;
- broker/exchange fees;
- market-data fees;
- MetaTrader/broker account costs;
- third-party strategy purchases;
- other external platform costs.

SBT must clearly distinguish:

1. Bitey/SBT platform charges, if any;
2. SBT execution/data/tool charges, if any;
3. third-party provider charges paid under the user's own account.

SBT must not silently use a paid external AI, silently fall back to another provider, or create uncontrolled background usage that can generate third-party charges.

## Original product areas

### 1. Bitey Research Lab

Market questions, hypotheses, news/event context, technical context and experiment design.

### 2. Bitey Bot Lab

A deterministic strategy workspace supporting market/instrument, timeframe, indicators, entry/exit rules, regime filters, stop loss/take profit, position sizing, capital allocation, exposure and hard risk limits.

AI may translate natural language into a structured strategy specification, explain decisions and propose experiments. The executable strategy and Risk Gate remain deterministic and authoritative.

### 3. Bitey Model Workshop

Users can select supported AI providers and compare proposals under controlled conditions. Models are advisors/proposers, not execution authorities.

### 4. SBT Evaluation

Evaluation may include net return, maximum drawdown, profit factor, risk-adjusted return, win rate, trade count, exposure, volatility, consecutive losses, out-of-sample performance, parameter sensitivity, stability, demo/paper consistency, execution quality and validation freshness.

The weighting is versioned. A score is an evaluation aid, not a prediction of future profit.

### 5. SBT Strategy Registry

Published strategies retain identity, version, provenance, market/timeframe, deterministic rules, backtest evidence, robustness evidence, demo/paper evidence, risk classification, evaluation score, validation timestamp and publication status.

Backtest, demo, paper and live evidence must always remain clearly separated.

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

A strategy can move backwards when evidence becomes stale, behavior changes or a safety condition is triggered.

## Initial bot groups

The existing seed profiles remain part of the product:

- **Conservador EUR/USD**
- **Equilibrado EUR/USD**
- **Agresivo EUR/USD**

They should evolve into versioned SBT strategies rather than being discarded.

## Intelligence model

Bitey Trading Intelligence can assist with market research, news/event analysis, affected-asset analysis, domino/event-chain analysis, time horizon, technical context, strategy hypotheses, experiment design, backtest interpretation, anomaly detection, strategy comparison, risk explanations and performance reports.

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

> **AI can propose and request tools. The deterministic SBT engine and Risk Gate decide whether an action is technically and financially permitted.**

The AI cannot bypass SBT risk rules through MCP, APIs, webhooks or another connector.

### Demo and paper

Demo and paper modes are the baseline for automated integration and testing.

### Real-money transition

Real-money trading is a separate, explicit stage. If the user chooses to invest real capital, SBT must require the appropriate controls before enabling a live connector.

Minimum gates include:

1. authenticated user;
2. explicit real-account selection;
3. explicit user intent to use real money;
4. broker/exchange connection and health check;
5. maximum capital allocation;
6. per-trade loss limit;
7. daily loss limit;
8. maximum exposure/position limits;
9. pre-trade validation;
10. validated strategy status and fresh evidence;
11. audit trail;
12. emergency stop;
13. execution health checks;
14. explicit final confirmation;
15. fail-closed behavior whenever a mandatory safety dependency is unavailable.

SBT may guide and automate permitted work after authorization, but it does not guarantee profitability, finance the user's trading account, or assume trading losses.

**The user's real-money capital, broker account, external AI services, platform subscriptions and third-party fees remain the user's responsibility.**

Live execution must never be enabled merely because a backtest or AI recommendation looks profitable.

## Current MT5 boundary

MetaTrader 5 is currently a **read-only market-data/demo bridge**. The present milestone does not send real broker orders.

Future live connectors must remain behind the same strategy, validation, Risk Gate, audit, permission and emergency-stop controls.

## Participation model for Bitey-branded strategies

The commercial concept remains a possible **0.1% participation on verified realized net profit** when another trader uses an eligible Bitey-branded strategy.

The intended calculation is based on realized results attributable to the strategy after explicitly defined costs and adjustments. It does not apply to backtest returns or unrealized gains.

Before any real-money implementation, commercial definitions, accounting, taxation, jurisdictional requirements, broker rules and applicable financial regulations must be reviewed. This mechanism is not a profit guarantee.

## Independent web product

The future Cloudflare web application is a separate frontend/product from `bitey-web`.

It will have its own domain/subdomain, frontend, navigation, visual identity, authentication UX, SBT dashboards, AI selection, MCP connection flow, platform connection flow, bot laboratory, registry, research tools and trading views.

It connects to this backend through explicit versioned APIs. It must never become a copy of another platform's frontend.

## Mobile app

`bitey-system-bots-trading-app` is the mobile channel for Bitey SBT. It consumes the same SBT contracts and must never duplicate the trading engine.

## Repository architecture

- `core/` — trading state and domain primitives.
- `strategies/` — deterministic strategy contracts.
- `risk/` — mandatory risk controls.
- `backtest/` — historical simulation.
- `execution/` — broker/exchange adapters.
- `api/` — SBT API contracts.
- `tests/` — unit, integration, simulation and safety tests.
- `docs/` — product and architecture specifications.
- `web/` — independent SBT web application.

Future MCP implementation should have explicit connector, capability, permission and audit contracts rather than embedding provider-specific logic throughout the trading engine.

## Intellectual-property guardrail

Every future feature must pass this design test:

**What problem are we solving?**
→ implement the general capability if useful.

**Are we copying a particular expression of that capability?**
→ redesign it from first principles for Bitey.

Never import competitor code, assets, text, logos, screenshots or proprietary implementation details.

## Disclaimer

Trading financial assets involves substantial risk, including loss of capital. Backtests, simulations, demo results and paper results do not guarantee future performance. Slippage, gaps, liquidity, execution failures and market-regime changes can materially alter results.

Real-money trading remains disabled in the current implementation until the required technical, operational, security, legal and regulatory controls are validated and implemented.

## MT4 EA — v1.58.0 adaptive risk ladder and three-candle profit-only SL/TP

The MT4 Expert Advisor is a separate execution adapter. The downloadable source is a reconstructed test build, not a claim that MetaEditor compilation or broker execution has already been verified.

### Position-management contract

- Fixed strategy allocation: **USD 500**; the broker account balance does not redefine this cap.
- One open position per canonical asset for this EA's magic number; no same-direction stacking.
- Adaptive SL/TP management runs **only when floating net P/L is strictly greater than the configured threshold**, calculated as `OrderProfit + OrderSwap + OrderCommission`.
- Default activation threshold: **net floating profit > USD 0.05**. At a net loss, zero, or profit at/below the threshold, adaptive management leaves the current SL and TP unchanged.
- On a BUY, the SL may only rise and the TP may only extend upward. On a SELL, the SL may only fall and the TP may only extend downward. Existing protective levels are never loosened by the adaptive manager.
- TP extension additionally requires favorable price movement and closed-bar trend confirmation.
- Per-ticket modification cooldown and minimum ATR change reduce repeated tiny modifications.
- Journal audit records the profit gate, requested SL/TP, MT4 modify result, error code and server readback.

### MT4 test checklist

1. Compile the MQ4 file in MetaEditor and resolve any compiler errors/warnings before attaching it.
2. Test on a demo account and verify the EA's magic number and symbols.
3. Confirm `SLTP PROFIT GATE` appears when net floating P/L is at or below the threshold and that adaptive modifications are not requested.
4. When net floating P/L exceeds the threshold, inspect `SLTP MODIFY AUDIT` and verify `modifyOK`, `readbackOK`, `confirmedSL`, and `confirmedTP`.
5. Confirm there is at most one position per canonical asset and that capital/risk gates remain active.

The profit gate only controls **adaptive** changes. It does not remove the initial SL/TP, bypass broker protections, guarantee an exit price, or guarantee that a profitable trade cannot become a loss due to slippage, gaps or broker execution limits. The EA source must be compiled and validated in MT4 before use.


## Adaptive portfolio risk specification

The complete adaptive risk and position-management rules are maintained in [docs/ADAPTIVE_TRADING_RULES.md](docs/ADAPTIVE_TRADING_RULES.md). The specification defines the USD 500 fixed strategic allocation; adaptive maximum risk per operation (USD 3 → 2 → 1 in losses and USD 5 → 6 → 7 → 8+ only after sustained, confirmed net profits); aggregate-risk and daily-loss gates; one managed position per canonical asset; and profit-only adaptive SL/TP changes after three consecutive favorable closed candles, with trend confirmation, no SL loosening, and MT4 readback audit. These are intended behavioral rules and must be verified against the current MQ4 source and MetaEditor/demo tests before claiming implementation or compilation is complete.


### v1.58.0 adaptive-risk implementation

The current downloadable test source adds the portfolio-conditioned per-trade risk ladder (USD 3 → 2 → 1 under losses; USD 5 → 6 → 7 → 8+ after sustained net profits), configurable persistence thresholds, a default USD 12 per-trade ceiling and USD 14 aggregate stop-risk ceiling. Adaptive SL/TP requires net floating profit above USD 0.05 and three consecutive favorable closed candles on the configured timeframe (H1 by default). It also wires MACD_CONFIRM and BOLLINGER_EXPANSION into the chart-local engine, bringing that engine to 16 model families, while retaining the separate 16-proxy cross-asset ranking, seven-asset allowlist, one-position-per-canonical-asset gate, train/holdout evidence, candidate ranking, telemetry, and modification readback audit.

The source is a reconstructed test build. Static checks passed for balanced delimiters, duplicate input names, all 16 model names and signal wiring, risk-ladder branches, three-candle gating and aggregate-risk checks. **MetaEditor compilation and demo validation have not been performed here**; do not treat this as a compiled or broker-validated release.


## Bitey SBT Multi-Asset v1.95.0 — Democratic Adaptive Governance (approval draft)

### Mandatory protections — immutable to model voting
- Fixed strategy reference capital: **USD 500**, independent of MT4 account balance/equity.
- Maximum **7 simultaneous positions** in total.
- Exactly **one position per canonical asset**, including broker aliases.
- **No martingale**, loss-recovery volume escalation, risk bypass, or control evasion.
- Broker/terminal execution and deterministic risk gates remain authoritative; a vote never authorizes bypassing a failed gate.

### Democratic decision policy
- The EA evaluates 16 chart-local model families; cross-asset ranking separately evaluates 16 model-family evidence proxies.
- Each model's BUY/SELL proposal counts only when its directional train/holdout evidence passes. Silent or failed-evidence models abstain.
- When BUY and SELL both have qualified votes, the EA compares aggregate reliability-adjusted expected-R scores per qualified vote. It requires a meaningful edge; a near tie means WAIT. A single model's score or raw majority alone cannot override evidence or execution controls.
- The winning direction/model is only a candidate. Quote freshness, spread, symbol specification, lot/margin, duplicate-asset, open-position and risk gates must still pass before an order can be sent.
- Adaptive SL/TP management remains: tighten stops to protect favorable movement, never widen an SL to increase risk, and adapt targets to validated market conditions.
- The target governance extends adaptive evaluation to volume, asset ranking, thresholds, model weights and position exits, seeking positive **net** expectancy after trading costs. These broader parameters must have explicit auditable proposal/score/selection logic before being described as fully democratically voted; v1.95.0 currently operationalizes aggregate democratic BUY/SELL conflict resolution while retaining the existing adaptive parameter calculations.

### Approval and validation status
This is a review draft, not a production release. The source has not been compiled in MetaEditor or validated in MT4 Strategy Tester/demo as part of this change. Historical-bar proxy evidence is not equivalent to real executed-trade evidence and does not guarantee future profits. Keep main unchanged until code review, compilation, and test results are approved.


## Bitey SBT Multi-Asset v1.96.0 — Detailed Adaptive SL/TP Audit (approval draft)

Source: `Bitey_SBT_MultiAsset_v1_96_0_DemocraticAdaptive_DetailedSLTPAudit_USD500_SevenAssets.mq4`.

This draft preserves the v1.95.0 execution and protection logic while adding rate-limited, per-position diagnostics to make the expert's SL/TP supervision visible in the MT4 Journal:
- `SLTP POSITION DIAGNOSTIC`: ticket, symbol, side, lots, entry/current quotes, spread, floating profit/swap/commission/net P/L, existing SL/TP, estimated stop risk and target reward, ATR, favorable distance in ATR, profit-gate status, three-candle result and each of the three candles' OHLC comparison values, plus the active break-even/trailing/TP-extension thresholds.
- `SLTP MANAGER STATUS`: records when management is disabled or trade permissions/context prevent the manager from running.
- Existing `SLTP PROFIT GATE`, `SLTP MODIFY DEFERRED`, `SLTP SUPERVISION DECISION`, `SLTP MODIFY SKIPPED` and `SLTP MODIFY AUDIT` records remain. A successful change is only reported as `MODIFY_CONFIRMED` after readback verifies the broker-visible SL and TP values.
- Diagnostics are rate-limited by ticket (default 30 seconds) to keep the Journal useful; set `InpSLTPVerboseDiagnostics=true` and adjust `InpSLTPDiagnosticIntervalSeconds` in EA inputs.

The additional diagnostics are observational and do not by themselves make a trade or SL/TP modification more profitable. The existing profit threshold, three-favorable-closed-candle gate, break-even/trailing triggers, broker stop/freeze-distance checks and one-successful-modification-per-closed-bar policy still govern modifications. No MetaEditor compilation, Strategy Tester run, or demo execution has been performed for this draft. Do not deploy as production until those checks pass; keep `main` unchanged pending review.
