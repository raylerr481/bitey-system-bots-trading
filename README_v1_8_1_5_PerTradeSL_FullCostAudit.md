# Bitey Ensemble Scalper MultiAsset v1.8.1.5 — Per-Trade SL and Full Cost Audit

**Experimental. Not compiled in MetaEditor or validated in MT4 Strategy Tester.**

## Loss-control policy

- No daily or monthly loss cutoff.
- No consecutive-loss pause and no account-equity floor that closes all positions.
- No aggregate portfolio-risk cap. Each trade's lot size is calculated from its own initial Stop Loss and `InpRiskPctPerTrade` against the configured reference capital (default USD 500).
- Adaptive SL / net-profit lock and adaptive TP expansion remain enabled by default. Stops may tighten to reduce risk or lock profit; they must not be widened to increase the planned loss.
- Broker/terminal permissions, valid stop distances, per-symbol position rules, cost/spread filters, max positions, lot caps, and the daily trade-count cap remain. The daily trade-count cap is not a daily loss limit.
- The configured risk amount is a target under normal execution, not a guaranteed maximum: gaps, slippage, rejected stop modifications, and market closure can produce worse fills.

## Cost accounting

Two fresh versioned CSV files are written under the terminal's `MQL4\Files` directory:

- `Bitey_TradeAudit_v1_8_1_5.csv`
- `Bitey_ClosedTrades_v1_8_1_5.csv`

They record gross result, actual commission, actual swap, net after commission and swap, entry slippage when measurable, and the estimated entry spread cost and configured commission estimate. Per-symbol and total performance summaries continue to report gross, commission, swap and net.

**Accounting rule:** MT4's gross trade P/L is calculated from bid/ask execution prices, so spread is already reflected in gross P/L. The spread estimate is recorded for attribution and must not be deducted from gross P/L a second time. Net realized result is `gross profit + actual commission + actual swap`. Other fees are only included if the broker posts them in MT4 history (typically as commission or balance/fee entries); this EA cannot infer unposted taxes or external charges.

The estimated entry spread/commission are estimates, not a replacement for actual history. Commission and swap in the closed-trade record use the broker's recorded values.

## Asset selection and tester

The existing candidate ranking and per-symbol net-edge selector remain to help compare opportunities after estimated costs. This does not guarantee accurate predictions. The standard MT4 Strategy Tester normally models the chart symbol only; multi-asset portfolio selection needs a separate multi-symbol harness or forward demo validation.

Compare net results after costs, profit factor, expectancy, maximum drawdown, average win/loss, and per-symbol selected/rejected candidate logs. Keep chronological out-of-sample periods separate from strategy tuning.

## Validation

The source is saved in GitHub but has **not** been compiled or tested in MetaEditor/Strategy Tester by this change. Validate the code and confirm the CSV columns in a fresh tester run before considering any live use.
