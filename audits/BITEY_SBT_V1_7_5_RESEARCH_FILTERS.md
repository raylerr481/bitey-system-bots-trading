# Bitey SBT v1.7.5-R — entry filter experiment

Status: **research candidate only; not compiled, backtested, or approved for live use**.

## Why this exists
The reported v1.7.2.1 tester run was negative: net -$30.34, profit factor 0.82, expectancy -$0.16/trade over 186 trades. It also reported 74 chart-mismatch errors and used a $10,000 tester deposit, not the intended $500 reference capital. Those results do not establish whether v1.7.4 or this candidate is profitable.

## Changes from v1.7.4
- Adds `InpMinSignalScore=26.0`: blocks signals whose consensus score, after the existing spread/commission penalty, falls below the threshold.
- Adds `InpMaxSignalBarATR=2.0`: blocks a signal if the last closed candle's high-low range exceeds 2 ATR, to test whether avoiding volatility spikes reduces chasing.
- Retains the v1.7.4 source's existing risk controls, SL monotonicity guard, adaptive exits, accountMode policy and symbol universe.

These are testable hypotheses, **not a claim of improved profitability**. They may reduce trade count or miss profitable breakouts.

## Required A/B test
1. Compile both v1.7.4 and v1.7.5-R in MetaEditor; save compiler logs.
2. Use identical symbol, timeframe, date range, history, spread, commission, swap, slippage assumptions, and strategy inputs. Resolve the 74 chart-mismatch errors before accepting results.
3. Test v1.7.5-R with both new filters disabled (`InpMinSignalScore=0`, `InpMaxSignalBarATR=0`) as a control, then enable each filter separately, then together.
4. Use chronological train/validation/holdout windows; never tune on the holdout.
5. Compare net P/L, PF, expectancy, trade count, max drawdown in USD, long/short split, average win/loss, and costs. Reject changes that only improve one interval or reduce trades without improving out-of-sample expectancy.
6. Confirm the $500 reference-capital sizing and hard per-trade/aggregate risk in logs. Tester deposit $10,000 must not be mistaken for a $500 portfolio test.

Do not merge this candidate into main or use it on a real account until the tests are reproducible and independently reviewed.
