# Bitey SBT MT5 Bridge

Local read-only bridge between a MetaTrader 5 Demo terminal and the existing SBT API.

## Purpose

The bridge exposes only market-data endpoints. It does not submit orders.

Required endpoints:

- `GET /health`
- `GET /quote/{symbol}`
- `GET /candles/{symbol}`

The SBT API consumes these endpoints through `MT5_BRIDGE_URL`.

## Safety

- Demo/Paper market data only.
- No broker order submission.
- No live execution.
- No real capital.
- No paid market-data provider.

## Runtime

Run this bridge on the Windows machine where the MT5 Demo terminal is installed and logged in. Keep it bound to a controlled local interface. The SBT API must reach it through a secure network path before `MT5_BRIDGE_URL` is configured.

The bridge must fail closed when MT5 is unavailable; it must never fabricate candles or quotes.
