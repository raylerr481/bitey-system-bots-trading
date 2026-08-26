# Bitey Ecosystem Integration

## Position in Bitey IA

Bitey System Bots Trading is an independent specialized module inside the Bitey IA / Supracerebro ecosystem. It is not a separate AI ecosystem and must use the existing Bitey IA identity, configuration, learning and persistence boundaries where appropriate.

## Related modules

- **Bitey IA / Supracerebro**: orchestration, shared knowledge, identity and cross-module coordination.
- **Bitey IA App**: user-facing mobile client for Bitey IA.
- **Bitey Trainer**: training, evaluation and learning workflows for AI agents.
- **JobIA**: job/work opportunity and task-oriented module connected to Bitey Trainer and Bitey IA.
- **Bitey System Bots Trading**: specialized strategy, backtesting, demo/paper trading and risk-control module.
- **Bitey System Bots Trading App**: mobile client for the trading module.

## Data and learning flow

```text
                    Bitey IA / Supracerebro
                              |
          +-------------------+-------------------+
          |                   |                   |
      Bitey IA App       Bitey Trainer          JobIA
          |                   |                   |
          +-------------------+-------------------+
                              |
                     shared knowledge/events
                              |
                              v
                  Bitey System Bots Trading
                              |
                 +------------+------------+
                 |                         |
             strategies              experiments
                 |                         |
                 +------------+------------+
                              |
                     evaluation/results
                              |
                              v
                       Bitey Trainer
                              |
                              v
                         Bitey IA
```

## Boundaries

Shared learning does **not** mean unrestricted permissions. Trading execution remains isolated behind strategy validation and the Risk Engine. Trainer/AI outputs may propose or evaluate strategies, but they must not directly authorize real-money execution.

Trading progression is:

1. Backtest
2. Demo
3. Paper trading
4. Controlled small-capital testing only after explicit validation
5. Gradual expansion based on measured performance and risk controls

## Shared infrastructure

The trading module should reuse the existing Bitey IA Supabase project and environment conventions rather than creating an unrelated database. Trading-specific tables use the `trading_` namespace. Secrets remain server-side environment variables and are never bundled into the mobile application.

## Goal

The modules evolve together through controlled knowledge and experiment results while remaining independently deployable, testable and auditable.
