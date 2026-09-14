# MT5 Demo Bridge

Read-only local bridge between a Windows MetaTrader 5 Demo terminal and SBT.

## Safety boundary

- Demo/read-only data only.
- `live_trading_enabled` is always `false`.
- No order, position modification, withdrawal, or trading endpoint is exposed.
- Do not expose this bridge directly to the public internet without authentication and a secure tunnel.

## Requirements

- Windows machine with MetaTrader 5 installed.
- MetaTrader 5 terminal running and connected to a Demo account.
- Python 3.11+.

## Run

```powershell
cd tools/mt5-demo-bridge
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app:app --host 127.0.0.1 --port 8787
```

## Endpoints

- `GET /health`
- `GET /quote/{symbol}`
- `GET /candles/{symbol}?timeframe=M1&limit=100`

The bridge returns real data from the local MT5 terminal and never fabricates market prices.

SBT should only be configured with `SBT_MARKET_PROVIDER=mt5` and `MT5_BRIDGE_URL` after the bridge has been tested successfully with `/health` and at least 35 valid BTCUSDT M1 candles.
