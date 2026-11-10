# Bitey Scalper v1.5.31 — Intraday Performance Manager

Branch: `experimental/scalper-v1-5-31-intraday-performance-manager`

Base: `experimental/scalper-v1-5-30-market-session-aware-quote-recovery`

## Objective

Continuously pursue a positive net daily result: cumulative net gains should exceed cumulative net losses, while preserving open-ended upside. This is an optimization objective, not a profit guarantee or a reason to force trades.

The manager evaluates the MT4 server day and publishes a live global balance plus a 24-hour close-time scorecard.

## New live monitoring

Default cadence: 60 seconds (minimum 15 seconds).

CSV: `Bitey_Intraday_Performance_v1_5_31_<account>_<magic>.csv`

Rows:
- `GLOBAL`: closed wins/losses, net realized P/L, floating P/L, live combined P/L, open position count, objective and remaining realized objective.
- `HOUR`: closed trades attributed to the MT4 server hour in which each trade closed, hourly win/loss counts, hourly net and cumulative realized net through that hour. The current server hour is emitted even if no trade has closed in it.

All trade net values use `OrderProfit()+OrderSwap()+OrderCommission()`. Floating P/L is kept separate from realized P/L and is included only in `live_combined_net`. The daily objective remaining is based on realized P/L; an open floating profit is not treated as banked profit. Existing cumulative objective carry is reflected in the objective field when its ledger is initialized.

## Management policy selected

Daily P/L state is a soft risk-sizing controller, not a new entry filter:
- Existing daily levels continue to scale new-entry risk by their configured factors (default 1.00 / 0.75 / 0.50 / 0.25).
- Daily P/L levels no longer add score-floor points, an extra HTF hard rejection, extra ADX requirements, or a tighter hard spread ceiling. The separate daily-sample quality flag also no longer adds an extra score-floor penalty.
- Existing base signal quality, quote freshness, broker permission, spread, exposure, aggregate-risk, stop validity and independent rolling-loss safeguards remain in force.
- No daily hard entry lock, no forced entry, no lot/risk increase to catch up, no filter relaxation, no daily profit cap and no automatic close of profitable positions to hit the objective.
- The existing multi-family signal engine and candidate quality ranking remain in place. This version does not invent or hot-swap untested strategy families; strategy-level attribution is a separate evidence task.

## Interpretation

A green day is not a reason to increase risk. A red hour is not a reason to stop the EA. A loss streak or deteriorating daily net can reduce the size of future entries through the existing graduated risk multiplier, but must not erase the base opportunity set. Genuine broker, quote, spread, stop, exposure and rolling-loss safety checks remain active.

A positive win count alone is insufficient: net P/L, average payoff, profit factor and transaction costs matter. Conversely, one or two losses do not prove that an asset or strategy has stopped working. Hourly labels are descriptive; they are not statistical proof when the sample is small.

## Verification status and test plan

This GitHub source has not been compiled or backtested in MetaEditor/MT4 as part of this change.

Required before any live deployment:
1. Compile in the exact MT4 build used by the broker.
2. Confirm the CSV header and row field counts in MT4, and verify file writes/flushes over multiple hours.
3. Reconcile GLOBAL realized P/L against MT4 history for the EA magic number, including commission and swap.
4. Reconcile floating P/L against open EA positions and ensure it is not double-counted in realized P/L.
5. Verify hourly buckets use broker server close time, including midnight rollover.
6. Verify the cumulative daily target carry agrees with the existing ledger and that floating P/L does not prematurely credit the objective.
7. Diff entry prefilters: daily selectivity level must affect only risk sizing, while the base score and independent safety/rolling-loss checks remain intact.
8. Run demo forward tests across profitable, losing, low-sample, spread-widening, stale-quote and overnight-session periods. Compare candidate counts and reject reasons against v1.5.30.

## Research basis

- CME Group, Risk Management and Your Trade Plan: define risk per trade, total exposure and daily risk boundaries.
  https://www.cmegroup.com/education/courses/building-a-trade-plan/risk-management-and-your-trade-plan
- FINRA, Frequent Intraday Trading: costs, margin and the risks of frequent trading.
  https://syndication.finra.org/content/frequent-intraday-trading-understanding-basics
- FINRA, 3 Ways to Guard Against Excessive Trading: evaluate rationale, transaction costs and break-even cost burden.
  https://syndication.finra.org/content/3-ways-guard-against-excessive-trading-your-brokerage-account
- FIA, Best Practices for Automated Trading Risk Controls and System Safeguards: pre-trade controls complemented by post-trade monitoring.
  https://www.fia.org/sites/default/files/2024-07/FIA_WP_AUTOMATED%20TRADING%20RISK%20CONTROLS_FINAL_0.pdf
- B3, Gerenciamento de risco no Day Trade: risk planning and continuous monitoring.
  https://borainvestir.b3.com.br/tipos-de-investimentos/renda-variavel/day-trade/gerenciamento-de-risco-no-day-trade-tecnicas-para-proteger-seu-capital/
