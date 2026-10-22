# Bitey Ensemble Scalper MultiAsset v1.2 — Adaptive SL/TP + Risk Budget

New version based on the 32-variant committee source. This file preserves the 32-vote strategy and entry filters, while sizing each candidate against the remaining aggregate-risk budget and improving the open-risk audit when a stop has moved beyond breakeven.

## Changes in v1.2

- Calculates remaining aggregate risk before sizing a new candidate.
- Effective candidate risk budget is the smaller of the per-trade budget (1% of the USD 500 reference capital by default) and remaining aggregate risk.
- If the broker's minimum lot or contract specification exceeds that budget, the EA rejects the candidate and logs `RISK_BUDGET_NO_VALID_LOT`; it does not raise the risk cap or bypass the gate.
- Open-risk accounting counts only adverse distance from entry. If a BUY stop is at/above entry or a SELL stop is at/below entry, that position contributes zero price-distance risk to the aggregate calculation. This avoids treating protected profit distance as loss risk.
- A position without an SL remains fail-closed and consumes the full reference-capital risk budget in the aggregate audit.
- Keeps the adaptive break-even, one-way ATR trailing stop and conditional ATR/ADX TP extension.
- Preserves existing vote thresholds, spread gate, one-position-per-symbol, maximum open positions and broker trading permissions.

## Default risk settings

- Reference capital: USD 500
- Per-trade risk budget: 1% (USD 5)
- Aggregate risk cap: 2% (USD 10)
- Maximum open positions: 3
- No martingale and no risk-cap bypass.

## Validation status

Source-level checks only: braces and parentheses are balanced. **Not compiled in MetaEditor and not backtested.** The tick-value calculation relies on broker-provided `MODE_TICKVALUE`; verify its currency and contract behavior for every symbol, especially crypto CFDs and symbols with nonstandard contract sizes. Test in demo first. TP extensions do not guarantee higher profitability, and all results must be evaluated net of spread, commission, swap and slippage.
