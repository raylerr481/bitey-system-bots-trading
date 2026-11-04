# Bitey Scalper v1.5.5.2 — Series Readiness Guard

## Base and isolation
- Created from `experimental/scalper-v1-5-5-1-balanced-active-management`.
- New branch: `experimental/scalper-v1-5-5-2-series-readiness-guard`.
- v1.5.5.1, v1.5.5 and v1.5.4.9 remain unchanged.
- This release adds a new EA file; it does not replace any earlier EA.

## Source review findings
1. v1.5.5.1 logged `SERIES_SYNCHRONIZED` through `LogMarketDataState()`, but `Prefilter()` did not require a confirmed synchronized series before signal analysis.
2. `HISTORY_READY` only checked minimum M15 bar count and a positive current-bar timestamp; it did not validate ordered timestamps for current and two closed bars.
3. The session filter is a fixed server-hour window (except symbols accepted by the existing crypto-prefix heuristic). It is not the broker's actual per-contract session schedule.
4. Aggregate oldest quote age includes every configured symbol, including instruments with inactive/closed markets; it is not a measure of the oldest active tradable quote.

## v1.5.5.2 changes
- Adds `InpRequireSynchronizedSeriesForEntry=true`.
- Before indicator/signal evaluation, M15 must have sufficient history, valid nonzero timestamps for bars 0/1/2, strictly descending timestamps (bar 0 newer than 1, 1 newer than 2), no future current/closed timestamps, and a confirmed `SERIES_SYNCHRONIZED=true`.
- When `InpUseHTFFilter=true`, H1 (or configured HTF) must have at least 52 bars, valid ordered timestamps, a closed HTF bar not newer than the signal's last closed bar, and confirmed synchronization.
- Distinguishes unknown synchronization status from an explicit false result in the rejection reason.
- Logs `ENTRY_DATA_READINESS` with the exact reason and timestamps when a symbol is blocked.
- Corrects misleading diagnostic labels `M5`/`M15` to explicit configured signal and higher timeframe labels.
- Session diagnostics now state the fixed server-hour policy, configured window, server hour, and the existing crypto-prefix exemption. They explicitly state that the broker contract schedule is not confirmed.
- Renames the aggregate oldest-age field to make clear it covers all configured symbols, including inactive markets.

## Preserved behavior
- Entry signal families, voting, scoring and ranking.
- Balanced live analysis and progressive-loss exit from v1.5.5.1.
- Adaptive SL/TP, break-even, trailing, TP expansion and 50% net giveback.
- Risk sizing, maximum five positions, exposure limits, loss-response scaling and same-direction cooldown.
- 120-second stale-quote gate.
- Existing session filter and its configured hours; no global removal or blanket USDT classification.
- No martingale, SL widening, risk bypass or account-mode gate.

## Fail-closed behavior
- Unknown or false M15 synchronization blocks new entries.
- If HTF filtering is enabled, unknown or false HTF synchronization blocks new entries.
- Invalid/insufficient timestamps or history block new entries.
- This gate does not itself close or modify existing positions. Existing safe position management and broker-resident SL/TP remain governed by the inherited code.

## Validation status — NOT PASSED
Source has been statically edited and reviewed for the intended control-flow insertion. It has not been compiled in MetaEditor, run in MT4 Strategy Tester, or forward-tested. The strict synchronization requirement may reject symbols if the broker terminal does not report `SERIES_SYNCHRONIZED` correctly; inspect the new rejection diagnostics before any deployment.

Required before replacement:
1. Compile the exact v1.5.5.2 file in MetaEditor and resolve all compiler errors/warnings.
2. Confirm active symbols report M15 and H1 synchronization as true.
3. Verify closed-bar timestamps and entry blocks under missing/unsynchronized history.
4. Run identical Strategy Tester conditions against v1.5.5.1.
5. Demo forward-test and collect at least 100 closed trades before judging win rate, net expectancy, profit factor, drawdown and per-asset/direction performance.
