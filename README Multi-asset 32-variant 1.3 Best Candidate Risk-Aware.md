# Multi-asset 32-variant 1.3 — Best Candidate Risk-Aware

## Changes
- Qualifies symbols whose signal-timeframe bar has advanced, ranks qualifying candidates, then selects only the highest-ranked candidate for that scan cycle.
- Ranking weights directional agreement (40%), active-vote coverage (30%), vote margin (15%), spread quality (10%) and risk-budget utilization (5%). This is a heuristic, not a measured win probability.
- Adds a per-trade hard cap of min(USD 5, reference capital × configured risk percentage) and a spread-to-ATR filter.
- Converts MODE_TICKSIZE from points into price units using MODE_POINT in risk calculations.
- Adds candidate and risk audit logs.
- Automatic trading is enabled in this branch (`InpEnableTrading=true`). Do not attach it to a live account until MetaEditor compilation, broker contract validation, backtesting and demo forward testing are complete.
- Keeps existing break-even and ATR trailing stop logic.

## Important limitations
- MODE_TICKVALUE is in the account deposit currency. If the account is not USD, explicit currency conversion is required before treating estimates as USD.
- Validate tick values and contract sizes for each broker symbol, especially crypto, synthetic and share CFDs.
- No profitability claim is made. This source has not been compiled in MetaEditor or backtested here.
