# Bitey Ensemble Scalper MultiAsset v1.2.4 Adaptive SLTP RiskBudget

## Purpose
This is a new branch-only version based on v1.2.3. It preserves the 32-variant entry committee, candidate-before-position-limit audit, USD 500 reference capital, 1% per-trade risk budget, 2% aggregate planned-risk cap, and maximum three open positions.

## Changes in v1.2.4
- Adds a per-ticket cooldown after successful SL/TP modifications: `InpMinSecondsBetweenExitModifications=30`.
- Requires a meaningful SL change of at least `InpMinSLChangePoints=5` broker points before a stop modification is sent.
- Requires a meaningful TP change of at least `InpMinTPChangePoints=10` broker points before a target modification is sent.
- Adds `ADAPTIVE_EXIT_MODIFY_THROTTLED` records when a change is suppressed by the cooldown.
- Adds `ADAPTIVE_EXIT_MODIFY_AUDIT` with Bid/Ask, market price, old/new SL and TP, distances from executable quotes, broker stop/freeze levels and active thresholds.
- Failure logs now include the requested prices, quote and broker stop/freeze levels.
- Retains the one-way stop rule: BUY SL can only rise; SELL SL can only fall. No automatic widening-and-retry is added.
- Retains v1.2.3's `CANDIDATE_BLOCKED_PORTFOLIO_FULL` diagnostic after consensus scoring.

## Safety limits retained
- Reference capital: USD 500.
- Per-trade planned risk budget: 1% (USD 5).
- Aggregate planned risk cap: 2% (USD 10).
- Maximum open positions for this EA magic number: 3.
- No martingale, no risk-cap increase, no automatic widening of stops.

## Test status and deployment
This source has been committed to the feature branch only; it has not been compiled in MetaEditor or backtested. The live account's existing EA is not changed by this GitHub commit. Before testing, compile this file in MT4 MetaEditor, attach it to a demo chart, verify the Inputs and magic number, and observe the journal. Do not run two instances with the same magic number on the same account because they can manage the same positions. A 30-second cooldown can delay a later protective adjustment; the minimum-change filters also intentionally suppress very small changes. Confirm broker-specific point sizes and quote digits before considering live use.

## File
`Bitey_Ensemble_Scalper_MultiAsset_v1_2_4_Adaptive_SLTP_RiskBudget.mq4`
