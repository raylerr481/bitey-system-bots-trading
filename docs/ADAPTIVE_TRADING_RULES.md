# Bitey SBT — Adaptive Trading Rules

**Status:** behavioral specification for implementation and verification. This document defines intended behavior; it does not by itself prove that any particular MQ4 build implements or compiles these rules.

## 1. Capital and hard risk controls

- Strategic capital allocation is fixed at **USD 500** and is not recalculated from the broker's account balance.
- Calculate per-trade monetary risk from actual order volume, entry price, Stop Loss distance, tick size/value, contract specifications, and relevant costs where available.
- The adaptive per-trade risk budget is a **maximum**, never a required amount to risk.
- Reject a trade if the minimum permitted volume would exceed the applicable risk budget or if a valid protective Stop Loss cannot be established.
- Enforce an aggregate portfolio risk ceiling before each new entry. The sum of open-position risk plus proposed new risk must remain within the configured ceiling.
- The daily loss limit remains configurable and must block new entries when reached. The previously used setting was USD 10; verify the actual EA input before treating that value as active.
- No martingale, no increasing volume to recover losses, no removal of protective stops, and no bypassing broker or risk restrictions.
- No forced entries: unused capacity does not require the EA to trade.

## 2. Adaptive risk per trade

The numbers **3 → 2 → 1** and **5 → 6 → 7 → 8 → higher** mean **USD of maximum risk per individual operation**, not number of entries.

### Portfolio in loss

- Confirmed portfolio losses: maximum risk budget USD 3 per new operation.
- Persistent losses: reduce the maximum to USD 2.
- Severe loss or elevated portfolio risk: reduce the maximum to USD 1, or block new entries when required by the risk gate.
- Losses must never cause a larger lot or a higher risk budget to recover money.

### Portfolio in sustained profit

- First sustained, confirmed net-profit level: maximum risk budget USD 5 per new operation.
- Further confirmed profit levels: USD 6, then USD 7, then USD 8 and higher only through configured, explicitly bounded steps.
- Profit confirmation must persist for a configurable period and meet configurable thresholds; one winning trade or one brief positive tick is insufficient.
- If profit retreats or risk rises, freeze expansion and reassess; reduce the budget when the portfolio enters the corresponding loss state.
- Every step remains subject to the fixed USD 500 allocation, per-trade budget, aggregate risk ceiling, daily limits, symbol constraints, and position limits.
- USD 8 is 1.6% of USD 500 for one trade. Seven positions each risking USD 8 would represent USD 56 of stop-defined exposure before execution effects, so the aggregate risk gate must be authoritative and can reject further entries.

## 3. Portfolio and entry selection

- Evaluate the configured seven canonical assets and the strategy's 16 model evaluators. Verify the actual asset aliases and that all 16 evaluators are present in the code.
- Rank candidates using model evidence, market regime, direction, historical validation, and risk checks.
- Open only candidates that pass all filters; never force an entry to fill available capacity.
- Maximum simultaneous positions remains seven unless explicitly changed in a separate approved specification.
- Maintain at most one managed position per canonical asset, regardless of BUY/SELL direction. Normalize broker symbol aliases to avoid duplicate exposure.
- Manage all positions belonging to the EA's configured magic number and portfolio, even when the EA is attached to a single asset chart.
- Do not close an existing position merely to free a slot. Existing positions remain under their normal protective management unless an independent, explicit exit or safety rule applies.
- The adaptive risk scale changes the USD risk budget per new operation; it does not change the number of positions allowed.

## 4. Portfolio state and adaptation

The portfolio state should account for:
- Net floating P/L of managed open positions, including profit, swap and commission.
- Realized results over a configured evaluation window.
- Net portfolio result and its persistence over a configurable period.
- Current stop-defined open risk and proposed new risk.
- Daily loss state, open-position count, and candidate quality.

Rules:
- On confirmed losses, step down the per-trade risk budget (USD 3 → 2 → 1) and tighten entry selection.
- If risk is elevated or the daily loss limit is reached, block new entries as required.
- If the state is neutral or recovery is not yet confirmed, keep the current level rather than oscillating on every tick.
- On sustained confirmed net profit with controlled aggregate risk, step up gradually (USD 5 → 6 → 7 → 8+).
- On profit deterioration or increased risk, freeze expansion and reassess the budget.
- Portfolio mode changes must be logged with prior/new mode, net realized/floating P/L, risk budget, aggregate exposure, and reason.

## 5. Adaptive Stop Loss (SL) and Take Profit (TP)

### When a position has net floating loss
- Do not make adaptive SL or TP modifications while that position's net floating P/L is negative.
- Net floating P/L is calculated as `OrderProfit + OrderSwap + OrderCommission`.
- Leave the existing SL/TP unchanged under the adaptive manager. Independent emergency/safety exits, if separately implemented and explicitly specified, must not be confused with adaptive SL/TP changes.
- Never loosen the SL to increase the loss the position can tolerate.

### After three favorable closed candles
Adaptive SL/TP management may activate only when all of these are true:
1. Three consecutive candles have closed on the configured strategy timeframe; do not count the currently forming candle.
2. The candles and market context confirm a sustained favorable move in the direction of the open position.
3. The position's net floating P/L is strictly positive, including swap and commission.
4. Any configured minimum-profit threshold and broker restrictions are satisfied.
5. The proposed change improves protection or is a justified favorable TP extension.

Direction:
- **BUY / price rising:** SL may move upward to protect profit; TP may extend upward with favorable trend confirmation.
- **SELL / price falling:** SL may move downward to protect profit; TP may extend downward with favorable trend confirmation.
- SL must never move in the adverse direction or increase potential loss.
- TP must only extend in the favorable direction and only with sufficient trend/model confirmation.
- Three candles are a minimum confirmation condition, not a guarantee of future profit and not an instruction to modify on every candle.
- Further modifications require renewed confirmation, a meaningful minimum price/ATR change, and per-ticket cooldown. Avoid micro-adjustment spam.
- If net floating P/L becomes negative, suspend adaptive SL/TP modifications for that position.
- Existing protective SL/TP must not be removed. Respect broker stop/freeze levels, tick size, and price precision.

## 6. Order execution and confirmation

Before a new order, validate quote freshness, symbol trading availability, spread, volume step/min/max, tick economics, valid SL, proposed monetary risk, aggregate risk, daily limits, and duplicate-asset exposure.

For every modification:
- Record ticket, canonical asset, direction, net floating P/L, candle-confirmation state, old SL/TP, requested SL/TP, cooldown/minimum-change result, OrderModify return value, and error code.
- Re-read the order from MT4 after the modification.
- Mark the change **confirmed** only if the readback shows the expected applied levels. If modification fails or readback does not match, record failure/deferred state and do not claim success.
- Recommended audit labels include `PORTFOLIO ADAPTIVE MODE`, `SLTP MODIFY AUDIT`, and `SLTP MODIFY DEFERRED`.

## 7. Priority order

When rules conflict, apply this priority:
1. Capital protection and hard risk ceilings.
2. Valid protective SL and prohibition on increasing potential loss.
3. Daily loss and aggregate portfolio risk limits.
4. Normal management of existing positions.
5. Confirmed-profit adaptive SL/TP rules.
6. Adaptive risk budget for new entries.
7. Candidate ranking and optimization.

## 8. Required verification before release

Do not declare the implementation complete until the MQ4 source is inspected and MetaEditor compilation/testing verifies:
- All 16 model evaluators and all seven canonical assets are actually configured.
- Risk budget transitions are implemented consistently across every order-entry path.
- Aggregate risk is enforced for existing plus proposed positions.
- One-position-per-canonical-asset protection works across aliases and directions.
- Three closed favorable candles are counted on the configured timeframe, per ticket.
- No adaptive SL/TP path modifies a position with net floating loss.
- SL can never loosen; TP only extends favorably after confirmation.
- Cooldown and minimum-change filters prevent repetitive modifications.
- Journal records distinguish requested changes from readback-confirmed changes.
- Demo testing covers BUY and SELL, profitable and losing positions, broker rejections, and portfolio transitions.

## 9. Risk disclosure

These rules can constrain risk but cannot guarantee that losses will not occur or that a stop executes at its exact price. Gaps, slippage, liquidity, spread changes, terminal disconnection, broker restrictions and rejected modifications can change realized outcomes. The EA must be compiled and validated in MetaEditor and tested on demo before use.
