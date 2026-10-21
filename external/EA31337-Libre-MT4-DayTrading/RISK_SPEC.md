# Proposed risk specification — MT4 day-trading research

This document defines requirements for a future adaptation. It is not executable EA code and does not guarantee a maximum loss.

## Initial test scope

- Platform: MT4 / MQL4.
- Symbols: EURUSD and XAUUSD tested independently.
- Reference capital: USD 500.
- Initial planned risk budget: 0.25% of reference equity per trade (USD 1.25 at USD 500).
- Maximum simultaneous positions: 2 total and no more than 1 per canonical symbol.
- Timeframes to compare: M5 and M15, with separate reports.
- No martingale, grid recovery, averaging down, or forced minimum lot.
- No trading when market metadata, tick value, contract size, lot step, stop level, or quotes are invalid.

## Order safety requirements

1. Calculate risk using broker-specific tick size/value, contract specifications, account currency conversion, spread, and stop distance; reject if values are invalid or unverifiable.
2. Normalize lots to broker lot step and round down. If minimum lot exceeds the risk budget, reject the trade and log the reason.
3. Validate SL/TP distances against stop/freeze levels and price precision before submitting an order.
4. Check spread and slippage against explicit inputs. Do not silently relax filters after rejected orders.
5. Check trade permission and market session; never infer demo/live account status from a symbol name.
6. Respect manual trading authority. Do not close, reverse, or modify unrelated manual positions.
7. Avoid duplicate submissions on the same signal/bar and log broker ticket, requested/actual prices, lots, SL/TP, risk estimate, spread, slippage, and exact error/rejection reason.
8. Do not claim a fixed maximum loss: gaps, stop execution, liquidity, and broker behavior can exceed estimated risk.

## Validation gates

- Static source review and compile in MetaEditor with zero errors; warnings documented.
- Backtest with tick-quality assumptions documented and realistic commissions, spread, swap, and slippage.
- Report net profit, profit factor, maximum equity drawdown, trade count, expectancy, average win/loss, exposure, and costs.
- Separate optimization and out-of-sample periods; do not tune using the holdout period.
- Forward demo test with logs and reconcile EA-estimated risk against actual order specifications.
- No live deployment until all gates pass and the user explicitly authorizes it.

## No performance claims

A source adaptation, successful compile, backtest, or demo test is not proof of future profitability. Reports must distinguish simulated, demo, and live account results.
