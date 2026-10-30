# Bitey Ensemble Scalper MultiAsset v1.3.0

## Exit design
- **Stop Loss (SL) defines the trade loss boundary.** There is no fixed -USD 0.10 market-close rule and no separate monetary loss-cut threshold.
- **Take Profit (TP)** is initially calculated from the same SL distance multiplied by `InpRewardRisk` (default 1.5R). Existing adaptive management may move the SL only toward protection and may extend TP in a strong trend.
- **Net-profit cash close:** in addition to the broker-side TP, the EA attempts to close when conservative estimated net proceeds reach `InpNetCloseThreshold` (default 0.10 in account currency).
- The net-profit test is first priority in position management; it is not delayed by a trend filter.

## Net calculation and costs
The estimate starts from MT4 `OrderProfit()+OrderSwap()+OrderCommission()`:
- Opening commission and accrued swap are included by MT4.
- BUY floating P/L is marked at Bid and SELL at Ask, so the broker spread is already reflected once. It is not deducted a second time.
- The EA subtracts configured closing commission per lot, an adverse slippage reserve, `InpCloseCostBuffer`, and optional `InpNetTaxReservePct`.
- Configure `InpEstimatedCloseCommissionPerLot` using the broker's actual closing-side commission per 1.00 lot and set `InpNetTaxReservePct` to the reserve you want to model. The default tax reserve is 0%; this is not a calculation of Brazilian tax liability.
- The threshold is in account currency. It equals USD 0.10 only when the MT4 account is denominated in USD.

## Risk controls retained
- Position sizing is based on the distance from entry to SL and the configured per-trade and aggregate risk budgets.
- Existing daily loss control blocks new entries; it does not introduce a separate fixed loss close for open positions.
- No martingale or loss-recovery lot increase is introduced.
- Broker-side SL remains essential: market gaps, slippage, terminal disconnection, missed ticks or rejected close requests can cause realized losses to exceed the planned SL.

## Execution limitation
The +0.10 trigger is an estimated net trigger, not a guarantee that the final booked amount will be exactly +0.10. Fast price movement, gaps, commissions differing from configuration, slippage and broker rejection can change the realized result. If a market close fails, the EA logs the failure and retries management on a later cycle; the broker-side SL/TP remain the independent protection.

## Validation
Source created from the existing multi-asset scalper implementation with the requested exit-policy change. **Not compiled in MetaEditor, not Strategy-Tested and not forward-tested.** Compile and test on demo before any live use, including BUY/SELL, FX/crypto, commission, swap, spread, stop/freeze levels and close rejection cases.
