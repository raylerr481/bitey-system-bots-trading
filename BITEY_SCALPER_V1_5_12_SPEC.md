# Bitey Scalper v1.5.12 — Entry Flow Diagnostics

- **Baseline:** `experimental/scalper-v1-5-11-mql4-series-readiness`
- **EA:** `Bitey_Scalper_MultiAsset_v1_5_12_EntryFlowDiagnostics.mq4`
- **Version:** 1.5.12; MQL4 Market property: 1.512
- **Branch:** `experimental/scalper-v1-5-12-entry-flow-diagnostics`

## Purpose

Make the path from a newly detected M15 bar through prefilter, signal analysis, scoring, candidate queue, execution preflight, and broker order submission observable. Clarify MQL4 history-update error 4066 without treating valid bar counts/timestamps as a synchronization guarantee.

## Changes

1. Add `InpEnableEntryFlowDiagnostics=true` to report entry decisions independently of the legacy `InpLogRejects` setting.
2. Emit `ENTRY_FILTER` for prefilter and signal-analysis rejects, directional cooldown/permission filters, HTF selectivity, and score decisions.
3. Emit `ENTRY_CANDIDATE` when a BUY/SELL signal is generated and again when it is queued for execution.
4. Emit `ENTRY_EXECUTION_ATTEMPT` and `ENTRY_EXECUTION_RESULT` around the existing execution preflight.
5. Emit `ORDER_SEND` request/result events around the actual MQL4 `OrderSend()` call; existing detailed broker diagnostics remain.
6. Classify MQL4 error 4066 as `HISTORY_UPDATE_PENDING`. When bar count and timestamps are valid but an error code is present, log `ENTRY_SERIES_NOTICE`; do not mislabel the valid snapshot as an API failure and do not change the existing fail-closed behavior for missing/invalid bars.
7. Add error-name fields to `SERIES_READINESS_DIAG` and a five-minute `ENTRY_FLOW_DIAGNOSTICS` summary. Existing `SCAN_CYCLE_SUMMARY` and dashboard counters remain.

## Bar-scan behavior confirmed by source inspection

- The EA evaluates entries on a newly detected signal-timeframe bar, not continuously on every tick.
- `INITIAL_BASELINE` intentionally records an already-existing bar and does not evaluate it as a new bar.
- `NO_NEW_BAR` means the current bar timestamp has not changed; it is not an entry rejection.
- A fresh quote and valid history are prerequisites, not proof that a BUY/SELL setup exists.

## Protections and strategy invariants

No intentional changes to signal formulas, family votes, minimum score (15 at level 0), session filters, quote-age limit (120 seconds), risk sizing, reference capital, max five positions, cooldowns, adaptive SL/TP, break-even, trailing, net-profit protections, loss management, progressive selectivity, broker permissions, or no-martingale behavior. Broker-resident SL/TP remain independent of the new-entry diagnostics.

## Validation status

Static source transformation checks: all expected replacements applied exactly once; no `SERIES_SYNCHRONIZED` references; braces and parentheses balanced. This is not a MetaEditor compilation, Strategy Tester run, backtest, or forward test. Keep the PR in draft until the user compiles and performs controlled demo validation.
