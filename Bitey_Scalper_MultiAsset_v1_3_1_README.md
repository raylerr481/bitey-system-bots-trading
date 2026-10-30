# Bitey Scalper MultiAsset v1.3.1 — Net Profit Protection

This is an isolated successor to the original v1.3.0 Claude file. The original file and `main` are unchanged.

## Preserved strategy
- Market Watch universe (or explicit CSV), up to 128 symbols.
- M5 signal timeframe and M15 higher-timeframe trend filter by default.
- BUY and SELL entries.
- Four signal families (EMA trend, RSI momentum, Donchian breakout, Bollinger re-entry).
- Maximum five open positions, one position per normalized asset key.
- ATR-based initial SL/TP and trend-confirmed TP expansion.
- No martingale or loss-based lot escalation was introduced.

## v1.3.1 changes
- Persistent per-ticket peak floating-net-profit tracking using MT4 terminal Global Variables.
- Net-profit lock converts a target account-currency amount into a protective SL using tick value/size.
- The lock accounts for current swap and commission, configurable estimated closing commission, and a configurable adverse stop-fill slippage reserve. The current Bid/Ask mark already includes spread.
- The net-lock SL is merged with break-even and ATR trailing; it only tightens the existing SL.
- Added an FX currency-concentration cap. Each open trade's adverse stop risk is attributed to both currencies in its six-character FX symbol key; unknown stop risk fails closed. Crypto symbols are excluded from this FX currency calculation but remain subject to aggregate risk.
- Added ZEC, LRC and UNI to crypto-prefix recognition (also TRX, ETC, FIL, ATOM, LINK, SHIB and TON).
- Initialization warnings identify account-currency mismatch and missing closing-commission configuration.

## Important configuration
All monetary thresholds are in **account currency**, despite legacy parameter names containing USD. The reference capital is configured as USD 500 in the source. Keep the MT4 account currency in USD or verify conversion/risk sizing before use.

Set `InpEstimatedCloseCommissionPerLot` to the broker's estimated closing-side commission for 1.00 lot, in account currency. Leave it at zero only if there is no closing-side commission. No software can guarantee an exact net result because stop execution can slip or gap.

Default new controls:
- `InpNetLockStartUSD = 1.00`
- `InpNetLockMinUSD = 0.25`
- `InpNetLockGivebackPct = 35` (aims to retain 65% of peak net floating profit)
- `InpNetLockStepUSD = 0.25`
- `InpNetLockSlippagePoints = 3`
- `InpMaxCurrencyRiskPct = 1.5`

The lock is a price-level protection, not a guaranteed market exit. Gaps, broker stop rules, rejected modifications, execution costs, and unavailable quotes can still produce a worse realized result.

## Validation status
Source changes are committed to this feature branch only. The EA has **not** been compiled in MetaEditor and has **not** been backtested or forward-tested. Compile first, inspect all warnings/errors, then test both BUY and SELL on multiple FX and crypto symbols in Strategy Tester/demo. Verify broker tick values, lot steps, stop/freeze levels, commission, swap and slippage before any live use.
