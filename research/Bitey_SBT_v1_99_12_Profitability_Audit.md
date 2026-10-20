# Bitey SBT version and profitability audit — v1.99.12

Date: 2026-10-20  
Scope: repository research sources, Journal excerpts, and the MT4 account-history report available in the working conversation.

## Executive conclusion

A positive MT4 account result is documented, but the available evidence does not reliably attribute that profit to one particular EA version. Do not label v1.65, v1.68, v1.62, v1.99.11, or any other release "the profitable version" without joining each closed ticket to the exact opening version and netting commission and swap.

## Evidence-backed account result

The MT4 report dated 2026-10-12 records:
- Closed net P/L: +USD 69.26
- Gross profit: USD 115.00
- Gross loss: USD 45.74
- Profit factor: 2.51
- 21 closed trades; 8 profitable (38.10%)
- Maximal drawdown: USD 30.80 (0.29% as reported)

This is an account-level report, not a version-level performance report. It includes EURUSD positions with lots up to 0.53 and a reported individual loss of USD 30.80. It cannot be assumed to have respected the later SBT strategy reference of USD 500 and USD 1.25 maximum intended stop risk per position.

## Version evidence available

- v1.13 onward: archived source and logs prove iterative development and trading-related decisions; source presence alone does not establish profitability.
- v1.49.2: code documents seven-asset deduplication and historical proxy gates; this is not an audited profit statement.
- v1.58–v1.62: Journal excerpts show actual position supervision and entry/rejection decisions. A closed-trade report received HTTP 429 in one excerpt, which is a telemetry failure and does not negate the MT4 close itself.
- v1.65–v1.68: available conversation records show operating activity and a HYPE position opened by v1.68.0 and later supervised by v1.72.0. No complete per-ticket net outcome mapping proves which version earned positive net profit.
- v1.99.11: heartbeat shows connectivity, fresh quotes and terminal trading permission. It does not prove a profitable trade, nor does it prove that the live signal, commission/swap, stop-risk, and portfolio gates all pass.

## Historical model proxies — candidates for further validation, not proven profitable models

Previously observed historical-bar proxy metrics included:
- VWAP_DEVIATION SELL: n=46, win rate 0.630, average proxy R +0.382
- MEANREV SELL: n=16, win rate 0.563, average proxy R +0.356
- HTF_TREND_CONFIRM SELL: n=129, win rate 0.442, average proxy R +0.133
- BREAK_RETEST SELL: n=14, win rate 0.500, average proxy R +0.118
- LINEAR_REGRESSION SELL: n=82, win rate 0.439, average proxy R +0.084
- ATR_VOLATILITY_BREAKOUT SELL: n=27, win rate 0.519, average proxy R +0.077

Counterexamples from the same analysis included MOMENTUM BUY n=48, win rate 0.313, average proxy R -0.332; BOLLINGER_EXPANSION SELL average proxy R -0.139; DONCHIAN SELL average proxy R -0.036; RSI_DIVERGENCE with only three samples.

These are bar-based forward-outcome proxies, not executed broker trades. They do not fully model spread, slippage, swaps, commissions, partial fills, or real intrabar ordering in all cases. Retain per-direction training and chronological holdout gates; do not whitelist a model solely from these figures.

## v1.99.12 research candidate changes

New source: Bitey_SBT_MultiAsset_v1_99_12_AdaptiveProfitSLTP.mq4

- MQL4 property version: 1.992; descriptive EA version: 1.99.12.
- Fixed strategy capital remains USD 500.
- Per-position intended stop-risk cap remains USD 1.25; aggregate intended open stop-risk cap remains USD 8.75; daily loss limit remains USD 10.
- Maximum seven concurrent positions; one position per canonical asset; no martingale.
- Spread ceilings: SOL 100, EURUSD 30, USDJPY 35, NEAR 100, BTC 100, XAU 80, ETH 100, other fallback 100 points. The broker's point scale must be verified per symbol; a ceiling of 100 is not a promise that the spread is economically cheap.
- Adaptive SL/TP net-floating-profit activation lowered from USD 5.00 to USD 0.50; persistence reduced from 120 seconds to 30 seconds. Three favorable closed candles remain required.
- Break-even trigger 0.60 ATR; lock buffer 0.08 ATR; trailing begins at 0.90 ATR with 0.80 ATR distance; TP extension begins at 0.85 ATR and extends 1.50 ATR when the closed-bar trend continues; minimum modification threshold 0.10 ATR.
- SL remains monotonic (never loosened); TP only extends favorably. Broker stop/freeze constraints and readback checks remain required.
- Emergency floating-loss close attempt remains at net floating P/L <= -USD 1.25. This is best-effort; gaps, slippage, rejected closes, and unavailable trade context can exceed the threshold.
- Unknown commission/swap defaults remain negative/unknown and intentionally block new entries until configured to verified broker costs. Do not set them to zero unless the account is genuinely commission/swap-free.
- The cross-asset scanner's discovery records indicate candidates, not orders. Execution still requires the EA to run in the terminal and all current local signal, training, holdout, quote, spread, cost, broker, and portfolio risk gates to pass.

## Required verification before production use

1. Compile the source in MetaEditor; resolve all compiler errors and warnings.
2. Run MT4 Strategy Tester with realistic symbol specifications, spread, commission and swap.
3. Forward-test on demo and verify every open/close ticket against the Journal.
4. Export MT4 Account History with full details. Attribute tickets to EA version/build using versioned order comments or a version field in the trade journal; calculate net profit as profit + commission + swap.
5. Compare per-version profit factor, expectancy, drawdown, loss tails, risk-at-stop, and results by asset/model/direction.
6. Verify the ASSET DISCOVERY, CROSS-ASSET CANDIDATE, order-send, order-result, and closed-trade records. Discovery alone is not evidence of execution.

## Status

Research-only candidate. This source has been committed to a dedicated research branch; it has not been compiled, backtested, forward-demo tested, or deployed by this audit. Production/main branch was not modified.
