# MT4 ↔ Bitey SBT telemetry setup

## What the Worker now exposes

The Cloudflare Worker relays these requests to the SBT API:

- `GET /api/v1/mt4/health` — reports whether the backend has a current MT4 snapshot.
- `GET /api/v1/mt4/active-bot` — most recent snapshot.
- `GET /api/v1/mt4/trades` — closed-trade history.
- `POST /api/v1/mt4/bitey-report` — live snapshot and model evidence.
- `POST /api/v1/mt4/trade-closed` — closed-trade outcome.

Base URL: `https://bitey-system-bots-trading.raylerr481.workers.dev`

## EA setup

Use `Bitey_SBT_MultiModel_Engine_v1_31.mq4` for integrated telemetry. The EA reports its model signals, directional votes, evidence statistics, symbol/timeframe, indicator snapshot, account mode, operating-capital reference, risk limits, open-position count and execution result. Telemetry is read-only: it does not tell the EA to open or close an order.

1. Compile the v1.31 EA in MetaEditor.
2. In MT4, open **Tools → Options → Expert Advisors** and add this origin to **Allow WebRequest for listed URL**:
   `https://bitey-system-bots-trading.raylerr481.workers.dev`
3. Keep `InpSbtTelemetryEnabled=true`. If the backend has `MT4_INGEST_TOKEN` configured, enter the same token in `InpSbtToken`; never publish that token.
4. Attach the EA to the intended demo chart and check the Experts log for `SBT TELEMETRY OK | HTTP=200`.
5. Open `/api/v1/mt4/health` on the Worker URL. It should show `connected: true` after the first accepted snapshot; until then, the UI should say it is awaiting telemetry.

## Safety and limitations

- The SBT Worker is research/demo-only and reports `live=false`, `real_money=false`, and `broker_orders=0`. The MT4 EA's local order execution remains separate.
- The EA's configured daily loss limit is scoped to that EA's symbol and magic number; it is not an account-wide loss limit.
- A Worker health response with `connected: false` means no accepted MT4 snapshot is currently visible to the backend. It is not proof that MT4 itself is offline.
- HTTP delivery is not proof of profitability. Validate multiple closed trades, costs, and out-of-sample results before drawing performance conclusions.
