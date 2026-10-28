# Bitey SBT profitability audit — 2026-10-28

## Scope and evidence

Repository: `raylerr481/bitey-system-bots-trading`

Audit branch: `audit/profitability-2026-10-28`, based on `feature/crypto-classification-v1-8-0-7`.

Files reviewed:
- `Bitey_Ens_NetByAsset_21102027.csv`
- `Bitey_Ens_MFE_MAE_21102027.csv`
- `Bitey_Ens_TradeAudit_21102027.csv`
- `Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_7_CryptoClassificationExperimental.mq4`
- `20261027.log`

This is a source/data audit, **not** a verified profitable strategy. No MetaEditor compilation or Strategy Tester run was performed by this audit.

## Current realized results (NetByAsset CSV)

Updated server time: 2026-10-28 12:03:30. Magic: 21102027. MT4 history orders visible: 408. Matched closed trades: 83. Skipped symbols due to the CSV symbol limit: 0.

| Metric | Result |
|---|---:|
| Closed trades | 83 |
| Net wins / net losses | 33 / 50 |
| Win rate | 39.76% |
| Gross P/L | -$23.68 |
| Commission | -$17.25 |
| Swap | $0.00 |
| Net P/L | -$40.93 |
| Commission magnitude / net loss magnitude | 42.1% |

The negative gross P/L means transaction costs are not the only problem. Lowering commissions alone would not turn this sample profitable.

## Per-symbol observations (small samples; not proof of edge)

Most negative net results:
- HYPEUSDT: 5 trades, 0 wins, -$10.11 net
- USDJPY: 7 trades, 1 win, -$9.34 net
- GBPJPY: 6 trades, 1 win, -$8.09 net
- EURJPY: 4 trades, 0 wins, -$7.16 net
- AMDUSDT: 3 trades, 0 wins, -$6.64 net
- CHFJPY: 2 trades, 0 wins, -$4.36 net

Positive results, but too few trades to call them persistent:
- GBPAUD: 4 trades, +$10.55 net
- VVVUSDT: 1 trade, +$6.31 net
- EURUSD: 4 trades, +$3.68 net
- TSLAUSDT: 3 trades, +$3.36 net
- AUDJPY: 5 trades, +$2.69 net

Do not permanently disable/enable symbols from these samples alone. Use them to prioritize further out-of-sample testing.

## MFE/MAE and version audit

The MFE/MAE CSV contains 222 rows spanning multiple versions and includes a previously identified duplicate for ticket 95769012. Deduplicate by ticket plus symbol and open time before training or computing aggregate results.

For `BE1.7.2`: 196 rows, 97 net wins and 99 net losses, gross +$3.31, commissions -$38.25, net -$34.94. Costs erased the gross gain. The summed MFE_R/MAE_R columns are not expectancy; calculate averages/distributions after deduplication.

The TradeAudit sample for `BE1.8.0.7` has 5 trades and net -$5.13:
- TAOUSDT BUY: +$0.41 net, MFE 0.88R, MAE 0.89R
- AMDUSDT BUY: -$1.96 net, MFE 0.25R, MAE 0.99R
- HYPEUSDT BUY: -$2.15 net, MFE 0.35R, MAE 0.89R
- TAOUSDT BUY: +$0.58 net, MFE 1.01R, MAE 0.22R
- USDJPY BUY: -$2.01 net, MFE 0.06R, MAE 0.90R

Three losers had low favorable excursion and roughly 0.9–1.0R adverse excursion. This is consistent with weak continuation entries in this tiny sample, but does not prove the cause. Avoid tuning the whole strategy from five trades.

## Code review findings

1. `main` contains `Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_7_CryptoPriorityExperimental.mq4`, where the USDT classification path can classify any symbol containing `USDT` as crypto when `InpUSDTIs24x7` is enabled. The strict-classification branch contains an explicit crypto-base allowlist, which is safer for symbols such as `TSLAUSDT` and `AMDUSDT`. Keep testing this branch; do not silently overwrite `main`.
2. The current strict-classification EA already includes a cost-to-stop guard (`InpMaxCostR`), spread-versus-stop rejection, adaptive exits, a net-profit lock, cooldowns, a consecutive-loss pause, and a per-symbol expectancy guard. The expectancy guard requires at least 12 trades by default, so the 2–7 trade symbol samples here will not activate it. Do not lower that minimum simply to force a reaction to small samples.
3. Risk settings observed in the code are reference capital $500, 0.5% risk per trade, 2.5% aggregate risk, and a 3% daily loss block for new entries. Do not increase these limits to recover losses.
4. `accountMode=NOT_A_GATE` means the EA should not reject a demo account merely because it is demo; it does not override MT4 AutoTrading, broker symbol permissions, market hours, margin rules, or server rejections.
5. The `20261027.log` includes repeated daily-loss blocks at dayNet -$16.79 and monthNet -$35.80, and spread/stop rejects. Preserve these guards; do not loosen them to increase trade count.

## Next engineering steps (in order)

1. Freeze this data snapshot and deduplicate closed trades by ticket/symbol/open time. Reconcile the 83-trade summary against MT4 Account History set to All History.
2. Produce per-version, per-symbol, and time-ordered performance summaries using **net** P/L, profit factor, expectancy, maximum drawdown, and cost as a fraction of initial risk. Keep historical versions separate.
3. Test the strict crypto-classification EA against the previous build on the same symbol universe, dates, spread/commission assumptions, and data quality. Use chronological train/validation/holdout windows; never optimize on the holdout.
4. Test entry quality before changing exit logic: require stronger agreement across independent model families and compare the result with the current assembly. Use a small number of predeclared parameter variants to limit overfitting.
5. Keep the cost-to-stop, spread, broker stop-level, aggregate risk, daily-loss, and terminal/broker permission guards intact.
6. Run MT4 Strategy Tester with realistic variable spread and commission; then demo forward-test. Only promote a candidate if it improves net expectancy and drawdown on unseen data, with enough trades to make the estimate meaningful.

## Promotion criteria (predeclared)

A candidate is not labelled profitable unless:
- MetaEditor compiles it without errors;
- the backtest and holdout use the same documented cost assumptions;
- holdout net expectancy is positive after commission, spread, swap and slippage;
- results are not dependent on one symbol or a handful of trades;
- drawdown remains within the declared risk limits;
- demo forward results do not materially contradict the holdout.

**Current conclusion:** the audited sample is losing. The strict-classification branch is the safer base for the next experiment, but there is not enough evidence to claim or guarantee profitability. No entry/risk parameters were changed in this audit because doing so without controlled testing would risk overfitting.
