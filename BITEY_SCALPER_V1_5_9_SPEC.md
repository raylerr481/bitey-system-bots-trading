# Bitey Scalper v1.5.9 — Series & Quote Diagnostics

- **Baseline:** `experimental/scalper-v1-5-8-series-sync-entry-guard`
- **Parent EA:** `Bitey_Scalper_MultiAsset_v1_5_8_SeriesSyncEntryGuard.mq4`
- **EA:** `Bitey_Scalper_MultiAsset_v1_5_9_SeriesQuoteDiagnostics.mq4`
- **Version:** 1.5.9; MQL4 Market property: 1.590
- **Branch:** `experimental/scalper-v1-5-9-series-quote-diagnostics`

## Purpose

Resolve diagnostic ambiguity observed in the v1.5.8 Journal without weakening entry or execution protections. This release makes quote-age reporting consistent, identifies the symbol responsible for the oldest observed quote, and distinguishes a failed series-status query from a successful query that reports an unsynchronized series.

## Changes

### 1. One quote-age calculation in scan diagnostics
- `BAR_SCAN_SYMBOL` now uses the same `QuoteAgeSeconds()` monotonic/server-anchored calculation as the stale-quote gate.
- The log also includes raw `MODE_TIME` (`quoteTickTime`) and labels the age source as `SERVER_ANCHORED_MONOTONIC`.
- This removes the previous diagnostic mismatch where bar-scan output used a fresh raw server-time subtraction while the actual gate used the monotonic quote-age tracker.
- It does not change the stale threshold or gate behavior.

### 2. Identify the oldest quote by symbol
- `MARKET_DATA_DIAGNOSTICS` now reports `oldestSymbol`, `oldestTickTime`, and `oldestRawServerAgeSec` alongside `oldestObservedAgeSec`.
- The scan still counts fresh, stale, missing and never-refreshed quotes.
- This exposes the exact instrument behind extreme ages instead of reporting only a universe-wide number.

### 3. Series synchronization diagnostics
- The diagnostic calls to `SeriesInfoInteger(..., SERIES_SYNCHRONIZED, ...)` now reset and capture `GetLastError()` independently for signal and higher timeframes.
- `MARKET_DATA_SYMBOL` includes both query error codes.
- Its state signature distinguishes `SYNC_UNKNOWN` (query failed) from a known result of synchronized or not synchronized. A failed query is no longer collapsed into the same diagnostic state as a known false result.
- The entry guard remains fail-closed: query failure is still `SYNC_UNKNOWN` and blocks only new entry analysis for that symbol while leaving the bar pending for retry.
- No fallback bypass was added. A usable `iBars/iTime` history does not, by itself, override an unknown synchronization result.

### 4. Bar-age interpretation
- The v1.5.8 signal-bar stale check remains in place: with a fresh quote, a signal bar older than twice its timeframe duration is rejected for new entries and retried.
- No universal 900-second M15 cutoff was introduced. A bar age just over one timeframe is diagnostic evidence, not by itself proof of corrupt history.
- The higher-timeframe series must still pass the synchronization and history checks whenever the HTF filter or Level 2/3 selectivity requires it.

## Protections retained from v1.5.8

- Quote age maximum remains **120 seconds**.
- At stale age, skip new entries and EA-managed exit modifications for that symbol; broker-resident SL/TP remain active.
- `ManageExits()` remains ahead of the per-symbol entry scan and is not gated by another symbol's series readiness.
- Adaptive SL/TP, break-even, trailing, no-SL-widening, TP extension, net-profit giveback, small-profit and progressive loss exits remain inherited and unchanged by this diagnostic patch.
- Progressive analytical selectivity remains active; daily loss does not impose a blanket hard entry lock.
- Maximum five open positions, existing risk caps, spread checks, broker permissions, cooldowns and no-martingale behavior remain inherited.
- No risk multiplier, lot sizing, signal family, entry score, stop or target parameter was intentionally changed.

## Validation status

- Source-level static assertions passed for version metadata, unified quote-age logging, oldest-symbol identification, series-query error reporting, distinction between unknown and false synchronization, retained fail-closed entry guard, and retained 120-second quote threshold.
- These are source checks only. **Not compiled in MetaEditor; not run in Strategy Tester; not backtested or forward-tested on demo.**
- Keep this pull request in draft until MetaEditor compilation and controlled demo/backtest validation are completed.
