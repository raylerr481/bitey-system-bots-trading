# ABC EMA50 Scalping V1

## Source

This strategy is a deterministic conversion of the user-provided trading-video transcript. It preserves the transcript's core idea without copying proprietary code, branding or UI.

## Status

- Strategy version: `ABC-EMA50-SCALPING-v1`
- Mode: research / backtest / paper / MT5 Demo
- Real-money execution: disabled
- Primary instrument for first validation: EURUSD
- Timeframes: H1 → M5 → M1
- Indicator: EMA 50 only

## Trading logic

### A. H1 directional bias

A bias is created only when:

1. A support or resistance zone has at least two deterministic pivot touches.
2. Price is currently near that zone.
3. The latest three H1 candles satisfy the configured deceleration test: shrinking range relative to the preceding candle, body/range below the configured threshold, and meaningful wick presence.

Resistance + deceleration = short bias.

Support + deceleration = long bias.

No bias means no trade.

### B. M5 strategy confirmation

The M5 chart must show a deterministic structure change:

- short: latest confirmed swing high is lower than the previous swing high AND latest confirmed swing low is lower than the previous swing low;
- long: latest confirmed swing high is higher AND latest confirmed swing low is higher.

After the structure change, price must touch the M5 EMA50 within the configured tolerance. The candle must remain on the intended side of EMA50.

### C. M1 execution

The M1 chart is execution only.

- short: the last completed candle crosses from at/above EMA50 to below EMA50;
- long: the last completed candle crosses from at/below EMA50 to above EMA50.

The signal is generated only after A + B + C align.

## Risk model for first tests

The strategy module produces an initial stop reference but does not place orders. The SBT Risk Gate must decide whether a trade is permitted.

Recommended initial research defaults:

- risk per trade: 0.25% of simulated/demo equity;
- maximum simultaneous positions: 1;
- daily loss limit: 1%;
- no martingale;
- no averaging down;
- spread/slippage checks required;
- reject a trade if calculated position size is below the broker minimum or if the required margin is unavailable.

These values are research controls, not claims of optimal profitability.

## Exit / management

The transcript describes two exit concepts:

1. previous swing low/high as an initial reference target;
2. trailing the position with M1 EMA50 and exiting after a confirmed close through EMA50 against the position.

V1 uses the M1 EMA50 confirmation as the deterministic management rule. The reference target remains informational for evaluation.

## Limit-entry variant

The transcript also describes a discretionary sell-limit entry when several zones converge. This is **not part of V1** because "convergence" is subjective. It should be tested later as a separate V2 rule with an explicit scoring definition.

## No-lookahead rule

Only completed candles and confirmed pivots may be used. The strategy must never use future bars to decide a historical signal.

## Evaluation

Backtests and demo runs must report at minimum:

- trade count;
- win rate;
- gross/net P&L;
- profit factor;
- expectancy;
- maximum drawdown;
- average win/loss;
- consecutive losses;
- exposure time;
- spread/slippage assumptions;
- out-of-sample results.

A profitable single trade, including the approximately US$1,945 trade described in the transcript, is not evidence that the strategy is profitable in general.
