# Multi-asset 32-variant 1.5 — Committee Selection

## Purpose

This revision separates the ensemble's **signal vote and ranking** from hard execution and risk controls. It selects at most one highest-scoring eligible symbol per scan cycle; it does not force an order when no candidate clears the minimum signal quorum and mandatory safety gates.

## What changed from v1.4

- Minimum directional quorum defaults to **5 active votes**, directional agreement to **65%**, and vote margin to **3**. This lets clear smaller majorities compete (for example, 5–1 or 7–0) instead of requiring at least 8 active votes in every case.
- All 32 model votes are logged before spread, open-position, and risk eligibility gates are evaluated.
- Spread/ATR above 10% is now a **graded ranking penalty**, not an automatic rejection. A separate hard ceiling of **35% of ATR** remains, alongside the absolute spread cap of 80 points. The hard ceiling is configurable and is not bypassed by a strong vote.
- Candidate scoring considers directional agreement, active-vote coverage, vote margin, absolute spread, spread/ATR cost, and risk-budget utilization. The score is a ranking heuristic, **not a probability of profit**.
- `BEST_CANDIDATE_NONE` reports counts of vote, spread, risk, and other rejections; repeated no-scan log spam is avoided when no symbol has a new bar.
- When aggregate risk prevents selection, logs include each open EA position's lots, stop distance, tick value, tick size, and estimated risk so abnormal contract specifications can be investigated.

## Risk and execution safeguards retained

- Reference capital USD 500; default per-trade risk is capped at the smaller of USD 5 or 1% of reference capital (USD 5); aggregate planned risk cap is 2% (USD 10).
- Position-count and one-position-per-symbol restrictions remain.
- Lot size is rounded down to broker lot step. If the broker minimum lot exceeds the available risk budget, the candidate is rejected.
- The EA rechecks position count and aggregate risk before `OrderSend`.
- ATR-based initial SL/TP remain. Break-even and trailing may tighten the stop; they must not widen it.
- Account type is not used as an entry gate, but broker trade permission, valid quotes, contract specs, spread, stop-distance, and risk gates still apply.
- A high or nonsensical calculated open risk (such as the logged VVVUSDT figure of USD 504,758.88 against a USD 10 aggregate cap) remains a **block**, not a reason to disable the risk gate. Use the new `OPEN_RISK_POSITION_AUDIT` output to diagnose tick value, tick size, account currency, contract size, lots, and SL.

## Interpretation of the supplied log examples

- AAPLUSDT (5 sell / 1 buy) and MUUSDT (7 sell / 0 buy) can now satisfy the default vote quorum and compete, assuming all hard cost, contract, position, and risk checks pass.
- MSFTUSDT's 17/17 sell consensus can receive a spread/ATR penalty rather than an automatic rejection at 10%; it is still blocked if spread/ATR exceeds the 35% hard ceiling or the absolute spread limit.
- LABUSDT's 9/9 buy consensus can compete if its actual spread/ATR ratio is within the hard ceiling.
- SPCXUSDT and HYPEUSDT remain below the 65% direction threshold in the supplied log and should not pass merely because there are many votes.

## Validation status

- Source and README are committed on the v1.5 feature branch.
- **Not compiled in MetaEditor and not backtested.** The source change is not proof of profitability or runtime correctness.
- Run in MT4 demo first. Verify the `OPEN_RISK_POSITION_AUDIT` output and the broker's symbol specifications before allowing live orders, especially for share/crypto CFDs and non-USD deposit currencies.
- This feature branch is based on the v1.4 feature branch. No changes were merged to `main`.
