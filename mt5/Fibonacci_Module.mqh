//+------------------------------------------------------------------+
//|                                          Fibonacci_Module.mqh     |
//|  Fractal swing detection and Fibonacci levels for the             |
//|  EMA + RSI + ATR demo-safe strategy.                              |
//+------------------------------------------------------------------+
#property strict

input group "=== Fibonacci Module ==="
input int    Fib_FractalLookback = 2;
input int    Fib_MaxBarsSearch   = 200;
input double Fib_ZoneMin         = 0.382;
input double Fib_ZoneMax         = 0.618;
input double Fib_InvalidLevel     = 0.786;
input bool   Fib_UseAsFilter     = true;

struct FibSwing
  {
   bool     valid;
   bool     isUptrend;
   double   priceStart;
   double   priceEnd;
   datetime timeStart;
   datetime timeEnd;
   double   level0;
   double   level236;
   double   level382;
   double   level50;
   double   level618;
   double   level786;
   double   level1000;
   double   ext1272;
   double   ext1618;
   double   ext2618;
  };

bool IsFractalHigh(const double &high[], const int shift, const int lookback, const int totalBars)
  {
   if(lookback < 1 || shift - lookback < 0 || shift + lookback >= totalBars)
      return false;

   const double center = high[shift];
   for(int i = 1; i <= lookback; i++)
     {
      if(high[shift - i] >= center || high[shift + i] >= center)
         return false;
     }
   return true;
  }

bool IsFractalLow(const double &low[], const int shift, const int lookback, const int totalBars)
  {
   if(lookback < 1 || shift - lookback < 0 || shift + lookback >= totalBars)
      return false;

   const double center = low[shift];
   for(int i = 1; i <= lookback; i++)
     {
      if(low[shift - i] <= center || low[shift + i] <= center)
         return false;
     }
   return true;
  }

void CalcFibLevels(FibSwing &swing)
  {
   const double range = MathAbs(swing.priceEnd - swing.priceStart);

   if(range <= 0.0)
      return;

   if(swing.isUptrend)
     {
      swing.level0    = swing.priceEnd;
      swing.level236  = swing.priceEnd - range * 0.236;
      swing.level382  = swing.priceEnd - range * 0.382;
      swing.level50   = swing.priceEnd - range * 0.500;
      swing.level618  = swing.priceEnd - range * 0.618;
      swing.level786  = swing.priceEnd - range * 0.786;
      swing.level1000 = swing.priceStart;
      swing.ext1272   = swing.priceEnd + range * 0.272;
      swing.ext1618   = swing.priceEnd + range * 0.618;
      swing.ext2618   = swing.priceEnd + range * 1.618;
     }
   else
     {
      swing.level0    = swing.priceEnd;
      swing.level236  = swing.priceEnd + range * 0.236;
      swing.level382  = swing.priceEnd + range * 0.382;
      swing.level50   = swing.priceEnd + range * 0.500;
      swing.level618  = swing.priceEnd + range * 0.618;
      swing.level786  = swing.priceEnd + range * 0.786;
      swing.level1000 = swing.priceStart;
      swing.ext1272   = swing.priceEnd - range * 0.272;
      swing.ext1618   = swing.priceEnd - range * 0.618;
      swing.ext2618   = swing.priceEnd - range * 1.618;
     }
  }

FibSwing FindLastSwing(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   FibSwing swing;
   ZeroMemory(swing);
   swing.valid = false;

   const int lookback = MathMax(1, Fib_FractalLookback);
   const int requestedBars = MathMax(Fib_MaxBarsSearch, lookback * 2 + 5);
   const int availableBars = Bars(symbol, tf);
   if(availableBars < lookback * 2 + 3)
      return swing;

   const int totalBars = MathMin(requestedBars, availableBars);
   if(totalBars <= lookback * 2 + 1)
      return swing;

   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   const int copied = CopyRates(symbol, tf, 0, totalBars, rates);
   if(copied < lookback * 2 + 3)
      return swing;

   const int barsCount = copied;
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArrayResize(high, barsCount);
   ArrayResize(low, barsCount);

   for(int i = 0; i < barsCount; i++)
     {
      high[i] = rates[i].high;
      low[i]  = rates[i].low;
     }

   int lastHighShift = -1;
   int lastLowShift  = -1;

   // Shift 0 is the live/unclosed bar; start at shift 1.
   for(int i = 1; i < barsCount - lookback; i++)
     {
      if(lastHighShift == -1 && IsFractalHigh(high, i, lookback, barsCount))
         lastHighShift = i;

      if(lastLowShift == -1 && IsFractalLow(low, i, lookback, barsCount))
         lastLowShift = i;

      if(lastHighShift != -1 && lastLowShift != -1)
         break;
     }

   if(lastHighShift == -1 || lastLowShift == -1)
      return swing;

   // Smaller shift = more recent closed fractal.
   if(lastLowShift < lastHighShift)
     {
      // Most recent structural point is a low: use high -> low as a bearish retracement swing.
      swing.isUptrend  = false;
      swing.priceStart = high[lastHighShift];
      swing.priceEnd   = low[lastLowShift];
      swing.timeStart  = rates[lastHighShift].time;
      swing.timeEnd    = rates[lastLowShift].time;
     }
   else
     {
      // Most recent structural point is a high: use low -> high as a bullish retracement swing.
      swing.isUptrend  = true;
      swing.priceStart = low[lastLowShift];
      swing.priceEnd   = high[lastHighShift];
      swing.timeStart  = rates[lastLowShift].time;
      swing.timeEnd    = rates[lastHighShift].time;
     }

   if(swing.priceStart <= 0.0 || swing.priceEnd <= 0.0 || swing.priceStart == swing.priceEnd)
      return swing;

   CalcFibLevels(swing);
   swing.valid = true;
   return swing;
  }

bool IsPriceInGoldenZone(const double currentPrice, const FibSwing &swing)
  {
   if(!swing.valid || currentPrice <= 0.0)
      return false;

   const double zoneMin = MathMin(Fib_ZoneMin, Fib_ZoneMax);
   const double zoneMax = MathMax(Fib_ZoneMin, Fib_ZoneMax);
   const double range   = MathAbs(swing.priceEnd - swing.priceStart);
   if(range <= 0.0)
      return false;

   double zoneLow;
   double zoneHigh;

   if(swing.isUptrend)
     {
      zoneLow  = swing.priceEnd - range * zoneMax;
      zoneHigh = swing.priceEnd - range * zoneMin;
     }
   else
     {
      zoneLow  = swing.priceEnd + range * zoneMin;
      zoneHigh = swing.priceEnd + range * zoneMax;
     }

   return (currentPrice >= zoneLow && currentPrice <= zoneHigh);
  }

bool IsSwingInvalidated(const double currentPrice, const FibSwing &swing)
  {
   if(!swing.valid || currentPrice <= 0.0)
      return false;

   const double invalidLevel = MathMax(0.0, Fib_InvalidLevel);
   const double range = MathAbs(swing.priceEnd - swing.priceStart);
   if(range <= 0.0)
      return false;

   double level;
   if(swing.isUptrend)
      level = swing.priceEnd - range * invalidLevel;
   else
      level = swing.priceEnd + range * invalidLevel;

   if(swing.isUptrend)
      return (currentPrice < level);

   return (currentPrice > level);
  }

// Example integration in EA_EMA_RSI_ATR.mq5:
//
// #include "Fibonacci_Module.mqh"
//
// Inside the signal path, before the EMA/RSI/ATR entry is accepted:
//
// FibSwing swing = FindLastSwing(_Symbol, PERIOD_M15);
// double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
//
// if(Fib_UseAsFilter)
//   {
//    if(!swing.valid)
//       return;
//
//    if(IsSwingInvalidated(currentPrice, swing))
//       return;
//
//    if(!IsPriceInGoldenZone(currentPrice, swing))
//       return;
//   }
//
// The Fibonacci module is a signal filter only. It does not place orders,
// bypass the Risk Gate, enable live trading, or enable real-money execution.
//+------------------------------------------------------------------+
