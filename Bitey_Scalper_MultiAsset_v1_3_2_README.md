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
