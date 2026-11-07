# Bitey Scalper v1.5.13 — Quote Recovery Pending Analysis

- **Baseline:** `experimental/scalper-v1-5-12-entry-flow-diagnostics`
- **EA:** `Bitey_Scalper_MultiAsset_v1_5_13_QuoteRecoveryPendingAnalysis.mq4`
- **Version:** 1.5.13; MQL4 Market property: 1.513
- **Branch:** `experimental/scalper-v1-5-13-quote-recovery-pending-analysis`

## Purpose

Make quote-recovery behavior explicit and observable while preserving the existing one-evaluation-per-unfinalized-signal-bar design.

## Behavior

1. When a symbol transitions from stale to fresh, inspect its existing `g_pendingBar`.
2. If an unfinalized bar is pending, mark it for recovery diagnostics. The normal scan path retries that same pending bar after quote freshness and series-readiness checks pass.
3. Emit `QUOTE_RECOVERY_PENDING_ANALYSIS` when a pending bar exists, then `QUOTE_RECOVERY_ANALYSIS_RESUMED` when the existing pending bar reaches the ready stage.
4. If no bar is pending, emit `QUOTE_RECOVERY_NO_PENDING_BAR` and wait for the next genuinely new signal-timeframe bar. Do not re-run Analyze on an already finalized bar.
5. If a newer bar supersedes the pending bar, emit `QUOTE_RECOVERY_PENDING_SUPERSEDED` and process only the newer bar.
6. Clear the recovery marker when the bar is finalized.

## Important design finding

The v1.5.12 scanner already preserves transiently rejected bars in `g_pendingBar`; when the quote becomes fresh, the ordinary scan loop retries them. A forced same-bar re-analysis after `NO_NEW_BAR` would duplicate signal evaluation and could create repeated candidates. Therefore v1.5.13 adds explicit recovery-state diagnostics and makes the existing retry path observable; it does **not** force a second evaluation of a finalized bar.

## Preserved invariants

No changes to signal formulas, score floor, family votes, quote freshness threshold (120 seconds), retry backoff, risk sizing, USD 500 reference capital, max five open positions, directional cooldown, progressive selectivity, session/permission filters, adaptive SL/TP, break-even, trailing, net-profit exits, loss management, broker SL/TP, or no-martingale behavior. Recovery diagnostics do not bypass any filter or broker check.

## Expected log sequence

For a quote recovery with an unfinalized pending bar:

```text
QUOTE_FRESHNESS_GATE | state=RECOVERED
QUOTE_RECOVERY_PENDING_ANALYSIS | action=RETRY_EXISTING_UNFINALIZED_BAR
BAR_SCAN_SYMBOL | state=RETRY_PENDING
...
QUOTE_RECOVERY_ANALYSIS_RESUMED | action=RESUME_EXISTING_UNFINALIZED_BAR_NO_DUPLICATE_SIGNAL
BAR_SCAN_SYMBOL | state=RETRY_READY
```

If there is no pending bar:

```text
QUOTE_FRESHNESS_GATE | state=RECOVERED
QUOTE_RECOVERY_NO_PENDING_BAR | action=WAIT_FOR_NEXT_NEW_BAR_NO_SAME_BAR_REEVALUATION
BAR_SCAN_SYMBOL | state=NO_NEW_BAR
```

## Validation status

Source-level checks only. This is not a MetaEditor compilation, Strategy Tester run, backtest, or forward test. Keep the pull request in draft until the user compiles and validates it on demo.
