# Bitey SBT MCP Server

Bitey SBT exposes a protected MCP server through the same FastAPI service.

## Production endpoint

- SBT API: `https://bitey-system-bots-trading-api.onrender.com`
- MCP Streamable HTTP: `https://bitey-system-bots-trading-api.onrender.com/mcp`
- Web application: `https://bitey-system-bots-trading.raylerr481.workers.dev/`

The MCP server uses the official MCP Python SDK v2 and Streamable HTTP. The SDK's current v2 line is based on the 2026-07-28 MCP specification and supports modern and legacy clients.

## Current tools

- `sbt_system_status`
- `list_trading_platforms`
- `list_sbt_permissions`
- `create_connection_plan`
- `risk_gate_status`
- `mt5_status`
- `mt5_quote`

These tools are intentionally read/control-plan oriented. No tool exposes broker credentials to the AI and no tool can enable live trading.

## Execution boundary

```text
AI client
   |
   | MCP
   v
Bitey SBT MCP
   |
   +--> permissions
   +--> platform connector
   +--> deterministic Risk Gate
   |
   +--> MT5 read-only bridge / TradingView connector / Alpaca paper
```

The AI can request a tool. SBT remains authoritative over permissions, mode and risk. Live money remains locked.

## Authentication

The current server uses a fail-closed bearer gate controlled by `SBT_MCP_TOKEN`. If the variable is missing, MCP returns `503` rather than accepting unauthenticated tool calls.

Do not place broker/API credentials in MCP tool arguments. The long-term user-facing flow should issue a revocable per-user MCP credential after SBT authentication instead of sharing a global token.

## Client example

For a compatible MCP client, the Streamable HTTP URL is:

```text
https://bitey-system-bots-trading-api.onrender.com/mcp
```

The client must send the SBT MCP bearer token. The token is separate from MetaTrader, TradingView and broker credentials.

## Safety status

- Demo: allowed where the selected connector supports it.
- Paper: allowed where the selected connector supports it.
- Live: disabled.
- Emergency stop: required for future automation.
- Fail closed: required when mandatory safety dependencies are unavailable.
