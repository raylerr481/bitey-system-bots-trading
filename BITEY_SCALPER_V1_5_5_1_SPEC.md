# Bitey Scalper v1.5.5.1 — Balanced Active Trade Management

## Base and isolation
- Experimental branch created from `experimental/scalper-v1-5-5-balanced-live-analysis`.
- v1.5.5 and v1.5.4.9 branches/files are not modified.
- This branch adds a new EA file; it does not replace the v1.5.5 file.
- Existing entry logic, sizing, asset/direction ranking, adaptive SL/TP, net giveback, retracement exit, quote freshness, cooldown and exposure controls are retained.

## Main functional change: progressive-loss exit
The v1.5.5 source declared `InpEnableProgressiveLossExit` and `InpProgressiveLossBaseRiskPct`, but did not use them in the exit manager. v1.5.5.1 activates this policy.

A position may be closed early only when ALL conditions are true:
1. `InpEnableProgressiveLossExit=true`.
2. The closed-bar `DirectionalProgression()` result is adverse (`-1`) for the position direction.
3. Booked floating net (OrderProfit + OrderSwap + OrderCommission) is negative and has reached the configured fraction of the original monetary stop risk saved when the EA opened the ticket.
4. A completed candle confirms an adverse structure break using `ConfirmedRetracementBreak()`.
5. Ticket age is at least `InpProgressiveLossMinHoldSeconds` (default 120 seconds).
6. Original ticket risk is available and positive. If it is missing (e.g. a pre-existing/manual position or lost terminal GlobalVariable), this new exit fails closed and does not guess.

Default loss threshold: 60% of original ticket stop risk. It is configurable from 1% to 100% at runtime through the input; code clamps it to that range.

This is an early-loss containment rule, not a guaranteed loss cap. Gaps, slippage, broker execution and costs can produce a realized loss beyond the trigger. Existing broker SL remains active throughout. The new rule never widens or removes SL.

## Live analysis additions
The rate-limited `BALANCED_LIVE_ANALYSIS` record now also reports:
- `netPeak`: highest persisted booked floating net seen for the ticket.
- `givebackPct`: current pullback from that positive net peak.
- `originalRisk`: persisted initial stop-risk money, or zero if unavailable.

## Retained safeguards
- Hard maximum five open positions and one position per normalized asset.
- Existing aggregate/currency exposure and rolling-loss risk scaling.
- Existing six-closed-bar same-asset/same-direction loss cooldown.
- Existing 120-second stale-quote gate; no EA-side entry/exit modifications on stale quotes, broker SL/TP remain active.
- Existing adaptive SL/TP, break-even, ATR trail, TP expansion conditions and broker stop/freeze checks.
- Existing 50% net-peak giveback protection.
- Existing confirmed profitable retracement exit and small net-profit behavior.
- SL can only move toward reduced risk/profit; never widen.
- No martingale, risk bypass, account-mode gate or daily-loss hard entry lock.

## Important interpretation
- The new early-loss exit requires adverse progression AND structure break AND the risk threshold AND minimum age. A temporary negative floating result alone cannot trigger it.
- The policy uses booked floating net; it does not know future close commission or actual slippage. The close can realize a different amount.
- If quotes are stale, ManageExits skips the symbol before reaching this policy; broker-resident SL/TP remain active.
- The observer remains diagnostic; executable actions are performed by ManageExits rules.

## Validation gate — NOT YET PASSED
1. Compile this exact file in MetaEditor and resolve every compiler warning/error.
2. Strategy Tester: compare v1.5.5 and v1.5.5.1 on identical symbols, dates, timeframe, spread, modelling and costs.
3. Include scenarios with adverse progression + structure break, adverse progression without structure break, neutral progression, unavailable original risk, and stale quotes.
4. Verify no SL widening, no unexpected closes, and no changes to the source v1.5.5/v1.5.4.9 branches.
5. Forward-test on demo before considering replacement. Require at least 100 closed trades and report win rate, net expectancy, profit factor, drawdown, average win/loss, and net results by asset and direction.

Source creation does not compile, run Strategy Tester, or operate the MT4 terminal. Do not deploy this EA to a live account based only on source inspection.
