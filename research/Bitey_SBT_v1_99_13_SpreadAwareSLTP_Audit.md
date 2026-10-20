# Bitey SBT v1.99.13 — spread-aware SL/TP and profitability evidence audit

Date: 2026-10-20
Branch: `research/v1.99.13-spread-aware-sltp`
Status: research-only; no production merge or deployment.

## What changed from v1.99.12

- MQL4 property version is `1.993`; human-readable EA version is `v1.99.13`.
- Added `InpSLTPSpreadCostMultiplier=1.50` (minimum accepted value 1.0).
- Added per-ticket `AdaptiveSLTPProfitThresholdUSD()`. The threshold is the larger of the configured USD0.50 baseline and 1.5x the estimated live spread cost plus any nonnegative configured round-turn commission and expected swap.
- Wired the dynamic threshold into the adaptive SL/TP activation gate, timer reset, diagnostics, and break-even fallback condition.
- Kept the 30-second persistence and three favorable fully closed candles before adaptive changes.
- Kept monotonic stop-loss tightening, favorable-only take-profit extension, ATR management, broker stop/freeze checks, the fixed USD500 strategy reference, USD1.25 intended per-position risk cap, USD8.75 aggregate intended stop-risk cap, USD10 daily loss limit, max seven positions, one position per canonical asset, no martingale, and the existing train/holdout evidence gates.
- New helper returns the baseline threshold when broker point/tick data are invalid. It does not assume that a spread ceiling of 100 is economically cheap.
- The estimate depends on correct broker MODE_POINT, MODE_TICKSIZE, MODE_TICKVALUE and spread reporting. For synthetic symbols such as AMZNUSDT/METAUSDT/GOOGLUSDT/AVGOUSDT/ORCLUSDT, confirm these values in MT4 Symbol Specification and test calculated dollar costs against a known ticket before enabling live execution.

## Interpretation of the supplied ASSET DISCOVERY logs

The five examples are configured candidates with sufficient displayed bars and a current reported spread below the 100-point ceiling:
- AMZNUSDT: spread 50 points, quote age 46 seconds.
- METAUSDT: spread 50 points, quote age 5 seconds.
- GOOGLUSDT: spread 50 points, quote age 6 seconds.
- AVGOUSDT: spread 50 points, quote age 6 seconds.
- ORCLUSDT: spread 10 points, quote age 6 seconds.

These logs only show discovery/initial eligibility. They do not prove that an order was sent, filled, or profitable. The log itself says execution is conditional on an EA instance running on the chart and all live signal/risk gates passing. The EA must also pass local directional signal quorum, training and chronological holdout evidence, fresh quote, verified tick economics, commission/swap, margin, stop distance, portfolio capacity/risk, and broker order checks.

## What is actually known about profitability

- The available MT4 account report dated 2026-10-12 showed closed net P/L +USD69.26, gross profit USD115.00, gross loss USD45.74, profit factor 2.51, 21 closed trades with 8 winners (38.10%), and reported maximum drawdown USD30.80 (0.29%).
- This is account-level performance and cannot be attributed to a particular Bitey SBT build. It included EURUSD positions up to 0.53 lots and a single reported loss of USD30.80; it does not demonstrate compliance with the later USD500 reference capital and USD1.25 intended risk cap.
- No specific EA version can honestly be called the proven profitable version until each closed ticket is linked to its opening build and netted as profit + commission + swap.

## Previously observed model proxies — not verified broker profitability

| Model / direction | n | Win rate | Average proxy R | Interpretation |
|---|---:|---:|---:|---|
| VWAP_DEVIATION SELL | 46 | 0.630 | +0.382 | Best observed candidate; re-test out of sample |
| MEANREV SELL | 16 | 0.563 | +0.356 | Promising but small sample |
| HTF_TREND_CONFIRM SELL | 129 | 0.442 | +0.133 | Larger sample, modest edge proxy |
| BREAK_RETEST SELL | 14 | 0.500 | +0.118 | Small sample |
| LINEAR_REGRESSION SELL | 82 | 0.439 | +0.084 | Modest proxy edge |
| ATR_VOLATILITY_BREAKOUT SELL | 27 | 0.519 | +0.077 | Re-test net of costs |
| MOMENTUM BUY | 48 | 0.313 | -0.332 | Negative proxy; do not whitelist |
| BOLLINGER_EXPANSION SELL | — | — | -0.139 | Negative proxy |
| DONCHIAN SELL | — | — | -0.036 | Negative proxy |
| RSI_DIVERGENCE | 3 | — | — | Too few samples |

These are historical-bar forward-outcome proxies, not executed trades. They do not fully account for spread, slippage, swap, commissions, partial fills or intrabar ordering. Keep per-direction train/holdout gates; do not whitelist solely from the table.

## Validation still required

1. Compile in MetaEditor and fix all errors/warnings.
2. In Strategy Tester, use realistic spread, tick value/size, commission, swap and execution assumptions for each asset.
3. Check that the new dynamic activation threshold equals or exceeds the USD0.50 baseline and responds correctly to changes in spread and lots.
4. Validate spread-cost conversion against a real demo ticket for every synthetic USDT symbol.
5. Forward-test on demo; record build ID, model, symbol, direction, lot, spread, tick specs, SL/TP modifications, ticket outcome, commission and swap.
6. Attribute net results per version and report expectancy, profit factor, drawdown, loss tails, and per-asset/model/direction performance.

No MetaEditor compile, Strategy Tester run, forward-demo test, or deployment was performed as part of this source change. The `main` branch remains untouched.
