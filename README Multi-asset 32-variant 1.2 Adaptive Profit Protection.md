# Multi-asset 32-variant v1.2 — Adaptive Profit Protection

## What changed
This is a new version based on `Multi-asset 32-variant 1.1.mq4`. The original file on `main` is unchanged.

- Adds break-even protection, enabled by default.
- Adds ATR trailing-stop protection, enabled by default.
- Manages only market orders whose magic number matches `InpMagic`.
- Preserves the existing take-profit when modifying an order.
- Includes a monotonicity guard: an existing stop loss may only tighten, never move farther away.
- Logs successful changes as `PROFIT_PROTECTION_MODIFIED` and rejected/deferred modifications as `PROFIT_PROTECTION_DEFERRED`.

## New inputs
| Input | Default | Meaning |
|---|---:|---|
| `InpEnableBreakEven` | `true` | Enable break-even stop management |
| `InpBreakEvenTriggerATR` | `1.0` | Favorable movement in ATR units required before break-even |
| `InpBreakEvenOffsetPoints` | `2` | Place stop a small number of points beyond entry; does not guarantee net profit after all trading costs |
| `InpEnableATRTrailing` | `true` | Enable ATR trailing |
| `InpTrailingStartATR` | `1.5` | Favorable movement in ATR units required before trailing begins |
| `InpTrailingDistanceATR` | `1.0` | Distance between current quote and trailing stop, in ATR units |
| `InpTrailingStepPoints` | `5` | Minimum improvement required before sending a stop modification |

## Safety notes
- This feature does not guarantee profitability or that a stop will execute at its requested price; gaps, slippage, broker rules, and market closures remain possible.
- Broker stop/freeze levels are checked before modification. If a modification is invalid or rejected, the EA logs the error and tries again on a later tick.
- Break-even offset is point-based and does not model commission, swaps, or all spread effects. A stop near entry is not necessarily net break-even.
- The EA manages positions only while it is running and receiving ticks on its attached chart. If no ticks arrive, management may be delayed.
- Existing entry logic and risk sizing are inherited from v1.1 and have not been independently validated here.
- This source has not been compiled in MetaEditor or backtested in this workflow. Compile first, then validate on a demo account and review logs before considering any live use.
