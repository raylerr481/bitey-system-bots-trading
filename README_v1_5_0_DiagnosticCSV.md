# Bitey Scalper v1.5.0 — Diagnostic CSV

## File
`Bitey_Scalper_MultiAsset_v1_5_0_DiagnosticCSV.mq4`

Branch: `feature/scalper-v1-5-0-diagnostic-csv`

Based on v1.4.9. This is a diagnostics/export build: it does not intentionally change the signal rules, position sizing, risk limits, symbol universe, quote-freshness gate, or order-management rules.

## CSV output
On EA initialization it creates a timestamped file similar to:

`Bitey_Scalper_v1_5_0_Diagnostic_2026-11-01_06-46.csv`

- Normal MT4 chart: `File → Open Data Folder → MQL4 → Files`
- Strategy Tester: `File → Open Data Folder → Tester → Files`

The CSV is append-only for that timestamped filename, flushed after each row, and closed on EA deinitialization. The Journal prints `DIAGNOSTIC_CSV_OPEN` with the exact filename and folder. If file creation fails, check `DIAGNOSTIC_CSV_ERROR` and its error code.

## Captured data
- Configuration snapshot: reference capital, risk percentages, position limit, BUY/SELL flags, timeframes, quote-age and history thresholds, ADX/ATR and spread parameters.
- One heartbeat snapshot per symbol every five minutes, including quote freshness, history state, current/previous M5 bar times, closed M5 OHLCV, previous close, HTF close/EMA50, bid/ask/spread, ADX, ATR and RSI.
- Bar-scan state changes, prefilter passes and rejection reasons.
- Indicator evaluation outcomes and the EA's indicator/vote summary.
- BUY/SELL candidates, score and ranking context.
- Execution summary, dry-run candidates, broker order accepted/rejected events.
- Closed-trade gross P/L, commission, swap and realized net.

## How to provide the file for analysis
1. Compile the MQ4 in MetaEditor.
2. Attach the EA to the intended MT4 chart and confirm `DIAGNOSTIC_CSV_OPEN` in the Experts/Journal tab.
3. Let it run for at least 10–15 minutes so several heartbeat snapshots are recorded (longer if waiting for new M5 bars or trading sessions).
4. Open the data folder and upload the generated `.csv` file in ChatGPT.

The CSV can contain account/trading activity. Review it before sharing and remove any information you do not want to disclose.

## Validation status
Committed to GitHub; not yet compiled in MetaEditor or validated in Strategy Tester. Do not treat the file as compile-tested or performance-validated until those checks have been run.
