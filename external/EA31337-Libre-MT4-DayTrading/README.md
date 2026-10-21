# EA31337 Libre — MT4 Day Trading Adaptation

**Status:** research scaffold / not yet adapted, compiled, or tested.

This directory is an isolated work area for evaluating an MT4 day-trading adaptation of [EA31337/EA31337-Libre](https://github.com/EA31337/EA31337-Libre). The upstream project remains the authoritative source. This is not an official EA31337 release.

## Goals

- Preserve Bitey SBT and all existing Expert Advisors unchanged.
- Keep the upstream source and strategy/framework dependencies traceable.
- Evaluate EURUSD and XAUUSD separately for intraday trading.
- Start validation with a 0.25% planned risk budget per trade (USD 1.25 on a USD 500 reference balance), no martingale, no grid-based loss recovery, and no forced minimum lot when it exceeds the budget.
- Require broker-aware lot sizing, stop-distance checks, spread/slippage controls, order-result logging, and demo validation before any live use.

## Current contents

- `AUDIT.md`: initial source/dependency review and unresolved items.
- `RISK_SPEC.md`: proposed risk and validation requirements.
- `UPSTREAM.md`: provenance and licensing notes.

No adapted trading EA source is included yet. Do not compile this folder as an EA or attach it to a trading chart.

## Next steps

1. Pin an upstream commit/tag and inspect the complete source plus submodules.
2. Verify MQL4 build compatibility in MetaEditor and resolve dependencies without replacing upstream history.
3. Implement changes in separately named files and document every change.
4. Compile in MetaEditor; record the exact build and diagnostics.
5. Run reproducible backtests with realistic commission, spread, swap, and slippage; preserve out-of-sample data.
6. Run demo forward tests and audit orders, risk estimates, and drawdown before considering any live use.

## Safety

This repository folder is research only. Backtests and demo performance do not guarantee live profitability. Trading may lose the entire deposit. The risk budget is an estimate, not a guaranteed maximum loss under gaps or execution failures.
