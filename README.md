# Bitey System Bots Trading

Trading-system module of **Bitey IA**. This repository is intentionally independent from Bitey Trainer, while exposing interfaces that can later integrate with it.

## Mission

Build, test, evaluate and operate algorithmic trading systems through a controlled progression:

**Research → Backtest → Demo → Paper Trading → Micro-capital → Controlled scaling**

Real-money execution is disabled by default.

## Architecture

- `core/` — domain models and trading state
- `strategies/` — deterministic strategies and signal contracts
- `risk/` — mandatory pre-trade and portfolio risk controls
- `backtest/` — historical simulation with fees/slippage
- `execution/` — broker/exchange adapters; starts with a paper adapter
- `api/` — FastAPI service for Bitey IA and future apps
- `tests/` — unit and integration tests

## Design principles

1. One signal/risk path for backtest, paper and future live modes.
2. Strategy code never sends orders directly.
3. Risk checks cannot be bypassed by strategies or AI agents.
4. LLM/AI components may analyze or rank strategies but cannot override hard risk limits.
5. Live execution requires explicit configuration and independent safety gates.
6. Every order intent, risk decision and execution event is auditable.

## Initial milestone

The first implementation is a safe paper/demo engine. It will not connect to a live broker or exchange until the test suite and operational safeguards are established.
