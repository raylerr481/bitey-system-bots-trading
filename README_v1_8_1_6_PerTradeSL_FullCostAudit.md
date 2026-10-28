# Bitey Ensemble Scalper MultiAsset v1.8.1.6 — Per-Trade SL / Full-Cost Audit

**Status:** experimental; static edits reviewed, but not compiled in MetaEditor and not backtested in MT4. Do not treat this commit as a verified trading build until it compiles and passes Strategy Tester checks.

## Changes in v1.8.1.6

- Fixes the reported undeclared `lossBlock` reference by removing the obsolete diagnostic reference to the removed loss-streak brake.
- Defines the per-trade `budget` before sizing and logging it, fixing the reported undeclared `budget` identifier.
- Keeps the SL/TP decision identifier in one local scope in the exit-modification path to avoid the reported shadowing warning.
- Logs every attempted `OrderModify` for SL/TP, including ticket, symbol, estimated current net P/L (profit + commission + swap), previous and proposed SL/TP, reason, broker minimum distance, success/failure, and error code.
- Writes the detailed modification audit to `Bitey_SLTP_ModificationAudit_v1_8_1_6.csv` in MT4's `MQL4/Files` directory.
- Adds TP-expansion gate events to the action log: `TP_EXPANSION_WAITING`, `TP_EXPANSION_CANDIDATE`, and `TP_EXPANSION_BLOCKED`. Gate events are throttled by per-ticket state so the waiting/block reason is not written on every tick.
- Uses version-specific filenames for trade-open, closed-trade, and adaptive-exit CSVs.

## Risk and behavior constraints

- This version does not add risk or intentionally widen an open position's SL. The break-even, trailing-stop and net-profit-lock logic only accepts an SL that improves protection.
- The TP expansion feature may extend the target only after its configured favorable-move and ADX thresholds are met, and only if the candidate respects the configured step and broker distance.
- Broker rejection, market gaps, slippage, commission/swap changes, terminal disconnection, or broker stop/freeze rules can still prevent a modification or reduce realized profit. A stop cannot guarantee a specific exit price or a profit.
- Existing entry rules and operational limits remain in place.

## Validation still required

1. Compile the exact file in MetaEditor and resolve any remaining compiler errors/warnings.
2. Run MT4 Strategy Tester and inspect the Experts log for `SLTP_AUDIT`, `ADAPTIVE_MODIFY_FAILED`, and TP-expansion action records.
3. Verify ticket by ticket that each SL change is monotonic toward lower loss / higher protected profit and that TP changes only occur when the expansion gate is satisfied.
4. Reconcile closed trades against broker history: realized net = `OrderProfit + OrderCommission + OrderSwap`. The current-net value in the modification audit is an estimate at modification time, not the final realized result.

## Compile-error report addressed

- `lossBlock` — obsolete reference removed.
- `budget` — declared and used for per-trade lot sizing / rejection diagnostics.
- `exitDecisionId` — the updated modification path declares it once in its local scope.

The code was committed to the feature branch only; it has not been merged into `main` or installed in the user's MT4 terminal.
