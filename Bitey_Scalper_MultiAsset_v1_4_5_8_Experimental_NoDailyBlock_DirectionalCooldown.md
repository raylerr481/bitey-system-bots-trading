# Bitey Scalper v1.4.5.8 — Experimental Build

## Purpose

This experimental branch evaluates the scalper through the full trading session without the daily-loss entry block being enabled by default. It also changes the loss cooldown from a blocking rule to direction-specific diagnostic logging.

The v1.4.5.7 source file is preserved unchanged. This build is a separate file and branch.

## Changes

### 1. Daily-loss threshold: warning by default

- `InpDailyLossPct = 3.0` remains the threshold.
- New input: `InpEnableDailyLossBlock = false`.
- Default behavior after the threshold is crossed: emit `DAILY_LOSS_WARNING` and continue evaluating otherwise-valid entries.
- If the input is explicitly set to `true`, the previous `DAILY_LOSS_BLOCK` behavior remains available.
- Existing positions continue to be managed by the existing exit logic.

The daily P/L calculation in `TodayNet()` includes realized net P/L for orders closed since the broker-server day's start, plus the current floating net P/L of all open EA market positions. Net is gross profit + swap + commission. It is not a pure closed-trades-only statistic.

### 2. Directional loss context: log only, never block

- A losing BUY is recorded as context for subsequent BUY candidate analysis on the same broker symbol.
- A losing SELL is recorded as context for subsequent SELL candidate analysis on the same broker symbol.
- The configured `InpCooldownBars = 6` is a diagnostic lookback window only. It does **not** reject, delay, or suppress any entry.
- When a valid candidate appears within that window, the journal emits `DIRECTIONAL_LOSS_CONTEXT` with symbol, candidate side, previous losing side, last net result, close time, elapsed seconds, and estimated remaining bars.
- BUY and SELL candidates continue through the ordinary entry pipeline. A prior loss is evidence for analysis, not an entry permission rule.
- The existing one-position-per-asset rule remains in place, along with all independent signal, score, session, spread, quote, permission, volume, margin, and portfolio-risk checks.


## Protections retained

- Reference capital: USD 500.
- Per-trade risk: 0.5% of reference capital.
- Aggregate open risk cap: 2.5%.
- Maximum open positions: 5.
- Hard spread-to-stop cap: 35%.
- Quote freshness limit: 120 seconds.
- Existing broker-side initial SL/TP, adaptive exits, stop management, permission checks, symbol trading checks, margin/volume checks, and session classification remain in the source.
- Account mode remains `NOT_A_GATE`: the EA does not use demo/live account type as a strategy filter. MT4 terminal permissions, Expert Advisor permissions, broker permissions, symbol trading status, and margin requirements still apply.

## Validation status

- Source copied from the v1.4.5.7 crypto-session-classification commit.
- New source file and branch committed to GitHub.
- Follow-up source verification confirmed the new default, warning path, optional block, diagnostic-only directional context logger, and retained risk constants.
- **Not compiled in MetaEditor and not run in MT4 Strategy Tester or on a broker account.**
- This is not evidence of profitability or proof that any broker will accept orders. Test on demo first and inspect the complete journal and trade-history costs.

## Evaluation data to collect

For each closed trade, retain symbol, direction, open/close server time, lots, entry, SL, TP, gross P/L, commission, swap, net P/L, close classification, and ticket. Also record floating P/L, daily realized P/L, and aggregate open risk at each scan cycle. Compare BUY and SELL separately and include rejected candidates, not only accepted trades. The loss-context log must never be treated as a rejection reason.
