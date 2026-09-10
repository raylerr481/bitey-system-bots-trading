# Bitey SBT Market SDK

Provider-neutral market-data boundary for Bitey System Bots Trading.

## Goals

- Own the canonical quote/candle contract inside SBT.
- Keep provider-specific protocols behind adapters.
- Never fabricate market data.
- Keep provider credentials outside browser clients.
- Allow provider replacement without rewriting the SBT chart.
- Keep public-data activation behind an explicit licensing gate.

## Current adapter

`BiQuoteProvider` is implemented as a dormant adapter. It is **not activated**
for public SBT traffic until its data-display/redistribution rights are
explicitly confirmed.

The registry requires `SBT_BIQUOTE_PUBLIC_APPROVED=true` before selecting
BiQuote. This prevents an accidental production activation based only on an
API being free or technically accessible.

## Provider contract

Every provider supplies:

- `quote(symbol)`
- `candles(symbol, timeframe, limit)`
- `stream(symbol)`

SBT clients receive only the SBT-owned `sbt-quote-v1` and `sbt-candles-v1`
contracts, never provider-specific payloads.

## Future providers

A new provider only needs an adapter implementing `MarketDataProvider` and a
review of its current market-data license. The provider must explicitly permit
the intended public display before it is enabled.
