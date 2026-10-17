# Bitey SBT v1.97.0 — Bidirectional Evidence Fix

This branch contains a small MQL4 include module intended to correct the evidence-evaluation behavior discussed in the 2026-10-17 ADAUSD.hb Journal excerpt.

## What it changes

- Evaluates BUY and SELL evidence independently when the caller invokes the evaluator for both directions.
- Emits explicit Journal reasons for unavailable calculations, insufficient train/holdout samples, failed win-rate thresholds, failed average-R thresholds, and successful validation.
- Rejects an entry when there is no current live signal, even if historical evidence passes.
- Does not send, modify, or close orders.
- Does not change the USD 500 effective capital, position sizing, open-position limits, manual trading authority, spread checks, or existing risk controls.

## Evidence thresholds

- Training: N >= 12, win rate >= 0.420, average R > 0.020.
- Holdout: N >= 6, win rate >= 0.400, average R > 0.000.

## Integration status

This is an integration module, not a replacement for the complete v1.96.9 EA. The current EA source was not available through the repository's code search index during creation, so the helper has **not** been wired into the EA's existing model-data structures and has **not** been compiled in MetaEditor. Do not deploy it as if it were a complete EA.

To integrate, include this file in the EA and map the EA's actual train/holdout statistics into BiteyEvidenceStats. Call BiteyEvaluateDirectionEvidence() for both BITEY_DIRECTION_BUY and BITEY_DIRECTION_SELL for each scanned symbol, then call BiteyBidirectionalEvidenceAllowsEntry() with the actual current signal. If it returns true, continue through every existing risk and order gate; it does not authorize bypassing those checks.
