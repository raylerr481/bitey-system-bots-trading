# Bitey Turtle DayTrading MultiAsset v2

Status: research candidate. The source has been committed, but it has NOT yet been compiled in MetaEditor, backtested, or forward-tested by the assistant. Do not treat it as validated or profitable.

## Design
- Multi-symbol scanner runs from one chart using a comma-separated symbol list and a 5-second timer.
- Default list: EURUSD, GBPUSD, USDJPY, XAUUSD. Edit SymbolsCSV to match exact broker names/suffixes, for example EURUSD.a.
- M15 Donchian breakout using 20 prior closed bars, with H1 EMA 50/200 direction filter.
- BUY and SELL entries.
- Initial stop uses 1.5 × ATR(14), subject to broker stop distance.
- Take profit starts at 2R, where R is the initial stop distance. This target is volatility-adaptive through ATR-based initial stop distance, but it is not dynamically extended after entry.
- Break-even protection begins at 1R; ATR trailing stop can then tighten the stop. The stop is never intentionally widened.
- Default session end close is 22:45 broker server time. Verify server timezone and market hours; disable or adjust only with care.
- Daily loss limit USD 10 (estimate), max 3 simultaneous positions and max 6 entries/day.
- USD 500 reference capital and USD 1.25 planned risk budget per entry.
- No martingale, grid, averaging down, forced minimum lot, or forced trades without a signal.
- Does not block solely because the account is demo or live.

## Important broker-specific requirements
1. SymbolsCSV must exactly match names shown in Market Watch, including suffixes/prefixes.
2. Verify tick value/size, contract specification, minimum lot, lot step, stop level, spread units, account currency, commissions, swap, and margin for every symbol.
3. Commission and swap defaults are zero (unknown/not included) and can understate the loss estimate.
4. Risk sizing uses broker MODE_TICKVALUE and assumes its value is compatible with the USD risk budget. Non-USD account currencies and nonstandard CFD/crypto contract specifications need special verification; do not deploy if the calculated lot risk does not match broker economics.
5. Daily P/L is read from the MT4 account history currently loaded in the terminal. Set Account History to include all history when evaluating results.
6. Session-end close attempts to close this EA's positions; market closure, disconnected terminal, rejected orders, or slippage can prevent the intended close. Keep the protective server-side SL active.
7. This is an EA running in one terminal, not a broker-hosted scanner. MT4 must remain open, connected, AutoTrading enabled, and the EA must be permitted to trade.

## Install and verify
1. Open the .mq4 file in MetaEditor and press F7. Resolve every error and investigate warnings.
2. Check the Experts log for BITEY_DAYTRADING_INIT, SYMBOL_CONFIG, NO_ENTRY, SYMBOL_GATE, ORDER_OPENED, ORDER_REJECTED, and trailing/close errors.
3. Backtest each symbol with realistic variable spreads, commissions, swaps and slippage; use chronological out-of-sample data.
4. Forward-test on demo. Compare estimated risk with actual fills and stop losses before any live use.

A compile success or backtest profit does not guarantee future profitability. Gaps, slippage, stale quotes, broker metadata errors, terminal disconnection, and execution failures can cause losses beyond estimates.
