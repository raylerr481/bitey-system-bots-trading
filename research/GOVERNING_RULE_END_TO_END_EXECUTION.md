# Bitey SBT governing rule: end-to-end execution on the attached MT4 account

**Status:** mandatory acceptance rule for all future Bitey SBT code and releases.

## Governing requirement

Bitey SBT must demonstrate a complete, auditable path from closed-bar data through model evaluation, evidence selection, risk preflight, broker order submission, ticket readback, SL/TP supervision, close detection, and realized-result reporting. A build that only logs signals, stays permanently in observation mode, or never demonstrates an eligible order attempt does not satisfy the requirement.

The EA must behave consistently on the MT4 account the user has manually connected, whether that account is DEMO or REAL. MT4 is the source of truth for account selection. SBT must never switch accounts, falsify `IsDemo()`, or apply a DEMO/REAL classification mismatch as an order gate. The user controls the account by connecting MT4; SBT follows that account while preserving the same strategy and risk gates.

## Required operational behavior

1. Default to `AUTO_EXECUTION` and permit cross-asset execution when all normal gates pass; do not default to `OBSERVE_ONLY` for the operational candidate.
2. Preserve the fixed USD 500 strategy capital independent of broker balance/equity.
3. Preserve the USD 1.25 hard per-position stop-risk ceiling, USD 8.75 aggregate open-risk ceiling, USD 10 daily-loss entry gate, at most seven simultaneous positions, and exactly one position per canonical asset.
4. Keep all evidence, closed-bar, spread, quote freshness, broker symbol, minimum-lot, tick-value, margin, commission/swap, SL/TP, daily-loss, and terminal permission checks. Unknown cost assumptions must be explicitly configured or fail closed; never bypass a gate just to force an order.
5. A valid signal may be rejected by a gate, but every rejection must state a specific reason. Demonstrating operation means proving that the full pipeline can send and supervise an eligible order when all conditions pass, not forcing a trade when conditions do not pass.
6. No martingale, no balance-based scaling, no account switching, no duplicate stacking on the same canonical asset, and no blind retry after a failed `OrderSend`.
7. Record a traceable correlation ID/bar timestamp from candidate signal through order attempt, ticket, SL/TP readback, closure, net realized P/L, and telemetry acknowledgement.

## End-to-end acceptance evidence

A release is not accepted until evidence is attached for all of these:

- MetaEditor compile result for the exact source commit, with zero errors and reviewed warnings.
- Strategy Tester results for signal/risk logic, including variable spread, commission, swap, slippage/gaps, broker stop level and lot-step/minimum-lot constraints.
- A running MT4 terminal test on the attached account, first DEMO when available, proving: signal selected; all gates passed; `OrderSend` attempted; ticket opened or broker rejection recorded; SL/TP read back; position monitored; closure detected; realized net result reconciled.
- Explicit demonstration that account-type detection is informational and that DEMO/REAL do not have separate strategy gates. Never switch the user's MT4 account automatically.
- Multi-asset test showing canonical-symbol deduplication, up to seven slots where broker/specification/risk/evidence allow, and no more than one position per canonical asset.
- Telemetry test confirming HTTP status, backend authentication, schema validation, deduplication and durable research-store persistence. Do not upload account identifiers, IPs, passwords or tokens in ordinary log payloads.
- Forward-demo observations and untouched chronological holdout analysis before making profitability claims.

## Honest reporting

Do not call the system operational, compiled, end-to-end verified, or profitable until the corresponding evidence above exists. Distinguish source-level changes, Python CI, MQL4 compilation, Strategy Tester, broker-demo execution and backend persistence as separate validations.

## Current candidate

The operational research branch changes the defaults to `AUTO_EXECUTION` and enables cross-asset execution without bypassing risk/evidence/cost/permission gates. Commission and swap inputs remain fail-closed when unknown; they must be set to actual/conservative values for the selected broker before a new entry can pass. The change is not production deployment and is not proof of compilation or successful order execution.
