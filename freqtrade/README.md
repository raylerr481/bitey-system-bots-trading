# Bitey SBT — Freqtrade Adapter

This directory integrates Freqtrade as an isolated crypto-trading execution and research engine for Bitey SBT.

## Boundary

- MT4 remains independent under `mt4/`.
- Freqtrade is crypto-oriented and lives only under `freqtrade/`.
- Bitey SBT remains the orchestration, research, validation and Risk Gate layer.
- This integration starts in backtest and dry-run only.
- No exchange credentials are committed to the repository.
- Live trading is intentionally not configured.

## Architecture

```
Bitey IA
   |
Bitey SBT Risk Gate / Strategy Registry
   |
Freqtrade Adapter
   |
Freqtrade
   |
Exchange public data / dry-run
```

Freqtrade provides the deterministic strategy/execution engine. Bitey SBT remains responsible for permissions, validation state, auditability and the transition between research, simulation, demo/paper and any future live connector.

## Local start

From this directory:

```bash
docker compose pull
docker compose run --rm freqtrade download-data --config /freqtrade/user_data/config.dryrun.json --pairs BTC/USDT ETH/USDT --days 30 -t 1h
docker compose run --rm freqtrade backtesting --config /freqtrade/user_data/config.dryrun.json --strategy BiteyBaselineV1 --timerange 20260901-20261001 -i 1h
```

For dry-run:

```bash
docker compose up -d
```

The compose file keeps the API bound to localhost. Do not expose the Freqtrade API publicly without adding authentication, a strong JWT secret and an external access-control layer.

## Next integration stage

1. Backtest adapter output.
2. Normalize trades and metrics into SBT contracts.
3. Add the Freqtrade REST client as a READ/DEMO connector.
4. Feed results into the SBT Validation Passport.
5. Add FreqAI only after deterministic baseline tests are reproducible.
6. Keep LIVE disabled until the SBT real-money gate exists.

See the official Freqtrade documentation for installation, strategy development, REST API and FreqAI.


## FreqAI research mode

The repository now includes an isolated `BiteyFreqAI_v1` research strategy and a `config.freqai.dryrun.json` configuration. FreqAI is enabled, but the config keeps `dry_run: true` and contains no exchange credentials.

Run the deterministic baseline first:

    docker compose run --rm freqtrade download-data --config /freqtrade/user_data/config.freqai.dryrun.json --pairs BTC/USDT ETH/USDT --days 60 -t 1h
    docker compose run --rm freqtrade backtesting --config /freqtrade/user_data/config.freqai.dryrun.json --strategy BiteyFreqAI_v1 --freqaimodel LightGBMRegressor --timerange 20260901-20261001 -i 1h

Then use dry-run:

    docker compose run --rm freqtrade trade --config /freqtrade/user_data/config.freqai.dryrun.json --strategy BiteyFreqAI_v1 --freqaimodel LightGBMRegressor

FreqAI performs periodic retraining and can emulate that process during backtesting. The SBT integration treats its predictions as research evidence, not as authorization to trade real money. Features must remain causal and must not look ahead into future candles.
