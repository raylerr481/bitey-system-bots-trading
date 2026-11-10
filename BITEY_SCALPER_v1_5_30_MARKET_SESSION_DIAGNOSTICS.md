# Bitey Scalper v1.5.30 — Market Session Aware Quote Recovery Intelligence

Experimental branch: `experimental/scalper-v1-5-30-market-session-aware-quote-recovery`

Base: `experimental/scalper-v1-5-29-trade-protection-evidence`

## Scope

This version adds broker-session schedule diagnostics to the existing stale-quote path. It queries MQL4 `SymbolInfoSessionTrade()` for the current server weekday and the previous weekday (to recognize overnight sessions), counts returned sessions, and emits:

- `BROKER_SESSION_OPEN_NOW`
- `BROKER_SESSION_CLOSED_NOW`
- `SESSION_UNKNOWN_API_UNAVAILABLE_OR_NO_SCHEDULE`

The existing crypto and explicit 24/7 labels remain explicitly qualified and are not treated as proof of a live quote feed.

## Safety boundaries

- Session lookup is diagnostic only. It does not authorize, reject, or schedule an entry.
- The existing `SessionOK()` configured-hour gate is unchanged.
- Stale quote rejection, quote-age/backoff recovery, signal logic, lot sizing, risk limits, open-position management, adaptive SL/TP, and daily objective/protections are unchanged.
- No stale quote is made tradable by a session-open result.
- If the broker does not expose a usable session schedule, the state remains UNKNOWN. No closed-market inference is made from missing data.

## New stale-quote log fields

`brokerSessionState`, `brokerScheduleAvailable`, `brokerSessionsToday`, `brokerSessionsYesterday`, `brokerSecondsToBoundary`, and `sessionDecision=DIAGNOSTIC_ONLY_NO_ENTRY_GATE_CHANGE`.

## Validation still required in MetaTrader 4

This source has not been compiled or backtested in MetaEditor/MT4 as part of this GitHub change. Before enabling it on a trading account:

1. Compile with the target broker's MT4 build and confirm `SymbolInfoSessionTrade` is supported.
2. Inspect a known weekday-session instrument, a weekend/closed period, a split-session instrument, and an overnight-session instrument.
3. Compare reported sessions with the broker's published contract specifications/server schedule.
4. Verify that symbols with no returned schedule remain UNKNOWN.
5. Confirm stale symbols remain blocked by the existing quote freshness gate even when the broker session is OPEN.
6. Diff the trading behavior and verify `SessionOK()` and the entry prefilter are unchanged.

A broker session schedule can describe permitted trading hours; it does not prove that the quote feed is live, that a symbol is currently tradeable, or that a market order will be accepted.
