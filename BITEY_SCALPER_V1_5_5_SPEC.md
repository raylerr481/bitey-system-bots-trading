# Bitey Scalper v1.5.5 — Balanced Live Analysis

## Base and compatibility
- Forked from `experimental/scalper-v1-5-4-9-net-giveback-50-fix`.
- v1.5.4.9 source remains untouched.
- Retains existing signal families, risk sizing, five-position hard cap, one position per normalized asset, six-closed-bar same-asset/same-direction loss cooldown, stale-quote gate, rolling loss-risk scaling, currency/aggregate exposure guards, adaptive SL/TP, confirmed retracement exit and 50% net-peak giveback protection.
- No martingale, risk bypass, daily-loss entry lock, account-mode gate or SL widening.

## Equilibrated mode
1. Live position observer evaluates every open EA position in the existing management cycle and emits a rate-limited `BALANCED_LIVE_ANALYSIS` record: directional progression, EMA alignment, ADX, RSI, ATR, booked floating net, SL and TP. Existing management remains authoritative; the observer does not force-close or modify orders.
2. Asset/direction history ranking examines the latest closed EA trades for the same normalized asset and direction. At least eight matching outcomes are required by default. A ranking bonus requires both >=55% win rate and positive aggregate net. Low win rate or negative aggregate net receives only a capped ranking penalty, never a hard asset ban.
3. Candidate order retains signal score, spread penalty and session-performance adjustment, then adds the bounded historical asset/direction adjustment. Existing execution, broker, quote, stop, permission and risk checks remain authoritative.

## New defaults
- `InpEnableBalancedLiveAnalysis=true`
- `InpBalancedAnalysisLogIntervalSec=60`
- `InpAssetWinRateLookback=20`
- `InpAssetWinRateMinSample=8`
- `InpAssetWinRateScoreWeight=12.0`
- `InpAssetWinRateMaxAdjustment=3.0`

## Validation gate
Compile in MetaEditor, then compare v1.5.4.9 and v1.5.5 using identical Strategy Tester dates, symbols, spread and modelling. Forward-test on demo before replacement. Require at least 100 closed trades and report net win rate, loss rate, average net winner/loser, expectancy, profit factor, drawdown and all costs by asset and direction. Target is winners > losers AND positive net expectancy; neither is guaranteed.

## Limitations
The live observer is diagnostic and delegates actions to v1.5.4.9 management. Historical ranking is inactive below minimum sample and may be noisy. Floating net is booked profit+commission+swap; future close commission and slippage remain dependent on broker configuration. Stale quotes still prevent EA-side management while broker SL/TP remain active. Source editing does not perform MetaEditor compilation, Strategy Tester or terminal validation.
