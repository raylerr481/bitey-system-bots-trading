# Bitey Scalper v1.4.5.9 — Adaptive Risk Research Audit

## Purpose

This branch is a research/audit copy of v1.4.5.8. It adds append-only lifecycle CSV telemetry so the loss, time-in-trade, trailing-stop, and TP-extension questions can be evaluated from MT4 data before changing trading behavior.

**No entry, sizing, stop, target, time-exit, daily-loss, or directional-entry rule is intentionally changed in this build.** v1.4.5.8 remains preserved on its original branch.

## Source

- Parent: `experimental/v1-4-5-8-scalping-no-daily-entry-block`
- Research branch: `research/v1-4-5-9-adaptive-risk-audit`
- EA: `Bitey_Scalper_MultiAsset_v1_4_5_9_AdaptiveRisk_Audit.mq4`
- Version: `1.4.5.9`

## Historical-data audit result

The v1.4.5.8 branch currently contains two MT4 HTML statements, but neither supplies an attributable v1.4.5.8 trade sample:

- `DetailedStatement.htm` contains other magic numbers/strategies (including 21102027 and unrelated Bitey SBT builds); it does not identify v1.4.5.8 trades.
- `DetailedStatement2.htm` contains magic 21102026 trades labeled v1.3.0 through v1.4.3, but no v1.4.5.8 trades.

Therefore these statements must **not** be presented as a v1.4.5.8 performance audit. The exact v1.4.5.8 historical CSV/trade export was not found in this branch. No performance conclusions or adaptive-risk parameter changes are justified from those mixed-version records.

## New CSV telemetry

The EA writes an append-only file named:

`Bitey_v1_4_5_9_Lifecycle_YYYY-MM-DD_HH-MM.csv`

Location:
- Strategy Tester: MT4 `Tester\Files`
- Normal terminal: MT4 `MQL4\Files`

Events:
- `SNAPSHOT`: first observed management snapshot and then at most once per 60 seconds per open ticket.
- `ADAPTIVE_MODIFY`: each successful adaptive OrderModify, with old/new SL and TP and flags showing which changed. This allows trailing-stop changes and TP extensions to be separated.
- `TRADE_CLOSED`: final broker-history outcome with actual gross, booked commission, swap, net, open/close times and close classification.

Fields include ticket, symbol, direction, lot size, open time, elapsed seconds, bars held, entry/mark/SL/TP, floating gross/commission/swap/net, observed maximum favorable and adverse floating net, final realized costs and outcome.

MFE/MAE are sampled from the EA's periodic management snapshots; they are **observed sampled extrema**, not tick-perfect extrema. Very short excursions between snapshots may be missed. The final realized P/L and booked costs come from MT4 account history.

The CSV is research telemetry only. File-write failure is logged and does not alter trading decisions.

## What remains unchanged

- Reference capital USD 500.
- Per-trade risk 0.5%; aggregate open risk cap 2.5%.
- Maximum 5 positions; one position per asset key.
- Daily loss threshold 3%; daily entry block remains disabled by default.
- Directional loss context remains diagnostic only and does not block or delay entries.
- Initial SL, adaptive break-even, trailing SL, net-profit lock and adaptive TP extension retain v1.4.5.8 parameters and logic.
- The existing 48-bar time exit remains active; this research build does not yet convert it to a reevaluation-only checkpoint.
- No martingale or recovery multiplier is introduced.

## Analysis plan after collecting the CSV

1. Separate BUY and SELL, symbols, and close classifications.
2. Calculate net P/L after booked commission and swap; measure spread/execution costs where available.
3. Measure loss distribution and time-to-close, including the 48-bar time exit.
4. Compare observed adverse/favorable excursions with realized outcomes to estimate whether early exits would have helped or harmed.
5. Attribute profit giveback to trailing SL/net lock separately from additional profit captured by TP extension. The current CSV captures sampled excursions and final outcomes, but TP/SL modification-event logging can be added if the tester report does not preserve enough modification history.
6. Test any candidate risk throttle and exit policy on an in-sample period, then freeze parameters and validate on a separate out-of-sample period.
7. Compare net profit, profit factor, maximum drawdown, average loss, tail loss, trade count, exposure time, and missed-winner rate.

## Validation status

- GitHub branch and source file created.
- Static source review only; not compiled in MetaEditor.
- Not run in MT4 Strategy Tester or on a broker account.
- No claim of profitability, successful compilation, or live readiness.
- Demo/tester validation is required before any operational use.

## Required next input

Run this audit build in MT4 Strategy Tester or demo long enough to produce a representative CSV, then provide the CSV and the corresponding tester report. Only then should adaptive risk throttle levels, time-exit behavior, trailing parameters, or TP-extension parameters be selected.
