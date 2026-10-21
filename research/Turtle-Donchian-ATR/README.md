# Bitey Turtle Donchian ATR — MT4 research EA

Status: research candidate. It has not been compiled or backtested by the authoring assistant.

This is a new, independent MQL4 Expert Advisor inspired by the classic Turtle trend-following family. It does not copy or replace the existing Bitey SBT multi-model EA, Infinity EA, or EA31337 Libre. The strategy is a transparent breakout hypothesis, not proof of current profitability.

## Strategy
- Signal timeframe default: H1.
- Entry: the last fully closed candle closes above the prior 20-bar high channel (BUY) or below the prior 20-bar low channel (SELL).
- Initial stop: approximately 2 × ATR(20), subject to broker stop-distance requirements.
- Exit: close BUY below the prior 10-bar low channel or SELL above the prior 10-bar high channel, using closed candles. No fixed take-profit; this follows trend-following logic.
- Channel calculations exclude the signal candle to avoid look-ahead.
- No pyramiding, grid, martingale, averaging down, or forced minimum lot.
- One open position total across charts sharing the same magic number.

## Safety defaults
- Reference capital: USD 500.
- Planned risk budget: USD 1.25 per trade, estimated from broker tick metadata and stop distance.
- Daily loss threshold: USD 10; blocks new entries and does not guarantee forced liquidation.
- Version 1.01 defaults to EnableTrading=true so it can attempt entries once all signal, quote, spread, cost-input, margin, and risk checks pass. Set it to false to disable trading immediately. Test on demo first; do not assume it is profitable or production-validated.
- Commission and expected swap inputs default to 0 so the EA can run without account-type gating; zero means the cost may be unknown and excluded from estimated risk. A warning is logged. Configure actual broker costs before interpreting results; unmodeled costs can make actual risk exceed the estimate.
- If the broker's minimum lot would exceed the planned risk budget, the EA rejects the trade.
- Demo/live account type is not used as a trading gate, and USD account currency is not required by default. Risk sizing still uses USD-denominated assumptions and broker tick metadata; non-USD accounts or non-USD quote currencies require extra verification. Spread, quote freshness, margin, and broker metadata checks remain active.
- The EA only manages its own magic-number positions. Stop loss and daily threshold are estimates/guards, not guaranteed maximum losses.

## Required validation before enabling
1. Open the file in MetaEditor and compile with F7. Require 0 errors; investigate every warning.
2. Test each broker symbol separately. Verify tick value/size, contract size, minimum lot, lot step, spread scale, stop level, commission, swap, and account currency.
3. Backtest with realistic variable spread, commission, swap, and slippage. Record net profit, profit factor, maximum equity drawdown, trade count, expectancy, average win/loss, and costs.
4. Keep chronological out-of-sample data untouched during tuning; compare 20/10 and 55/20 channels without selecting based only on the best in-sample result.
5. Forward-test on demo and reconcile the logged estimated risk with actual broker fills and stop distances.
6. Run first on demo and review order logs. For safety, set EnableTrading=false until compilation, backtest, and demo-forward gates are passed; the current version defaults to enabled to satisfy the request for observable execution, so verify the account and terminal before attaching it.

A successful compile or positive backtest does not establish future profitability. Gap risk, slippage, execution failures, or inaccurate broker metadata can cause realized losses to exceed the estimate.
