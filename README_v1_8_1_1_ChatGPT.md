# Bitey Ensemble Scalper MultiAsset v1.8.1.1-EXP — ChatGPT Indicator

**Experimental. Not compiled in MetaEditor or validated in MT4 Strategy Tester. Test locally before any use with real money.**

Based on v1.8.0.9 ProfitSelector. Reviews the bridge parser and adds stricter numeric-response validation to the optional external ChatGPT advisory bridge that contributes a bounded ranking bonus to a candidate that already passed the EA's normal signal and prefilters. This is **not** a built-in ChatGPT model and does not call OpenAI directly.

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
