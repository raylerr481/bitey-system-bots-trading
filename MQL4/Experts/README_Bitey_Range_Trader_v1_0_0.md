# Bitey Range Trader v1.0.0 (MT4)

Standalone Expert Advisor for range-reversion research. It does not modify or replace any existing Bitey SBT EA.

## Logic
- Uses completed candles on the selected signal timeframe (default M15).
- Builds a range from the prior 30 completed candles, excluding the signal candle.
- Buys only after a bullish rejection near the range low; sells only after a bearish rejection near the range high.
- Optional RSI confirmation.
- Rejects ranges that are too narrow/wide relative to ATR and blocks new range entries after a confirmed close outside the range plus an ATR buffer.
- Sets a stop beyond the relevant range edge and calculates lot size from a percentage of account balance.
- Limits entries per day and blocks new entries when equity loss from the day's starting equity reaches the configured limit.
- Only manages the chart symbol. Attach one instance per symbol/timeframe as needed.

## Safety defaults
- `EnableTrading = false`: no orders are sent until explicitly enabled in EA inputs.
- `RiskPercent = 0.25`: intended risk budget per trade, subject to broker tick-value/lot-step accuracy.
- `MaxTradesPerDay = 3`
- `DailyLossLimitPct = 2.0`
- No martingale, no grid, no averaging down, and no widening stop-loss logic.

## Install and validate
1. In MT4 choose **File → Open Data Folder**.
2. Copy `MQL4/Experts/Bitey_Range_Trader_v1_0_0.mq4` into the terminal's `MQL4/Experts` directory.
3. Open MetaEditor, compile the EA, and resolve any broker/build-specific errors.
4. Backtest in Strategy Tester with realistic spread, commission, swaps, and tick modelling.
5. Forward-test on demo before considering any real-money use.

## Important limitations
- Source has been committed to GitHub but has **not** been compiled in MetaEditor or backtested from this environment.
- Broker tick-value and tick-size conventions can vary, especially for CFDs and crypto symbols; verify lot sizing on each symbol.
- The daily-loss guard uses account equity versus the equity recorded when the EA initializes/rolls to a new server day. Restarting the EA mid-day resets that reference, so this guard is not a substitute for a terminal/account-level risk control.
- A range strategy can lose repeatedly when markets trend or break out. No profitability is guaranteed.

## Version
v1.0.0 — initial standalone range-trading EA.
