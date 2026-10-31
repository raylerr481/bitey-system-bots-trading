# Bitey SBT v1.8.3.1 — Scratch Path Audit (experimental)

## Provenance

This is a new experimental continuation of the recoverable v1.8.3.0 AdaptiveRangeNetProfit source. It is **not** a recovered copy of the missing v1.8.2.0 Scratch file and must not be represented as that version.

The existing v1.8.3.0 branch and source remain unchanged.

## What changed

- Preserves the existing multi-asset Range/Trend entry logic, BUY/SELL handling, portfolio limits, risk governor, SL/TP logic and cost-aware net-profit protection.
- Keeps InpScratchSafetyUSD = 0.02 by default.
- Separates two measurements:
  - Research threshold: +$0.10 net after booked commission/swap and configured estimated close costs.
  - Execution trigger: +$0.10 + safety; with the default safety this is +$0.12.
- Samples each open ticket every 2 seconds by default, configurable with InpScratchSampleIntervalSec.
- Writes Bitey_Scratch_Samples.csv with ticket, symbol, side, elapsed seconds, marked net, estimated net after close costs, MFE/MAE, bid/ask and spread.
- Writes Bitey_Scratch_Trades.csv once for each closed trade seen by the EA history synchronizer, including SL/TP/manual/EA closes where the excursion state is available.
- Adds an inferred exit_class (SL, TP, OTHER) based on close price proximity to the recorded stop/target. This is diagnostic, not a broker-provided close-reason field.
- Adds Bitey_Scratch_Analysis.py to calculate, per asset, +$0.10 and +$0.12 hit rates within 20 minutes, hit rates among losing/SL-classified trades, realized net win rate, net breakeven win rate, PF and net P/L.

## Required broker-cost configuration

Do not enable the Scratch close until the broker's commission treatment is verified.

1. Read actual closed-trade statements and determine the **additional close commission per 1.00 lot** that is not already reflected in the current OrderCommission().
2. Set InpEstimatedCloseCommissionPerLot to that verified amount in account currency.
3. Set InpCloseCommissionConfirmed = true only after the above is confirmed.
4. Keep InpScratchSafetyUSD >= 0.02; the default is 0.02.

If the account is not USD-denominated, the USD reference-capital and USD-target assumptions must be checked before interpreting the results. Do not guess a conversion.

## Where MT4 writes the CSVs

In the MT4 terminal, use **File → Open Data Folder → MQL4 → Files**. Strategy Tester may use its own tester file area; inspect the tester's data folder after the run. The CSVs are local terminal files and are not automatically committed to GitHub.

## Run the analyzer

Place Bitey_Scratch_Analysis.py in the same folder as both CSVs, then run: py .\Bitey_Scratch_Analysis.py

Optional explicit paths: py .\Bitey_Scratch_Analysis.py --trades .\Bitey_Scratch_Trades.csv --samples .\Bitey_Scratch_Samples.csv --window-sec 1200

## Interpretation rules

- The key test is how many eventual losers and SL-classified trades first reached +$0.10 net within 1,200 seconds. The old statement cannot answer that.
- The +$0.12 count measures the stricter safety-buffered execution trigger separately.
- Periodic samples can miss a short-lived touch between observations; they approximate the path and are not tick-perfect.
- net_after_close_costs is only as accurate as the broker commission input and slippage reserve.
- A high win rate is insufficient: compare net expectancy, PF, average win/loss, drawdown, costs and out-of-sample stability.
- Do not automatically remove USDJPY, EURCAD, TRXUSDT, GBPJPY or AUDJPY from the universe from a small sample or win rate alone. Require adequate sample size and net expectancy evidence.

## Validation status

Static source checks only. This branch has **not** been compiled in MetaEditor and has **not** passed MT4 Strategy Tester or demo execution. Compile with F7, resolve any compiler diagnostics, then run Strategy Tester and demo before considering any live use. Do not merge this experimental branch into main until those checks and out-of-sample results are reviewed.
