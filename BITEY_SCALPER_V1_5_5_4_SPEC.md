# Bitey Scalper v1.5.5.4 — Broker session permission correction

Created from the isolated v1.5.5.3 branch. This patch corrects false negatives caused by the optional fixed server-hour window.

## Change
- `InpUseSessionFilter=false` by default. The fixed 07:00–21:00 window no longer blocks explicitly classified session-bound instruments merely because the server clock is outside that manually configured window.
- When the operator explicitly enables `InpUseSessionFilter`, the configured server-hour window remains available as an additional conservative filter.
- This does **not** assume that `MODE_TRADEALLOWED` guarantees the exchange/contract is currently open. The EA still checks current broker symbol permission, terminal/expert permission, quote freshness, valid Bid/Ask, market metadata, synchronized M15/HTF series, spread, and all existing risk gates before a new order. The broker remains authoritative at order submission and may reject a closed-market order.
- Exact-symbol metadata remains mandatory. Unknown or conflicting market classes still block new entries. No USDT suffix/prefix inference is introduced.
- The series synchronization guard remains enabled and fail-closed. Unknown/false synchronization blocks new entries only; it does not by itself close or modify an open position. Broker-resident SL/TP remain active.
- The fixed session-hour filter is not a replacement for broker contract schedules. MQL4 does not expose a reliable universal weekly session schedule.

## Preserved
Balanced live analysis and active management; adaptive SL/TP; no SL widening; break-even; trailing; adaptive TP extension; 50% net-profit giveback protection; rolling loss management; exposure and currency-risk limits; quote stale recovery; daily loss warning-only behavior; maximum five open positions.

## Operator configuration
The three exact-symbol lists remain empty by default:
- `InpCryptoSymbolsCSV`
- `InpAlwaysOpenSymbolsCSV`
- `InpSessionBoundSymbolsCSV`

Populate them only from TradeWill's actual contract specifications. Until configured, unknown symbols remain blocked from new entries. Do not classify a symbol solely by its ticker suffix.

## Validation status
Source updated on a separate branch. It has **not** been compiled in MetaEditor, run in MT4 Strategy Tester, or forward-tested. This patch is not proof of profitability or win-rate improvement. Compile and test on demo before enabling live trading.
