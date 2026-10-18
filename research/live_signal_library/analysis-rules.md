# SBT Variant Analysis and Promotion Rules

## 1. Separate current signal from historical evidence
A model's current closed-bar signal (BUY/SELL/NONE) is not the same as its historical BUY/SELL performance. Only a model whose current signal matches the side under consideration contributes a current directional vote.

## 2. Evidence quality
For each variant and direction, report:
- sample count and independent train/validation/holdout periods;
- win rate, mean R, median R, profit factor, expectancy, maximum drawdown, loss streak, and trade count;
- results after commission, spread, swap/funding where applicable, and conservative slippage assumptions;
- per-symbol, per-timeframe, and per-regime breakdown;
- confidence intervals or bootstrap uncertainty where feasible.

Historical OHLC replay must use signal on a fully closed bar and entry on the next available bar. If a candle touches both SL and TP, count SL first unless lower-timeframe/tick data resolves ordering. Historical spread must be sourced from historical data; if only current spread is available, label it as a proxy and do not claim execution-accurate backtesting.

## 3. Avoid leakage
- Chronological split only: train first, validation next, untouched holdout last.
- Do not tune parameters against the final holdout and then report that holdout as independent.
- Keep variants and data ranges versioned; record source commit and exact parameters.
- Require sufficient samples; tiny samples with 100% win rate are not qualified evidence.
- Compare against simple baselines and account for multiple variants tested.

## 4. Direction and decision
Evaluate BUY and SELL symmetrically. Return BUY or SELL only when the current signal agrees with enough qualified independent model groups and the side passes all risk and execution gates. Return WAIT when evidence is insufficient, directions conflict without a robust margin, quotes are stale, spread is excessive, or costs erase expectancy.

## 5. Real-money-equivalent risk
Risk controls are identical on demo and live accounts. A demo run tests mechanics; it does not prove profitability. Respect the fixed effective capital reference, per-trade risk cap, daily loss cap, position limits, stop-level constraints, and manual MT4 authority. Do not increase size to force a trade.

## 6. Variant ranking
Rank by out-of-sample net expectancy and drawdown-adjusted performance after costs, with stability across time and assets. A higher training win rate alone is not a promotion criterion. No report can guarantee future profitability.

## 7. Promotion gate
Research candidate -> compile successfully -> deterministic Strategy Tester checks -> demo forward test -> manual review -> separately authorized deployment. No automated promotion, live-order enablement, or production overwrite.
