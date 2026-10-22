# Multi-asset 32-variant 1.1 — Adaptive SL/TP

This is based directly on `main:Multi-asset 32-variant 1.1.mq4`. It adds adaptive exit management only; the original 32-variant voting/committee, entry filters, lot sizing, candidate evaluation, and order-entry logic are retained.

## Added exit behavior

- Initial SL and TP calculation is unchanged: ATR-based stop distance and `InpRewardRisk`.
- Break-even protection starts after a favorable move of 1.0 ATR by default.
- ATR trailing starts after 1.5 ATR favorable movement and follows at 1.5 ATR by default.
- SL modifications are one-way: BUY stops can only move upward; SELL stops can only move downward. The EA does not widen SL to increase loss capacity.
- TP can extend outward only when price has moved favorably by at least 1 ATR, ADX is at least 22 by default, and price approaches the existing TP. The target is extended to maintain an ATR buffer and capped at 6 ATR from entry by default.
- Respects broker stop/freeze distance and writes `ADAPTIVE_SL_TIGHTENED`, `ADAPTIVE_TP_EXTENDED`, or modification-failure logs.

## Default parameters

- `InpEnableAdaptiveExits = true`
- `InpBreakEvenTriggerATR = 1.0`
- `InpTrailStartATR = 1.5`
- `InpTrailDistanceATR = 1.5`
- `InpTPExpandTriggerATR = 1.0`
- `InpTPExpandBufferATR = 1.5`
- `InpTPExpandADXMin = 22.0`
- `InpTPMaxDistanceATR = 6.0`

These are starting values, not optimized parameters. Extending TP may capture larger trends but can also delay exits or reduce target fills; the trailing stop may protect some open gains but cannot guarantee positive net performance.

## Validation status

Source is committed to a feature branch based directly on `main`; no changes were merged to `main`. **Not compiled in MetaEditor or backtested.** Test in MT4 demo and compare results after spread, commission, swap, slippage and execution costs before considering live deployment.
