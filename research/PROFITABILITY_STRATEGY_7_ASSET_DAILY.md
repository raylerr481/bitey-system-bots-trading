# Bitey SBT: Daily Seven-Asset Net-Expectancy Strategy
## Research contract for `research/v1.99.1-operational-contract`

**Status:** strategy specification only. This document is not a claim of profitability, a compiled EA, or a completed backtest. It does not change production or the MT4 execution authority.

## 1. Objective

At each completed H1 bar, scan the symbols visible in MT4 Market Watch, rank all eligible canonical assets, and open **up to seven** positions only when every signal, evidence, execution-cost, broker, and portfolio-risk gate passes. Seven is a capacity limit, not a daily quota. Never force an entry to fill a target count.

Optimize **realized net expectancy after spread, commission, swap, and slippage**, with drawdown and reliability constraints. Do not optimize win rate alone: a high win rate with large average losses can still have negative expectancy.

## 2. Safety invariants

- Strategy capital remains fixed at USD 500; never scale from terminal account balance/equity.
- Maximum initial stop-risk per position: USD 1.25, calculated from broker tick size/value and the actual proposed SL/lot size.
- Maximum aggregate open stop-risk: USD 8.75 for seven positions, and never above the lower effective portfolio cap.
- Daily realized-plus-floating net loss of USD 10 blocks new entries. Continue protective supervision of existing positions.
- At most seven open positions, one per canonical underlying asset. Collapse broker aliases (for example, USD/USDT variants) to prevent duplicate exposure.
- No martingale, no automatic account switching, no retry loop that bypasses a rejected gate, no removal of the user's MT4 manual authority.
- Emergency close is best-effort only. Gaps, slippage, trade-context errors, and market closure can cause realized losses to exceed a nominal cap.
- If commission or expected swap is unknown, fail closed for new entries until the values are verified. Do not silently treat unknown cost as zero.

## 3. Daily candidate pipeline

1. **Universe discovery:** scan Market Watch only; log that this is not the broker's entire instrument catalogue. Require fresh quote (age <= 120 seconds), trading permission, sufficient bars, valid positive tick size/value, and configured spread ceiling.
2. **Canonical asset normalization:** select one preferred broker symbol per underlying asset and reject aliases already represented by an open position.
3. **Signal confirmation:** evaluate all 16 model families on the same symbol and completed bar. Require the live directional consensus and cross-asset direction to agree. Do not use an unfinished candle for an entry signal.
4. **Chronological evidence:** keep training older than the holdout window; do not shuffle time-series samples. Require at least train N >= 12, train WR >= 0.42, train average proxy R > 0.02; holdout N >= 6, holdout WR >= 0.40, holdout average proxy R > 0.00. These are minimum filters, not proof of an edge.
5. **Execution realism:** calculate net expected value with symbol-specific tick economics, current spread, conservative slippage, round-turn commission, and expected swap. Reject if any essential input is unknown or expected net value <= 0.
6. **Rank globally:** rank only fully qualified candidates by conservative net expectancy and stability, then penalize stale/expensive execution and correlated exposure. Avoid selecting seven highly correlated instruments that express essentially the same bet.
7. **Recheck at send time:** quote age, spread, permissions, minimum/step lot, stop/freeze levels, duplicate asset, per-position risk, aggregate risk, daily loss, and current open positions must be rechecked immediately before OrderSend.
8. **Protect and audit:** manage existing SL/TP, cost-aware break-even/trailing, and risk-limit alerts independently of whether new entries are allowed. Log a structured accept/reject reason for every candidate and every order attempt.

## 4. Ranking objective

Use a conservative score rather than raw win rate or technical score alone:

- Primary: lower-confidence-bound net expectancy per unit of stop risk, estimated from chronological out-of-sample observations.
- Secondary: holdout stability, adequate sample size, profit factor, drawdown, and consistency across regimes.
- Penalties: execution cost as a fraction of expected gross edge, stale/variable spread, high correlation with open positions, and unstable broker contract specifications.
- Tie-breaker: cleaner quote/execution conditions, then higher independent model agreement.

Do not use a model's `selectedExpectedRScore` as a win probability or a promise of profit. A positive historical proxy is not equivalent to actual filled-trade expectancy.

## 5. Evidence quality: current source limitations to resolve

The candidate source currently implements a directional historical bar proxy in `CrossAssetHistoricalEvidence()`: it scores a future close relative to the signal-bar close over a fixed horizon, normalized by 1.5 ATR, and subtracts a spread-price proxy. It does **not** reconstruct whether an intrabar stop or target would have been hit first, real order fills, variable spread, broker commission, swap, or slippage. It should remain a prefilter, not the final profitability validator.

The source's `ValidatePositiveExpectedNetProfit()` estimates costs using broker tick economics and configured commission/swap. Verify that the historical expected-R input and cost terms use the same accounting basis. In particular, avoid subtracting spread twice if expected R already includes it. A final validator should replay the proposed SL/TP path with conservative intrabar assumptions and all trading costs.

The scan uses `SymbolsTotal(true)`, so it only evaluates instruments visible in Market Watch. Make the intended universe explicit in MT4 and report discovered, eligible, blocked, and evidence-qualified counts separately.

Commission and swap inputs default to unknown negative values and intentionally block entries. Configure them from the broker's actual contract/statement; setting zero is valid only when confirmed. Check that tick value is expressed in account currency and correctly converted to USD when the account currency is not USD.

The three-closed-candle confirmation may be too late for some strategies and should be tested as a model-specific rule, not assumed to improve all assets. Compare variants strictly out of sample and retain it only when it improves net expectancy after costs.

## 6. What the available log excerpts show

The user-provided recent excerpts include a SOLUSDT H1 candidate with `MOMENTUM` selected and `selectedExpectedRScore=0.1465`; that score is a historical estimate, not a 14.65% win probability. They also show rejected model evidence, including BOLLINGER_EXPANSION SELL with train WR 0.400 and average R -0.182, and MACD_CONFIRM SELL with train WR 0.404 and average R -0.078. Those samples should not be promoted merely to increase trade frequency.

An excerpt with `campaignNetUSD=-27.10` needs separate realized P/L, floating P/L, broker-day boundary, and governor-state fields before concluding which daily-loss rule fired. Logs should include the exact rejection reason and a daily P/L reconciliation.

**Archive extraction status:** the branch contains dated ZIP/7z/RAR archives, but this connector returns UTF-8 text and cannot return those binary archive bytes for extraction. Therefore the contents of those archives have not been parsed in this pass. Do not treat the excerpts above as a full log audit.

## 7. Validation gates before enabling real-money use

1. Reconcile broker closed trades with EA telemetry, including commission, swap, partial closes, and time-zone/day boundary.
2. Run a tick-quality or conservative intrabar backtest across multiple market regimes and symbols; avoid look-ahead and survivorship bias.
3. Freeze parameters before the final holdout; report net expectancy, profit factor, maximum drawdown, exposure, number of trades, cost share, and confidence interval.
4. Forward-test on demo with identical broker symbol specifications and cost inputs. Verify that each order's actual stop risk matches the pre-trade estimate.
5. Test failures: stale quotes, disabled symbols, unknown costs, invalid tick size/value, min-lot risk above USD 1.25, stop/freeze restrictions, duplicate aliases, full portfolio, daily loss reached, requotes, and failed emergency close.
6. Do not deploy merely because compilation passes or a few trades are profitable. Promote only when the out-of-sample and forward evidence meet predeclared acceptance thresholds.

## 8. Required per-candidate audit record

At minimum log: timestamp/server day, symbol and canonical key, direction, closed-bar time, model votes, train/holdout N/WR/avgR, expected gross R, spread, commission, swap, slippage allowance, expected net USD/R, quote age, tick size/value, lot/minimum lot, estimated stop risk, aggregate open risk, correlation/duplicate check, daily net P/L, decision, and a machine-readable rejection reason.

## Bottom line

The current design already has the right structural idea—global ranking, per-symbol evidence gates, up to seven distinct positions, and bounded USD 500-based risk—but the historical bar proxy and unextracted archives do not establish profitability. The highest-value next step is to extract and reconcile the dated MT4 logs, then replace or validate the proxy against cost-aware SL/TP trade-path simulation before relaxing any gate.
