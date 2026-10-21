# Bitey Ensemble Scalper Multi-Asset v1

**Status: prototype; not yet compiled or performance-validated. Trading is disabled by default.**

EA source: Experts/Bitey_Ensemble_Scalper_MultiAsset_v1.mq4

## Design
- Scans comma-separated symbols or symbols visible in Market Watch from one EA instance.
- 32 parameter variants across EMA trend, RSI momentum, closed-bar breakout, and Bollinger re-entry.
- BUY and SELL; entry requires minimum vote count and vote margin.
- USD 500 reference capital, 1% initial planned risk (USD 5), 2% aggregate planned-risk cap, maximum 3 open positions, one position per symbol.
- ATR-based initial stop and reward/risk target.
- Lot calculation fails closed when tick/lot metadata is missing or minimum lot exceeds planned risk.
- InpEnableTrading=false by default; emits dry-run candidates until explicitly enabled.

## Limitations and safety
1. The 32 votes are parameter variants, not 32 independent models; predictive value is unknown.
2. No profitability claim or verified backtest is included.
3. No persistent daily asset ranking, trailing stop, news filter, or complete commission/slippage model yet.
4. Broker tick value/size and contract behavior must be verified per instrument/account currency. Stops cannot guarantee the planned loss during gaps/slippage.
5. Generic spread threshold requires per-symbol calibration.
6. Exposure cap counts positions with this EA's magic number only; coordinate with other EAs/manual positions.
7. Compile in the target MT4 MetaEditor build and resolve all errors/warnings before testing; compilation was not performed during this repository update.

## Required validation
1. Compile in MetaEditor.
2. Confirm symbol names/suffixes and Market Watch coverage.
3. Backtest with realistic ticks, variable spread, commissions, swaps and slippage.
4. Perform walk-forward/out-of-sample testing and compare to a simpler baseline.
5. Start in demo with trading disabled; inspect ENSEMBLE_AUDIT, DRY_RUN_CANDIDATE and SYMBOL_REJECT logs.
6. Enable trading only after independent review; monitor execution and begin at low risk.

Research software only; not financial advice or a guarantee of returns.
