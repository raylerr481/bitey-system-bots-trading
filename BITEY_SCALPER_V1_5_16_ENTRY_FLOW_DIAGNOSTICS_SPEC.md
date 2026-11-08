# Bitey Scalper v1.5.16 — Entry Flow Diagnostics

## Status
Experimental draft derived from v1.5.15. Source-level changes are committed, but this version has NOT been compiled in MetaEditor, backtested, or forward-tested. It must not replace the running EA until validation is complete.

## Objective
Make the path from market-data readiness to broker order acceptance auditable. The change is observability-only: it adds counters to the existing five-minute diagnostic window and does not alter signal generation, ranking, execution permissions, sizing, risk, or exit management.

## New diagnostic event
`ENTRY_FUNNEL_DIAGNOSTICS | windowSec=300` reports:
- `staleQuoteChecks`: scan passes rejected before bar analysis due to stale quote.
- `historyUnavailable`, `noNewBarChecks`, `insufficientHistory`, `seriesWait`: reasons a symbol scan did not reach signal analysis.
- `prefilterPass` / `prefilterReject`: prefilter results.
- `signalPass` / `signalReject`: generated signals and all signal-stage rejections, including cooldown/direction/score/HTF selectivity.
- `queued`: candidates that passed all signal-stage eligibility checks and entered the ranked execution queue.
- `executionAttempts`: calls that reached `OpenTrade()`.
- `accepted`: orders accepted by MT4 (ticket returned).
- `executionRejected`: candidates whose `OpenTrade()` call returned false.
- `aliasSkipped`: candidates skipped because the normalized asset already has an open position.
- `capacitySkipped`: queued candidates not attempted because portfolio capacity was reached.

Counters reset after each five-minute heartbeat. Scan-check counters are event counts, not unique-symbol counts; they must not be interpreted as the number of distinct assets. Existing per-symbol state-transition logs remain the source for symbol-specific diagnosis.

## Entry-flow audit
Use the following events together:
1. `BAR_SCAN_SYMBOL` / `SERIES_RECOVERY_PENDING`: whether the asset reached a new, ready bar.
2. `ENTRY_FILTER`: prefilter, signal, cooldown, direction, HTF and score decision.
3. `ENTRY_CANDIDATE`: signal generated and candidate queued.
4. `BEST_CANDIDATE_SELECTED`: ranking result.
5. `ENTRY_EXECUTION_ATTEMPT`: call into the execution function.
6. `ORDER_SEND event=REQUEST`: MT4 order request sent.
7. `ORDER_SEND event=RESULT` and `ENTRY_EXECUTION_RESULT`: broker/terminal acceptance or rejection and error category.
8. `CANDIDATE_EXECUTION_SUMMARY`: per-cycle candidate/attempt/rejection reconciliation.

An `ENTRY_EXECUTION_ATTEMPT` proves only that the EA called its execution function. `ORDER_SEND event=REQUEST` proves a request was sent. Only `ORDER_SEND event=RESULT result=ACCEPTED` / `ORDER_ACCEPTED` with a ticket proves MT4 accepted an order. A broker fill/position should then be confirmed in MT4 trade state/history.

## Safety invariants retained
- USD 500 reference capital; maximum five open positions.
- Minimum score 15 and maximum quote age 120 seconds.
- Existing spread, series readiness, session, permission, stop-distance, lot-size, currency-risk and aggregate-risk checks remain unchanged.
- Existing best-eligible-candidate ranking and fallback after execution rejection remain unchanged.
- Existing adaptive SL/TP throttling, monotonic protective SL, net-cost protection, loss management and broker-side SL/TP remain unchanged.
- No martingale, lot escalation, forced order, filter bypass, or daily hard lockout is introduced.

## Validation checklist
1. Compile in MetaEditor (MT4/MQL4) and resolve all errors and warnings.
2. Confirm the new funnel line appears every five-minute heartbeat and counters reset only after it is emitted.
3. Demo-test with no new bars, stale quotes, insufficient history, history-update-pending, prefilter rejection, signal rejection, queued candidate, full portfolio, alias collision, trade permission rejection and broker rejection.
4. For an eligible candidate with available capacity, verify the sequence from `ENTRY_CANDIDATE` through `ENTRY_EXECUTION_ATTEMPT` to `ORDER_SEND`.
5. Reconcile queued candidates against attempts, accepted orders, execution rejections, alias skips and capacity skips; investigate any unexplained difference.
6. Verify accepted tickets against MT4 open positions/history.
7. Confirm all protective SL/TP and risk behavior remains unchanged in Strategy Tester and demo forward test.

No production deployment or merge is authorized by this draft.
