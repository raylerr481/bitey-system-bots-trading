# Bitey SBT — Experimental 30 Evaluators / Two Assemblies

This branch is experimental and does not replace or modify the currently used EA file.

## Experimental EA now added

`Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_0_ThirtyEvaluatorsExperimental.mq4` is a separate copy of the v1.7.2.4 baseline with the original adaptive exit/risk-management code retained and its signal analyzer replaced by 30 named rule evaluators.

### Evaluator inventory (6 families × 5 parameter variants)

1. EMA trend alignment: fast/slow EMA pairs.
2. MACD direction and momentum: five fast/slow/signal parameter sets.
3. Donchian price-channel breakouts: five lookback lengths.
4. RSI momentum: five lookback lengths.
5. Bollinger re-entry / mean reversion: five lookback lengths.
6. Stochastic reversal cross: five K lookback lengths.

The five variants within each family are aggregated first. Assembly 2 uses family-level direction rather than counting all 30 variants as independent votes. In the default trend regime it requires the configured number of the first four families to agree and applies the existing higher-timeframe filter. Range entries remain controlled by the existing range-regime setting and require both mean-reversion families to agree plus an RSI extreme.

Assembly 1 uses the existing cross-asset candidate ranking/diversification loop, with CSV records for eligible candidates and the candidate selected for execution.

These are rule-based technical evaluators, not 30 independently trained AI models. No rule is claimed to be profitable before validation.

## First artifact: CSV audit module

`MQL4/Include/Bitey_Ensemble_Experimental_CSV_Audit.mqh` supplies logging functions for:
- individual evaluator votes (including abstentions and reasons)
- Assembly 1 asset rankings/selections
- Assembly 2 BUY/SELL/ABSTAIN decisions
- accepted order entries
- closed trades and realized net P/L
- adaptive SL/TP transitions
- performance snapshots

### Install and use

1. Copy `MQL4/Include/Bitey_Ensemble_Experimental_CSV_Audit.mqh` into the terminal's `MQL4/Include` folder, preserving the path.
2. Open `Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_0_ThirtyEvaluatorsExperimental.mq4` in MetaEditor; the include and logger calls are already wired into this experimental EA.
3. Compile and fix any MetaEditor diagnostics before attaching it. Compilation has not been performed by this workflow.
4. Run a Strategy Tester pass and a demo forward test, then inspect the CSVs in the terminal's `MQL4/Files` folder.
5. Reconcile tickets and net P/L with MT4 Account History; do not treat the zero-valued expected-net/cost placeholders as measured values.

Files are opened in append mode and flushed/closed after each row. This favors audit durability over speed; do not call every logger on every tick. Log at decision, order, exit-change, close, and snapshot events.

## Important limitations

- The branch now contains the experimental EA and the audit module. Compilation, runtime logging, and Strategy Tester validation remain pending; this is not a production-ready or proven-profitable release.
- The caller must supply valid values, including a stable decision ID, actual commission/swap, and real slippage when available. If slippage cannot be measured, pass a documented estimate and label it in the reason/note.
- The module does not calculate profit factor, drawdown, model weights, or expected net value. It records those metrics supplied by the EA or an offline analysis.
- The audit helper uses per-symbol digits for order prices. Some estimated-cost/expected-net fields are currently placeholders (zero) and must not be treated as measured costs or forecasts.
- CSV output is not a substitute for comparing the broker history with the audit files.
- Compilation, runtime logging, and Strategy Tester validation remain pending. Do not use this module as evidence of profitability or change the active EA based on it.

## Validation still required

1. Compile the experimental EA in MetaEditor and resolve any compiler diagnostics.
2. Confirm the EA discovers the broker's actual symbol suffixes and that no more than five positions are open simultaneously.
3. Verify BUY and SELL on symbols where broker permissions allow both directions; account type itself is not a gate, but broker permissions and risk guards remain authoritative.
4. Confirm the adaptive SL/TP manager never widens stop-loss risk and that every modification is logged.
5. Verify all CSVs in `MQL4/Files`, match the 30 evaluator rows to the two assemblies and the eventual ticket, and reconcile close net P/L against broker history.
6. Run out-of-sample Strategy Tester and demo tests with spread, commission, swap, and slippage accounted for. Keep the production EA unchanged until these checks pass.
