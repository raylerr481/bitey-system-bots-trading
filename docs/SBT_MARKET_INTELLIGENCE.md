# Bitey SBT Market Intelligence

Bitey SBT now has a first-layer market-intelligence engine designed to evolve from news discovery into causal market-impact analysis.

## User flow

1. Select language: `es`, `pt`, or `en`.
2. Enter available capital.
3. Press **Analyze Market**.
4. Collect normalized evidence from trusted news, official sources, specialist sources and social commentary.
5. Build an effect-domino graph.
6. Rank potentially affected assets and sectors.
7. Produce scenarios, invalidation conditions, time horizon and capital/risk envelope.
8. Require technical/market confirmation before any Demo action.
9. Record the prediction for later backtesting and outcome validation.

## API

`GET /api/v1/sbt/market-intelligence/languages`

`POST /api/v1/sbt/market-intelligence/analyze`

Example request:

```json
{
  "capital": 1000,
  "language": "es",
  "event": "energy_supply_risk",
  "evidence": [
    {
      "source": "Reuters",
      "source_type": "news",
      "title": "Hormuz shipping and oil market update",
      "reliability": 0.95,
      "impact": 0.95,
      "direction": "long"
    }
  ]
}
```

The engine returns opportunity scores, not guaranteed win probabilities. A score becomes a statistically meaningful probability only after sufficient historical validation.

## Safety

- MT5 remains Demo/read-only in the current environment.
- No live order is created by the intelligence endpoint.
- Social posts are evidence, not verified facts.
- High-impact claims should be confirmed by independent reliable sources.
- Conflicting news and price action should produce `watch`/`no trade`, not forced execution.
- Risk is expressed as a maximum loss envelope, not a promise of profit.
