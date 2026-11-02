# Bitey Scalper MultiAsset v1.4.5.7 — Crypto Session Classification

## Scope
This branch corrects the hard-coded crypto-prefix classifier used by `SessionOK()`. The session filter remains enabled and retains its existing server-hour window (07:00 inclusive to 21:00 exclusive) for instruments not recognized as crypto.

## Added crypto prefixes
The existing 24 prefixes are preserved. The following prefixes were added based on instruments present in the supplied MT4 logs:

- `ICP` — Internet Computer
- `IOT` — IOTA
- `AST` — ASTER
- `TRU` — TRUMP
- `DASH` — Dash
- `GRT` — The Graph
- `ARU` — Arweave symbols beginning with ARU (for example ARUSD / ARUSDT)

The classifier uses `AssetKey()`, which retains at most six leading alphanumeric characters. Prefixes are therefore deliberately short enough to match broker symbol variants such as USD/USDT and suffixes.

## Preserved behavior
- No change to BUY/SELL permissions.
- No change to strategy signals, spread filters, SL/TP, sizing, position limits, daily loss limits, or aggregate risk.
- No global disabling of the session filter.
- No blanket exemption based solely on a `USDT` suffix.
- Tokenized equities, commodities, and other broker-specific products remain subject to the existing session window unless explicitly classified; broker trading schedules have not been queried by this EA.

## Validation required
1. Compile in MetaEditor and confirm zero errors/warnings.
2. At server hour 21, verify `ICPUSDT`, `ICPUSD`, `IOTAUSDT`, `IOTAUSD`, `ASTERUSDT`, and `TRUMPUSDT` no longer receive `OUTSIDE_SESSION` solely because of the crypto-prefix classifier.
3. Verify `IBMUSDT`, `WMTUSDT`, `NATGASUSDT`, `NFLXUSDT`, and other non-classified instruments remain governed by the configured session window.
4. Confirm spread, permissions, broker trading hours, and all existing risk controls still reject unsafe orders.
5. Confirm actual order execution only from broker-confirmed order tickets/logs; this code change does not prove order acceptance.

## Status
Static source review only. MetaEditor compilation, Strategy Tester results, and live/demo execution have not been performed or verified.
