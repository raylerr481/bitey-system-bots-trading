# Bitey Ensemble Scalper MultiAsset v1.8.0.9-EXP (ProfitSelector)

EXPERIMENTAL. Not compiled in MetaEditor by the author of this change and not validated in the MT4 tester. Test before any use with real money.

Base: v1.8.0.8 (equity-token session window, prefilter, crypto priority) on top of the 30 evaluators / 2 election assemblies / CSV audit architecture.

## Why

Data in the repo (`Bitey_Ens_MFE_MAE_21102027.csv`, 222 trades, 27/08 to 24/10, older versions): gross +5.91 USD, commission -44.00 USD, net -38.09 USD. Win rate 48%, average win 1.66 USD vs average loss 1.88 USD. The signal is roughly break-even before costs, so costs and payoff decide the result.

Break-even win rate with reward/risk `RR` and cost `c` (in R) is `(1 + c) / (1 + RR)`. With RR 1.8 and c 0.20: 43%. With RR 2.0 and c 0.10: 36.7%.

## The six levers

| # | Lever | Inputs | Default |
|---|-------|--------|---------|
| 1 | Adaptive stop: widen the stop in 0.25 ATR steps until cost-R <= target. Lot shrinks so money risk is constant, so commission and spread per R fall. | `InpStopATR` (base), `InpStopATRMax`, `InpTargetCostR` | 1.5 / 2.25 / 0.10 |
| 2 | Selectivity: minimum ensemble score and a daily trade cap. | `InpMinScore`, `InpMaxTradesPerDay` | 30 / 12 |
| 3 | Let winners run: reward/risk by regime. | `InpRewardRisk` (trend), `InpRewardRiskRange` | 2.0 / 1.5 |
| 4 | Lower cost ceiling. | `InpMaxCostR` | 0.15 (was 0.20) |
| 5 | Cheap assets first: ranking subtracts `InpCostRankExtra x cost-R`. | `InpCostRankExtra` | 15 |
| 6 | Optional limit entries at the touch price, deleted when unfilled. | `InpUseLimitEntry`, `InpLimitMaxSpreadMult`, `InpLimitExpireBars` | false / 1.5 / 2 |

`InpMinScore = 30` equals three agreeing families. In the 27/10 ActionLog, 35% of approved signals scored below 30 and every opened trade scored 30.4 or more.

## Profit selector (analysis and choice)

Enabled by `InpUseProfitSelector`. For each candidate that passes the 30-model assemblies:

1. Realized history: the symbol's last `InpMemWindow` closed trades (at most `InpMemDays` days old) from this magic number, net of commission and swap, divided by the nominal risk per trade, gives R per trade.
2. Shrinkage: `edge = (sumR + w x prior) / (n + w)` with `w = InpMemPriorWeight`. With few trades the edge stays near the prior, so noise does not dominate.
3. Ranking: `adjusted = score - overlap penalty + crypto bonus + InpMemWeight x edge - InpCostRankExtra x costR`.
4. Soft ban: if `n >= InpMemMinTrades` and `edge < -InpMinNetEdgeR`, the symbol is skipped (earlier than the existing 12-trade expectancy ban).
5. Audit: every pick writes a `SELECTOR / RANKED` row in `Bitey_ActionLog.csv` with edgeR, memN, costR and rawScore. Score and edge rejections write `SELECTOR / REJECT` rows (throttled).

It is a heuristic ranking, not a guarantee. Per-symbol samples are small (the 27/10 NetByAsset file has 1 to 5 trades per symbol).

## Limit entries (lever 6): read before enabling

- A resting order at the touch price saves the spread only when it fills. It tends to fill when price moves against the entry, so fills skew toward losers and misses skew toward winners. Keep it OFF until the tester shows a net gain.
- Pending orders count toward open positions, one-per-asset and aggregate risk while the mode is on. FX net-exposure and crypto/equity cluster caps count filled positions only.
- Unfilled orders are deleted after `InpLimitExpireBars` signal bars and logged as `LIMIT_EXPIRED`.

## Suggested tester protocol

Same period (for example 01/08 to 24/10), same deposit, same symbols, every-tick model. Compare net after commission, profit factor, max drawdown and trade count.

1. v1.8.0.7 as baseline.
2. v1.8.0.8 (session window and prefilter only).
3. v1.8.0.9 with defaults.
4. v1.8.0.9 with `InpStopATRMax = InpStopATR` (no widening) to isolate lever 1.
5. v1.8.0.9 with `InpMinScore = 0` to isolate lever 2.
6. v1.8.0.9 with `InpUseProfitSelector = false`.

A wider stop lengthens the time a trade needs to resolve; if many trades end by the time exit, raise `InpMaxHoldBars` (for example 48 to 72).

## Known limits

- The equity-token window (16:45 to 22:30 server) is an assumption; check it against your broker and US daylight saving time.
- NATGASUSDT and other non-stock tokens not in the crypto list follow the equity window.
- The selector learns only from this magic number's history visible to the terminal (set Account History to All History).
