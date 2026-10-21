# Validation plan — Turtle Donchian ATR

## Hypothesis
A Donchian breakout with an ATR-scaled initial stop and channel-based exit may capture persistent trends while keeping entry rules transparent. Profitability is not assumed and must be tested per instrument.

## Required experiment
- Instruments: test EURUSD and XAUUSD separately first; add other instruments only after validating broker contract metadata.
- Signal timeframe: H1 initially; M15 is a separate experiment, not pooled with H1.
- Candidate parameters: entry/exit 20/10 and 55/20; ATR(20), initial stop 2N.
- Use chronological train/optimization period, a later untouched holdout, and then forward demo.
- Include variable spread, commission, swap, slippage, and realistic execution assumptions.
- Do not optimize the holdout. Report each parameter set, not just the winner.

## Metrics
Net profit after all costs; profit factor; maximum balance and equity drawdown; number of trades; expectancy per trade; average win/loss; win rate; exposure; largest loss; consecutive losses; and the share of orders whose realized risk differed from the estimate.

## Acceptance gates
- MetaEditor compilation: 0 errors, warnings reviewed.
- Out-of-sample net expectancy positive after costs, with enough trades to make the estimate meaningful.
- Profit factor above 1 after costs and drawdown within a predeclared acceptable range.
- No risk-sizing mismatch, duplicate entries, unprotected position, or unexplained broker rejection.
- Demo-forward behavior consistent with backtest assumptions.
- If any gate fails or evidence is insufficient, keep trading disabled and do not loosen risk/evidence gates merely to increase trade frequency.

No parameter set can be called the “best proven strategy” until comparative, reproducible results support that conclusion.
