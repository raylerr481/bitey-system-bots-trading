# Bitey Scalper v1.5.5 — Adaptive Win-Rate Ranking

Baseline: `experimental/scalper-v1-5-4-9-net-giveback-50-fix` (v1.5.4.9 strategy source). EA: `Bitey_Scalper_MultiAsset_v1_5_5_AdaptiveWinRateRanking.mq4`. Version: 1.5.5; MQL4 Market property: 1.550.

## Purpose
Improve ordering of valid BUY/SELL candidates while preserving candidate generation and the intended v1.5.4.9 operating pace. This experiment does not guarantee a higher win rate.

## Changes
- Ranking-only adjustment from closed-bar EMA alignment, ADX regime, RSI momentum/extremes, candle close location and ATR relative to its recent mean.
- Same-asset/same-direction historical net performance influences ranking only after at least five closed trades (configurable).
- Emits `ADAPTIVE_WINRATE_RANKING` records and exposes the adjustment in candidate priority data.
- No new rejection threshold, global cooldown, forced entry, signal-direction change or lot-size change.

## Preserved
Multi-symbol universe, BUY/SELL, maximum five positions, existing signal families/hard filters/session/cooldown/quote checks, risk sizing and exposure controls, progressive and rolling loss management, warning-only daily loss policy, adaptive SL/TP, break-even, trailing, TP expansion, no SL widening, net-profit protection and 50% net peak-giveback logic. Open-position management is unchanged.

## Validation
Compile in MetaEditor; compare .9 and 1.5.5 on identical data, symbols, timeframe, date range, spreads, commissions and inputs. Compare trade count, win rate, net after costs, PF, DD, average win/loss, and per-asset/direction results. Then use out-of-sample and demo forward tests. Not compiled or tested yet; no performance improvement is claimed.
