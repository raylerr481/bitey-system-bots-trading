# Bitey SBT v1.8.1.6 — SL/TP Modification Audit

This experimental version branches from v1.8.1.5 and focuses on exit-management observability. It does not increase risk or intentionally widen an existing stop-loss.

## Changes
- New CSV: `Bitey_SLTP_ModificationAudit_v1_8_1_6.csv`.
- Records each `OrderModify` attempt and result, MT4 error code, ticket, timestamp, reason, old/new SL and TP, estimated floating net P/L, broker minimum distance, and an SL monotonicity check.
- Logs TP expansion blocks (ADX, distance/step conditions) once per signal bar to avoid tick-by-tick CSV flooding.
- Adds a final guard against loosening an existing SL. A TP-only modification may still proceed.
- Failed modifications are also written to ActionLog and Experts output.
- Realized net result remains recorded when the trade closes.

## Important
- A protective stop cannot guarantee realized profit: gaps, slippage, commission, swap, execution failures, and broker stop/freeze restrictions remain.
- Current net is a floating estimate from `OrderProfit()+OrderCommission()+OrderSwap()`; realized result is logged at close.
- TP expansion only applies when configured trigger, ADX, distance/step, and broker constraints are met.
- Not yet compiled in MetaEditor or validated in the MT4 Strategy Tester. Compile and test in demo before deployment.
