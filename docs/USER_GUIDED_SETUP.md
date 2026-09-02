# Bitey SBT — User Registration and Guided Setup

## Purpose

The independent SBT web application is an interactive workspace, not only a dashboard. A registered user can save preferences, choose an AI client/provider, choose a trading platform, select permissions and decide whether authorized Demo/Paper tasks may be automated.

## User flow

```text
Visitor
  ↓
Register / Sign in
  ↓
Choose AI
  ↓
Choose trading platform
  ↓
Choose permissions
  ↓
Choose Demo / Paper
  ↓
Choose manual / authorized automation
  ↓
Generate implementation plan
  ↓
Connect through API / MCP / webhook / SDK
  ↓
Risk Gate
  ↓
Run and monitor
```

## AI choice

The user can select Bitey Trading Intelligence or an external AI/client such as ChatGPT, Claude, Codex, DeepSeek or another supported MCP-compatible client where an integration exists.

The selection is explicit. Automatic fallback to another provider is disabled by default and must never silently create third-party usage costs.

## Platform choice

Initial platform registry:

- MetaTrader 5 — Demo/read-only market-data baseline.
- TradingView — webhook/Paper integration baseline.
- Alpaca — Paper integration baseline.

New platforms must be added through the connector registry and must inherit the same permission and Risk Gate model.

## Permissions

Permissions are granular:

- `read_market`
- `read_account`
- `research`
- `strategy_write`
- `demo_execute`
- `paper_execute`
- `live_execute` (reserved and blocked in the current milestone)

Automation requires an explicit execution permission. It never bypasses the Risk Gate.

## Registration

The web UI exposes registration and sign-in. The backend uses `/api/v1/auth/signup`, `/api/v1/auth/signin` and `/api/v1/auth/status`, backed by Supabase Auth when configured.

The browser must never collect or store broker credentials as part of registration.

## External costs

The user owns external provider subscriptions/API/token/credit costs unless Bitey explicitly establishes a different commercial relationship. SBT must disclose this boundary and must not silently pay for or retry paid external AI usage.

## Real-money transition

Live execution is a separate safety stage. It requires authenticated user identity, explicit real-account selection, validated strategy, configured capital/risk limits, broker health, audit trail, emergency stop and explicit confirmation. The current milestone keeps live execution disabled.
