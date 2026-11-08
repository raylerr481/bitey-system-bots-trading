# Bitey Scalper v1.5.17 — Cumulative Minimum Profit Intelligence

## Status
Experimental branch derived from v1.5.16 Entry Flow Diagnostics. This is a source-level implementation only. It has NOT been compiled in MetaEditor, backtested, or forward-tested. Do not replace the running v1.5.16 EA until validation is complete.

## Objective
Add an informational cumulative minimum net-profit objective:
- Daily reference minimum: USD 20 (configurable).
- Any unmet amount carries forward as a positive target deficit.
- Any realized amount above the current objective becomes surplus credit (negative carry), reducing future objectives.
- No upside cap. Reaching or exceeding the objective never stops entries or closes positions.
- The objective is not a promise of daily returns and never forces trades.

## Accounting
- Uses MT4 broker-server calendar days.
- Counts only closed EA market orders matching InpMagic.
- Realized net = OrderProfit + OrderSwap + OrderCommission.
- Open-position floating net is logged separately and never credited toward objective completion.
- Carry state persists in MT4 terminal Global Variables, namespaced by account number and magic number.
- First activation creates a clean baseline for the current server day; no retroactive debt is invented.
- On each day rollover, the completed day's realized net is reconciled once and the carry ledger advances.
- If the terminal is offline for multiple days, each elapsed day accrues the configured minimum; available closed MT4 history is used to credit realized trades.
- Run one EA instance per account/magic pair to avoid concurrent ledger writers. In MT4 Account History, select All History so completed days remain available for rollover reconciliation; if broker history is incomplete, the carry ledger can under-credit realized trades.

## Safety invariants
This module is reporting/accounting only:
- Does not gate, delay, force, rank, or authorize entries.
- Does not alter lot sizing, risk percentages, aggregate exposure, max positions, or recovery sizing.
- Does not relax the score floor (15), quote freshness limit (120 seconds), spread, series, session, or broker-permission checks.
- Does not alter SL, TP, break-even, trailing, net-profit protection, loss-duration management, cooldowns, or progressive selectivity.
- No martingale, lot escalation, daily hard lockout, or profit ceiling.

## Diagnostics
- CUMULATIVE_PROFIT_BASELINE: ledger initialization.
- CUMULATIVE_PROFIT_SNAPSHOT: periodic daily objective, carry-in, realized net, remaining objective, potential surplus credit, and floating net.
- CUMULATIVE_PROFIT_DAY_FINALIZED: completed-day reconciliation and carry-forward amount.
- CUMULATIVE_PROFIT_CLOCK_WARNING: server-day rollback safeguard.

## Weekday operability evidence (observational only)

The experimental source also maintains persistent weekday profiles, using the MT4 broker-server calendar (Sunday=0 through Saturday=6) and two conservative asset classes:
- `RECOGNIZED_CRYPTO_24_7`: symbols recognized by the existing `IsCrypto()` classifier.
- `NON_CRYPTO_SESSION_UNVERIFIED`: every other symbol. This is deliberately not labeled Forex or equities because broker suffixes and CFD contracts do not reliably identify the underlying market or its trading calendar.

Persistent per-weekday/per-class counters:
- `scans`: symbol scan cycles observed.
- `fresh` / `stale`: quote-freshness outcomes.
- `bars`: new signal bars observed.
- `signals`: generated directional signal candidates.
- `queued`: candidates admitted to the execution queue after existing filters.
- `accepted`: successful MT4 order acceptance.
- `rejected`: execution attempts rejected by the execution path.

The counters are namespaced by account number and EA magic number in MT4 terminal Global Variables. They are cumulative by weekday across observed weeks, not a claim that a market is open or closed. They are saved at the five-minute profile cadence and on EA deinitialization; a terminal crash may lose the unsaved interval. The `DAY_OPERABILITY_PROFILE` log reports queued-to-accepted percentage separately for each weekday and class.

**Safety:** these counters do not authorize, reject, rank, delay, or force trades. They do not infer a closed session from stale quotes or old bars. The profile is evidence for later calibration; actual broker permission, quote freshness, series readiness, spread, and all existing strategy checks remain authoritative.

## Validation checklist
1. Compile in MetaEditor and resolve all errors/warnings.
2. Verify the first activation starts with zero carry and does not invent historical debt.
3. Verify USD 12 realized against USD 20 produces USD 8 carry.
4. Verify next-day objective becomes USD 28; USD 18 realized leaves USD 10 carry.
5. Verify USD 35 realized against USD 30 objective creates USD 5 surplus credit and next-day objective becomes USD 15.
6. Verify a day with no trades adds USD 20 to the carry.
7. Verify open floating profit/loss is displayed separately and never reduces the objective.
8. Verify terminal restart preserves carry and does not double-count a completed day.
9. Verify reaching USD 20 or exceeding it does not change entry count, score floor, lot size, or exit management.
10. Demo forward-test and reconcile daily net against MT4 history including commission and swap.

No merge, production deployment, or replacement of v1.5.16 is authorized by this draft.
