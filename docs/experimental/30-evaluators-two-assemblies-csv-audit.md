# Bitey SBT — Experimental 30 Evaluators / Two Assemblies

This branch is experimental and does not replace or modify the currently used EA file.

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

1. Copy the include file to the terminal's `MQL4/Include` folder.
2. Add `#include <Bitey_Ensemble_Experimental_CSV_Audit.mqh>` to the experimental EA.
3. Assign one stable `decisionId` to each candidate decision; reuse it across the 30 evaluator rows, both assembly rows, and the resulting trade.
4. Call `BiteyCsvLogTradeOpened` only after a successful order send. Call `BiteyCsvLogTradeClosed` once per closed order using actual history values.
5. Compile in MetaEditor and inspect the generated CSVs in the terminal's `MQL4/Files` directory.

Files are opened in append mode and flushed/closed after each row. This favors audit durability over speed; do not call every logger on every tick. Log at decision, order, exit-change, close, and snapshot events.

## Important limitations

- This commit adds the audit module only. It does **not** claim that the 30 evaluators or the two assemblies have been integrated into a complete EA.
- The caller must supply valid values, including a stable decision ID, actual commission/swap, and real slippage when available. If slippage cannot be measured, pass a documented estimate and label it in the reason/note.
- The module does not calculate profit factor, drawdown, model weights, or expected net value. It records those metrics supplied by the EA or an offline analysis.
- In MT4, the `Digits` global refers to the current chart symbol. For multi-symbol logging, callers should pass normalized prices or extend the helper to use per-symbol digits.
- CSV output is not a substitute for comparing the broker history with the audit files.
- Compilation, runtime logging, and Strategy Tester validation remain pending. Do not use this module as evidence of profitability or change the active EA based on it.

## Next implementation stage

Inventory existing signal functions; define 30 non-duplicative evaluators with out-of-sample weights; implement Assembly 1 asset selection and Assembly 2 direction/abstention; wire all decisions to these audit functions; preserve existing adaptive SL/TP and independent risk controls; then compare the experimental EA and baseline with identical MT4 conditions and transaction costs.
