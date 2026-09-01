# Bitey SBT — Original Product Specification

Status: baseline specification v1.0

## 1. Purpose

Bitey SBT is an original Bitey IA trading product. It can implement broad capabilities already validated by the market, but its product expression, architecture, terminology, UX, scoring, orchestration and implementation are designed independently.

## 2. Product promise

Help traders investigate, build, simulate, stress-test, validate and monitor systematic trading ideas with transparent evidence and mandatory risk controls.

Bitey SBT does not promise profits.

## 3. Product pillars

1. **Research** — investigate markets, events and hypotheses.
2. **Strategy Lab** — turn an idea into a deterministic specification.
3. **Model Workshop** — obtain proposals from Bitey and supported external AI models.
4. **Simulation** — backtest under explicit assumptions.
5. **Robustness** — test periods, parameters, regimes and out-of-sample behavior.
6. **Risk Gate** — apply deterministic hard limits.
7. **Demo/Paper** — observe behavior without real capital.
8. **Strategy Registry** — version and publish validated strategies.
9. **Monitoring** — measure behavior after publication/deployment.

## 4. Original terminology

Use these Bitey terms consistently:

- Bitey Research Lab
- Bitey Bot Lab
- Bitey Model Workshop
- SBT Evaluation
- SBT Strategy Registry
- SBT Risk Gate
- Strategy Evidence Card
- Validation Passport

Do not use competitor product names as internal module names.

## 5. Navigation baseline

```text
Inicio
Investigación
  ├─ Market Research
  ├─ Event Analysis
  └─ Experiments
Bot Lab
  ├─ Create Strategy
  ├─ My Strategies
  ├─ Simulation
  ├─ Robustness
  └─ Validation
Model Workshop
  ├─ Bitey
  ├─ External Models
  └─ Model Comparison
Markets
Strategy Registry
  ├─ Bitey Strategies
  ├─ Community Strategies
  └─ Validation Evidence
My Trading
  ├─ Demo
  ├─ Paper
  ├─ Active Strategies
  └─ Performance
Research Reports
Account
```

This is an original information architecture and must not be treated as a copy of any competitor's navigation.

## 6. Strategy Evidence Card

Every strategy shown to a user should expose evidence before emphasizing performance:

- identity;
- version;
- author;
- model provenance;
- market/timeframe;
- strategy rules;
- test period;
- trade count;
- costs and slippage assumptions;
- drawdown;
- return;
- risk-adjusted metrics where meaningful;
- out-of-sample evidence;
- robustness status;
- demo/paper evidence;
- validation freshness;
- risk classification.

## 7. Validation Passport

A strategy receives a versioned validation record containing the tests performed, assumptions, results, warnings and approval status. Any material strategy change invalidates or reopens the relevant validation state.

## 8. Model comparison contract

When multiple AI models are compared, use the same hypothesis, data, test period, cost assumptions, simulation engine and risk constraints whenever technically possible.

Models may propose different implementations. The evaluation environment remains controlled so the comparison is meaningful.

## 9. Safety contract

AI cannot bypass the deterministic Risk Gate. Real execution requires authentication, explicit account selection, capital and loss limits, pre-trade validation, auditability, emergency stop and health checks.

## 10. Originality gate

Before merging a feature, ask:

1. What user problem does this solve?
2. Is the capability a general/non-exclusive market concept?
3. Is the implementation independently designed?
4. Are the names and copy original?
5. Are the UI/layout/assets original?
6. Did we avoid importing competitor code or proprietary material?
7. Can the feature be explained without referencing a competitor as its blueprint?

If the answer to 3–6 is no, redesign before merge.

## 11. Implementation order

Phase 1 — product contracts and domain models.

Phase 2 — Strategy Evidence Card + Validation Passport.

Phase 3 — Bot Lab and simulation APIs.

Phase 4 — robustness and SBT Evaluation.

Phase 5 — Model Workshop abstraction.

Phase 6 — Strategy Registry.

Phase 7 — independent Cloudflare web frontend.

Phase 8 — demo/paper monitoring.

Phase 9 — future controlled live execution only after safety/legal/regulatory validation.
