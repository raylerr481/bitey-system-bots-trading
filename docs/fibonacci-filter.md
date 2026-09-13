# Fibonacci Filter — SBT

## Purpose

The Fibonacci module adds a structural swing filter to the EMA + RSI + ATR strategy. It uses closed-bar fractals on a configurable timeframe (the reference integration uses M15) and accepts a signal only when price is inside the 38.2%–61.8% retracement zone and the swing has not been invalidated.

## Safety boundary

This module is analysis/filter logic only. It does not place broker orders, enable live mode, bypass the Risk Gate, or change `live=false`, `real_money=false`, or `broker_orders=0`.

## MQL5 artifact

`mt5/Fibonacci_Module.mqh`

The module provides:

- `FibSwing` — detected swing and Fibonacci levels.
- `IsFractalHigh()` / `IsFractalLow()` — closed-bar fractal detection.
- `FindLastSwing()` — latest valid structural swing.
- `CalcFibLevels()` — retracement and extension levels.
- `IsPriceInGoldenZone()` — configurable golden-zone filter.
- `IsSwingInvalidated()` — configurable invalidation threshold.

## Reference integration

```mql5
#include "Fibonacci_Module.mqh"

FibSwing swing = FindLastSwing(_Symbol, PERIOD_M15);
double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

if(Fib_UseAsFilter)
  {
   if(!swing.valid)
      return;

   if(IsSwingInvalidated(currentPrice, swing))
      return;

   if(!IsPriceInGoldenZone(currentPrice, swing))
      return;
  }

// Continue with the existing EMA + RSI + ATR signal path.
```

## Design notes

- Shift `0` is excluded because it is the live/unclosed candle.
- The implementation validates the number of bars actually returned by `CopyRates()` before indexing arrays.
- The search range is protected against too-small history for the selected fractal lookback.
- `Fib_InvalidLevel` is used directly when calculating the invalidation threshold; it is not hard-coded to 78.6%.
- The swing direction is derived from which of the latest high/low fractals is more recent.
- The module does not guarantee profitability. It is a confirmation/filter layer and must be evaluated with backtesting and demo/paper validation before any future consideration of real-money execution.

## Current repository limitation

The SBT repository does not currently contain the original `EA_EMA_RSI_ATR.mq5` source file. Therefore this commit adds the reusable module and its integration contract without inventing or duplicating the missing EA. When the EA source is restored to the repository, the include and filter block can be integrated directly into its existing signal path.
