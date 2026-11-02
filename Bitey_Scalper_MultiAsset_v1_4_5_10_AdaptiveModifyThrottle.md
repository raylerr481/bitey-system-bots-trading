# Bitey Scalper MultiAsset v1.4.5.10 — Adaptive SL Modification Throttle

## Purpose

Experimental branch based on the v1.4.5.9 lifecycle-audit build. This version tests whether reducing repeated adaptive stop-loss modifications can lower broker request frequency without disabling protective stop management.

## Changes

- New input `InpAdaptiveSLModifyMinIntervalSeconds = 5`: after a successful adaptive SL modification, another ordinary SL modification for the same ticket is deferred until at least five seconds have elapsed.
- New input `InpAdaptiveSLModifyMinStepATR = 0.10`: every adaptive SL path (break-even, ATR trailing, and net-profit lock) must improve the existing stop by at least 0.10 ATR. The first protective SL is not delayed by this minimum-step rule.
- New input `InpAdaptiveSLEmergencyStepATR = 0.50`: a stop improvement of at least 0.50 ATR bypasses the five-second interval.
- Successful SL modifications persist their timestamp in a terminal Global Variable keyed by account and ticket.
- Deferred changes are logged as `ADAPTIVE_SL_DEFERRED`, with reason `BELOW_MIN_STEP` or `MIN_INTERVAL`.
- TP extension remains independently evaluated. A TP-only modification is not blocked by the SL interval.
- Existing lifecycle CSV telemetry from v1.4.5.9 remains in place.

## Unchanged controls

- Reference capital: USD 500.
- Risk per trade: 0.5%; aggregate stop-risk cap: 2.5%.
- Maximum open positions: 5.
- Daily loss block remains disabled by default.
- Directional loss context remains diagnostic-only and does not block entries.
- No martingale, no account-mode gate, and no risk bypass added.
- Initial SL and existing adaptive exit calculations remain otherwise unchanged.
- SL is only tightened; the code does not intentionally widen an existing SL.

## Important experimental trade-off

This version can leave an existing stop at its previous level for up to five seconds when a smaller improvement is deferred. Large improvements (>= 0.50 ATR) bypass that interval, but this is not a guarantee against fast gaps, slippage, rejected modifications, or broker-side execution limits. The minimum-step rule can also postpone small protective improvements. Therefore this build is for controlled Strategy Tester comparison and demo observation only until validated.

## Suggested test protocol

1. Compile in MetaEditor and resolve every compiler warning/error.
2. Run the same symbol universe, dates, timeframe, spread model, deposit, and input values used for v1.4.5.9.
3. Compare v1.4.5.9 versus v1.4.5.10:
   - net profit after commission and swap;
   - profit factor and maximum drawdown;
   - number of adaptive SL modifications per closed trade;
   - number and duration of deferred SL modifications;
   - stop-out/slippage outcomes and average winner/loser;
   - time-to-recovery after a losing trade.
4. Repeat on a separate out-of-sample date range.
5. Keep the version only if it reduces modification frequency without materially worsening net expectancy, drawdown, or winner retention.

## Validation status

- GitHub source was updated and static string/structure checks passed.
- Not compiled in MetaEditor.
- Not run in MT4 Strategy Tester or on a broker/demo account.
- No performance improvement is claimed.
