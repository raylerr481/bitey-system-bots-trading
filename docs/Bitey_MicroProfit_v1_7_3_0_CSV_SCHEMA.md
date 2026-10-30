# Bitey MicroProfit AI v1.7.3.0 — CSV audit schema

## Runtime files

All files are written to the MT4 terminal's local `MQL4\Files` folder (not Common\Files).

1. `Bitey_MicroProfit_Process_<magic>.csv` — append-only event stream.
2. `Bitey_Ens_TradeAudit_<magic>.csv` — one row per captured closed EA trade, extended with negative duration, entry score and close reason.
3. `Bitey_Ens_NetByAsset_<magic>.csv` — existing per-symbol closed-trade net summary.

Set MT4 Account History to **All History** for the most complete closed-trade audit.

## Process CSV columns

| Column | Meaning |
|---|---|
| schema_version | CSV schema version |
| session_id | Account + Magic + EA initialization timestamp |
| event_id | Unique event key using server time, tick counter and ticket |
| server_time | Broker/server timestamp |
| event_type | Stable event identifier |
| process_id | Process family: INIT, ENTRY, MONITOR, EXIT, REENTRY, DAILY_GUARD, TRADE or LIFECYCLE |
| ticket | MT4 order ticket; 0 for portfolio-level events |
| symbol / side | Broker symbol and BUY/SELL |
| magic / ea_version | EA ownership and version |
| elapsed_seconds | Time since open, where applicable |
| negative_seconds | Accumulated observed time with net P/L below zero |
| net_current | Current posted net P/L |
| net_after_estimated_close | Net after reserving estimated remaining close commission |
| gross / commission / swap | MT4 order components |
| estimated_remaining_close_commission | Remaining round-turn commission estimate |
| target_net | Configured net close target |
| entry_score | Existing rule-based signal score |
| regime_vote_descriptor | Counts for EMA, RSI, Donchian and Bollinger variants plus regime, ADX, cost-R and family agreement |
| reason | Machine-readable event detail / exit or rejection reason |

## Main event_type identifiers

- `EA_INIT`, `EA_DEINIT`
- `ENTRY_OPENED`, `ENTRY_REJECT`
- `TRADE_ENTERED_NEGATIVE`, `TRADE_RECOVERED_NONNEGATIVE`
- `MICROPROFIT_TARGET_REACHED`, `MICROPROFIT_TIME_EXPIRED`
- `CLOSE_CONFIRMED`, `CLOSE_FAILED`, `TRADE_CLOSED`
- `REENTRY_LOCK_SET`, `REENTRY_STRICT_REJECT`
- `DAILY_PEAK_GIVEBACK_TRIGGERED`

## Strategy rules in this experimental build

- Close when estimated net after remaining commission is at least USD 0.10.
- Close at 20 minutes from open if the target was not reached.
- Record accumulated time while posted net P/L is negative.
- After a losing close, block that symbol in either direction for at least 20 minutes; afterward require a score at least 8 points above the previous failed entry's score.
- Persist daily net peak per account + Magic + broker/server date. At a 50% giveback from the positive peak, close only this EA's positions and block entries until the next server day.
- Preserve the inherited entry signal, lot sizing, risk caps, SL/TP construction, and Magic ownership.

## Interpretation cautions

- Spread is already reflected in MT4's floating order profit; do not subtract it a second time.
- MT4 exposes profit, commission and swap through its standard order functions. It does not expose a separate universal tax field for every broker; any tax embedded in broker commission/fees is reflected only as the broker reports it. Verify Tradewill's statement against the CSV.
- The remaining close commission is estimated from the configured round-turn commission minus commission already posted on the open order. Calibrate `InpCommissionPerLotFX` and `InpCommissionPerLotOther` to actual Tradewill statements.
- Slippage, requotes, partial fills and broker-side fees can make realized net differ from the estimate.
- The inherited signal engine is four rule-based families with eight variants each (32 indicator variants). It is **not** a connected 30-independent-AI-model assembly. The CSV records the real family vote counts; no model votes are fabricated.
- Negative time is accumulated while the EA is running and observing the order; terminal downtime is intentionally not counted as observed negative time.
- CSV rows depend on MT4 exposing the relevant order history. Use All History and preserve the files between test runs.

## Validation status

Source-level changes only. This file has not been compiled in MetaEditor or backtested in MT4. Validate compilation, CSV creation, close-cost calibration, broker execution and demo behavior before enabling it on a live account.
