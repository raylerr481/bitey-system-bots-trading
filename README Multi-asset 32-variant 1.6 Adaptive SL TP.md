# Multi-asset 32-variant 1.6 — Adaptive SL/TP

This version keeps the v1.5 committee and candidate selection, adding a volatility-aware TP extension alongside the existing ATR initial SL/TP, break-even and ATR trailing stop management.

## Adaptive exit behavior

- Initial SL remains ATR-based; initial TP is based on the stop distance multiplied by the configured reward/risk ratio.
- Existing break-even and ATR trailing can tighten SL but must never widen it.
- Optional adaptive TP extension is enabled by default. It requires favorable movement of at least the configured ATR trigger and ADX at/above the configured directional-strength threshold.
- TP extension is driven by volatility-adjusted target distance, moves the target outward only, and has a maximum distance of 6 ATR from entry by default. It does not lower a target to make it easier to hit.
- TP extension logs `ADAPTIVE_TP_EXTENDED` or `ADAPTIVE_TP_DEFERRED`; SL protection continues to log `PROFIT_PROTECTION_MODIFIED`.

## Default adaptive TP settings

- `InpTPExpandTriggerATR = 1.0`
- `InpTPExpandADXMin = 22.0`
- `InpTPExpandStepATR = 0.5`
- `InpTPMaxDistanceATR = 6.0`

These are starting parameters, not optimized values. More distant targets can reduce the chance of a TP fill; a trailing SL may protect some open profit, but neither mechanism guarantees positive net results.

## Safeguards retained

- Reference capital USD 500; max planned risk per trade is the lower of USD 5 and 1% of reference capital; aggregate planned risk cap USD 10.
- No martingale, no wider SL, no bypass of broker trading permissions or risk gates.
- Committee selects at most one best eligible candidate per scan cycle.
- Account type is not used as an entry gate, but valid prices, broker permissions, lot/contract specifications, spread, minimum-lot feasibility and risk caps still apply.
- An anomalous risk estimate such as VVVUSDT's logged USD 504,758.88 remains a block until diagnosed.

## Validation

The source and README are on a feature branch based on v1.5. The EA has **not** been compiled in MetaEditor or backtested here. Run in MT4 demo first and compare net results after spread, commissions, swap, slippage, missed fills and stop execution. Do not infer profitability from the adaptive logic alone.
