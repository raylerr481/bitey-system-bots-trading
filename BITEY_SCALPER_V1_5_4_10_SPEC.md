# Bitey Scalper v1.5.4.10 — Execution Diagnostics

## Base
- Parent: `experimental/scalper-v1-5-4-9-net-giveback-50-fix`
- EA: `Bitey_Scalper_MultiAsset_v1_5_4_10_ExecutionDiagnostics.mq4`
- Version: 1.5.4.10
- Purpose: improve observability of entry preflight and broker OrderSend failures. This is a diagnostic-only code change; it does not change trading decisions, sizing, exits, or protections.

## Preserved behavior
- Existing v1.5.4.9 signal families, ranking and entry filters.
- Adaptive SL/TP; SL is never widened.
- Existing break-even, trailing, TP extension and 50% net peak-giveback protection.
- Existing progressive/rolling loss management, cooldown and open-exposure controls.
- Reference capital and risk settings, maximum five open positions.
- Daily loss remains warning/reporting only; no automatic daily entry lockout.
- Existing quote freshness and broker-133 handling.

## New diagnostics
When `InpEnableDetailedExecutionDiagnostics=true`, rejected entry paths emit `EXECUTION_DIAGNOSTIC` with:
- Event classification: stale/invalid data, spread preflight, invalid stops, aggregate risk, minimum lot, currency risk, trade permission, or broker send failure.
- Symbol contract properties: min/max lot, lot step, stop/freeze levels, tick value/size, margin required.
- Current market/permission context: bid, ask, spread points, quote age, symbol/terminal/EA permission, trade-context busy state.
- Requested order details: side, lots, entry, SL and TP.
- For failed `OrderSend()`, the captured error code and description are logged immediately after the call.

`ORDER_SEND_FAILED` specifically means the EA called `OrderSend()` and the broker/API returned a negative ticket. Preflight failures are explicitly marked `PREFLIGHT_...` and must not be interpreted as broker rejections. `ORDER_ACCEPTED` remains the positive acknowledgement.

## Validation status
Static source checks only. This version has not been compiled in MetaEditor and has not been run through MT4 Strategy Tester or forward demo. Compile and test before enabling live execution.
