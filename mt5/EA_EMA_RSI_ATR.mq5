//+------------------------------------------------------------------+
//| EA_EMA_RSI_ATR.mq5                                               |
//| DEMO-SAFE REFERENCE EA FOR BITEY SBT                             |
//| Real-money execution is intentionally blocked.                  |
//+------------------------------------------------------------------+
#property strict
#property version   "1.2"
#property description "EMA + RSI + ATR strategy with Fibonacci golden-zone filter and demo-only execution."

#include <Trade\Trade.mqh>
#include "Fibonacci_Module.mqh"

input group "=== Strategy ==="
input ENUM_TIMEFRAMES Trade_TF = PERIOD_M15;
input int EMA_Fast = 9;
input int EMA_Slow = 21;
input int RSI_Period = 14;
input double RSI_Buy_Min = 50.0;
input double RSI_Sell_Max = 50.0;

input group "=== Risk / ATR ==="
input int ATR_Period = 14;
input double ATR_SL_Multiplier = 1.5;
input double ATR_TP_Multiplier = 3.0;
input double Risk_Percent = 1.0;
input int Magic_Number = 202601;

input group "=== Circuit Breakers ==="
input double Daily_Loss_Limit_Percent = 3.0;
input double Monthly_Reduce_DD_Percent = 5.0;
input double Monthly_Hard_Stop_DD_Percent = 10.0;
input double Monthly_Risk_Reduction_Factor = 0.5;

input group "=== Fibonacci Filter ==="
input ENUM_TIMEFRAMES Fib_TF = PERIOD_M15;

CTrade trade;
datetime lastBarTime = 0;
double dayStartEquity = 0.0;
double monthStartEquity = 0.0;
int trackedMonthKey = -1;

int emaFastHandle = INVALID_HANDLE;
int emaSlowHandle = INVALID_HANDLE;
int rsiHandle = INVALID_HANDLE;
int atrHandle = INVALID_HANDLE;

int MonthKey()
  {
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   return dt.year * 100 + dt.mon;
  }

void ResetDailyTracking()
  {
   dayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
  }

void ResetMonthlyTracking()
  {
   monthStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   trackedMonthKey = MonthKey();
  }

bool IsDemoAccount()
  {
   return (AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO);
  }

bool CheckDailyCircuitBreaker()
  {
   if(dayStartEquity <= 0.0)
      return false;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double lossPct = (dayStartEquity - equity) / dayStartEquity * 100.0;

   if(lossPct >= Daily_Loss_Limit_Percent)
     {
      Print("Daily circuit breaker active. Loss % = ", DoubleToString(lossPct, 2));
      return true;
     }
   return false;
  }

double GetMonthlyDrawdownFactor()
  {
   int key = MonthKey();
   if(key != trackedMonthKey)
      ResetMonthlyTracking();

   if(monthStartEquity <= 0.0)
      return -1.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double ddPct = (monthStartEquity - equity) / monthStartEquity * 100.0;

   if(ddPct >= Monthly_Hard_Stop_DD_Percent)
     {
      Print("Monthly hard stop active. Drawdown % = ", DoubleToString(ddPct, 2));
      return -1.0;
     }

   if(ddPct >= Monthly_Reduce_DD_Percent)
      return Monthly_Risk_Reduction_Factor;

   return 1.0;
  }

bool HasOpenPosition()
  {
   for(int i = PositionsTotal() - 1; i >= 0; --i)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (int)PositionGetInteger(POSITION_MAGIC) == Magic_Number)
         return true;
     }
   return false;
  }

double CalculateLotSize(double slDistancePrice, double reduceFactor)
  {
   if(slDistancePrice <= 0.0 || reduceFactor <= 0.0)
      return 0.0;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(equity <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0 ||
      minLot <= 0.0 || maxLot <= 0.0 || lotStep <= 0.0)
      return 0.0;

   double riskAmount = equity * (Risk_Percent / 100.0) * reduceFactor;
   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return 0.0;

   double rawLot = riskAmount / lossPerLot;

   // Fail closed: never force minLot when it would exceed intended risk.
   if(rawLot < minLot)
      return 0.0;

   double lot = MathFloor(rawLot / lotStep) * lotStep;
   if(lot < minLot)
      return 0.0;

   lot = MathMin(lot, maxLot);
   return NormalizeDouble(lot, 8);
  }

bool IsNewBar()
  {
   datetime currentBar = iTime(_Symbol, Trade_TF, 0);
   if(currentBar <= 0 || currentBar == lastBarTime)
      return false;

   lastBarTime = currentBar;
   return true;
  }

bool ReadIndicatorValue(int handle, int shift, double &value)
  {
   if(handle == INVALID_HANDLE)
      return false;

   double buffer[1];
   if(CopyBuffer(handle, 0, shift, 1, buffer) != 1)
      return false;

   value = buffer[0];
   return (value != EMPTY_VALUE);
  }

int OnInit()
  {
   // Hard safety boundary for this SBT reference EA.
   if(!IsDemoAccount())
     {
      Print("EA initialization blocked: this EA is DEMO-ONLY.");
      return INIT_FAILED;
     }

   if(EMA_Fast <= 0 || EMA_Slow <= 0 || EMA_Fast >= EMA_Slow ||
      RSI_Period <= 0 || ATR_Period <= 0)
      return INIT_PARAMETERS_INCORRECT;

   emaFastHandle = iMA(_Symbol, Trade_TF, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, Trade_TF, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   rsiHandle = iRSI(_Symbol, Trade_TF, RSI_Period, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, Trade_TF, ATR_Period);

   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE ||
      rsiHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
     {
      Print("Indicator initialization failed.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(Magic_Number);
   ResetDailyTracking();
   ResetMonthlyTracking();
   Print("EA_EMA_RSI_ATR demo-safe reference initialized on ", _Symbol);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(rsiHandle != INVALID_HANDLE) IndicatorRelease(rsiHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
  }

void OnTick()
  {
   if(!IsDemoAccount())
      return;

   // Safety controls run on every tick, before new-bar gating.
   if(CheckDailyCircuitBreaker())
      return;

   double ddFactor = GetMonthlyDrawdownFactor();
   if(ddFactor < 0.0)
      return;

   if(HasOpenPosition())
      return;

   if(!IsNewBar())
      return;

   // Evaluate the just-closed candles for deterministic signal generation.
   double emaFast0, emaFast1, emaSlow0, emaSlow1, rsi0, atr0;
   if(!ReadIndicatorValue(emaFastHandle, 1, emaFast0) ||
      !ReadIndicatorValue(emaFastHandle, 2, emaFast1) ||
      !ReadIndicatorValue(emaSlowHandle, 1, emaSlow0) ||
      !ReadIndicatorValue(emaSlowHandle, 2, emaSlow1) ||
      !ReadIndicatorValue(rsiHandle, 1, rsi0) ||
      !ReadIndicatorValue(atrHandle, 1, atr0) || atr0 <= 0.0)
      return;

   bool buySignal = (emaFast1 <= emaSlow1 && emaFast0 > emaSlow0 && rsi0 >= RSI_Buy_Min);
   bool sellSignal = (emaFast1 >= emaSlow1 && emaFast0 < emaSlow0 && rsi0 <= RSI_Sell_Max);

   if(!buySignal && !sellSignal)
      return;

   // Fibonacci is fail-closed when enabled: no valid swing means no trade.
   if(Fib_UseAsFilter)
     {
      FibSwing swing = FindLastSwing(_Symbol, Fib_TF);
      if(!swing.valid)
         return;

      double currentPrice = buySignal
                            ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                            : SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(currentPrice <= 0.0 ||
         !IsPriceInGoldenZone(currentPrice, swing) ||
         IsSwingInvalidated(currentPrice, swing))
         return;
     }

   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(point <= 0.0)
      return;

   double slDistance = atr0 * ATR_SL_Multiplier;
   double tpDistance = atr0 * ATR_TP_Multiplier;
   double minStopDistance = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * point;

   if(slDistance <= 0.0 || tpDistance <= 0.0 || slDistance < minStopDistance)
      return;

   double lot = CalculateLotSize(slDistance, ddFactor);
   if(lot <= 0.0)
     {
      Print("Trade skipped: calculated lot is below broker minimum or risk constraints.");
      return;
     }

   if(buySignal)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      if(ask <= 0.0)
         return;

      double sl = NormalizeDouble(ask - slDistance, _Digits);
      double tp = NormalizeDouble(ask + tpDistance, _Digits);
      bool ok = trade.Buy(lot, _Symbol, 0.0, sl, tp, "Bitey SBT EMA-RSI-ATR-Fib DEMO");
      if(!ok)
         Print("Buy failed. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         Print("Buy accepted. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
   else if(sellSignal)
     {
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(bid <= 0.0)
         return;

      double sl = NormalizeDouble(bid + slDistance, _Digits);
      double tp = NormalizeDouble(bid - tpDistance, _Digits);
      bool ok = trade.Sell(lot, _Symbol, 0.0, sl, tp, "Bitey SBT EMA-RSI-ATR-Fib DEMO");
      if(!ok)
         Print("Sell failed. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      else
         Print("Sell accepted. retcode=", trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
     }
  }
//+------------------------------------------------------------------+
