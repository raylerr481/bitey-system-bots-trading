# Bitey Scalper MultiAsset v1.3.2 — Net Profit Opportunity Exit

Successor to v1.3.1, isolated on `feature/scalper-v1-3-2-net-profit-opportunity-exit`. The original v1.3.0 and `main` remain unchanged.

## New exit decision
- Estimate closeable net P/L from current floating P/L + swap + charged commission, less configured closing commission, adverse-slippage reserve and optional tax reserve.
- MT4 floating profit is marked at Bid for BUY and Ask for SELL, so spread is already reflected. It is deliberately NOT subtracted a second time.
- When estimated closeable net exceeds `InpNetCloseThreshold` (default 0.10 in account currency), evaluate trend direction and strength.
- If trend evidence is weak or contrary, close and log `NET_PROFIT_WEAK_TREND`.
- If trend remains strong and aligned, keep the position; the existing adaptive break-even, ATR trailing, net-profit-lock SL and trend-confirmed TP expansion continue to manage it.
- Strong-trend check uses ADX, +DI/-DI direction and HTF EMA(50) price alignment. Optional ADX-change floor is configurable.

## New inputs
- `InpNetCloseThreshold = 0.10`
- `InpNetTaxReservePct = 0.0` (optional planning reserve, not a statement of actual Brazilian tax liability)
- `InpCloseCostBuffer = 0.02`
- `InpHoldTrendADXMin = 22.0`
- `InpHoldTrendADXRiseMin = -1.0` (disabled unless set to 0 or higher)

## Costs and limitations
- Configure `InpEstimatedCloseCommissionPerLot` with broker's closing-side commission per 1.00 lot, in account currency.
- `InpNetLockSlippagePoints` is used as an adverse execution reserve.
- Actual tax treatment is jurisdiction-, instrument-, account- and transaction-dependent. The tax percentage is only a user-configured reserve; it does not calculate or remit taxes.
- Swap and charged commission are read from the selected MT4 order. Floating P/L already includes spread through Bid/Ask marking.
- No EA can guarantee exact realized net profit because gaps, slippage, rejected closes, commissions that differ from estimates and execution delays can change the result.
- A profitable position is not closed solely because it crosses 0.10 if directional trend remains strong; it is retained for the existing SL/TP system to manage.

## Validation
Committed source only. Not compiled in MetaEditor; not Strategy-Tested or forward-tested. Compile and test BUY/SELL, weak/strong trend, FX and crypto symbols, broker commissions, swap, stop/freeze levels and rejected-close handling on demo before live use.


## First-priority net-profit floor (updated)

The EA now checks the net-profit floor at the start of managing each open position,
before the time exit, trend filter, ATR-dependent logic, R-multiple target, break-even,
trailing stop, or adaptive take-profit logic. When the conservative estimate is
**greater than or equal to** `InpNetCloseThreshold` (default `0.10` in account
currency), it immediately attempts to close the position with reason
`PRIORITY_NET_PROFIT_FLOOR`. A strong trend no longer delays this close.

The estimate starts with MT4 `OrderProfit()+OrderSwap()+OrderCommission()`:
- swap and opening commission are included by MT4;
- the executable-side Bid for BUY / Ask for SELL already reflects the broker spread,
  so spread is not subtracted a second time;
- estimated closing commission per lot, configured slippage reserve, close-cost
  buffer, and optional tax reserve are deducted before comparing with the floor.

**Configuration is essential:** set `InpEstimatedCloseCommissionPerLot` to the
broker's actual closing commission per 1.0 lot in account currency, and set
`InpNetTaxReservePct` to the tax reserve you want to model. The default tax reserve
is 0% because the EA cannot determine the user's actual tax liability. The 0.10
threshold is in account currency; it represents USD 0.10 only on a USD-denominated
account.

This is a conservative estimated-net trigger, not a guarantee of the final booked
amount. Gaps, fast price changes, broker execution, rejected closes, and slippage
beyond the configured reserve can result in a realized net below 0.10. If a close
request fails, the EA logs the failure and checks again on the next management cycle.
Compile in MetaEditor and validate on demo before live use.


## Two-sided first-priority net guard (updated)

The EA now applies a two-sided, conservative net-result guard before the time exit,
trend/ATR checks, optional R target, break-even, trailing stop, or adaptive TP:

- **Profit protection:** attempt to close when estimated net proceeds are
  `>= InpNetCloseThreshold` (default 0.10 in account currency).
- **Loss containment:** attempt to close when estimated net proceeds are
  `<= -InpNetLossCutThreshold` (default 0.20 in account currency).

The loss threshold is a positive magnitude; the comparison is against its negative
value. Both rules use the same estimated close result, including current MT4
floating profit, opening commission and swap, estimated closing commission,
slippage reserve and extra cost buffer. Positive tax reserve is deducted only from
positive estimated proceeds. The executable-side Bid/Ask mark already reflects the
broker spread; spread is not subtracted twice.

This is an additional market-close guard, **not a replacement for the broker-side
Stop Loss**. The SL remains essential for terminal disconnection, missed ticks,
gaps and rejected/failed close requests. Adaptive TP remains useful to capture
larger trends only while neither net guard has triggered. A loss cut at -0.10 can
also exit a trade before its original SL; that is intentional for this experiment.

The 0.10 and 0.20 values are in account currency (USD only on a USD account).
Closing commission must be configured accurately. Taxes are user-configured
reserves, not a legal tax calculation. Market execution cannot guarantee the exact
threshold: gaps, slippage and broker rejection can produce a worse realized result.
Compile and run controlled demo tests before any live use.
