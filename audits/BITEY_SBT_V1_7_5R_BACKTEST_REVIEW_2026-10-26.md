# v1.7.5-R backtest review — user-reported 2026-10-26

## Result reported by user
- Bars: 15,365; modeled ticks: 17,128,940; model quality: 90%
- Chart mismatch errors: 74
- Tester deposit: $10,000; spread shown as Current (0)
- Net: -$34.82; gross profit: $160.84; gross loss: -$195.66
- Profit factor: 0.82; expected payoff: -$0.18/trade
- Maximum drawdown: $47.41 (0.47%)
- Trades: 195; winners 91 (46.67%); losers 104 (53.33%)
- Average winner: $1.77; average loser: -$1.88
- Shorts: 104 trades, 50.00% wins; longs: 91 trades, 42.86% wins
- Longest losing streak: 8 trades, -$16.21

## Interpretation
This is a losing test and does not validate v1.7.5-R as profitable. With the reported average win/loss, the simple break-even win rate is approximately 51.5%, before any costs not already reflected in those averages. The long side is weaker in this sample, but that alone is not enough to permanently disable BUY entries; results need comparable, direction-separated tests.

Compared with the previously reported run (net -$30.34, PF 0.82, 186 trades, 50% winners, max DD $37.03, spread Current (1)), this run lost $4.48 more and had $10.38 more maximum drawdown. The spread setting differs (0 vs 1), so this is not a controlled comparison and the difference cannot be attributed to the v1.7.5 filters alone.

## Blocking issues before strategy optimization
1. Resolve the 74 chart mismatch errors and verify historical data quality.
2. The EA's `ParseSymbols()` explicitly adds only the chart symbol when `IsTesting()` is true. Therefore, a standard MT4 Strategy Tester run does **not** test the full 114-symbol live portfolio; it tests the chart symbol only.
3. The tester deposit is $10,000. Verify that lot sizing and all risk brakes truly use `InpReferenceCapitalUSD=500` as intended.
4. Keep spread, commission, swap, slippage, dates, symbol, timeframe and all other settings identical for A/B comparisons.

## Controlled next tests
Run on the same symbol and date range with the same history/cost settings:
- A: both v1.7.5 filters off (`InpMinSignalScore=0`, `InpMaxSignalBarATR=0`) — baseline.
- B: score filter only (`InpMinSignalScore=26`, `InpMaxSignalBarATR=0`).
- C: volatility-spike filter only (`InpMinSignalScore=0`, `InpMaxSignalBarATR=2`).
- D: both filters on (`InpMinSignalScore=26`, `InpMaxSignalBarATR=2`).
- Repeat with BUY-only and SELL-only as diagnostic runs using existing `InpAllowBuy` / `InpAllowSell` switches, without treating a single period as sufficient evidence to remove a direction permanently.
- Compare chronological out-of-sample results; do not tune on the holdout.

Record net P/L, profit factor, expectancy, trade count, maximum drawdown in USD, average win/loss, long/short performance, costs, and exact input settings for every run.

**Decision:** do not deploy this candidate to a real account and do not raise risk. This review records the reported outcome; no source changes are claimed to improve profitability until controlled tests confirm it.
