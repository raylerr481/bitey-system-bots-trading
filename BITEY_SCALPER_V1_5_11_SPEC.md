# Bitey Scalper v1.5.11 — MQL4 Series Readiness

- **Baseline:** `experimental/scalper-v1-5-10-series-sync-error-isolation`
- **Parent EA:** `Bitey_Scalper_MultiAsset_v1_5_10_SeriesSyncErrorIsolation.mq4`
- **EA:** `Bitey_Scalper_MultiAsset_v1_5_11_MQL4SeriesReadiness.mq4`
- **Version:** 1.5.11; MQL4 Market property: 1.511
- **Branch:** `experimental/scalper-v1-5-11-mql4-series-readiness`

## Purpose
Correct the invalid use of an MQL5-only series synchronization property. Both the entry guard and diagnostics now use MQL4-supported bar-count and bar-time functions.

## Changes
1. Removed all `SeriesInfoInteger` synchronization-property calls.
2. Signal readiness requires at least `InpMinBars`, valid current/previous bar times, and strictly chronological timestamps.
3. HTF readiness remains mandatory whenever the HTF filter or elevated selectivity requires it: 52 bars normally, 202 bars at selectivity level 3, plus valid chronological current/previous timestamps.
4. Fail-closed entry behavior and pending-bar retry remain in place when history is insufficient or unreadable.
5. Replaced the old synchronization diagnostic with `SERIES_READINESS_DIAG`, including separate bar-count/time error codes.
6. Existing stale-bar threshold (two timeframe periods when quote is fresh) and 120-second quote freshness remain unchanged.

## Protections retained
- Broker-resident SL/TP remain active independently of EA history checks.
- Stale quotes continue to skip new entries and EA-managed exit modifications for that symbol; broker SL/TP remain active.
- Adaptive SL/TP, break-even, trailing, no-SL-widening, adaptive TP extension, net-profit/giveback protections, progressive loss management, and progressive analytical selectivity are retained.
- No hard daily entry lock; maximum five open positions; existing risk caps, spread checks, broker permissions, cooldowns, and no-martingale behavior remain.
- No intentional signal, scoring, lot-sizing, risk multiplier, stop/target formula, or position-limit changes.

## Validation
Static source checks only: version metadata, unsupported API removal, bar-count/time guard, 52/202 HTF thresholds, 120-second quote threshold, and balanced braces/parentheses.
**Not compiled in MetaEditor; not run in Strategy Tester; not backtested or forward-tested.** Keep this PR in draft pending user compilation and controlled demo validation.
