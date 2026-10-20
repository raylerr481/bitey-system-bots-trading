# MT4 MCP Gateway

Local bridge architecture for the Turtle Trading project:

`MetaTrader 4 -> MT4 Bridge EA -> FILE_COMMON -> Local MCP Gateway -> Bitey/SBT`

## Components

- `Turtle_Trading_EA_v1_23_MCP_READY.mq4`: Turtle v1.23 with common-file audit and state export.
- `Turtle_MT4_MCP_Bridge.mq4`: read-only account/positions/market/history exporter.
- `mt4_mcp_gateway.py`: local MCP-style JSON-RPC server over stdio.
- `mt4_mcp_config.example.json`: Windows path template.

## Safety

The gateway is **read-only by default**. Compilation, deployment and Strategy Tester launch require `read_only=false` in the config. The parameter tool only writes a review patch and does not change a running EA.

No live order-placement tool is included in v0.1.

## MT4 setup

1. Compile and attach `Turtle_Trading_EA_v1_23_MCP_READY.mq4` to the test chart.
2. Compile and attach `Turtle_MT4_MCP_Bridge.mq4` to one chart in the same terminal.
3. Keep `InpAllowCommands=false`.
4. The bridge writes `MT4_MCP_state.json` into MT4's Common\Files directory.
5. The Turtle EA writes its audit CSV into the same Common\Files directory.

## Gateway setup

Copy `mt4_mcp_config.example.json` to `mt4_mcp_config.json` and adjust paths if necessary.

Run:

`python mt4_mcp_gateway.py`

The process uses MCP-style stdio framing and exposes:

- `get_account_status`
- `get_open_positions`
- `get_market_data`
- `get_trade_history`
- `get_turtle_audit`
- `change_ea_parameter`
- `compile_ea`
- `deploy_ea`
- `run_backtest`

## Next stage

After the read-only path is verified, add a separate reviewed command layer for controlled tester automation. Live trading commands should remain disabled until explicitly designed and tested.
