# Bitey Quant FreqAI v1 — Research Specification

Status: RESEARCH ONLY. LIVE and REAL_MONEY remain OFF.

Market/timeframe: BTC/USDT spot, 1h. The hypothesis targets directional continuation in identifiable trend regimes. Risks include regime shifts, volatility clustering, exchange costs, weekend effects, non-stationarity and transferability limits.

Hypothesis: when multi-horizon trend is positive, realized volatility is not extreme, momentum is positive but not overextended, and FreqAI predicts a sufficiently positive 12-candle return with acceptable uncertainty, conditional forward return should exceed a matched baseline after costs. It is falsified if out-of-sample expectancy does not exceed the baseline or disappears under reasonable perturbations.

Features: EMA distances/slopes, ADX, trend score, 1/3/12-candle returns, acceleration, RSI, ROC, ATR%, realized volatility, volatility regime ratio, range expansion, volume ratio and optional relative spread. All are causal.

Targets: 12 candles. future_return = close[t+12]/close[t]-1. future_max_profit = max(high[t+1:t+12])/close[t]-1. future_max_loss = min(low[t+1:t+12])/close[t]-1. trade_outcome = future_return - 0.0015 cost allowance. Targets are labels only.

Entry: FreqAI do_predict=1, predicted future return >0.25%, prediction uncertainty <=1%, trend score >=0.20, RSI 48–72, volume ratio >=0.70, volatility regime <=2.50 and nonzero volume. Prediction alone is insufficient.

Exit: stoploss -2.5%; ROI 3.0%, 1.8%, 0.8%, then unrestricted after 6h; model/regime exit on negative prediction or broken trend; maximum hold 24 candles.

Risk: spot only, no leverage; CooldownPeriod, StoplossGuard and MaxDrawdown. SBT Risk Gate remains authoritative for daily loss, exposure and demo permission.

FreqAI: LightGBMRegressor; 30-day training window; 7-day backtest retrain period; label horizon 12; shifted candles 2; periods 10/20/50; internal split 25%, seed 42. Temporal out-of-sample is mandatory.

Gates: clean data; >=30 closed trades; >=100 test samples; >=70% prediction coverage; drawdown <=20%; lookahead_bias_count=0; unseen OOS test; robustness to costs/parameters/regimes; dry-run true.

MT4 remains untouched. Current MT4 baseline is EURUSD while first FreqAI research is BTC/USDT, so cross-market P&L is descriptive rather than a direct superiority test. Compare signals, operations, coverage, coincident/exclusive signals, expectancy, drawdown, PF and regime behavior.

Evidence Bundle: dataset manifest, strategy version/hash, model identifier, backtest export, prediction export, lookahead export, OOS split/timerange, metrics JSON, robustness matrix, MT4 comparison JSON/CSV and validation passport JSON.

Final states: RESEARCH_REWORK if any mandatory gate fails; DEMO_ELIGIBLE only if all mandatory gates pass. LIVE=OFF and REAL_MONEY=OFF in both states.
