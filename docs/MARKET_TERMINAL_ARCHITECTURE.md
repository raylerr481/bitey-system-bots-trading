# Bitey SBT Market Terminal Architecture

## Objective

Bitey SBT provides a professional market-analysis workspace inspired by the interaction model of MT5 and TradingView, while keeping market data, intelligence, simulation, and execution authority explicitly separated.

## Runtime flow

```text
Broker / Market
      |
      v
MetaTrader 5 terminal / authorized bridge
      |
      +--> real-time quote
      +--> OHLC candles
      +--> optional market-book data
      |
      v
Bitey SBT market contract
      |
      +--> chart engine
      +--> indicators
      +--> strategy engine
      +--> backtest visualization
      +--> Bitey market analysis
      |
      v
Risk Gate
      |
      +--> Demo / Paper
      +--> Live execution remains BLOCKED unless explicitly authorized
```

## Current backend contract

The native market API is exposed under `/api/v1/market`.

- `GET /connections` reports the authorized connector and its capabilities.
- `GET /quote/{symbol}` returns bid/ask/last data from the MT5 bridge.
- `GET /candles/{symbol}?timeframe=H1&limit=200` returns the `sbt-candles-v1` OHLC contract.
- `WS /stream/{symbol}` provides a live quote stream.

The market API fails closed when the MT5 bridge is unavailable. It must not fabricate prices or silently replace the configured connector with a paid market-data provider.

## Terminal UI target

### Left panel: Watchlist

- Symbol search.
- Forex, metals, indices, crypto and other supported instruments.
- Bid/ask/last.
- Spread.
- Connection status.
- Selected symbol drives the central chart.

### Center: Professional chart

- Japanese candlesticks from the native OHLC contract.
- Timeframe selector: M1, M5, M15, M30, H1, H4, D1 and supported higher periods.
- Zoom and horizontal history navigation.
- Crosshair with time and price.
- Volume when the source provides it.
- EMA/SMA overlays.
- RSI, MACD, ATR and other indicator panels.
- Entry, SL and TP overlays for strategy/backtest events.
- No synthetic candles when the real feed is unavailable.

### Right panel: Bitey analysis

The analysis panel consumes the same selected symbol/timeframe and should show structured facts before natural-language interpretation.

Example:

```text
EURUSD · H1

Trend       Bullish
EMA 20      > EMA 50
RSI 14      61
ATR 14      Moderate volatility
Signal      NONE

Bitey:
The current structure is bullish, but the configured strategy
has no valid entry condition yet. No trade is proposed.
```

The wording must distinguish measured market facts, strategy state, and Bitey's interpretation.

## Backtest visualization

Backtest results should use the exact same chart coordinate model as live analysis. Each event can be rendered as:

- entry marker;
- exit marker;
- stop-loss line;
- take-profit line;
- position direction;
- realized P/L;
- strategy identifier;
- timestamp.

This allows a user to inspect *why* a simulated trade happened instead of reading a detached results table.

## Safety boundary

The chart and intelligence layer are read/analyze surfaces. They do not acquire broker credentials and do not bypass the Risk Gate.

The MT5 adapter currently reports market data and Demo capability while live order submission is disabled at the broker boundary. That invariant must remain true while the terminal UI is being expanded.

## Implementation order

1. Keep the existing native `/api/v1/market` contract stable.
2. Connect the terminal chart to `/candles/{symbol}` and `/stream/{symbol}`.
3. Add deterministic candle normalization and timestamp handling.
4. Add indicator calculations from the same candle series.
5. Add crosshair/zoom/history interaction.
6. Add strategy event overlays for backtests.
7. Feed the resulting structured snapshot to Bitey's analysis layer.
8. Keep Demo/Paper and Live execution controls behind the existing Risk Gate.
9. Add contract tests for missing bridge, malformed candles, symbol changes and timeframe changes.

## Non-goals

- No automatic live trading.
- No hidden paid market-data fallback.
- No broker credentials in browser code.
- No replacement of the existing SBT Risk Gate.
- No coupling of SBT to BiteFixes.
