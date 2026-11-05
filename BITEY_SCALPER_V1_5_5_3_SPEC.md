# Bitey Scalper v1.5.5.3

Created from v1.5.5.2 on an isolated branch. The EA adds exact-symbol metadata lists for crypto, non-crypto 24x7 instruments, and session-bound instruments. All lists default to empty; unknown or conflicting symbols cannot open new trades. No ticker-prefix or suffix inference is used.

New entries also require confirmed symbol selection, broker trade permission, a fresh quote, valid Bid/Ask, confirmed M15 and configured higher-timeframe series, configured session permission where applicable, and spread quality within the existing hard limits. MQL4 does not provide a dependable per-contract weekly schedule; the configured server-hour window is only a conservative filter.

Existing strategy, balanced management, adaptive SL/TP, break-even, trailing, TP expansion, 50% net giveback, rolling loss management, exposure limits, and five-position cap are preserved. Existing open positions are not closed merely because metadata is unknown or quotes are stale.

Operator action: populate all three CSV inputs from verified TradeWill contract specifications. Crypto symbols must be included in InpCryptoSymbolsCSV; non-crypto 24x7 symbols in InpAlwaysOpenSymbolsCSV; session-bound symbols in InpSessionBoundSymbolsCSV. Do not guess.

Validation: NOT PASSED. This source has not been compiled in MetaEditor, tested in Strategy Tester, or forward-tested. All lists are empty by default, so new entries remain blocked until configured. Compare with v1.5.5.2 and demo-forward-test before live use; require at least 100 closed trades before drawing performance conclusions.
