# Bitey Ensemble Scalper MultiAsset v1.8.1.4 — Adaptive Selection, No Daily/Monthly Loss Brake

**Experimental. Not compiled in MetaEditor or validated in MT4 Strategy Tester.** This is a test build, not a claim of profitability.

## Intended behavior

- Removes the daily loss entry brake and monthly profit/loss entry cutoffs so historical tests can observe the strategy across losing periods without those time-based brakes censoring entries.
- Retains the per-trade initial Stop Loss, risk-based position sizing, aggregate open-risk limit, maximum open positions, broker/terminal permissions, spread/cost filters, session controls, and other execution protections.
- Retains adaptive stop/profit-lock logic and adaptive take-profit expansion. After favorable price movement, the stop may ratchet toward break-even and then toward estimated net profit after costs. It must not be widened to increase the loss on an already-open position.
- Retains candidate ranking, estimated cost-R penalty, and optional realized per-symbol net-edge selector. The goal is to choose stronger net opportunities after costs; this is a hypothesis to validate, not a guarantee.
- Retains `InpMaxTradesPerDay=12` and other entry-selection limits. This is a trade-count cap, not a daily loss brake.

## Important risk clarification

A Stop Loss limits the planned loss under normal execution but cannot guarantee an exact loss in gaps, slippage, rejected modifications, or market closure. Moving a stop to break-even requires favorable movement and successful broker modification; it cannot turn an already-realized loss into zero. The EA does not promise that losses will always return to zero.

The initial risk budget is based on `InpReferenceCapitalUSD=500`, `InpRiskPctPerTrade=0.5` and `InpMaxAggregateRiskPct=2.5` by default. These are sizing targets; actual execution may differ. There is no daily/monthly loss brake in this build, so a prolonged sequence of losing trades can continue to generate entries within the remaining controls.

## Evaluation

Use MT4 Strategy Tester for the chart symbol and a separate portfolio/multi-symbol test harness or demo forward test for cross-asset selection. A standard single-symbol MT4 test does not prove simultaneous ranking across all broker symbols works.

Evaluate net profit after commission, swap, spread and realistic slippage; profit factor; expectancy; maximum drawdown; average win/loss; trade count; per-symbol net results; and selected-vs-rejected candidates from CSV audit files. Use chronological train/validation/holdout periods, and do not tune and report on the same period.

## Optional ChatGPT ranking bridge

`InpUseChatGPTIndicator=false` by default. It is a generic external numeric advisory bridge, not a built-in ChatGPT model or direct OpenAI integration. It can only add a bounded ranking bonus to a candidate that already passed normal EA checks. Keep API keys out of source and logs.

## Validation status

The source has not been compiled in MetaEditor or run in Strategy Tester by this change. Do not deploy to a real account until compilation and historical validation are complete.
