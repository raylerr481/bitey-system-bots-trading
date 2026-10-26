# Bitey SBT source audit — risk, sizing, symbols and execution

**Date:** 2026-10-26  
**Scope:** Static source review only. No MT4 compilation, Strategy Tester run, live execution, or profitability claim was performed as part of this audit. This report is intentionally separate from the production EA files.

## Executive conclusion

Do not promote a newer version just because its version number is higher. The available evidence favors **v1.64.1's explicit fail-closed $1.25 per-position risk policy as the safer reference for risk control**, while the Ensemble v1.7.2.1 is the more convenient candidate for multi-asset trend entries and adaptive exits. They are different strategies and must not be merged without a controlled comparison.

The previously reported Strategy Tester result for Ensemble v1.7.2.1 remains negative: net **−$30.34**, profit factor **0.82**, expected payoff **−$0.16/trade** over 186 trades. Its tester path deliberately limits the universe to the chart symbol, so that result is **not a multi-asset portfolio test**.

## Files reviewed

- [Ensemble v1.7.1.1](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey_ensemble_scalper_multiasset_v1_7_1_1_1_claude.mq4) — blob `c1a02f107b94a882bec92f81bc94a81d3918b67b`
- [Ensemble v1.7.2.1](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey%20ensemble%20scalper%20multiasset%20v1%207%202%201%20claude.mq4) — blob `bb3c6228e733e0a4c14694294ab24a3dba5cb2d6`
- [SBT Multi-Asset v1.63.1.2](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey%20SBT%20Multi-Asset%20v1.63.1.2.mq4) — blob `7f794a671f4e76d198336f111c413f0c83404065`
- [SBT v1.64.1 FailClosedRiskCap USD500](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey_SBT_MultiAsset_v1_64_1_FailClosedRiskCap_USD500.mq4) — blob `1b043fca7af7be852b0ff4ffd4e0d3dc9a6d70d2`
- [SBT v1.97.7](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey%20SBT%20v1.97.7.mq4) — blob `831b6b1706dbaac0d998eb64bcc3e9c48ef78976`
- [SBT v1.98.3](https://github.com/raylerr481/bitey-system-bots-trading/blob/main/Bitey%20SBT%20v1.98.3.mq4) — blob `f337da094e06801ab33dc753e944ea3de060e16b`

## 1. Ensemble v1.7.1.1 → v1.7.2.1

### What actually changed

The source-level diff is relatively small compared with the version-number jump. The new behavior is primarily:

- Adds a **gross FX currency-leg cap** (`InpMaxCcyGross=3`) in addition to the existing signed/net currency exposure check.
- Adds a diversification penalty (`InpDiversifyPenalty=4.0`) that adjusts candidate rank when a candidate overlaps existing same-direction exposure.
- Re-ranks the candidate list and applies the correlation guard to the selected best candidate.

The core risk-sizing functions `EstimateRisk()` and `LotsForRisk()`, the base risk inputs, and the general adaptive exit/OrderSend/OrderModify structure are materially unchanged between these two files. Therefore, v1.7.2.1 should not be described as a fix for the negative expectancy seen in v1.7.2.1's own tester report; the version's notable change is portfolio exposure/ranking control, not a proven edge improvement.

### What looks useful

- Buy and sell are both enabled by default.
- Fixed reference capital is used for sizing by default; the configured baseline is 0.5% per trade, 2.5% aggregate risk, up to five positions.
- The lot calculator rounds down to broker lot-step, enforces broker minimum/maximum, applies a symbol-class lot cap, and rejects if estimated stop risk exceeds the requested budget.
- The cost gate rejects candidates where spread plus estimated commission is too large relative to stop distance.
- NEARUSDT and ZECUSDT are explicitly listed; auto-discovery may add other broker-visible crypto symbols.

### Remaining limitations / risks

1. **Tester coverage:** `ParseSymbols()` returns only the chart symbol under `IsTesting()`; the multi-asset scanner is disabled in tester mode. A single-symbol test cannot validate portfolio correlation, aggregate risk, symbol rotation, or simultaneous fills.
2. **Broker-dependent symbol names/specifications:** including NEARUSDT/ZECUSDT in the input does not guarantee that the broker exposes those exact names, enables trading, has usable tick values, or allows the calculated minimum lot. The logged `MIN_LOT_EXCEEDS_BUDGET_OR_CAP`, spread, and trade-disabled rejects must be treated as real constraints—not bypassed.
3. **Cost/risk estimates:** the lot model depends on `MODE_TICKVALUE`, `MODE_TICKSIZE`, and configured commission assumptions. Verify each asset class against actual broker contract specifications, account currency, commissions, and swap. The stop-risk estimate does not guarantee realized loss under gaps/slippage.
4. **Order modification:** adaptive SL/TP and net-profit-lock code calls `OrderModify()` and logs success/failure. It does not prove every broker accepts each modification. Audit StopLevel/FreezeLevel, normalization, error code, read-back of the accepted SL, and per-ticket cooldown before treating protection as reliable.
5. **Performance:** the existing negative tester report is a stop signal for promotion. New diversification logic may reduce concentration but does not itself establish positive expectancy.

## 2. SBT risk policy comparison

| Version | Fixed capital | Per-trade settings | Aggregate setting | Interpretation |
|---|---:|---:|---:|---|
| v1.63.1.2 | $500 | target $3; hard cap $12; 2.40% cap = $12 | $14 | Broad and materially looser than the later $1.25 policy. Seven configured slots do not mean seven positions will pass every gate. Treat this as a risk-policy outlier, not a preferred base. |
| v1.64.1 | $500 | target $1.25; hard cap $1.25; 0.25% cap = $1.25 | effective cap scales by active slots, at most $8.75 | Clearest fail-closed baseline in this family. Risk unknown, missing stop, or cap violation should block or trigger explicit protection logic. |
| v1.97.7 | $500 | target/hard cap $1.25; 0.25% cap = $1.25 | $8.75 | Similar nominal hard-risk policy to v1.64.1, but seven slots mean the theoretical maximum aggregate stop risk is $8.75 (1.75% of the $500 reference) if all seven reach the cap. Check active-slot scaling and aggregate gate in runtime logs. |
| v1.98.3 | $500 | baseline $1.25; hard cap $2; 0.40% cap = $2 | $8.75 | Can scale individual risk to $2 after its adaptive conditions. Seven positions at $2 each would be $14, so the $8.75 aggregate gate must be verified on every order. The per-position cap and aggregate cap are not interchangeable. |

### Important distinction

`InpRiskPerTradeUSD` is a requested/target budget, `InpHardRiskCapUSD` is a per-position ceiling, and `InpPortfolioOpenRiskCapUSD` is the aggregate ceiling. A value in an input or comment is not enough: verify the effective budget, computed lot size, estimated stop risk, existing open risk, and post-entry risk gate in the execution path.

### v1.63.1.2 is not a safe baseline for the $1.25 policy

The source declares $3 requested risk, $12 hard cap, $14 aggregate cap, a 2.4% capital risk ceiling, and a $12 adaptive maximum. It also contains an adaptive ladder that can request higher dollar amounts after sustained campaign profit, with later hard caps applied. Even if other gates block some orders, this is a different risk policy from the later $1.25 versions. Do not copy its risk ladder into v1.64.1 or the Ensemble EA.

### v1.64.1 / v1.97.7 are the conservative risk reference

Both use $1.25 per-position settings and a 0.25% capital ceiling. v1.64.1 explicitly derives aggregate capacity from effective slot count and per-position cap, so the cap falls when the campaign governor reduces the number of allowed positions. That is preferable to relying on a stale comment or a single input alone. This is a source-level conclusion, not a backtest result.

### v1.98.3: verify the adaptive jump and aggregate gate

The code sets an adaptive risk budget after sustained positive campaign P/L and later clamps it using the effective per-trade cap (up to $2). That can raise risk above the $1.25 baseline, but the aggregate cap remains $8.75. Before using it, test these cases explicitly: (a) one position at $2; (b) four positions at $2; (c) a fifth position when open risk is already near $8.75; (d) missing SL or unknown tick-value; (e) restart with existing positions. Any unknown risk must block new entries rather than be treated as zero.

## 3. Execution and symbol handling

### Account type

The SBT versions reviewed have `InpBlockOnAccountTypeMismatch=false` with comments that demo/real classification does not gate entries. That aligns with the requested account-mode policy. It does **not** override terminal AutoTrading, broker symbol restrictions, market hours, margin, lot limits, or a broker response such as “Trade is disabled.” Those restrictions must remain enforced.

### Fail-closed behavior to preserve

- Reject a new order if tick value/size, stop distance, account currency, or existing-position risk cannot be established.
- Reject or explicitly remediate a position with no SL; do not silently count its risk as zero.
- Normalize lots down to the broker step, then recalculate the projected risk after normalization.
- Check both per-position and portfolio aggregate stop risk immediately before `OrderSend()`.
- After an accepted order, re-select it and read back SL/TP; log and handle missing or rejected protection.
- For every `OrderModify()`, record ticket, old/new SL/TP, error code, and post-modification read-back. Never assume the request succeeded just because a desired price was calculated.
- A failed protective modification must be visible and escalated; no automatic widening of SL to make an order acceptable.

### Asset discovery is not asset authorization

A wildcard Market Watch scanner or auto-added crypto symbol is only discovery. Each candidate still needs: exact broker symbol, fresh Bid/Ask, nonzero tick value/size, valid lot-step, allowed trading status, acceptable spread/cost, adequate margin, valid SL/TP distances, signal/evidence pass, and both risk gates. Keep NEARUSDT and ZECUSDT requested, but do not force an entry when any gate fails.

## 4. Evidence integrity

The SBT v1.97.7 and v1.98.3 source comments describe a no-look-ahead correction for higher-timeframe evidence: the HTF candle must have been fully closed by the end of the historical signal candle. This is an important integrity fix. Any older train/holdout result computed before that correction should be recalculated; it is not comparable until the same closed-candle rule is used.

Historical signal proxies are not the same as executed portfolio trades. A valid evaluation must include actual spread, commission, swaps, slippage, order rejections, symbol-specific tick/contract specs, and chronological out-of-sample periods. Avoid selecting parameters on the same interval used to report performance.

## 5. Required validation before any production promotion

1. **Compile** each candidate in MetaEditor and save the full compiler log; resolve every error and review warnings.
2. **Reproduce** the known v1.7.2.1 tester report with the same symbol, timeframe, dates, deposit, spread mode, and inputs. Record the exact file hash.
3. **Single-symbol tests:** FX, gold, and each available crypto separately; long/short split; commission/swap enabled; variable spreads where possible.
4. **Risk-boundary tests:** minimum lot above budget, unknown tick size/value, missing SL, rejected OrderSend, rejected OrderModify, StopLevel/FreezeLevel, margin insufficiency, and account currency other than USD.
5. **Portfolio tests:** because the current tester path only tests the chart symbol, create a separate test harness or an explicitly documented portfolio replay. Do not present the single-symbol tester as proof of multi-asset performance.
6. **Chronological holdout:** no parameter tuning on the holdout. Report net P/L, profit factor, expectancy, max drawdown in dollars and percent of $500, largest loss, losing streak, total costs, number of trades, and per-symbol contribution.
7. **Demo forward test:** use the same EA build and inputs intended for deployment. Confirm accepted SL/TP on every ticket and reconcile EA logs to the broker statement.
8. **Promotion gate:** require positive net expectancy after costs on out-of-sample data and a drawdown compatible with the $500 reference. If it fails, do not increase risk to compensate.

## Recommended next step

Keep the production EA untouched while validating. Use v1.64.1 as the **risk-control reference** and v1.7.2.1 as the **strategy candidate**; do not merge them by copying isolated functions until their execution paths, magic numbers, portfolio scans, and risk calculations have been reconciled. The immediate engineering task is to build a reproducible multi-symbol test harness and a ticket-level execution audit, then rerun the candidate against the same chronology. This report does not claim that any version is profitable or compile-clean.
