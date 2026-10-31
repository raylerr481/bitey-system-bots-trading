# Bitey Ensemble Scalper v1.8.3.0 — Adaptive Range & Net Profit

## Status
Experimental branch. Not compiled in MetaEditor and not validated in Strategy Tester. Do not install on a live account until compilation, broker-cost configuration, and demo/backtest acceptance are complete.

## Source lineage
This experimental EA is based on the latest complete source retrievable during this task:
`Bitey_Scalper_MultiAsset_v1_4_4_PerSymbolMarketDiagnostics.mq4`
from `feature/scalper-v1-4-4-per-symbol-market-diagnostics`.

The requested `v1_8_2_0_Scratch.mq4` was not available in the repository or attached files. This is therefore a separate experimental continuation from v1.4.4, not a verified patch on top of v1.8.2.0. Later changes in the missing source may not be present.

## Included
- Retains the existing multi-asset, bidirectional signal engine: trend, momentum, breakout and Bollinger mean-reversion families, with ADX regime classification.
- Retains the existing portfolio risk controls: USD 500 reference capital, 0.5% per trade, 2.5% aggregate open risk, 1.5% currency risk, 3% daily loss entry block, maximum five positions.
- Retains adaptive SL/TP, break-even, trailing and net-profit lock logic.
- Adds per-ticket floating-net excursion telemetry:
  - `max_net_usd` (MFE in account currency, based on floating net)
  - `min_net_usd` (MAE in account currency, based on floating net)
  - `first_target_sec` (seconds from open until the configured scratch threshold is first reached)
  - `close_net_usd`
- Adds `InpScratchSafetyUSD` (default 0.02).
- Adds `InpCloseCommissionConfirmed` (default false). Scratch closes remain disabled until the operator confirms how the broker charges closing commission. This avoids treating an unknown close commission as zero.
- Scratch threshold is the configured net target plus safety margin, after booked commission/swap and configured close-commission and slippage reserves.

## Broker configuration required
1. Confirm account currency and contract tick-value/tick-size behavior for every traded asset.
2. Determine whether commission is charged on entry, exit, or both.
3. Set `InpEstimatedCloseCommissionPerLot` in account currency per 1.0 lot when applicable.
4. Set `InpCloseCommissionConfirmed=true` only after that verification.
5. Keep `InpSmallProfitCloseUSD=0.10` and `InpScratchSafetyUSD=0.02` as initial experimental values; validate them by symbol and lot size. They are not guaranteed profitable thresholds.

## Required validation
- Compile with MetaEditor (F7); resolve every error and warning.
- Strategy Tester with realistic variable spread, commission, swap and slippage.
- Compare against the exact baseline on identical dates and symbols.
- Out-of-sample test; report net profit, profit factor, expectancy, drawdown, trade count, costs, BUY/SELL breakdown and per-symbol results.
- Inspect `TRADE_EXCURSION_AUDIT` logs. In particular, quantify losing trades that reached the scratch threshold before their eventual loss.
- Do not optimize on the same period used for final evaluation.

## Safety
No martingale, no averaging down, no stop widening, no bypass of trade-permission checks. The EA's account type is not used as an order gate, but symbol/terminal permissions and all risk checks remain active.
