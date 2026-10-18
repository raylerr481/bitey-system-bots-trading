# Bitey SBT Live Signal & Variant Research Library

## Purpose
Version and analyze SBT signal telemetry, source versions, compile reports, Strategy Tester reports, and demo/live execution outcomes in one auditable research library. The objective is to compare variants on evidence, not to promise or assume profitability.

## Data flow
1. **MT4 EA** emits one structured JSON event per evaluated closed bar, per model, per assembly decision, and per order lifecycle event.
2. **Authenticated ingestion endpoint** (recommended: the existing SBT backend/Worker) validates and stores events in a dedicated research store. Do not send GitHub tokens or database service-role keys from MT4.
3. **Research exporter** periodically writes sanitized, immutable snapshots and reports to this GitHub directory. GitHub is the versioned research library, not the low-latency event database.
4. **Analyzer** compares variants by symbol, timeframe, direction, model, market regime, spread/cost assumptions, and source commit.
5. **Candidate gate** promotes a variant only after out-of-sample and forward/demo validation; it never changes production EA code or enables orders automatically.

## Repository layout
- `schemas/signal-event.schema.json`: event contract for EA telemetry.
- `analysis-rules.md`: evaluation and promotion rules.
- `snapshots/YYYY/MM/`: sanitized, append-only telemetry batches.
- `reports/`: reproducible comparison reports.
- `builds/`: source commit, compiler/build metadata, and test artifact checksums. Do not commit proprietary terminal data or account identifiers.
- `variants/`: source diffs and parameter manifests for each research candidate.

## Required event fields
Every record should include UTC timestamp, broker timestamp/offset when known, symbol, timeframe, closed-bar time, source version/commit, event type, decision, reason, 16-model signals, training/holdout metrics, spread, ATR, stop/target distances, intended risk in USD, and order result if any. Include account type only as diagnostic metadata; risk policy must be identical for demo and live.

## Current status
This directory defines the contract and governance. It is **not yet a connected live ingestion service**. Continuous collection requires wiring the EA's WebRequest telemetry to an authenticated endpoint and then configuring the exporter. Do not put GitHub credentials in EA inputs or source code.

## Safety
- No martingale, no automatic account switching, no bypass of manual MT4 authority.
- Treat every account as real-money risk.
- No candidate is labelled profitable from training metrics alone.
- Keep production EA separate; research code must not auto-deploy or alter live orders.
