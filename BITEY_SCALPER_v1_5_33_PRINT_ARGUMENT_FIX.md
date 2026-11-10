# Bitey Scalper v1.5.33 — Print Argument Fix

## Branch
`experimental/scalper-v1-5-33-print-argument-fix`

## EA
`Bitey_Scalper_MultiAsset_v1_5_33_PrintArgumentFixIntradayPerformanceManager.mq4`

## Change
The oversized `QUOTE_STATUS_DIAGNOSTIC` Print call was split into two independent Print calls:
- `QUOTE_STATUS_DIAGNOSTIC`: quote freshness, timestamp peer, and broker-session diagnostic fields.
- `QUOTE_STATUS_DIAGNOSTIC_DETAIL`: server/local/GMT time deltas, quote prices, trade permission, stale flag, retry timer, and diagnostic action.

This avoids the MQL4 Print argument-count limit that produced `Print - wrong parameters count`. The previous v1.5.32 string-literal syntax fix remains included.

## Preserved behavior
No entry filters, signal logic, order execution, risk sizing, SL/TP management, intraday calculations, or protection policies were changed. The two log records remain diagnostic-only.

## Validation status
- GitHub source updated and new branch created from v1.5.32.
- Static inspection confirms the diagnostic output is split into two Print calls.
- MetaEditor compilation and MT4 runtime/backtest have not been executed here. Do not treat this version as compile-verified until the user compiles it in MetaEditor.
