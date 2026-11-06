# Bitey Scalper v1.5.10 — Series Sync Error Isolation

- **Baseline:** `experimental/scalper-v1-5-9-series-quote-diagnostics`
- **Parent EA:** `Bitey_Scalper_MultiAsset_v1_5_9_SeriesQuoteDiagnostics.mq4`
- **EA:** `Bitey_Scalper_MultiAsset_v1_5_10_SeriesSyncErrorIsolation.mq4`
- **Version:** 1.5.10; MQL4 Market property: 1.510
- **Branch:** `experimental/scalper-v1-5-10-series-sync-error-isolation`

## Purpose

Make the unresolved market-data diagnostics readable and separable. The previous long `MARKET_DATA_SYMBOL` record was truncated in the user's MT4 Journal before its synchronization error fields could be inspected. This release emits short, independent records for quote freshness, series synchronization, bar age, and broker permission/session context.

## Changes

### 1. Isolated synchronization results and errors

- Reset and capture `GetLastError()` independently for the signal timeframe `SeriesInfoInteger` query, higher-timeframe query, and `SymbolInfoInteger(SYMBOL_SELECT)` query.
- Emit one compact `SERIES_SYNC_DIAG` record per symbol with each timeframe, state, and its own error code.
- States are explicit: `QUERY_FAILED`, `KNOWN_UNSYNC`, or `SYNCHRONIZED`.
- A known false result is not conflated with a failed query.
- The existing entry-series guard remains fail-closed. `SYNC_UNKNOWN` continues to reject only new entry analysis for that symbol and leaves the pending bar available for retry.

### 2. Independent quote and history age diagnostics

- `MARKET_DATA_SYMBOL` reports quote state/age, raw tick timestamp, history readiness, and available bar counts.
- `HISTORY_AGE_DIAG` reports signal and higher-timeframe bar ages separately, with `RECENT`, `OLD`, or `NO_BAR_TIME` classifications.
- Bar-age classification is diagnostic only; it does not assert that a market is closed or change the existing stale-bar entry guard.
- The 120-second quote freshness threshold is unchanged.

### 3. Broker permission and session context

- `SYMBOL_PERMISSION_DIAG` reports symbol selection query/result, its error, `MODE_TRADEALLOWED`, price validity, suffix, and session-context label.
- A false trade-permission flag is explicitly not treated as proof that the market is closed.
- For non-crypto instruments, session remains `UNCONFIRMED_NO_RELIABLE_SESSION_SCHEDULE`; the EA does not invent broker trading hours or infer closure from an old tick.
- Crypto session is marked `NOT_APPLICABLE_CRYPTO`.

### 4. Diagnostic output size

- Split one long diagnostic into four short single-argument `Print()` calls so a Journal line-length limit cannot hide synchronization errors behind unrelated fields.
- State-change throttling remains in place; records are emitted when the combined diagnostic state changes.

## Protections and behavior retained

- Quote age maximum remains **120 seconds**.
- Stale quotes continue to skip new entries and EA-managed exit modifications for that symbol; broker-resident SL/TP remain active.
- The fail-closed entry series guard remains unchanged.
- No fallback synchronization bypass is introduced.
- Adaptive SL/TP, break-even, trailing, no-SL-widening, TP extension, net-profit protections, progressive loss management, and progressive analytical selectivity are retained.
- No hard daily entry lock is introduced.
- Maximum five open positions, existing risk caps, spread checks, broker permissions, cooldowns, and no-martingale behavior are retained.
- No signal, scoring, lot-sizing, risk-multiplier, stop, or target logic is intentionally changed.

## Validation status

- Static source checks: version metadata, diagnostic record separation, independent error capture, fail-closed guard, 120-second quote threshold, adaptive exit/loss-protection symbols, and balanced braces/parentheses.
- **Not compiled in MetaEditor; not run in Strategy Tester; not backtested or forward-tested on demo.**
- Keep this pull request in draft until MetaEditor compilation and controlled validation are completed.
