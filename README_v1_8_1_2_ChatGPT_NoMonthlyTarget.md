# Bitey Ensemble Scalper MultiAsset v1.8.1.2-EXP — ChatGPT Indicator (No Monthly Profit Target)

**Experimental. Not compiled in MetaEditor or validated in MT4 Strategy Tester. Test locally before any use with real money.**

Based on v1.8.1.1 ChatGPT advisory version. Reviews the bridge parser and adds stricter numeric-response validation to the optional external ChatGPT advisory bridge that contributes a bounded ranking bonus to a candidate that already passed the EA's normal signal and prefilters. This is **not** a built-in ChatGPT model and does not call OpenAI directly.

## Monthly trading behavior

- The monthly **profit target cutoff has been removed**. The EA will not stop opening new trades just because a monthly profit target was reached.
- The monthly drawdown brake remains: `InpMonthDDPct=8.0` by default, blocking new entries when monthly net P&L reaches -8% of risk capital. Setting it to `0` disables this loss brake and is not recommended without further testing.
- The daily loss brake (`InpDailyLossPct=3.0`), daily trade cap (`InpMaxTradesPerDay=12`), per-trade/aggregate risk limits, max open positions, broker/terminal permissions, and other guards remain.

## New inputs

- `InpUseChatGPTIndicator=false` (disabled by default)
- `InpChatGPTIndicatorURL=""` (URL of a bridge you operate)
- `InpChatGPTBonusMax=5.0` (clamp response to +/- 5 ranking points)
- `InpChatGPTTimeoutMs=700`
- `InpChatGPTLog=true`

The response affects **ranking only**. It cannot approve a trade, change its direction, change position size, or bypass existing signal, cost, correlation, spread, session, drawdown, broker, terminal, or risk guards. Missing endpoint, HTTP failure or invalid response returns zero bonus.

## Bridge contract

For an eligible candidate the EA sends a GET request with `symbol`, `direction` (`BUY` or `SELL`), `timeframe`, and `score` query parameters. The endpoint must return only a plain numeric response such as `2.0`, `-1.5`, or `0`. No prose or JSON. Values are clamped to +/- the absolute value of `InpChatGPTBonusMax`. The parser accepts only a plain signed decimal and rejects prose, JSON, exponent notation, and trailing junk.

This is a generic bridge interface, **not a ready-made OpenAI integration**. Do not embed API keys in source code, URLs, or logs. A secured server-side bridge is needed to connect a model service. Add the bridge host to MT4 under **Tools → Options → Expert Advisors → Allow WebRequest for listed URL**.

## Limitations and test plan

- External requests can fail or delay candidate processing.
- The ranking bonus is experimental and does not establish predictive value or profitability.
- Existing ProfitSelector history normalization, partial-close handling, and spread/commission assumptions have not been fixed by this version.
- Multi-asset portfolio selection is not validated by a single-symbol Strategy Tester run.
- Compile in MetaEditor first. Test the feature OFF as baseline, then ON with known positive/negative/zero responses and simulate malformed responses, timeout, and HTTP errors. Compare net profit after costs, profit factor, drawdown, trade count, and out-of-sample results over identical conditions.
- Do not use real funds until compile and tester validation is complete.


## Change in v1.8.1.2

Removed `InpMonthTargetPct` and the `MONTH_TARGET_REACHED` entry-block reason entirely, so no monthly profit target can stop new entries. This does **not** disable the monthly drawdown brake or daily risk controls. The source has not been compiled in MetaEditor or validated in Strategy Tester; profitability is unproven.
