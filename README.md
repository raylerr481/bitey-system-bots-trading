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

---

# Bitey SBT — EA architecture and integration contract

**Scope:** experimental MT4 multi-asset EA. This section defines the intended integration contract for the 30-evaluator / two-assembly architecture and its audit trail. A README specification is not proof that every behavior has passed MetaEditor compilation or MT4 Strategy Tester validation. Keep changes on the experimental branch until those checks pass.

## 1. Portfolio and execution rules

- **Multi-asset universe, maximum five active positions/assets at a time.** The EA may scan a larger broker-supported symbol universe, but it must not exceed five simultaneous managed positions. Apply the limit to canonical assets after alias normalization, not just raw broker symbol strings.
- **One managed position per canonical asset.** A BUY and a SELL on aliases of the same underlying asset must not create duplicate exposure. Re-check the rule immediately before sending an order.
- **Multi-directional:** both BUY and SELL are allowed when their respective evaluation and risk checks pass. Do not force a trade, reverse a position merely to free a slot, or assume both directions are equally valid in every regime.
- **Candidate selection is separate from execution permission.** A high score is not authorization to trade. Every candidate must pass market-data freshness, symbol/trading availability, spread and estimated costs, lot-step/min/max, valid protective SL, per-trade risk, aggregate risk, daily-loss gate, active-position cap and duplicate-asset checks.
- **No risk bypass:** effective reference capital is USD 500 unless an explicitly reviewed specification changes it. Respect configured risk ceilings, broker restrictions, and terminal AutoTrading settings. No martingale, no loss-recovery lot escalation, and no entry solely to fill capacity.
- **Maximum five is a hard ceiling.** The configured InpMaxOpenPositions must be clamped to 1–5; available capacity is not a target.

## 2. Thirty evaluators and two assemblies

The architecture has two separate decision stages. They must not be collapsed into one opaque score:

1. **Assembly A — Asset/opportunity selection.** Collect the 30 evaluator outputs for each eligible symbol and decision bar. Record model identity, family, timeframe, direction, raw score, weight, confidence, validity and rejection reason. Compare candidates using expected net opportunity after estimated spread, commission and slippage, market regime and risk constraints. Select no more than the available slots, with a hard portfolio cap of five.
2. **Assembly B — Trade/direction decision.** For each selected candidate, aggregate supporting and opposing evidence, decide BUY / SELL / ABSTAIN, and record consensus, confidence, supporting/opposing evaluator counts, estimated costs and the reason for approval or rejection. Assembly B cannot override the risk gate or an invalid/stale quote.

**Decision identity and traceability**

- Generate one stable decision_id per canonical asset and closed signal bar. Reuse that ID through evaluator votes, both assembly records, entry/rejection, order ticket and close.
- Persist EA version, magic number, canonical symbol, broker symbol, timeframe, direction and timestamp.
- Keep all 30 evaluator records, including invalid, neutral, opposing and abstaining votes. Do not log only the winning models.
- Distinguish CANDIDATE, SELECTED, APPROVED, ORDER_SENT, ORDER_FAILED, REJECTED, CLOSED and ABSTAIN; never label a requested order or SL/TP modification successful until MT4 confirms it.
- If the source does not emit 30 identifiable evaluator rows and both assembly records for a decision, treat the run as **audit-incomplete** rather than inferring missing votes.

## 3. Adaptive SL/TP tied to net profit

Adaptive management is for protecting or extending a favorable move, not for allowing a losing trade more room.

- Compute ticket net floating P/L as OrderProfit + OrderSwap + OrderCommission.
- Do not make adaptive SL/TP changes while ticket net floating P/L is zero or negative. A separate emergency risk-control exit, if implemented, is not an adaptive SL/TP modification.
- Require at least **three consecutive favorable candles that have closed** on the configured confirmation timeframe. Never count the currently forming candle. The candles must confirm the move in the position direction.
- **BUY:** an approved adaptive SL can only move upward; TP can only extend upward after favorable confirmation.
- **SELL:** an approved adaptive SL can only move downward; TP can only extend downward after favorable confirmation.
- **Never loosen SL, increase the permitted loss, or remove a protective SL.** A TP change must be in the favorable direction; do not move TP farther away just to avoid taking a loss.
- Enforce broker stop/freeze levels, tick size and price precision; require a meaningful minimum change and per-ticket cooldown to avoid modification spam.
- After OrderModify, re-select/read the ticket. Log requested SL/TP, return value/error and actual read-back SL/TP. Only mark the change confirmed if read-back matches the intended levels. Failed or unconfirmed changes remain failures/deferred events in the audit.
- A positive P/L snapshot alone is insufficient: net profit, three closed favorable candles, directional confirmation and broker validity must all pass.

## 4. CSV audit contract

Write semicolon-delimited CSV files in the MT4 terminal's MQL4/Files directory unless a reviewed deployment configuration explicitly chooses another folder. Each file must have a stable header, timestamp, EA version, and the appropriate decision_id/ticket keys. Do not silently reuse an old schema after changing columns; version the filename or migrate the schema deliberately.

| CSV | Required audit purpose |
|---|---|
| Bitey_ActionLog.csv | Candidate lifecycle, selection, abstention, filter/risk rejection, order-send result and explicit reason/error |
| Bitey_EvaluatorVotes.csv | One row per evaluator and decision, including all 30 models, valid/invalid/neutral/opposing votes and reason |
| Bitey_AssetAssembly.csv | Assembly A scores, expected-net estimate, costs, valid-model count, BUY/SELL votes, selected flag and reason |
| Bitey_TradeAssembly.csv | Assembly B direction/abstention, consensus, confidence, supporting/opposing models, costs, approval and reason |
| Bitey_TradeAudit_v1_8_0_1.csv | Entry ticket, magic, decision_id, symbol, direction, lots, open price, initial SL/TP, reference capital and risk estimate |
| Bitey_ClosedTrades_v1_8_0_1.csv | One closure per ticket, linked decision and magic, open/close timestamps and prices, duration, gross P/L, commission, swap and net P/L |
| Bitey_AdaptiveExits.csv | Old/requested SL/TP, ticket net P/L, confirmation reason, modification outcome and read-back verification |
| Bitey_Performance.csv | Per-symbol/portfolio closed-trade metrics, gross, commission, swap, net, profit factor, drawdown, expectancy and abstentions |
| Net-by-asset summary CSV | Reconciliation reference for close count and gross/commission/swap/net totals by canonical asset and in total |

**Required operational behavior**

- Flush and close CSV handles after each record; check file-open/write errors and emit an MT4 Journal error when logging fails.
- Closure logging must be idempotent by ticket. Scan all available history entries, not an arbitrary fixed number such as the most recent 60. Do not mark a closure logged if its CSV write failed; retry on a later pass.
- On restart, reconcile persisted ticket records with MT4 history before appending. Detect duplicate tickets and missing/unmatched closure rows; do not silently deduplicate by deleting evidence.
- Every order attempt must have an outcome: confirmed ticket, OrderSend failure with error code, or a pre-trade rejection with stage and reason.
- Log each requested and confirmed SL/TP modification separately. Preserve failed attempts and mismatches.
- Keep audit records for **all** candidates, not only executed trades. Record why a candidate was rejected, why an evaluator abstained, and why either assembly declined to select/approve it.
- Do not add gross profit alone and call it net. Reconciliation uses net = gross + commission + swap for each close and compares per-asset and total sums within a documented rounding tolerance.
- Preserve source CSVs as evidence. Do not rewrite historic rows to make summaries match.

## 5. Release and acceptance checklist

Before considering a build ready:

1. Compile the exact MQ4 file in MetaEditor and resolve all compiler errors/warnings that affect behavior.
2. In Strategy Tester/demo, prove that no more than five canonical assets are active simultaneously, including alias and opposite-direction cases.
3. Verify 30 unique evaluator IDs per eligible decision and both assembly records linked by the same decision_id.
4. Test BUY and SELL, ABSTAIN, zero/negative/positive net P/L, three favorable closed candles, rejected OrderModify, invalid stops and terminal/broker order rejection.
5. Restart the EA and prove that older pending history closures are eventually logged once, with no duplicate ticket.
6. Run python tests/audit_integrity_check.py and the regression tests; tests must fail on duplicate tickets and on per-asset/total net mismatches.
7. Reconcile closure CSV against the net-by-asset summary, including gross, commission, swap and net. Investigate every mismatch.
8. Verify that risk inputs, entry conditions and SL/TP calculation are unchanged by audit-only patches. Keep production untouched until sign-off.

**Status note:** this architecture is a specification and test contract. The Python CSV checker tests audit exports; it does not compile the MQ4 EA or prove profitability. Do not promote this experimental build to production until the MQ4 and MT4 checks above are completed.



## v1.8.0.2 — experimental audit-integrity improvement

Source: `Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_2_AuditIntegrityImprovedExperimental.mq4`

- Uses version-isolated `Bitey_TradeAudit_v1_8_0_2.csv` and `Bitey_ClosedTrades_v1_8_0_2.csv` files so the previous v1.8.0.1 schema is not mixed with the corrected schema.
- Aligns the closed-trade CSV header with the actual 21-column writer, including magic number and aggregated BUY/SELL votes.
- Writes an explicit audit action for dry-run candidates and richer context when `OrderSend` fails.
- Records requested entry price and computes observed entry slippage in points from the actual fill; `-1` means the requested-price evidence is unavailable, not zero slippage.
- Marks a closed ticket as logged only after the audit write succeeds; subsequent scans can retry a failed write, while CSV ticket deduplication prevents repeated rows.
- Adds Python regression checks for version, position ceiling, header agreement, dry-run/failure evidence, retry order and slippage sentinel; CI runs the CSV and source-contract tests.

**Scope guard:** this is an experimental audit improvement. It intentionally does not change entry signals, risk inputs, SL/TP parameters, account-mode behavior, or the production branch. Automated source-contract tests do not replace MetaEditor compilation, MT4 Strategy Tester validation, or demo forward testing.
