# Bitey Range Trader v1.1.0 — Adaptive Net-Profit Lock

Standalone MetaTrader 4 Expert Advisor. This EA is separate from the existing Bitey SBT ensemble EAs.

## Strategy
- Defines a horizontal range from the previous 30 completed M15 candles (configurable).
- Buys only after a bullish rejection near the lower range edge.
- Sells only after a bearish rejection near the upper range edge.
- Uses ATR to reject ranges that are too narrow/wide and to invalidate confirmed breakouts.
- Uses RSI as an optional rejection filter.
- Calculates lot size by fractional account-balance risk and rounds volume down, never up.
- Places the initial stop beyond the relevant range boundary and a risk/reward target.

## Net-profit lock
- Runs position management on every tick, not only at a new signal candle.
- When a position's floating net result (profit + swap + commission) reaches the configured trigger (default 1.00 account-currency unit), it attempts to move the stop to a level intended to preserve the configured net floor (default 0.20).
- Stop-loss is only tightened; this EA never widens an existing stop.
- Broker stop/freeze levels and execution conditions can prevent a modification. The log records modification errors.
- The net floor is an estimate based on the broker's current tick value/size and the currently reported commission/swap. Slippage, future fees, gaps, and broker accounting can make the realized result differ.

## Conservative defaults
- `EnableTrading=false`: attach and inspect signals first; explicitly enable only after compilation and demo validation.
- Risk per trade: 0.25% of account balance.
- Maximum 3 entries per symbol per server day.
- Daily equity-loss guard: 2% from the EA's captured start-of-day equity.
- One open position per symbol and Magic Number.
- Maximum spread: 30 points (must be calibrated to the broker and symbol).

## Multi-symbol use
Attach a separate EA instance to each desired chart/symbol. Use a unique Magic Number per instance if you need independent tracking. The EA evaluates the chart's symbol only; it does not scan Market Watch or open trades on other symbols.

## Installation and validation
1. Copy the file to `MQL4/Experts/`.
2. Open MetaEditor and compile.
3. Keep `EnableTrading=false` for initial signal/log review.
4. Backtest each symbol with realistic spread, commission, swap, and tick data.
5. Run on demo and verify order sizing, stop distances, lock behavior, daily guard, and broker restrictions.
6. Enable live trading only after independent validation and explicit user decision.

## Known limitations
- Not compiled or backtested by the repository authoring step.
- Daily-loss reference is captured when the EA starts and resets on the broker-server day; restarting the EA mid-day resets that reference.
- Daily loss guard blocks new entries; it does not force-close existing positions.
- Trade count depends on the terminal's loaded account history.
- Tick-value/tick-size conversion must be validated on each broker instrument, especially CFDs and crypto symbols.
- The spread default is not universal; tune it per symbol only after measuring broker conditions.
- A range strategy can lose persistently during trends or breakouts. The breakout filter reduces, but cannot eliminate, this risk.
