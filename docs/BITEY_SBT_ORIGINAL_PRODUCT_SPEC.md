# Bitey SBT — Original Product Specification

Status: baseline specification v1.1

## 1. Purpose

Bitey SBT is an original Bitey IA trading product. It can implement broad capabilities already validated by the market, but its product expression, architecture, terminology, UX, scoring, orchestration and implementation are designed independently.

## 2. Product promise

Help traders investigate, build, simulate, stress-test, validate and monitor systematic trading ideas with transparent evidence and mandatory risk controls.

Bitey SBT does not promise profits.

## 3. Product pillars

1. **Research** — investigate markets, events and hypotheses.
2. **Strategy Lab** — turn an idea into a deterministic specification.
3. **Model Workshop** — obtain proposals from Bitey or a user-selected external AI provider.
4. **Simulation** — backtest under explicit assumptions.
5. **Robustness** — test periods, parameters, regimes and out-of-sample behavior.
6. **Risk Gate** — apply deterministic hard limits.
7. **Demo/Paper** — observe behavior without real capital.
8. **Strategy Registry** — version and publish validated strategies.
9. **Monitoring** — measure behavior after publication/deployment.

## 4. Original terminology

Use these Bitey terms consistently:

- Bitey Research Lab
- Bitey Bot Lab
- Bitey Model Workshop
- SBT Evaluation
- SBT Strategy Registry
- SBT Risk Gate
- Strategy Evidence Card
- Validation Passport
- AI Cost Guard
- Provider Consent Gate

Do not use competitor product names as internal module names.

## 5. Navigation baseline

```text
Inicio
Investigación
  ├─ Market Research
  ├─ Event Analysis
  └─ Experiments
Bot Lab
  ├─ Create Strategy
  ├─ My Strategies
  ├─ Simulation
  ├─ Robustness
  └─ Validation
Model Workshop
  ├─ Bitey
  ├─ External Models
  ├─ My Provider
  └─ Model Comparison
Markets
Strategy Registry
  ├─ Bitey Strategies
  ├─ Community Strategies
  └─ Validation Evidence
My Trading
  ├─ Demo
  ├─ Paper
  ├─ Active Strategies
  └─ Performance
Research Reports
Account
  └─ AI Providers & Costs
```

This is an original information architecture and must not be treated as a copy of any competitor's navigation.

## 6. Strategy Evidence Card

Every strategy shown to a user should expose evidence before emphasizing performance:

- identity;
- version;
- author;
- model provenance;
- market/timeframe;
- strategy rules;
- test period;
- trade count;
- costs and slippage assumptions;
- drawdown;
- return;
- risk-adjusted metrics where meaningful;
- out-of-sample evidence;
- robustness status;
- demo/paper evidence;
- validation freshness;
- risk classification.

## 7. Validation Passport

A strategy receives a versioned validation record containing the tests performed, assumptions, results, warnings and approval status. Any material strategy change invalidates or reopens the relevant validation state.

## 8. User-selected AI providers and cost responsibility

Bitey SBT is **model-agnostic**. Bitey is a platform/orchestration and validation environment; it is not required to be the AI provider used by the trader.

The user may choose:

- Bitey Trading Intelligence;
- ChatGPT/OpenAI when an approved integration is available;
- Claude/Anthropic when an approved integration is available;
- another supported provider/model.

The user may use **one external provider exclusively**. There is no requirement to use Bitey AI together with an external model.

When an external AI provider charges separately for its service, API, subscription, tokens, credits or usage, that cost belongs to the user under the provider's own terms unless Bitey has explicitly displayed and accepted a different commercial arrangement. Bitey must never silently absorb third-party AI usage costs.

This design follows a public market pattern observed in the current Trader.dev workflow: it supports "bring your own AI" with Claude, ChatGPT, Cursor, Codex and other MCP-compatible clients, and its pricing page states that AI usage is billed by the user's AI provider rather than Trader.dev. Trader.dev separately charges for its own platform credits. This is a product-behavior reference only, not a copying blueprint.

### 8.1 Provider selection contract

Before any external-model call, SBT must know:

- selected provider;
- selected model;
- connection method;
- who owns the credential/account;
- whether the provider bills the user directly;
- whether SBT has any platform fee for the operation;
- estimated or known usage cost when the provider exposes it;
- the user's spending/usage limit if supported;
- consent timestamp and policy version.

### 8.2 AI Cost Guard

Every external AI operation must pass the **AI Cost Guard** before execution.

Minimum states:

```text
NO_PROVIDER
   ↓
PROVIDER_SELECTED
   ↓
COST_DISCLOSED
   ↓
USER_CONSENTED
   ↓
WITHIN_LIMIT
   ↓
AUTHORIZED_CALL
```

If cost ownership, authorization or spending state cannot be established, the operation must fail closed.

The guard must prevent:

- automatic use of an external paid model without consent;
- silent fallback from a free/Bitey model to a paid provider;
- retry loops that unexpectedly create third-party charges;
- background jobs that continue consuming a user's external AI quota without an active authorization;
- Bitey credentials being used to pay for an external provider selected by the user;
- treating a provider subscription as if it were included in Bitey;
- charging Bitey for external usage merely because the user selected that model.

### 8.3 Explicit user controls

The SBT UI must provide, at minimum:

- **AI provider:** Bitey / ChatGPT / Claude / other supported provider;
- **Use only this provider:** ON/OFF;
- **Allow paid external AI:** ON/OFF;
- **Maximum spend per operation:** when technically enforceable;
- **Maximum spend per period:** when technically enforceable;
- **Ask before paid calls:** ON/OFF;
- **Automatic fallback to another provider:** OFF by default;
- **Background AI usage:** OFF by default for paid providers;
- **View usage/cost events:** available to the user;
- **Disconnect provider:** immediately revoke/disable the integration where supported.

A user who chooses "ChatGPT only" must not receive Claude or Bitey calls as an undisclosed fallback. The same applies to any other exclusive selection.

### 8.4 Billing boundary

SBT separates three ledgers:

1. **Bitey platform charges**, if any.
2. **SBT execution/data/tool charges**, if any.
3. **Third-party AI provider charges**, which remain the user's/provider-account responsibility unless explicitly contracted otherwise.

The UI must never combine these into a single ambiguous "AI cost" number.

Where an external provider bills directly, SBT should show a clear notice such as:

> This request uses your external provider account. Any provider/API charges are billed by that provider under your plan. Bitey does not assume those charges.

Where exact pricing is unavailable, SBT must say so rather than inventing a price.

### 8.5 Credential boundary

Provider credentials/API keys must never be embedded in the mobile/web client, committed to Git, exposed in logs, or reused across users. The preferred integration is user-authorized provider access or a server-side encrypted credential mechanism with least privilege.

Bitey SBT must not collect an external provider secret merely to make the product appear integrated when a safer provider-supported authorization method exists.

### 8.6 Failure and refund boundary

If an external provider rejects, retries, times out or partially completes a request, SBT must record the provider operation ID/status when available and prevent uncontrolled retries. SBT cannot promise reimbursement for charges imposed by the external provider unless Bitey explicitly operates the billing relationship.

### 8.7 No-Gemini policy

The current Bitey project requirement is **do not use Gemini API**. Adding another provider requires an explicit architecture decision, provider contract, cost policy and security review; it must not happen as an automatic fallback.

## 9. Model comparison contract

When multiple AI models are compared, use the same hypothesis, data, test period, cost assumptions, simulation engine and risk constraints whenever technically possible.

Models may propose different implementations. The evaluation environment remains controlled so the comparison is meaningful.

Model comparison must not imply that Bitey pays for external providers. Each provider's usage remains subject to its own authorization and billing boundary.

## 10. Safety contract

AI cannot bypass the deterministic Risk Gate. Real execution requires authentication, explicit account selection, capital and loss limits, pre-trade validation, auditability, emergency stop and health checks.

The AI Cost Guard is separate from, and complementary to, the trading Risk Gate. One protects the user's money/trading account; the other protects the user's AI-provider spending and prevents Bitey from assuming unapproved third-party costs.

## 11. Originality gate

Before merging a feature, ask:

1. What user problem does this solve?
2. Is the capability a general/non-exclusive market concept?
3. Is the implementation independently designed?
4. Are the names and copy original?
5. Are the UI/layout/assets original?
6. Did we avoid importing competitor code or proprietary material?
7. Can the feature be explained without referencing a competitor as its blueprint?

If the answer to 3–6 is no, redesign before merge.

## 12. Implementation order

Phase 1 — product contracts and domain models.

Phase 2 — Strategy Evidence Card + Validation Passport.

Phase 3 — **AI Provider Contract + AI Cost Guard + Provider Consent Gate**.

Phase 4 — Bot Lab and simulation APIs.

Phase 5 — robustness and SBT Evaluation.

Phase 6 — Model Workshop abstraction.

Phase 7 — Strategy Registry.

Phase 8 — independent Cloudflare web frontend.

Phase 9 — demo/paper monitoring.

Phase 10 — future controlled live execution only after safety/legal/regulatory validation.
