# Bitey Scalper v1.5.6 — Payoff, Daily Risk and Execution Diagnostics

Baseline: experimental/scalper-v1-5-4-10-execution-diagnostics
Parent EA: Bitey_Scalper_MultiAsset_v1_5_4_10_ExecutionDiagnostics.mq4
EA: Bitey_Scalper_MultiAsset_v1_5_6_PayoffRiskDiagnostics.mq4
Version: 1.5.6; MQL4 Market property: 1.560

Defaults:
- Net giveback 40% from peak net, activated only after peak net reaches +0.85R.
- InpIncludeEstimatedCloseCommission=false by default. Executable-side Bid/Ask reflects spread; booked commission and swap remain included. Enable and configure InpEstimatedCloseCommissionPerLot if a separate close commission applies.
- Small-profit close target max(USD 0.10, 0.80R), subject to existing progression condition.
- Reward/risk 2.0; hard spread ceiling 10% of stop distance; minimum entry score 15.
- New-entry lock until next MT4 server day after three consecutive net losing closed trades or daily net (closed plus floating) reaches -2% of reference capital. Open positions are not forcibly closed and remain managed.
- Detailed diagnostics throttled per symbol/event (60 seconds default); suppressed count logged. Minimum-lot rejection includes budget, risk distance, applied risk factor, loss per lot and minimum-lot loss.
- Audit CSV name updated to v1.5.6.

Preserved: v1.5.4.10 signals, multi-symbol scan, BUY/SELL, max five positions, adaptive loss risk scaling, cooldown, quote freshness, broker permission handling, adaptive SL/TP, break-even/trailing/TP extension, no SL widening and open-position management.

Daily threshold uses InpReferenceCapitalUSD (default USD 500; -2% = -USD 10) and TodayNet(), including current-day closed and floating P/L for this EA magic number. Lock persists through terminal/EA restarts using MT4 GlobalVariables and clears on next server day. Consecutive-loss streak uses closed EA trades for the current server day.

Validation: source-level patch/static checks only. Not compiled in MetaEditor, not run in Strategy Tester, and not forward-tested.