# Bitey Scalper v1.5.14 — M15 Series Recovery and Best Eligible Candidate

- **Baseline:** `experimental/scalper-v1-5-13-quote-recovery-pending-analysis`
- **Target EA:** `Bitey_Scalper_MultiAsset_v1_5_14_M15SeriesRecoveryBestCandidate.mq4`
- **Version:** 1.5.14; MT4 Market property: 1.514
- **Branch:** `experimental/scalper-v1-5-14-series-recovery-best-candidate`
- **Status:** EA source implementation committed; MetaEditor compilation, Strategy Tester and demo forward validation pending.

## 1. Objectives

1. Diagnose and recover stale M15 series without confusing an inactive market session with a frozen history series.
2. Make every eligible new-bar candidate observable from series readiness through broker order result.
3. When one or more candidates pass all existing eligibility gates, prioritize the single highest-ranked candidate as the first trade slot and make at least one order attempt per valid scan cycle. If it fails a symbol-specific execution check, continue down the ranked list until one order is accepted, the candidates are exhausted, or portfolio capacity is reached.
4. Do not force an order when there is no eligible candidate or when all candidates fail existing hard safety gates. This requirement is a minimum-one-attempt / best-candidate priority rule, not permission to bypass protections.

## 2. Evidence motivating this version

The 2026-11-07 logs repeatedly showed the same M15 current-bar timestamp across many instruments over several minutes, with `signalAgeState=OLD`, while H1 timestamps advanced and quotes were mixed fresh/stale. This proves a persistent M15 timestamp-age anomaly in the observed series; it does not yet prove whether the cause is broker history, MT4 cache, server clock, symbol session, or the EA's series access path.

`HISTORY_READY` means enough bars/timestamps are readable; it must not be treated as proof that the latest bar is current. MQL4 error 4066 remains `HISTORY_UPDATE_PENDING`, not proof of corruption.

## 3. M15 series freshness and recovery

### 3.1 Separate independent states

Track and log separately:
- Quote freshness: existing server-anchored quote age, maximum 120 seconds.
- Signal-series availability: `iBars`, `iTime(...,0)`, and required closed-bar history.
- Signal-series freshness: latest M15 bar timestamp relative to a trusted server-time reference and the M15 interval.
- Higher-timeframe availability/freshness: H1 independently, including error 4066.

Do not infer session closure from `tradeAllowed=true`, bar age alone, or `UNCONFIRMED_NO_RELIABLE_SESSION_SCHEDULE`.

### 3.2 Freshness classification

Introduce explicit diagnostic states:
- `SERIES_FRESH`
- `SERIES_OLD_SESSION_UNCONFIRMED`
- `SERIES_OLD_CLOCK_UNCERTAIN`
- `SERIES_HISTORY_UPDATE_PENDING`
- `SERIES_RECOVERY_PENDING`
- `SERIES_RECOVERED`
- `SERIES_UNAVAILABLE`

For M15, use a configurable diagnostic tolerance expressed in complete signal-timeframe intervals. Do not use a fixed wall-clock threshold as an unconditional trade block for markets with legitimate closed sessions. If the server clock cannot be trusted or session status cannot be established, fail closed for new entries on that symbol and emit the reason.

### 3.3 Bounded recovery

- Use MQL4-compatible history access only: bounded `iBars`/`iTime` re-reads, `RefreshRates()` where appropriate, and controlled retry scheduling.
- Do not use MQL5-only `SERIES_SYNCHRONIZED` or other MQL5-only APIs.
- Do not spin, block the timer, or repeatedly request history on every cycle.
- Apply per-symbol backoff and log retry count, last observed bar time, server time, quote age, and last error.
- Preserve an existing unfinalized `g_pendingBar`; retry it once the series and quote gates are valid.
- If a genuinely newer bar supersedes a pending bar, explicitly log the supersession and process the newer bar once.
- Never re-run a finalized bar or create duplicate candidates/orders.
- A stale/uncertain M15 series blocks only new entries for that symbol; it must not disable management of already-open positions. Existing broker-side SL/TP remain active.

## 4. Best eligible opportunity selection

### 4.1 Candidate ranking

The current v1.5.13 pipeline already collects candidates and sorts by `signal score - spread penalty + bounded session performance adjustment`. Preserve that basic order-of-quality approach, but make it explicit and fully observable in v1.5.14.

Rank eligible candidates using only data available at decision time:
1. Existing signal score and directional/family agreement.
2. Existing HTF confirmation when enabled and required by the current selectivity level.
3. Execution cost quality (spread relative to stop distance); hard spread ceiling remains a rejection gate, not a ranking override.
4. Existing session/per-symbol performance adjustment, bounded as currently implemented.
5. Deterministic tie-break: higher signal score, then lower spread ratio, then stable symbol ordering.

Log `BEST_CANDIDATE_SELECTED` with rank, candidate count, score, spread ratio, quality components, and the reason it outranked the next candidate.

### 4.2 No fabricated probability

Do not label a raw score or ranking value as a statistical probability or claim a calibrated win probability. A true probability estimate requires out-of-sample calibration on historical/forward trade outcomes, including costs. Until such evidence exists, call it `QUALITY_PRIORITY` or `BEST_ELIGIBLE_CANDIDATE`, not `WIN_PROBABILITY`.

### 4.3 Minimum-one best-candidate attempt

- Consider the top five ranked eligible candidates as the first-choice shortlist (or fewer when fewer than five exist). The five is a candidate shortlist, not a change to the existing maximum of five open positions.
- When at least one eligible candidate exists and portfolio capacity is available, select the highest-ranked candidate and make an order attempt. Do not skip the top candidate merely because another symbol is easier to execute.
- If the first candidate fails a symbol-specific execution check (spread, contract, stops, margin/risk, trade permission, broker response), log the exact rejection and immediately try the next ranked eligible candidate while capacity remains. Continue until at least one order is accepted, the shortlist/candidate list is exhausted, or the existing open-position cap is reached.
- Once one order has been accepted in the scan cycle, the EA may continue with other eligible candidates under the existing multi-position rules and max-five cap; this specification does not impose a new one-trade-per-cycle cap.
- Do not bypass any rejection to force an order. Existing score, quote freshness, risk, spread, session, cooldown, stop, margin, alias, permission, and broker gates remain mandatory.
- If no candidate survives all gates, do not manufacture an entry. Log `NO_ELIGIBLE_CANDIDATE` with the count and top rejection categories and explain why a minimum-one fill was impossible.

## 5. Entry pipeline observability

For each 5-minute window, report counts for:
- stale quote / quote recovered
- M15 series old / recovery pending / recovered / unavailable
- new bars / pending retries / superseded bars
- prefilter passed/rejected by reason
- indicator analyses / signal generated / signal rejected by reason
- score passed/rejected and required score
- candidates ranked / best candidate selected
- execution attempts / accepted / rejected by category and broker error

Keep per-symbol events `ENTRY_FILTER`, `ENTRY_CANDIDATE`, `BEST_CANDIDATE_SELECTED`, `ENTRY_EXECUTION_ATTEMPT`, `ENTRY_EXECUTION_RESULT`, and `ORDER_SEND`.

## 6. Preserved invariants

No changes to:
- minimum score 15 at selectivity level 0 and existing progressive score escalation;
- quote freshness maximum 120 seconds;
- reference capital USD 500 and existing risk sizing/multipliers;
- maximum five open positions and one position per normalized asset;
- spread, margin, stop-distance, broker permission, and session hard gates;
- directional cooldown, rolling loss policy, progressive selectivity, and daily warning-only/no hard daily lock;
- adaptive SL/TP, break-even, trailing, net-profit protection, giveback, progressive loss exit, and loss-duration management;
- broker-side SL/TP and no-martingale policy.

No lowering score to manufacture a signal, no increasing risk, no bypass of broker checks, and no automatic relaxation after a no-trade interval. The minimum-one rule means at least one attempt of the best eligible candidate when candidates exist; it cannot guarantee a broker fill when all candidates fail existing gates.

## 7. Acceptance criteria

1. Repeated stale M15 timestamps are classified separately from stale quotes and H1 4066.
2. Recovery attempts are bounded and observable; no tight retry loop.
3. An unfinalized pending bar resumes exactly once after recovery.
4. A finalized bar is never re-analyzed merely because a quote recovers.
5. If 1–5 eligible candidates exist and portfolio capacity is available, the highest-ranked one receives the first order attempt; a rejected first candidate falls through to the next ranked candidate.
6. At least one order is accepted when at least one candidate passes every existing hard gate and the broker accepts its order; no forced fill is allowed when every candidate fails a gate.
7. No candidate can bypass score, quote, risk, spread, session, position, or broker gates.
8. A no-trade cycle explains whether there was no new bar, no signal, insufficient score, or execution rejection.
9. MQL4 compilation succeeds; Strategy Tester checks cover normal bars, stale series, 4066, quote recovery, multiple candidates, first-candidate rejection/fallback, and all hard protections.
10. Demo forward validation is completed before replacing v1.5.13.

## 8. Implementation status

The v1.5.14 EA source is now present at `Bitey_Scalper_MultiAsset_v1_5_14_M15SeriesRecoveryBestCandidate.mq4`.

Implemented in source:
- Version identifiers updated to 1.5.14 / MT4 property 1.514.
- Added configurable signal-series age tolerance (default 2 complete signal-timeframe intervals).
- Added per-symbol bounded series rechecks with 5-second initial and 60-second maximum backoff, using MQL4 `iBars`, `iTime`, and `RefreshRates()`.
- Added `SERIES_RECOVERY_PENDING` and `SERIES_RECOVERED` diagnostics. Old/uncertain series remain fail-closed for new entries; `ManageExits()` remains before the scan gates.
- Added `BEST_CANDIDATE_SELECTED` and `MINIMUM_ONE_BEST_CANDIDATE_ATTEMPT` diagnostics. The existing ranked execution loop tries the highest-priority eligible candidate first and falls through after symbol-specific rejection, while retaining all existing hard gates and the five-position cap.
- Preserved score floor, quote age limit, risk sizing, cooldown, adaptive exits, loss management, and broker-side SL/TP.

Static source checks performed:
- Version identifiers and new diagnostic events present.
- No MQL5-only `SERIES_SYNCHRONIZED` identifier.
- Braces, parentheses, and brackets balanced.
- Existing score floor 15, quote-age limit 120 seconds, and hard maximum of five positions still present.

## 9. Validation status

The source has **not** been compiled in MetaEditor. No Strategy Tester run, backtest, or demo forward test is claimed. Keep the pull request draft until compilation and the specified test cases pass. Do not replace v1.5.13 in the active MT4 terminal until that validation is complete.
