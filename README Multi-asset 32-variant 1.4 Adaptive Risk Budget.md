# Multi-asset 32-variant 1.4 — Adaptive Risk Budget

## Changes
- Ranks qualifying symbols and selects only the highest-scoring candidate per scan cycle.
- Automatic trading is enabled in this branch (`InpEnableTrading=true`).
- Keeps the per-trade risk cap and aggregate risk cap.
- Sizes lots to the smaller of the per-trade cap and remaining aggregate risk budget, rather than rejecting a candidate simply because the standard lot size would exceed the remaining budget.
- If the broker's minimum lot would exceed the available risk budget, the EA rejects that candidate safely.
- Keeps ATR-based initial SL/TP, break-even and ATR trailing protection.
- The score is a ranking heuristic, not a measured probability of profit.

## Validation status and limitations
- Not compiled in MetaEditor and not backtested in this environment.
- Validate tick value, tick size, contract size and account deposit currency for each broker symbol, especially crypto, synthetic and share CFDs.
- The `MODE_TICKVALUE` value is in the account deposit currency; this implementation does not perform explicit conversion to USD. Treat the configured USD risk amounts as unverified if the deposit currency is not USD.
- Demo forward-test before any live use. Broker permissions, margin, minimum lot, stop/freeze levels and execution conditions can still reject orders.
