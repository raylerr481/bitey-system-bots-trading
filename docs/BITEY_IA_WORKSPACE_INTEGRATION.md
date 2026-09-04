# Bitey IA Workspace Integration

Bitey SBT is exposed to the general Bitey IA workspace as a specialized market-intelligence capability.

The general Bitey IA web workspace uses this deployed SBT environment as its current live-market workspace:

`https://bitey-system-bots-trading.raylerr481.workers.dev/`

## Boundary

```text
Bitey IA
  ↓ decides capability
Bitey SBT
  ↓ market intelligence / research / simulation
Risk Gate
  ↓ permits or blocks trading actions
Execution connector
```

SBT remains the specialized trading system. Bitey IA remains the cognitive controller. The integration must not bypass SBT permissions, deterministic strategy rules, validation or Risk Gate controls.

## Current behavior

- Live-market workspace can be opened from Bitey IA.
- Market data remains informational/read-only at the current milestone.
- Demo/Paper workflows remain separated from real-money execution.
- Real-money execution stays disabled until all required controls are implemented and validated.
- The integration does not require a new paid market-data service.

## Future API integration

A later milestone may expose normalized market snapshots, quotes, candles and news/event context through versioned SBT API contracts so Bitey Brain can consume current market state directly for analysis while keeping execution authority inside SBT Risk Gate.
