# Bitey Ensemble Scalper v1.8.1.7 — SBT / Bitey IA Audit Bridge

Research branch: `feature/v1-8-1-7-sbt-ia-audit-bridge`

## Scope
- Fixes the inherited undeclared `lossBlock` and `budget` references.
- Adds result/error fields to each adaptive SL/TP modification audit row.
- Logs successful and failed `OrderModify` calls to `Bitey_AdaptiveExits_v1_8_1_7.csv`.
- Logs TP expansion attempts skipped because the broker distance or minimum step is not satisfied.
- Reports SL/TP modification outcomes through the existing SBT Worker route `/api/v1/mt4/bitey-report`.
- Reports closed trades through `/api/v1/mt4/trade-closed`, with realized P/L including commission and swap and a backend-owned Q-learning metadata contract.
- Reporting is observational only. SBT/Bitey IA telemetry cannot send orders or change SL/TP.

## MT4 Demo validation
1. Compile this file in MetaEditor. Compilation is not claimed until MetaEditor reports zero errors.
2. Attach only to a DEMO terminal/chart first; leave the EA's existing risk and broker checks intact.
3. In **Tools → Options → Expert Advisors**, allow WebRequest for:
   `https://bitey-system-bots-trading.raylerr481.workers.dev`
4. Check Experts for `SBT TELEMETRY OK`, `SBT CLOSED TRADE REPORTED`, `ADAPTIVE_MODIFY`, and `ADAPTIVE_MODIFY_FAILED`.
5. Inspect `MQL4/Files/Bitey_AdaptiveExits_v1_8_1_7.csv` and confirm old/new SL/TP, reason, result and error code per attempted modification.

## Limitations
- WebRequest is synchronous and reporting can fail due to MT4 allow-list, network, Worker or backend errors. Failure does not alter trading decisions.
- The SBT/IA HTTP integration still needs a real Demo terminal test and confirmation of backend persistence/consumption. This branch has not been compiled or run in MT4 Strategy Tester here.
- A stop cannot guarantee the exact realized profit because gaps, slippage and broker constraints can affect fills.
