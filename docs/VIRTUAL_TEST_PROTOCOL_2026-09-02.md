# Conclusive Virtual-Money Validation — 2026-09-02

## Objective
Validate the Bitey System Bots Trading execution chain using **100% fictitious capital**, without sending broker orders or enabling live trading.

## Baseline
- Initial virtual capital: **R$10,000**
- Instrument: **EURUSD**
- Timeframe: **H1**
- Execution mode: **demo only**
- Real money: **false**
- Broker orders: **false**
- Risk Gate: **mandatory**
- Allowed symbol in demo trading API: **EURUSD**
- Default maximum position: **2% of initial capital**
- Default daily-loss limit: **1% of initial capital**

## Required evidence
A test is conclusive only when the run records:

1. Initial and final virtual equity/cash.
2. Every accepted and rejected order.
3. Rejection reason for every blocked order.
4. Entry/exit price and quantity.
5. Realized P/L and cumulative P/L.
6. Number of trades and winning/losing trades.
7. Maximum drawdown.
8. Risk-rule behavior when limits are reached.
9. Confirmation that no broker/live order was sent.
10. Deterministic/reproducible results from the same dataset and parameters.

## Software validation now implemented
- `DemoOrderRequest.side` uses the typed `Side` enum instead of a free-form string.
- Demo execution calculates realized P/L for closed virtual positions.
- Virtual positions and average entry price are maintained by the demo engine.
- Demo risk validation can restrict symbols and quantity in addition to position-size and daily-loss rules.
- `/api/v1/demo/portfolio` and `/api/v1/trading/portfolio` now expose the same in-memory demo portfolio.
- Demo responses explicitly identify `real_money=false` and `broker_order=false`.
- Live trading remains disabled at the application configuration boundary.

## Important distinction
This protocol validates **system correctness and safety in simulation**. A profitable simulation does not prove future live profitability. Live trading remains a separate milestone requiring independent security, authorization, broker, risk, persistence, and end-to-end validation.

## Execution status
**Implementation baseline recorded. Runtime execution of the full historical/MT5 dataset is not claimed by this document until an actual test run produces the metrics above.**
