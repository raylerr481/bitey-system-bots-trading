# Bitey SBT repository profitability and EA audit — v1.99.14

Date: 2026-10-20
Scope: default-branch README, research EA sources v1.99.9–v1.99.14, available profitability audit notes, repository commit history for research shortlist/backtest infrastructure, and the supplied MT4 Journal records.
Status: research only. No production branch modified.

## Executive conclusion

**Closest current EA candidate by structure:** `Bitey_SBT_MultiAsset_v1_99_14_BidirectionalAdaptiveSLTP.mq4` in `research/v1.99.14-bidirectional-audit`.

It is the closest candidate to the requested combination of multi-asset discovery, BUY/SELL evaluation, 16 model families, independent train/chronological holdout evidence, USD500 fixed strategy reference, constrained risk, and adaptive SL/TP. This is a structural recommendation, NOT a claim that v1.99.14 is profitable. No EA version has been proven most profitable from the evidence retrieved.

Code: https://github.com/raylerr481/bitey-system-bots-trading/blob/research/v1.99.14-bidirectional-audit/research/Bitey_SBT_MultiAsset_v1_99_14_BidirectionalAdaptiveSLTP.mq4

## Repository and version findings

- The repository README describes an evidence-driven lifecycle (research → simulate → stress-test → validate → demo/paper → deploy) and says the platform does not promise profits.
- The v1.99.9 reconstructed research source is the base of the recent research candidates. v1.99.12 introduced lower profit-activation settings; v1.99.13 added a spread-aware profit activation threshold; v1.99.14 makes that helper use the same `TickSizePriceForSymbol()` normalization used by the EA's risk/expectancy calculations and corrects stale EA version telemetry.
- The new branch is isolated from `main`; no production merge or deployment occurred.
- The source exposes 16 model families: TREND, MOMENTUM, DONCHIAN, MEANREV, STRICT_RANGE, ATR_VOLATILITY_BREAKOUT, SESSION_BIAS, RSI_DIVERGENCE, HTF_TREND_CONFIRM, VWAP_DEVIATION, BREAK_RETEST, FIBONACCI_PULLBACK, VOLATILITY_SQUEEZE, LINEAR_REGRESSION, MACD_CONFIRM and BOLLINGER_EXPANSION.
- The EA contains BUY and SELL order paths and logs independent BUY and SELL historical evidence per eligible asset. Directional capability exists in code; profitability evidence is not equally strong for both directions.
- Market Watch discovery can consider configured/visible instruments, while one-position-per-canonical-asset, fresh quote, symbol specs, spread, current directional consensus, train/holdout, cost, broker and portfolio risk gates still apply. Discovery log entries are not executions.

## Profitability evidence available

### MT4 account report (2026-10-12)

- Closed net P/L: +USD 69.26
- Gross profit: USD 115.00
- Gross loss: USD 45.74
- Profit factor: 2.51
- 21 closed trades, 8 winners (38.10%)
- Reported maximum drawdown: USD 30.80 (0.29%)

This is account-level evidence, not version-attributed evidence. It included EURUSD position sizes up to 0.53 lots and a reported USD30.80 individual loss, so it does not demonstrate that later USD500-reference/USD1.25 intended per-position risk policy was followed. There is no complete mapping from each ticket to its opening EA build and net result (profit + commission + swap). Therefore no version is confirmed as the profitable winner.

### Previously observed model proxies

| Model/direction | n | Win rate | Average proxy R |
|---|---:|---:|---:|
| VWAP_DEVIATION SELL | 46 | 63.0% | +0.382 |
| MEANREV SELL | 16 | 56.3% | +0.356 |
| HTF_TREND_CONFIRM SELL | 129 | 44.2% | +0.133 |
| BREAK_RETEST SELL | 14 | 50.0% | +0.118 |
| LINEAR_REGRESSION SELL | 82 | 43.9% | +0.084 |
| ATR_VOLATILITY_BREAKOUT SELL | 27 | 51.9% | +0.077 |
| MOMENTUM BUY | 48 | 31.3% | -0.332 |
| BOLLINGER_EXPANSION SELL | — | — | -0.139 |
| DONCHIAN SELL | — | — | -0.036 |
| RSI_DIVERGENCE | 3 | — | — |

These are OHLC forward-outcome proxies, not broker fills or net realised trades. They do not fully model spread, slippage, commissions, swaps, partial fills and intrabar ordering. The apparent edge is more developed on the SELL side than the BUY side. Do not whitelist any model from these metrics alone. Continue per-asset, per-direction, chronological holdout checks.

### Repository backtest infrastructure

Repository commit history shows the addition of deterministic built-in backtests, multi-asset rebalance simulation, research-priority shortlist, and persistent Supabase evidence-store plumbing. The retrieved commits and code describe infrastructure, not a verified result set for the current MT4 EA. The simple built-in engine's close-price simulation is not equivalent to tick-level MT4 execution and cannot establish live profitability. No persisted backtest rows, complete MT4 Strategy Tester report, or per-version trade ledger were retrieved as part of this audit.

## v1.99.14 design

- MQL4 property version `1.994`, descriptive version `v1.99.14`.
- Fixed strategy reference capital: USD500.
- Intended per-position stop-risk hard cap: USD1.25.
- Intended aggregate open stop-risk cap: USD8.75.
- Daily loss limit: USD10, blocks new entries while protective management continues.
- Maximum seven simultaneous positions, one per canonical asset; no martingale.
- 16 model families, independent BUY/SELL historical feasibility, live directional quorum and train/holdout gates.
- Adaptive stop and target logic: ATR initial SL/TP, profit-lock trigger 0.60 ATR, lock buffer 0.08 ATR, trailing trigger 0.90 ATR, trail distance 0.80 ATR, target extension trigger 0.85 ATR, extension distance 1.50 ATR, minimum change 0.10 ATR.
- Adaptive SL/TP activation requires net floating profit to remain above the larger of USD0.50 and 1.5x the estimated live spread plus configured nonnegative commission/swap cost for 30 seconds; three favorable closed candles remain required.
- The threshold helper now uses `TickSizePriceForSymbol()`, matching the EA's existing risk and expectancy calculations instead of independently reading raw `MODE_TICKSIZE`.
- Existing SL is never loosened; TP extends only in the favorable direction when trend continuation is confirmed.
- Unknown commission/swap inputs remain negative and block new entries. Do not set them to zero unless the broker/account is verified to have no such cost.
- The USD1.25 emergency floating-loss close is best-effort, not a guaranteed maximum loss; gaps, slippage, rejected requests and unavailable trade context can cause a larger realised loss.
- Source includes corrected v1.99.14 order comments/diagnostic version identifiers where the prior candidate still reported older versions.

## Supplied ASSET DISCOVERY logs

AMZNUSDT 50 points (quote age 46s), METAUSDT 50 (5s), GOOGLUSDT 50 (6s), AVGOUSDT 50 (6s), ORCLUSDT 10 (6s). They pass the shown 100-point ceiling, but that only means preliminary spread eligibility. The 46-second AMZNUSDT quote is relatively old and should be rechecked at execution. `tickValue=1` and `tickSize=0.01` must be checked against MT4's symbol specification and a demo ticket; incorrect synthetic-CFD tick economics can distort risk and spread-cost estimates.

## Required acceptance tests before live use

1. Compile the exact v1.99.14 file in MetaEditor; fix all errors and warnings.
2. Run Strategy Tester on a portfolio of symbols with realistic spread, tick specifications, commissions, swaps, slippage and broker stop/freeze levels.
3. Produce separate BUY and SELL results per symbol/model: trade count, net expectancy, profit factor, drawdown, average win/loss, tail loss, exposure and cost contribution.
4. Use chronological walk-forward and untouched out-of-sample periods. Avoid selecting a winner from the same sample used to tune it.
5. Confirm adaptive SL/TP does not loosen SL, extend TP against the position, or trigger modifications with invalid tick specs.
6. Forward-test on demo and record the exact build ID for every ticket. Reconcile each close with profit + commission + swap.
7. Only then rank versions by net expectancy and risk-adjusted performance; include drawdown and risk breaches, not profit alone.

No MetaEditor compile, Strategy Tester run, forward-demo test, or deployment was performed. This branch is research-only and `main` remains untouched.
