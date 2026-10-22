# Bitey Ensemble Scalper MultiAsset v1.2.3 — Adaptive SL/TP and Risk Budget

## Change in v1.2.3
- Moves the maximum-open-position check until after ensemble votes and consensus filters are calculated.
- When the portfolio is full, a signal-qualified symbol logs `CANDIDATE_BLOCKED_PORTFOLIO_FULL` with direction, votes, active-vote count, directional percentage, current position count, and configured maximum.
- Still rejects new entries at `InpMaxOpenPositions`; this does not increase the position limit or aggregate-risk budget.
- Spread and existing-position-per-symbol filters remain early gates. Symbols rejected by spread still do not receive an ensemble audit.
- This improves visibility into candidate signals; it does not rank all candidates globally or change the Market Watch scan order. A later candidate cannot replace an earlier open position.

## Risk controls retained
- Reference capital: USD 500.
- Per-trade planned risk budget: 1% (USD 5).
- Aggregate planned risk cap: 2% (USD 10).
- Maximum open positions: 3.
- No martingale, no automatic stop widening, and no automatic wider-stop retry.

## Validation status
Source braces and parentheses are balanced. This source has not been compiled in MetaEditor or backtested. Validate on a demo account before live use. Risk estimates do not guarantee realized loss limits under gaps, slippage, commissions, swaps, or broker execution conditions.
