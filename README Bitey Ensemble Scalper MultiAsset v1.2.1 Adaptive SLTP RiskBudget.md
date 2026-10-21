# Bitey Ensemble Scalper MultiAsset v1.2.1 — Adaptive SL/TP RiskBudget

## Purpose
This is a separate revision of the v1.2 EA that adds broker-stop preflight validation and richer diagnostics for MT4 error 130.

## Changes
- Preserves the existing 32-vote ensemble, signal thresholds, and USD 500 reference-capital / 1% per-trade / 2% aggregate-risk defaults.
- Calculates stop distance with the current spread and a conservative buffer based on the larger of broker stop level and freeze level.
- Validates normalized BUY stops against Bid and SELL stops against Ask before calling OrderSend.
- Recalculates the stop distance after price normalization so position sizing uses the actual normalized SL distance.
- Logs `STOP_LEVEL_PREFLIGHT_REJECT` if stop prices fail local validation.
- On an OrderSend failure, logs quote, SL/TP, stop-level and freeze-level values; error 130 gets a specific diagnostic.
- Does not automatically widen stops and retry after error 130. That avoids silently changing planned risk or reward/risk after sizing.
- Keeps the existing aggregate risk budget and minimum-lot rejection behavior.

## Important limits
- MT4 brokers may enforce dynamic stop rules or contract-specific tick grids not fully exposed through `MarketInfo`. A preflight check reduces avoidable error 130 rejections but cannot guarantee acceptance if quotes or broker rules change between validation and execution.
- The estimate based on `MODE_TICKVALUE` and `MODE_TICKSIZE` depends on correct broker metadata, especially for crypto CFDs.
- The file has been committed to the feature branch, but has **not** been compiled in MetaEditor or validated by a Strategy Tester/backtest. Test on demo first and review the Experts/Journal logs before enabling real-money trading.
