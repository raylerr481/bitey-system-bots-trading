# v1.5.55 vs v1.5.56 — Comparative validation report

## Scope
- Baseline: `Bitey_Scalper_MultiAsset_v1_5_55_WideTrailExperiment.mq4` on `main`.
- Candidate: `Bitey_Scalper_MultiAsset_v1_5_56_AdaptiveEvidenceIntelligence.mq4` on `experimental/v1-5-56-adaptive-evidence-intelligence`.
- The baseline file and `main` are unchanged.
- This is a test protocol and evidence template, not a completed backtest report.

## Implemented in v1.5.56
1. **Daily Adaptive Quality connected:** when the current server-day sample is complete and meets the minimum loss count, `InpDailyAdaptiveExtraScore` is added to the required entry score. It can only reject weaker candidates; it cannot create entries, increase risk, relax filters, or suspend the day.
2. **Original protections retained:** risk sizing and caps, broker permissions, fresh-quote checks, SL/TP management, entry breaker, net-cost protection, loss-duration policy and v1.5.55 exit parameters are carried forward.
3. **MFE/MAE cadence:** default snapshot interval is 5 seconds (configurable, 5-second minimum). Extrema remain sampled floating-net values, not tick-perfect extremes.
4. **Trailing evidence by asset and direction:** additional `TRAIL_EVALUATION` CSV rows record symbol, BUY/SELL, favorable excursion in ATR, trail activation, configured/effective weak-trend trail distance, SL gap in ATR and directional progression. Observation only; it does not modify orders.
5. **Event labels:** giveback event and close labels now reference the configured percentage, not a hard-coded “40%”. The 60% configured behavior is unchanged.

## Test protocol
Compile and test both builds with the same broker, account type, symbol universe, timeframe, date range, tick model, spread/commission assumptions and reference capital. Use separate demo terminals/accounts or strictly isolated magic numbers and CSV destinations; never run both builds against the same positions.

- Compile each source in MetaEditor and retain compiler output.
- Run matched backtests, then forward demo tests.
- Keep v1.5.55 baseline inputs unchanged.
- For v1.5.56, change only documented code changes and record any input overrides.

## Metrics
| Metric | v1.5.55 | v1.5.56 |
|---|---:|---:|
| Trades / closed trades | Pending | Pending |
| Net P/L after commission and swap | Pending | Pending |
| Profit factor | Pending | Pending |
| Win rate | Pending | Pending |
| Average win / average loss | Pending | Pending |
| Maximum equity drawdown | Pending | Pending |
| Median MFE / MAE sampled | Pending | Pending |
| Median MFE capture % | Pending | Pending |
| Median giveback % | Pending | Pending |
| Results by asset and BUY/SELL | Existing evidence | TRAIL_EVALUATION + closed-trade evidence |
| Daily adaptive strict activations | Diagnostic; score not wired | Score penalty applied when qualifying sample exists |
| Daily adaptive score rejections | 0 from this feature | Count from SCORE / ENTRY_FLOW logs |
| Compile errors / warnings | Pending | Pending |

## Acceptance criteria
- Zero compile errors.
- No increase in configured per-trade or aggregate risk.
- No new hard daily-loss lock and no weakened quote, permission, spread, SL/TP or net-cost protections.
- Daily score penalty occurs only after a complete qualifying sample.
- MFE/MAE and trailing evidence do not affect order actions.
- Do not promote to `main` until matched backtests and forward-demo evidence support it.

## Pending evidence / limitations
- `20261119.log.part0001` could not be read through the connected GitHub retrieval, so this report makes no claims about actual session outcomes.
- MetaEditor compilation and Strategy Tester execution have not been performed here.
- MFE/MAE use periodic floating-net samples; fast movements between samples can be missed. Taxes are not separately exposed by MT4 in these records.
