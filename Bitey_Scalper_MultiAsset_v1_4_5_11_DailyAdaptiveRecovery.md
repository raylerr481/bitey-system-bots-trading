# Bitey Scalper MultiAsset v1.4.5.11 — Daily Adaptive Recovery

## Status
Experimental branch: `research/v1-4-5-11-daily-adaptive-recovery`

Parent: `research/v1-4-5-10-adaptive-modify-throttle`

This version adds a daily strategy selector. The v1.4.5.10 execution, portfolio-risk, signal, adaptive-stop, throttle, and audit logic is retained except for the explicitly described recovery-mode exit selection.

## Daily state machine

1. **Start of broker/server day:** use the existing adaptive SL/TP strategy.
2. **First ten closed market trades:** count only closed BUY/SELL orders with this EA's `InpMagic`. Open trades are not counted.
3. **Evaluate the first ten:** sum `OrderProfit()+OrderCommission()+OrderSwap()` for the ten earliest close times of the current server day.
4. **If the first-ten net is zero or positive:** remain in adaptive SL/TP mode for the day.
5. **If the first-ten net is negative:** enter `SHORT_PROFIT_RECOVERY`. While in recovery, close an EA position when its estimated net after booked costs, configured closing commission, and adverse-slippage reserve reaches `InpDailyRecoveryShortProfitNetUSD` (default 0.50 account-currency units).
6. **Recovery progress:** sum the realized net of all closed EA market trades after the first ten. Later recovery losses increase the deficit; later gains reduce it.
7. **Once recovered:** when post-first-ten realized net is at least the absolute first-ten deficit, persist a daily completion latch in a terminal Global Variable and return to adaptive SL/TP for the remainder of that broker day. Later losses do not reactivate recovery until the next server day.
8. **Next server day:** the first-ten evaluation starts again for that date. Previous realized account losses are not erased.

## Recovery-mode behavior

- Keeps original initial SL, risk sizing, aggregate/currency risk caps, max positions, signal filters, broker permission checks, and SL protection.
- Keeps the v1.4.5.10 minimum SL step, five-second modification interval, and emergency protective-step bypass.
- Uses a short net-profit close target; default `InpDailyRecoveryShortProfitNetUSD=0.50`.
- Does not activate a new long profit runner in recovery mode.
- Does not extend TP in recovery mode; the existing broker-side TP remains in place.
- Does not disable the original max-hold time exit.
- Does not change lot sizes, add martingale, widen initial risk, or bypass daily-loss/risk protections.
- Existing adaptive SL tightening and cost-aware net-profit stop protection remain active.

## Net accounting and limitations

- Closed-trade realized net uses MT4 `OrderProfit()+OrderCommission()+OrderSwap()`.
- For open trades, `OrderProfit()` is marked at Bid for BUY / Ask for SELL, so spread is already reflected; do not subtract spread again.
- Estimated close costs include `InpEstimatedCloseCommissionPerLot` and the configured adverse-slippage reserve.
- MT4 MQL4 order history does not expose a separate universal tax field. If broker taxes are charged, confirm whether they are represented in commission or another broker statement field; the EA cannot claim exact after-tax net otherwise.
- The 0.50 target is in account currency. The existing EA warns when account currency is not USD; verify conversion before use.
- The daily selector relies on MT4 account history available to the terminal. Set the Account History tab to show all history so the EA can reconstruct the day's closed trades after restart.
- The first ten are selected by close timestamp, not by order-open time.
- Partial closes appear as separate history records if MT4 reports them as separate tickets.

## Preserved v1.4.5.10 controls

- Reference capital USD 500; 0.5% risk per trade; 2.5% aggregate risk; max five open positions.
- Daily-loss warning-only default remains unchanged (`InpEnableDailyLossBlock=false`).
- Existing signal, spread, quote-age, session, broker-permission, currency-risk, and trade-enable checks remain unchanged.
- Adaptive SL only tightens; TP expansion is permitted only in adaptive mode and retains its existing progression/ADX conditions.
- No martingale, no account-mode gate, and no changes to manual MT4/broker authority.
- Lifecycle CSV audit retained; filename prefix updated to v1.4.5.11.

## Verification status

Static source transformation checks only. Not compiled in MetaEditor, not run in MT4 Strategy Tester, and not tested on broker demo/live. This branch is experimental and must be compiled and tested before installation or trading.
