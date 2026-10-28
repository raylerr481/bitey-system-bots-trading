# Bitey Ensemble Scalper MultiAsset v1.8.1.0-EXP (SelectorShadow)

EXPERIMENTAL. Not compiled in MetaEditor and not validated in the MT4 tester or on a demo account. Test before any use with real money.

Base: v1.8.0.9 (six cost levers, profit selector) on top of v1.8.0.8 (equity-token session window, prefilter) and the 30 evaluators / 2 election assemblies / CSV audit architecture.

## What changed from v1.8.0.9

| Change | Why |
|--------|-----|
| Selector R uses the risk recorded at entry (`R0` distance x actual lots, commission included). The nominal 0.5% budget is only a fallback for trades the EA did not track. | Lot rounding and minimum lots make real risk differ from the nominal US$2.50. |
| A broker-created continuation ("from #...") is not counted as an extra trade. | Guards against inflated sample size. The EA itself always closes the full lot, so this should be rare. |
| `InpMemByDirection` and `InpMemByRegime` (both false). | Memory per symbol + side and per regime (read from the order comment ` T` / ` R`). Off by default: per-symbol samples are 1 to 5 trades, and splitting them makes that worse. |
| `InpSelectorShadow = true` (default). | The selector computes and logs its edge and its would-be vetoes (`SELECTOR / SHADOW_VETO`) but does not change ranking or block entries. Set to false only after the logged data supports it. |
| Cost-R ranking term (lever 5) no longer depends on the selector. | It is a cost rule, not a learned one. |

Not changed: money risk is computed from the stop distance measured from the entry price, so spread is already inside the stop-loss amount (a BUY enters at the ask and is stopped when the bid reaches the SL). Commission is added on top.

## The six cost levers (from v1.8.0.9)

| # | Lever | Inputs | Default |
|---|-------|--------|---------|
| 1 | Adaptive stop: widen in 0.25 ATR steps until cost-R <= target; lot shrinks so money risk is constant. | `InpStopATR`, `InpStopATRMax`, `InpTargetCostR` | 1.5 / 2.25 / 0.10 |
| 2 | Minimum ensemble score and daily trade cap. | `InpMinScore`, `InpMaxTradesPerDay` | 30 / 12 |
| 3 | Reward/risk by regime. | `InpRewardRisk`, `InpRewardRiskRange` | 2.0 / 1.5 |
| 4 | Lower cost ceiling. | `InpMaxCostR` | 0.15 |
| 5 | Cheap assets first in the ranking. | `InpCostRankExtra` | 15 |
| 6 | Optional limit entries (adverse selection risk). | `InpUseLimitEntry` | false |

## Profit selector

`edge = (sumR + w x prior) / (n + w)`, with `w = InpMemPriorWeight`, over the symbol's last `InpMemWindow` closed trades (at most `InpMemDays` days). In shadow mode it only writes rows to `Bitey_ActionLog.csv`:

- `SELECTOR / RANKED`: `SHADOW edgeR=... memN=... costR=... rawScore=...` for each pick.
- `SELECTOR / SHADOW_VETO`: the symbol had `n >= InpMemMinTrades` and `edge < -InpMinNetEdgeR`.

With `InpSelectorShadow = false` the edge adds `InpMemWeight x edge` to the ranking and the veto blocks the symbol.

## How to validate (corrected)

The MT4 Strategy Tester models only the chart symbol (`ParseSymbols` adds `Symbol()` when testing). So:

1. **Per-symbol levers (1 to 4)**: test them in the tester on one liquid symbol at a time (EURUSD, GBPJPY, a crypto), same period and deposit, every-tick model. Compare v1.8.0.7, v1.8.0.8, v1.8.0.9 or v1.8.1.0 with and without `InpStopATRMax` widening and `InpMinScore`. Judge net after commission, profit factor, drawdown and trade count. Keep a later date range untouched for a final check.
2. **Cross-asset ranking, equity-token window and the selector**: cannot be validated in the tester. Use a demo account with the real multi-asset universe, shadow mode on, and review the SELECTOR rows after several weeks. Only then consider `InpSelectorShadow = false`.
3. A wider stop lengthens trade duration; if many trades end by the time exit, raise `InpMaxHoldBars` (for example 48 to 72).
4. Keep `InpUseLimitEntry = false` for the first comparison.

## Known limits

- The equity-token window (16:45 to 22:30 server) is an assumption; check it against your broker and US daylight saving time.
- NATGASUSDT and other non-stock tokens not in the crypto list follow the equity window.
- The selector sees only this magic number's history visible to the terminal (set Account History to All History).
- Pending limit orders count toward open positions and aggregate risk, but FX net-exposure and crypto/equity cluster caps count filled positions only.
