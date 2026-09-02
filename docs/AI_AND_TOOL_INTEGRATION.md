# Bitey SBT — AI, MCP and Trading Tool Integration

## 1. AI choice

Bitey SBT is **model-agnostic**. The user chooses how they want to work.

Supported choices may include:

- Bitey Trading Intelligence;
- ChatGPT/OpenAI, when an approved integration is available;
- Claude/Anthropic, when an approved integration is available;
- Codex or another supported MCP-compatible client;
- DeepSeek or another supported provider/client;
- another compatible AI/MCP client.

The user can select a provider exclusively. Exclusive mode means **no silent fallback** to another AI.

## 2. Trading-platform choice

The user independently chooses the trading platform, broker, exchange or tool, for example:

- MetaTrader 5;
- TradingView;
- Alpaca;
- another supported connector.

The architecture must not assume one fixed AI/platform pair.

Examples:

```text
ChatGPT + MetaTrader 5
Claude + TradingView
Codex + TradingView
DeepSeek + Alpaca
Bitey IA + MetaTrader 5
```

## 3. MCP role

**Model Context Protocol (MCP)** is the preferred standardized tool-connection layer where the selected AI client supports it.

MCP connects the AI client to **controlled SBT tools**. It does not replace broker APIs, exchange SDKs, TradingView webhooks, MetaTrader bridges or other execution mechanisms.

Preferred flow:

```text
User-selected AI / MCP Client
          ↓
       SBT MCP
          ↓
 Tool capability + permission checks
          ↓
     Bitey SBT Core
          ↓
      SBT Risk Gate
          ↓
 Broker / platform connector
```

The AI must never receive unrestricted broker access merely because MCP is enabled.

## 4. Tool capability model

SBT tools must expose explicit capabilities:

- `READ` — market/account/bot data;
- `RESEARCH` — research and event analysis;
- `DESIGN` — strategy drafts;
- `SIMULATION` — backtests;
- `VALIDATION` — robustness and validation workflows;
- `DEMO` — demo execution controls;
- `PAPER` — paper execution controls;
- `LIVE` — real-money actions, disabled by default.

Every tool call must be authorized for the current user, selected AI, connector, account and trading mode.

## 5. Guided implementation

The SBT web application acts as a **guided implementation assistant**.

The user can choose:

```text
AI
 ↓
Trading platform
 ↓
Objective
 ↓
Connection method
 ↓
Permissions
 ↓
Strategy
 ↓
Simulation
 ↓
Stress test
 ↓
Validation
 ↓
Demo / Paper
 ↓
Optional real-money transition
```

The user may perform the workflow manually or authorize SBT to automate eligible steps. Automation cannot bypass permission checks, risk controls or explicit real-money confirmation.

## 6. User-owned external services and billing

External AI and trading services are **user-owned dependencies** unless Bitey explicitly contracts otherwise.

The user is responsible for applicable provider subscriptions, API/token/credit usage, broker fees, platform subscriptions, market-data fees and third-party strategy costs.

SBT must distinguish:

1. Bitey/SBT platform charges;
2. SBT execution/data/tool charges;
3. third-party provider charges billed to the user's own account.

SBT must never silently absorb an external provider's cost.

### AI Cost Guard

Before an external paid AI operation:

```text
NO_PROVIDER
 ↓
PROVIDER_SELECTED
 ↓
COST/BILLING_OWNER_KNOWN
 ↓
USER_CONSENTED
 ↓
WITHIN_CONFIGURED_LIMIT
 ↓
AUTHORIZED_CALL
```

The guard must prevent silent paid fallback, uncontrolled retry loops and unauthorized background usage.

## 7. Credential boundary

Provider and broker credentials must never be embedded in the browser, committed to Git or exposed in logs.

Preferred mechanisms are user-authorized connections, OAuth where supported, or server-side encrypted credentials with least privilege.

The AI should call SBT tools rather than receiving raw broker credentials.

## 8. Real-money execution

Current implementation supports demo/paper integration. Real-money execution is a separate gated capability.

Before a live action, SBT must require, at minimum:

- authenticated user;
- explicit real-account selection;
- explicit real-money intent;
- healthy broker/platform connection;
- maximum capital allocation;
- per-trade and daily loss limits;
- exposure/position limits;
- validated strategy status;
- pre-trade validation;
- audit trail;
- emergency stop;
- execution health checks;
- final explicit confirmation.

If a mandatory safety dependency is unavailable, the action must **fail closed**.

Bitey SBT does not finance the user's account, guarantee performance or assume trading losses.

## 9. Existing strategies and bots

SBT may contain community, third-party or previously published strategies. A strategy is never presented as guaranteed profitable. Before use, SBT records provenance, version, test period, costs/slippage assumptions, drawdown, out-of-sample evidence, robustness, validation freshness and execution mode.

Any external purchase, subscription, broker/data fee or AI-provider fee belongs to the user unless Bitey explicitly states otherwise.

## 10. User registration

User accounts are implemented through Supabase Auth. Production configuration keeps public/anonymous keys separate from service-role credentials and uses RLS for user-owned SBT data.

Required production configuration includes:

- `SUPABASE_URL`;
- `SUPABASE_ANON_KEY`;
- Supabase Auth confirmation/redirect settings;
- RLS policies for user-owned SBT data.

No provider API secret belongs in the browser, repository or logs.

## 11. No-Gemini policy

The current Bitey project requirement remains **do not use the Gemini API**. Adding another provider requires an explicit architecture decision, provider contract, cost policy and security review. It must never happen as an automatic fallback.

## 12. Safety principle

AI can propose and request tools. The deterministic SBT engine and **SBT Risk Gate** decide whether an action is technically and financially permitted.

`AI Cost Guard` protects the user's external AI spending boundary.

`SBT Risk Gate` protects the trading account and can block an action regardless of which AI requested it.
