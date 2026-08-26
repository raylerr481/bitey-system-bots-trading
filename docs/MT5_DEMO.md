# MetaTrader 5 Demo integration

## Goal

Bitey System Bots Trading uses MetaTrader 5 as a first additional execution platform while keeping live trading disabled.

## Architecture

```text
Bitey SBT App
      |
      v
SBT FastAPI backend
      |
      v
MT5 HTTP bridge
      |
      v
MetaTrader 5 terminal
      |
      v
Broker Demo account
```

The main FastAPI backend intentionally does not import the `MetaTrader5` Python package. The MT5 terminal/bridge runs on a machine that supports the MT5 Python integration. The backend communicates with that bridge over HTTP.

## Safety rules

- `MT5_MODE` defaults to `demo`.
- Live execution is not enabled by this milestone.
- Credentials must never be committed to GitHub.
- Store bridge credentials and URLs as environment secrets.
- The bridge should reject any live-account operation while SBT is in the demo/paper milestone.

## Backend endpoints

- `GET /api/v1/mt5/status`
- `GET /api/v1/mt5/account`
- `GET /api/v1/mt5/quote/{symbol}`

`MT5_BRIDGE_URL` must point to the HTTP bridge. If it is not configured, account/quote calls fail closed with HTTP 503.

## Next implementation step

Build the small MT5 bridge process on a Windows machine with MetaTrader 5 installed. It will expose only read-only account/quote operations first. Order submission will be added only after the demo safety tests pass.
