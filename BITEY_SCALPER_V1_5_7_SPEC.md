# Bitey Scalper v1.5.7 — Progressive Analytical Selectivity

Baseline: experimental/scalper-v1-5-6-payoff-risk-diagnostics  
Parent EA: Bitey_Scalper_MultiAsset_v1_5_6_PayoffRiskDiagnostics.mq4  
EA: Bitey_Scalper_MultiAsset_v1_5_7_ProgressiveAnalyticalSelectivity.mq4  
Version: 1.5.7; MQL4 Market property: 1.570

## Core behavior
- Preserve v1.5.6 adaptive SL/TP, TP extension, break-even, trailing, net-profit giveback protection, small-profit close, progressive loss exits, quote freshness, execution diagnostics, risk accounting, multi-symbol scanning and existing signal families.
- Never widen an SL. Existing open positions remain under normal exit management at every analytical-selectivity level.
- The daily loss threshold no longer latches a full-day entry lock. It raises analytical selectivity and reduces new-entry risk. New entries remain possible only when all active filters and risk checks pass.
- Three consecutive net losing closed trades escalate selectivity to Level 2; four or more escalate to Level 3. Two consecutive losses trigger at least Level 1.

## Selectivity levels
| Level | Trigger (reference capital USD 500) | Score floor | Additional behavior |
|---|---|---:|---|
| 0 | Stable | 15 | Existing filters |
| 1 | Daily net loss >= 1% or >= 2 consecutive losses | 20 | Reduce new-entry risk to 0.75x; tighten hard spread; higher ADX |
| 2 | Daily net loss >= 2% or >= 3 consecutive losses | 25 | 0.50x risk; require closed HTF price alignment with EMA50 |
| 3 | Daily net loss >= 3% or >= 4 consecutive losses | 30 | 0.25x risk; require HTF EMA50/100/200 directional alignment and stricter ADX/spread |

Loss percentage is calculated from TodayNet(), which includes current-day closed P/L and current floating P/L for this EA magic. The level escalates immediately. It recovers only one level after 1,200 stable evaluation cycles (approximately 20 minutes at the one-second cycle cadence); a single winning trade does not immediately restore normal selectivity. State diagnostics are throttled to 60 seconds.

## Risk and execution
- Risk multipliers are applied as an additional ceiling on the existing adaptive loss and open-exposure risk multipliers; never increase base risk.
- Aggregate risk cap, per-currency risk cap, broker minimum-lot checks, spread ceiling, permission checks and maximum five positions remain active.
- Existing three-consecutive-loss rule is an escalation trigger, not a hard entry lock.
- If no candidate passes the stricter analytical filters, no trade is opened. This is selectivity, not a blanket pause.

## Adaptive exits preserved
- Reward/risk 2.0; adaptive stop based on ATR; adaptive TP and confirmed TP extension remain unchanged.
- Break-even, trailing, no-SL-widening, retracement exits, progressive loss exits and small-profit close remain unchanged.
- Net giveback 40% after qualifying peak net profit reaches 0.85R.
- Small-profit close max(USD 0.10, 0.80R), subject to original progression and cost-validity guards.
- Existing stale-quote behavior remains: do not calculate/modify EA exits from stale prices; broker-resident SL/TP remain active and management resumes after quote recovery.

## Rejected-candidate audit
- Log symbol, side, observed score, required score, selectivity level and rejection reason.
- Rejected opportunities are explicitly marked as not executed; this build does not yet assign hypothetical P/L or future price outcomes to rejected candidates.

## Default parameters carried forward
- Reference capital USD 500; daily loss reference 2%.
- Reward/risk 2.0; hard spread ceiling 10% of stop distance; normal minimum score 15.
- Giveback 40% after +0.85R; small-profit close max(USD 0.10, 0.80R).
- Maximum five positions; no martingale; no lot multiplication.
- Estimated close commission inclusion remains off by default; booked commission/swap remain included and executable Bid/Ask reflects spread.

## Validation status
Source-level implementation and static checks only. Not compiled in MetaEditor, not run in Strategy Tester, and not forward-tested. Keep the pull request in draft until MetaEditor reports zero errors/warnings and demo/backtest comparisons are reviewed.
