# Bitey Scalper v1.4.5.8 — Experimental Build

## Purpose

This experimental branch evaluates the scalper through the full trading session without the daily-loss entry block being enabled by default. It also changes the loss cooldown from symbol-wide to direction-specific.

The v1.4.5.7 source file is preserved unchanged. This build is a separate file and branch.

## Changes

### 1. Daily-loss threshold: warning by default

- `InpDailyLossPct = 3.0` remains the threshold.
- New input: `InpEnableDailyLossBlock = false`.
- Default behavior after the threshold is crossed: emit `DAILY_LOSS_WARNING` and continue evaluating otherwise-valid entries.
- If the input is explicitly set to `true`, the previous `DAILY_LOSS_BLOCK` behavior remains available.
- Existing positions continue to be managed by the existing exit logic.

The daily P/L calculation in `TodayNet()` includes realized net P/L for orders closed since the broker-server day's start, plus the current floating net P/L of all open EA market positions. Net is gross profit + swap + commission. It is not a pure closed-trades-only statistic.

### 2. Direction-specific loss cooldown

- A losing BUY can block only a subsequent BUY on the same broker symbol.
- A losing SELL can block only a subsequent SELL on the same broker symbol.
- The opposite direction remains eligible for evaluation, but it is not opened automatically: it must independently pass signal, score, session, spread, quote, permission, position, and risk checks.
- Cooldown duration remains `InpCooldownBars = 6` bars.
- The history scan considers up to 80 matching closed trades for the same EA magic number, exact broker symbol, and exact direction.

The existing one-position-per-asset rule remains in place. Therefore, a SELL is not eligible while a BUY position on the same normalized asset key is still open.

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
- Follow-up source verification confirmed the new default, warning path, optional block, directional cooldown signature, and retained risk constants.
- **Not compiled in MetaEditor and not run in MT4 Strategy Tester or on a broker account.**
- This is not evidence of profitability or proof that any broker will accept orders. Test on demo first and inspect the complete journal and trade-history costs.

## Evaluation data to collect

For each closed trade, retain symbol, direction, open/close server time, lots, entry, SL, TP, gross P/L, commission, swap, net P/L, close classification, and ticket. Also record floating P/L, daily realized P/L, and aggregate open risk at each scan cycle. Compare BUY and SELL separately and include rejected candidates, not only accepted trades.
