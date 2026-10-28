# Bitey Ensemble Scalper MultiAsset v1.8.1.7 — SL/TP Trail Audit

Experimental branch derived from v1.8.1.5. This version addresses compile errors reported in the local v1.8.1.6 file and adds traceable SL/TP modification auditing.

## Changes
- Fix stale heartbeat reference to undeclared `lossBlock`; heartbeat reports configured exit-protection modes instead.
- Fix undefined `budget` diagnostic variable by logging the calculated `perTrade` budget.
- Add an explicit monotonic-stop guard: an existing SL is never moved away from the market to increase potential loss.
- Log each SL/TP modification attempt, including ticket, net P/L estimate, old/new SL and TP, and reason.
- Log successful modifications and `OrderModify` failures, including the broker error code.
- Log eligible TP-expansion checks that did not result in a TP change, with the reason (ADX, distance to target, or distance/broker constraint), throttled by the existing rejection-log interval.
- Keep existing close-history audit for realized gross profit, commission, swap and net result.
- Preserve the $500 reference capital, 0.5% per-trade risk setting, adaptive SL/TP settings, and broker permission checks.

## Validation status
Not compiled in MetaEditor and not backtested in MT4 in this commit. Compile and test on a demo account before relying on it. A stop-loss cannot guarantee the exact fill price or realized profit due to gaps, slippage, fees, and broker constraints.
