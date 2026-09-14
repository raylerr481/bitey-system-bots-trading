# MT5 Demo Data Bridge Contract

## Purpose

The SBT cloud API consumes read-only market data from an externally hosted MetaTrader 5 demo bridge. This document defines the minimum HTTP contract required by `MT5Provider`.

## Required endpoints

### GET /health

Returns HTTP 200 when the bridge process is reachable.

Example:

```json
{"status":"ok","mode":"demo","live_trading_enabled":false}
```

### GET /quote/{symbol}

Returns a verified quote from the connected MT5 terminal.

Minimum response fields:

```json
{
  "symbol":"BTCUSDT",
  "timestamp":"2026-09-14T20:00:00Z",
  "bid":100.0,
  "ask":101.0,
  "last":100.5
}
```

The bridge must not synthesize or cache fabricated prices.

### GET /candles/{symbol}?timeframe=M1&limit=100

Returns OHLC candles obtained from MT5.

Minimum response shape:

```json
{
  "candles":[
    {
      "timestamp":"2026-09-14T20:00:00Z",
      "open":100.0,
      "high":101.0,
      "low":99.5,
      "close":100.5
    }
  ]
}
```

SBT market intelligence requires at least 35 valid candles for the baseline analysis path.

### GET /account

Optional diagnostic endpoint. If implemented, it must expose only safe demo/paper account information and must not expose credentials.

## Security boundary

The bridge is a **read-only data bridge** for the current milestone.

It must not expose order-placement, position-modification, withdrawal, or real-money execution endpoints.

The SBT cloud service must connect to a bridge URL through `MT5_BRIDGE_URL` and must keep `MT5_MODE=demo`.

## Deployment requirement

The bridge must run on a machine where the MetaTrader 5 terminal is installed and connected to a demo account. The cloud SBT service does not install or import the desktop MetaTrader package.

Do not enable the SBT MT5 provider until the bridge has been independently health-checked and `/quote/BTCUSDT` plus `/candles/BTCUSDT?timeframe=M1&limit=100` return real terminal data.
