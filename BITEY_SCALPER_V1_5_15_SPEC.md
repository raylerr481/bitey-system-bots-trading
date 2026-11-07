# Bitey Scalper v1.5.15 — Adaptive Profit Protection

## Status
Experimental draft based on v1.5.14. Not compiled in MetaEditor and not backtested or forward-tested.

## Main objective
Reduce excessive broker modification requests while keeping adaptive SL and TP coordinated around protecting realized/net profit. No entry signal or risk gate is weakened.

## Entry-attempt policy
- Preserve the v1.5.14 ranked best-eligible-candidate flow.
- If at least one fully eligible candidate exists and portfolio capacity is available, attempt the highest-ranked candidate first; continue to the next eligible candidate only after an execution rejection and while capacity remains.
- Never manufacture a trade, bypass score/spread/series/quote/risk/session/permission checks, exceed five open positions, or promise broker acceptance. Therefore one *attempt* is guaranteed when a qualifying candidate and capacity exist; an actual fill cannot be guaranteed by EA code.

## Adaptive SL
- Initial broker-side SL remains installed at order entry.
- Existing SL may only move in the protective direction; it is never widened.
- Ordinary updates require at least 0.05 ATR improvement and 15 seconds since the prior successful SL modification (both configurable).
- A >=0.50 ATR improvement bypasses the time throttle.
- A stop that changes the projected outcome from not net-protective to net-profitable also bypasses both throttles.
- Existing break-even, trailing, weak-trend tightening and cost-aware net-profit lock calculations remain active.

## Adaptive TP
- TP expansion retains all existing conditions: favorable closed-bar progression, ATR trigger, ADX threshold and an already-installed SL that protects estimated net costs.
- Ordinary TP extensions require at least 0.15 ATR and 20 seconds since the prior successful TP modification (both configurable).
- TP throttling is independent of SL throttling. Deferring TP never defers a protective SL update.
- No TP expansion is allowed when the existing SL does not protect estimated net costs.

## Broker error 133
- A rejected symbol is blocked for the configured cooldown; no repeated test orders are sent.
- The log records terminal, expert and symbol permission diagnostics.
- Error 133 alone is not treated as proof of a global account lock; the block remains symbol-scoped unless independent permission diagnostics show otherwise.

## Preserved hard constraints
- Reference capital USD 500; max five open positions.
- Minimum score 15; quote maximum age 120 seconds.
- Existing risk sizing, aggregate exposure, daily progressive selectivity, loss-duration logic, series recovery, best-candidate ranking and broker-side SL/TP are retained.
- No martingale, lot escalation, blind entries or daily hard lockout.

## Required validation before replacing v1.5.14
1. Compile in MetaEditor and resolve all errors/warnings.
2. Strategy Tester: verify BUY and SELL, SL monotonicity, TP expansion only after net-protective SL, throttling and emergency bypass.
3. Demo forward test: compare modification counts, rejected modifications, net results and entry acceptance.
4. Confirm at least one eligible candidate reaches OrderSend; actual acceptance remains broker-dependent.


## Daily five-trade evaluation (server time)
- Enabled by default; the evaluation window is the latest five closed EA market trades within the current broker-server calendar day.
- Evaluation is refreshed as each trade closes; the first complete evaluation occurs after five closes. No elapsed-time threshold is used.
- A 4-win/1-loss result is tolerated and does not activate this daily strict-quality mode. The EA continues its normal v1.5.14 best-eligible-candidate scan, ranking, and execution-attempt flow.
- At least two losses (and more losses than wins, with negative net result) are required to activate the additional daily analytical selectivity. This raises the score requirement; it does not suspend the day or bypass any existing risk/market gates.
- The daily sample resets at broker server midnight via TimeCurrent()/server date. Existing progressive daily loss, rolling loss, per-asset cooldown, exposure and open-position protections remain independently active and are not disabled by the 4/1 tolerance.
- This is a latest-five rolling evaluation during the server day, not a fixed wall-clock timer or an absolute guarantee of a filled order.
