# Video hypothesis integration

The trading education material is treated as a falsifiable quantitative hypothesis, not as proof of profitability.

## Alex Ruiiz example hypothesis

- starting capital: 1000 USD
- risk budget: 2% per trade
- 10 trades/month
- win rate assumption: 40%
- average winner: +4%
- average loser: -1.5%
- partial at target: 50%
- trailing: EMA(21)
- explicit costs: commission, spread/slippage and swap

Expected gross expectancy is:

`0.40 * 0.04 - 0.60 * 0.015 = 0.007` = 0.70% per trade.

This is an expectation under assumptions, not a forecast. The engine must test historical data, realistic costs, stress scenarios, out-of-sample and walk-forward performance before accepting a strategy.

## Product boundary

Bitey IA Web should present technical results requested by the user without exposing internal module names. Specialized trading execution remains behind the safety boundary and is research/demo/paper only.

## News integration

News is an independent evidence stream. Each item should be normalized into symbol/sector, event type, direction hypothesis, impact intensity, time horizon, source quality and confidence. News must be compared with subsequent market data and cannot directly create a live order.

Safety invariants: `live=false`, `real_money=false`, `broker_orders=0`.
