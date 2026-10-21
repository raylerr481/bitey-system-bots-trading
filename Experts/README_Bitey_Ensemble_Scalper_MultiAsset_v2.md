# Bitey Ensemble Scalper Multi-Asset v2

## Purpose
A conservative MT4 Expert Advisor prototype that scans selected Market Watch symbols (or an explicit CSV list), scores 32 indicator-rule variants, and records auditable risk-gate decisions.

**This is not a proven profitable strategy.** The 32 votes are correlated indicator-rule variants, not 32 independent statistical models. No profitability claim is made; compile, backtest, out-of-sample and demo validation are required.

## Safety defaults
- Trading disabled by default (`InpEnableTrading=false`). Keep disabled until compile and testing are complete.
- Reference capital: USD 500.
- Target candidate risk: 1% (USD 5) before broker costs/slippage.
- Maximum candidate risk: USD 5 by default.
- Aggregate planned risk limit: 2% (USD 10).
- Maximum 3 open positions for this EA's magic number.
- One open position per symbol for this EA's magic number.
- No martingale or lot-size escalation.
- Refuses to calculate USD-based risk when the account currency is not USD, because FX conversion has not been implemented and validated.
- If broker minimum lot would exceed the per-trade risk target, the candidate is rejected rather than rounding lot size upward.

## Audit logs
- `ENSEMBLE_AUDIT`: BUY/SELL votes, active votes, directional percentage, margin and spread.
- `RISK_GATE_AUDIT`: candidate risk, open planned risk, aggregate-after-candidate, aggregate limit, reference capital and account currency.
- `SYMBOL_REJECT`: explicit rejection reason and, for risk-cap rejections, the values used in the decision.
- `ORDER_ACCEPTED` / `ORDER_REJECTED`: broker execution result.

Open-risk accounting only includes market orders matching this EA's `InpMagic`. It does not automatically include manual trades or other EAs; therefore the aggregate limit is not a cap on total account exposure. An order can lose more than its planned stop risk because of gaps, slippage, execution failures or market conditions.

## Important limitations
- The EA processes symbols as their new bars are detected; it does **not yet rank all candidates globally** before choosing entries. Consequently, Market Watch order can affect which candidates get evaluated first when open-position/risk caps are reached.
- The spread limit is a generic points threshold, not a calibrated instrument-specific cost model.
- Tick-value assumptions, commissions, swaps, slippage, stop-level constraints and instrument contract details must be checked with the broker.
- No robust news filter, independent walk-forward evaluation, persistent daily asset ranking, or proven expectancy gate is implemented.
- A strong vote consensus is not proof of positive net expectancy.

## Installation / validation
1. Copy `Bitey_Ensemble_Scalper_MultiAsset_v2.mq4` to MT4 `MQL4/Experts`.
2. Compile in MetaEditor and resolve every compiler warning/error.
3. Run Strategy Tester with realistic spread, commission and slippage assumptions.
4. Keep chronological out-of-sample data untouched until parameters are fixed.
5. Run demo forward testing and inspect every risk/entry/exit log.
6. Only consider enabling live trading after independent validation and explicit user review.

Never infer profitability from the number of signals or vote agreement alone.
