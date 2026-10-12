# Bitey SBT dashboard audit — 2026-10-12

## Scope and safety invariants

- Branch: `fix/q-learning-market-data-audit`
- Production branch `main` was not modified.
- No MT4 EA, order execution code, or Risk Gate policy was changed.
- Existing backend advertises research/demo-only operation; this patch does not enable live trading, real money, or broker orders.
- Operational capital policy remains USD 500; this patch does not change capital/risk settings.
- Manual MT4 control remains unchanged.

## Code changes

| Area | Change | Static verification |
|---|---|---|
| Frontend runtime | Removed Worker-side duplicate injection of `/runtime.js`; `web/index.html` already includes it. Added an idempotency guard to the runtime IIFE. | PASS: branch source contains the guard and Worker no longer injects runtime.js. |
| Q-learning | Corrected the Bitey IA status URL from the misspelled `bitey-ia-suprabrain` host to `bitey-ia-suprabain`. | PASS: corrected URL is present in `web/sbt-control-live.js`. |
| H4 candles | H4 now requests supported hourly source candles and aggregates only complete four-candle groups into UTC-aligned H4 bars. | PASS: source aggregation path is present; runtime provider response still needs live verification. |
| Bid/ask spread | Missing public-provider bid/ask values remain `null`; spread is `null` unless both bid and ask are supplied. No synthetic zero spread. | PASS: source no longer substitutes last price for absent bid/ask. |

## Control-by-control source audit

**Important:** "Static PASS" means the source contains a click handler or navigation route. It does not mean a real browser click or a live API request succeeded. Browser automation could not run because the Opera Browser Connector was disconnected; public endpoint probes were also inaccessible from the available web tool. Do not interpret pending tests as passing.

| Module / control | Expected action / endpoint | Static result | Live result |
|---|---|---|---|
| Sidebar navigation (17 destinations) | Switches page using `data-page`; no direct API call required for the navigation itself | PASS: navigation attributes found | BLOCKED: browser disconnected |
| Dashboard | Loads MT4 snapshot, Q-learning status, system summary and module snapshots | Handler/timer source present | BLOCKED: browser/API unavailable |
| Turtle / MT4 — Refresh | Reloads snapshot and history; MT4 proxy telemetry endpoints | PASS: click handler found | BLOCKED |
| Turtle / MT4 — Evaluate evidence | Evaluates Turtle readiness from available evidence | PASS: click handler found | BLOCKED |
| Bot Observer — Refresh | Reloads observer snapshots and recent activity | PASS: click handler found | BLOCKED |
| SBT Market Matrix — Scan | Requests market quote/candles for configured universe; public quote route `/api/v1/market/quote` and candle route `/api/v1/market/candles/:symbol` | PASS: click handler found | BLOCKED |
| SBT Market Matrix — Clear | Clears displayed scan rows and summary | PASS: click handler found | BLOCKED |
| Market Intelligence — Refresh | Reads market quote/candles and updates analysis | PASS: click handler found | BLOCKED |
| Market Intelligence — Back to Matrix | Navigation only | PASS: click handler found | BLOCKED |
| Research — Mine Ensemble M15 | `POST /api/v1/research/nonlinear-patterns` (verify actual route on backend before live test) | PASS: click handler found | BLOCKED |
| Research — Prepare experiment | `POST /api/v1/experiments` | PASS: handler in `web/sbt-control-live.js` | BLOCKED |
| Evolution — Refresh | Loads evolution status/experiments | PASS: click handler found | BLOCKED |
| Evolution — Compare Intraday | Runs intraday comparison for selected symbol | PASS: click handler found | BLOCKED |
| AI Bot Lab — Analyze | `POST /api/v1/ai-bot-lab/analyze` | PASS: click handler found | BLOCKED |
| AI Bot Lab — Optimize | `POST /api/v1/ai-bot-lab/optimize` | PASS: click handler found | BLOCKED |
| Virtual Validation — Run | Reads virtual validation and policy endpoints; does not submit broker orders | PASS: click handler found | BLOCKED |
| Strategy Library — Load | Loads the strategy catalog | PASS: click handler found | BLOCKED |
| Environment — Build Plan | `POST /api/v1/integrations/plan` | PASS: handler in `web/sbt-control-live.js` | BLOCKED |
| Financial Hub — Refresh | `GET /api/v1/financial/status` | PASS: click handler found | BLOCKED |
| Financial Hub — Prepare Pix | Local form navigation/selection only | PASS: click handler found | BLOCKED |
| Financial Hub — Prepare Open Finance | Local form navigation/selection only | PASS: click handler found | BLOCKED |
| Financial Hub — Prepare request | Validates request fields and prepares a request; must not be treated as money movement | PASS: click handler found | BLOCKED |
| Account — Create account | Opens local workspace modal | PASS: click handler found | BLOCKED |
| Account — Clear local workspace | Removes selected local workspace preferences and reloads page | PASS: click handler found | BLOCKED |
| Account modal — Close | Closes modal | PASS: click handler found | BLOCKED |
| Account modal — Save workspace | Saves workspace name/preferences locally | PASS: click handler found | BLOCKED |
| AI/provider/platform/permission selectors | Updates selected UI choices used by Build Plan | PASS: selector buttons found; behavior is local UI state | BLOCKED |

## Explicitly not verified

- Actual browser clicks, responsive/mobile navigation, console errors, and network panel outcomes.
- HTTP status and payload of live API calls.
- Live MT4 heartbeat and freshness of the latest snapshot.
- H4 candle count and OHLCV correctness against a live provider response.
- Deployment of this branch to the Cloudflare Worker.

## Next acceptance gate

1. Enable Opera Browser Connector ("Allow AI connection") and open the deployed dashboard.
2. Exercise each listed control once; record exact URL, HTTP status, payload/result, visible UI outcome, and console error (if any).
3. Verify H4 candle grouping with a known hourly sample and ensure missing bid/ask renders "unknown", not a zero spread.
4. Verify `/api/v1/system` still reports live trading disabled, real money disabled, and zero broker orders.
5. Only then consider merging/deploying. Do not change MT4 execution authority, Risk Gate protections, or the USD 500 operational capital cap.
