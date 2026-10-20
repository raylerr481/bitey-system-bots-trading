//+------------------------------------------------------------------+
//|                                Fibonacci_Module_MT4.mqh           |
//|   Modulo Optimizado: Rango flexible y alta eficiencia (MT4)      |
//|   Portado desde la version MQL5. Fib_UseAsFilter se declara en    |
//|   el EA principal (EA_EMA_RSI_ATR_MT4.mq4), no aqui, para evitar  |
//|   input duplicado al incluir este archivo.                        |
//+------------------------------------------------------------------+
#property strict

input string _grpFib               = "=== Fibonacci Module (Optimizado) ===";
input int    Fib_FractalLookback    = 1;
input int    Fib_MaxBarsSearch      = 150;
input double Fib_ZoneMin            = 0.236;
input double Fib_ZoneMax            = 0.786;
input double Fib_InvalidLevel       = 0.886;

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
  };

bool IsFractalHigh(const double &high[], int shift, int lookback, int totalBars)
  {
   if(shift - lookback < 0 || shift + lookback >= totalBars) return false;
   double center = high[shift];
   for(int i = 1; i <= lookback; i++)
     {
      if(high[shift - i] >= center || high[shift + i] >= center) return false;
     }
   return true;
  }

bool IsFractalLow(const double &low[], int shift, int lookback, int totalBars)
  {
   if(shift - lookback < 0 || shift + lookback >= totalBars) return false;
   double center = low[shift];
   for(int i = 1; i <= lookback; i++)
     {
      if(low[shift - i] <= center || low[shift + i] <= center) return false;
     }
   return true;
  }

void CalcFibLevels(FibSwing &swing)
  {
   double range = MathAbs(swing.priceEnd - swing.priceStart);
   if(swing.isUptrend)
     {
      swing.level0    = swing.priceEnd;
      swing.level236  = swing.priceEnd - range * 0.236;
      swing.level382  = swing.priceEnd - range * 0.382;
      swing.level50   = swing.priceEnd - range * 0.5;
      swing.level618  = swing.priceEnd - range * 0.618;
      swing.level786  = swing.priceEnd - range * 0.786;
      swing.level1000 = swing.priceStart;
     }
   else
     {
      swing.level0    = swing.priceEnd;
      swing.level236  = swing.priceEnd + range * 0.236;
      swing.level382  = swing.priceEnd + range * 0.382;
      swing.level50   = swing.priceEnd + range * 0.5;
      swing.level618  = swing.priceEnd + range * 0.618;
      swing.level786  = swing.priceEnd + range * 0.786;
      swing.level1000 = swing.priceStart;
     }
  }

FibSwing FindLastSwing(const string symbol, const ENUM_TIMEFRAMES tf)
  {
   FibSwing swing;
   swing.valid = false;
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int totalBars = MathMin(Fib_MaxBarsSearch, iBars(symbol, tf));
   if(CopyRates(symbol, tf, 0, totalBars, rates) <= 0) return swing;

   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArrayResize(high, totalBars);
   ArrayResize(low, totalBars);
   for(int i = 0; i < totalBars; i++)
     {
      high[i] = rates[i].high;
      low[i]  = rates[i].low;
     }

   int lastHighShift = -1, lastLowShift = -1;
   for(int i = 1; i < totalBars - Fib_FractalLookback; i++)
     {
      if(lastHighShift == -1 && IsFractalHigh(high, i, Fib_FractalLookback, totalBars)) lastHighShift = i;
      if(lastLowShift == -1 && IsFractalLow(low, i, Fib_FractalLookback, totalBars)) lastLowShift = i;
      if(lastHighShift != -1 && lastLowShift != -1) break;
     }

   if(lastHighShift == -1 || lastLowShift == -1) return swing;

   if(lastLowShift < lastHighShift)
     {
      swing.isUptrend  = false;
      swing.priceStart = high[lastHighShift];
      swing.priceEnd   = low[lastLowShift];
      swing.timeStart  = rates[lastHighShift].time;
      swing.timeEnd    = rates[lastLowShift].time;
     }
   else
     {
      swing.isUptrend  = true;
      swing.priceStart = low[lastLowShift];
      swing.priceEnd   = high[lastHighShift];
      swing.timeStart  = rates[lastLowShift].time;
      swing.timeEnd    = rates[lastHighShift].time;
     }
   swing.valid = true;
   CalcFibLevels(swing);
   return swing;
  }

bool IsPriceInGoldenZone(const double currentPrice, const FibSwing &swing)
  {
   if(!swing.valid) return false;
   double zoneLow, zoneHigh;
   if(swing.isUptrend)
     {
      zoneLow  = swing.priceEnd - MathAbs(swing.priceEnd - swing.priceStart) * Fib_ZoneMax;
      zoneHigh = swing.priceEnd - MathAbs(swing.priceEnd - swing.priceStart) * Fib_ZoneMin;
     }
   else
     {
      zoneLow  = swing.priceEnd + MathAbs(swing.priceEnd - swing.priceStart) * Fib_ZoneMin;
      zoneHigh = swing.priceEnd + MathAbs(swing.priceEnd - swing.priceStart) * Fib_ZoneMax;
     }
   return (currentPrice >= zoneLow && currentPrice <= zoneHigh);
  }

bool IsSwingInvalidated(const double currentPrice, const FibSwing &swing)
  {
   if(!swing.valid) return false;
   if(swing.isUptrend) return (currentPrice < swing.level786);
   else return (currentPrice > swing.level786);
  }
