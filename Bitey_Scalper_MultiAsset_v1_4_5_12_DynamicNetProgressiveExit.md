# Bitey Scalper MultiAsset v1.4.5.12 — Dynamic Net Profit & Progressive Loss Exit

## Status
Experimental branch: `research/v1-4-5-12-dynamic-net-progressive-exit`; parent `research/v1-4-5-11-daily-adaptive-recovery`. v1.4.5.11 and the default branch remain unchanged.

## Preserved from v1.4.5.11
- Daily first-ten-closed-trades selector and daily recovery state machine.
- Recovery close target `InpDailyRecoveryShortProfitNetUSD=0.50` net (account currency).
- Small-profit close `InpSmallProfitCloseUSD=0.10` net in adaptive mode when no runner is active and progression is neutral/adverse.
- Existing profit runner, cost-aware net-profit lock, adaptive SL tightening, and adaptive TP extension.
- TP expansion still requires favorable progression and ADX; existing recovery-mode TP behavior is unchanged.
- USD 500 reference capital, 0.5% per-trade risk, 2.5% aggregate risk, max five open positions, signal/quote/session/broker controls and lifecycle CSV.
- `InpEnableDailyLossBlock=false`; daily loss warning remains informational only.
- No martingale, account-mode gate, risk bypass, or widening/removal of the initial broker SL.

## New progressive net-loss exit
- Enabled by default, but only evaluated when closed-bar directional progression confirms adverse movement (`progression<0`). Neutral/uncertain progression cannot trigger it.
- Uses estimated net after booked commission/swap, configured closing commission and adverse-slippage reserve. Spread is already reflected in executable Bid/Ask mark and is not subtracted twice.
- New tickets persist original monetary stop risk at entry in a terminal Global Variable; it is not recomputed from a subsequently tightened SL.
- Initial loss allowance is 60% of original stop risk (`InpProgressiveLossBaseRiskPct`). As realized closed P/L for the server day becomes more negative, the allowance shrinks using `basePct/(1+pressureFactor*abs(closedTodayNet)/originalRisk)`, with a 15% floor (`InpProgressiveLossMinRiskPct`).
- Closed realized P/L drives daily pressure; each position's floating net is evaluated separately, preventing double counting. Realized gains reduce pressure; losses increase it.
- If adverse progression exists but the allowance is not exceeded, the EA holds with original broker SL and continues normal adaptive SL/TP management.
- Legacy positions without stored original risk use current SL risk as a conservative proxy; without a valid SL/risk, early exit is skipped.
- Legacy fixed small-loss exit remains disabled (`InpSmallLossCloseUSD=0`).

## Cost and currency limitations
- Net estimate = `OrderProfit()+OrderSwap()+OrderCommission()` less configured estimated closing commission and adverse-slippage reserve.
- MT4 does not expose a universal separate tax field; broker-specific taxes may not be separately modeled.
- Configure `InpEstimatedCloseCommissionPerLot` when a separate closing commission applies.
- Thresholds use account currency; verify currency conversion when account currency is not USD.

## Audit events
`PROGRESSIVE_NET_LOSS_MONITOR`, `PROGRESSIVE_NET_LOSS_EXIT`, `PROGRESSIVE_NET_LOSS_SKIP`.

## Verification
Source/documentation only. Not compiled in MetaEditor, not run in Strategy Tester, and not verified on a broker demo/live account. Compile and test before installation; compare trade-level CSV against v1.4.5.11 on identical data.
