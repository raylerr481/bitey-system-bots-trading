# Bitey Ensemble Scalper MultiAsset v1.8.1.3-EXP — ChatGPT Indicator (No Monthly Stop)

**Experimental. Not compiled in MetaEditor or validated in MT4 Strategy Tester. Test locally before any use with real money.**

Based on v1.8.1.1 ChatGPT advisory version. Reviews the bridge parser and adds stricter numeric-response validation to the optional external ChatGPT advisory bridge that contributes a bounded ranking bonus to a candidate that already passed the EA's normal signal and prefilters. This is **not** a built-in ChatGPT model and does not call OpenAI directly.

## Monthly trading behavior

- Both monthly cutoffs are removed: the EA will not stop new entries because of a monthly profit target or the former monthly drawdown brake.
- There is no monthly profit-target or monthly-loss entry block in this version.
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

Removed the monthly profit target and monthly drawdown stop inputs and code paths, including `MONTH_TARGET_REACHED`, `MONTH_DD_BLOCK`, and `MONTH_DD_FLAT`. The daily loss brake and per-trade/aggregate risk controls remain active. The source has not been compiled in MetaEditor or validated in Strategy Tester; profitability is unproven.


## v1.8.1.3 — Monthly stop removal

This version removes both monthly entry cutoffs: no monthly profit target and no monthly drawdown brake. Monthly P&L remains observable in logs, but it does not stop new entries. The daily loss brake remains at 3% by default, along with the daily entry cap, per-trade and aggregate risk controls, maximum open positions, and broker/terminal checks. This is an experimental diagnostic build, not an assertion of profitability. It has not been compiled in MetaEditor or validated in Strategy Tester.
