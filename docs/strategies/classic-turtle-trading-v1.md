# Classic Turtle Trading — SBT Strategy Contract v1.0

## Purpose
This strategy is the deterministic Turtle breakout profile for Bitey SBT. It is a strategy specification and signal engine, not a broker-order implementation.

## Rules
| Component | Rule |
|---|---|
| System 1 entry | 20-bar breakout |
| System 1 exit | 10-bar opposite breakout |
| System 2 entry | 55-bar breakout |
| System 2 exit | 20-bar opposite breakout |
| N | 20-period ATR |
| Initial stop | 2N |
| Pyramiding | +0.5N per additional unit |
| Maximum position | 4 units |
| Directions | Long and short |
| S1 skip | Optional one-time skip after a winning S1 trade |

The breakout channel excludes the current completed bar when calculating the reference level, preventing look-ahead.

## SBT lifecycle
Research → Simulation → Stress test → Validation → Demo/Paper → Risk Gate → deployment eligibility

## MT4 relationship
MT4 remains an external execution/test platform. SBT can ingest MT4 results and diagnostics, compare them with the deterministic Turtle contract, and expose the evidence to Bitey IA. This is separated from broker execution authority.

## Evidence required before deployment
- complete trade list
- net return and profit factor
- maximum drawdown
- trade count
- long/short distribution
- S1/S2 attribution
- stop/exit attribution
- slippage and spread assumptions
- in-sample/out-of-sample separation
- parameter sensitivity
- demo/paper consistency

A profitable backtest alone is not a deployment approval.