# Bitey v1.4.5.2 startup reference — 2026-11-01

Preserved from the MT4 Experts log supplied by the user.

## Observed startup

- EA: `Bitey_Scalper_MultiAsset_v1_4_5_2_MarketDataScannerDiagnostics`.
- MT4 reported `loaded successfully` at `2026.11.01 20:19:56.831`.
- The excerpt around 20:19:57 shows `INITIAL_BASELINE` for multiple symbols, with 4,997–5,362 bars against `minBars=250`.
- ETCUSD, BTCUSDT.m, AVAXUSDT, DOTUSDT, ETHUSDT.m, FILUSDT, SOLUSDT.p, ARUSD, NEARUSD, IOTAUSD and DASHUSD show `selected=true` and `tradeAllowed=true`.
- Quote ages shown range from 0 to 209 seconds. IOTAUSD at 209 seconds exceeds the configured 120-second freshness limit and should not qualify as a fresh entry quote.

## Interpretation

`loaded successfully` confirms EA loading, not signal generation or order acceptance. `INITIAL_BASELINE` / `EXISTING_BAR_NOT_COUNTED_AS_NEW` is expected: the already-open M5 candle is captured as a baseline and is not falsely counted as a new signal bar. Symbol permission flags are preliminary observations, not proof that an order will execute. Similar symbols and matching bar timestamps are possible aliases only; do not merge or remove contracts using the AssetKey heuristic alone.

## Next summary to inspect

The next heartbeat window should be checked for `newBarsScanned`, `indicatorsEvaluated`, `candidates`, `prefilterRejected`, `signalRejected`, `historyUnavailable`, `insufficientHistory`, quote freshness, and daily-loss guard state.

This is observational evidence from the supplied excerpt, not a claim of profitability or live order execution.
