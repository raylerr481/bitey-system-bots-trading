# Bitey Scalper v1.5.4.11 — Candidate Decision Trace

## Base and files
- Parent branch: `experimental/scalper-v1-5-4-10-execution-diagnostics`
- Parent commit: `782c822056ee386161639a768d8a41d1b167a811`
- EA: `Bitey_Scalper_MultiAsset_v1_5_4_11_CandidateDecisionTrace.mq4`
- Version: `1.5.4.11`
- MQL4 Market version property: `1.542`
- Diagnostic input: `InpEnableCandidateDecisionTrace=true`

## Purpose
Explain why a signal candidate is counted but does not reach the `OpenTrade()` preflight path. This is an observability-only extension of v1.5.4.10. It does not relax, bypass, reorder, or replace any trading condition.

## New candidate trace events
When `InpEnableCandidateDecisionTrace=true`, the EA emits `CANDIDATE_DECISION` records:

1. `stage=DETECTED`: candidate symbol, BUY/SELL, signal bar time, score, spread percentage of stop, priority score, and normalized asset key.
2. `stage=EXECUTION reason=POSITION_ALREADY_OPEN_ON_ALIAS`: candidate was skipped because an open position already exists for the same normalized asset identity. No order attempt is made.
3. `stage=EXECUTION reason=MAX_OPEN_POSITIONS_REACHED`: portfolio position count had reached the configured hard maximum before this candidate was routed. No order attempt is made. The current open count and configured maximum are logged.
4. `decision=CALL_OPEN_TRADE_PREFLIGHT`: candidate passed the execution-loop alias and portfolio-capacity checks and is about to enter `OpenTrade()`. This is not proof that the broker received an order.

The existing v1.5.4.10 diagnostics continue to identify preflight rejects, `OrderSend()` failures and accepted orders. The candidate summary now reports `aliasSkipped` and `portfolioCapacitySkipped` separately. `capacityNotAttempted` excludes alias skips so those cases are not mislabeled as portfolio-capacity skips.

## Preserved behavior
- Signal families, scoring, ranking, session filter, cooldown and all entry filters.
- Risk sizing, reference capital, aggregate/currency risk controls and maximum five open positions.
- Adaptive SL/TP, break-even, trailing, TP expansion and no-SL-widening rule.
- Net-profit protection and 50% net peak-giveback logic.
- Progressive and rolling loss management, open-exposure controls and warning-only daily loss handling.
- Quote freshness gate and broker-133 handling.
- Existing exit management and broker-side SL/TP behavior.

## Validation status
- Source was branched from the v1.5.4.10 execution-diagnostics branch.
- Static source inspection and patch-integrity checks are required before use.
- Not compiled in MetaEditor; not run in MT4 Strategy Tester or forward demo as part of this change. Compile and test on demo before any live use.
