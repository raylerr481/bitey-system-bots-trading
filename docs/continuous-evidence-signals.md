# Continuous Evidence-Based Signal Engine

The API endpoint `POST /api/v1/signals/analyze` receives timestamped OHLC candles, runs deterministic strategy votes, applies the operating-capital/risk gates, and records the result in SQLite. `GET /api/v1/signals/recent` retrieves the audit log; `GET /api/v1/signals/strategies` lists the research modules.

## Current safeguards

- Operating capital is fixed at USD 500.
- Target risk is USD 1.25; hard per-trade cap is USD 2.00.
- Daily realized loss limit is USD 10.
- Maximum three trades per day and one open position.
- Minimum modeled reward/risk is 1.5:1.
- Stale data, excessive spread, daily loss limit, trade-count limit, open position, or weak consensus force WAIT.
- The endpoint only creates signals; it never submits broker orders.

## Research candidates

- EMA trend-following (20/50)
- Donchian 20-bar breakout
- RSI mean reversion, gated to a low-trend-strength regime
- Five-bar momentum confirmation

These are candidates, not validated profitable strategies. They must pass walk-forward/out-of-sample tests, realistic spread/commission/slippage, parameter-sensitivity checks, and demo-forward validation before any promotion.

## Persistence requirement

Set `SBT_SIGNAL_DB_PATH` to a durable mounted disk path in production. The default `/tmp` path is suitable only for local/testing and can be ephemeral in hosted deployments. If persistence is unavailable, the API fails closed with HTTP 503 rather than claiming the signal was recorded.

## Important limitation

Risk dollars are represented as hard policy metadata here. The MT4 connector must still calculate broker-specific lot size from tick value, tick size, contract size, account currency, stop distance, and broker volume steps, then reject any order whose worst-case loss exceeds USD 2. This endpoint does not authorize or execute an order.
