//+------------------------------------------------------------------+
//| EA31337_Libre_MT4_DayTrading.mq4                                 |
//| Independent MT4 day-trading prototype; NOT an official EA31337 port |
//| Copyright (C) 2026. Released under GPL-3.0-or-later.              |
//| No profitability guarantee. Validate in Strategy Tester/demo.    |
//+------------------------------------------------------------------+
#property strict
#property version   "0.1.0"
#property description "Independent MT4 prototype. Does not include upstream EA31337 strategy/dependencies."

input double ReferenceCapitalUSD       = 500.0;
input double RiskPercent               = 0.25;   // Planned risk per trade; not guaranteed max loss
input int    MaxOpenPositionsTotal     = 2;
input int    MagicNumber               = 3133701;
input ENUM_TIMEFRAMES SignalTimeframe  = PERIOD_M15;
input int    FastEMA                   = 9;
input int    SlowEMA                   = 21;
input int    RSIPeriod                 = 14;
input double BuyRSIMin                 = 52.0;
input double SellRSIMax                = 48.0;
input int    ATRPeriod                 = 14;
input double StopATRMultiplier         = 1.8;
input double TakeProfitRiskMultiple    = 1.5;
input int    MaxSpreadPoints           = 35;
input int    SlippagePoints             =  5;
input int    TradingStartHourServer    = 7;
input int    TradingEndHourServer      = 20;     // No new entries at/after this hour
input bool   CloseAtTradingEnd         = true;   // Uses broker server time
input bool   RequireUSDAccount         = true;
input bool   EnableTrading             = false;  // Safety: enable only after tests
input string OrderCommentText          = "EA31337-Libre-MT4-prototype";

datetime g_lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   if (ReferenceCapitalUSD <= 0 || RiskPercent <= 0 || RiskPercent > 1.0 ||
       FastEMA < 2 || SlowEMA <= FastEMA || ATRPeriod < 2 ||
       StopATRMultiplier <= 0 || TakeProfitRiskMultiple <= 0 ||
       MaxOpenPositionsTotal < 1 || MaxSpreadPoints < 1)
   {
      Print("INIT_FAILED: invalid input parameters.");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if (RequireUSDAccount && AccountCurrency() != "USD")
   {
      Print("SAFETY BLOCK: account currency is ", AccountCurrency(),
            "; this prototype's reference capital/risk assumptions require USD.");
      return(INIT_FAILED);
   }
   Print("Initialized in ", (EnableTrading ? "TRADING ENABLED" : "SAFE DISABLED"),
         " mode. Prototype only; no EA31337 upstream strategy code is included.");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if (CloseAtTradingEnd && Hour() >= TradingEndHourServer)
      CloseOwnPositions();

   if (!EnableTrading) return;
   if (RequireUSDAccount && AccountCurrency() != "USD") return;
   if (!IsTradeAllowed() || IsTradeContextBusy()) return;
   if (Hour() < TradingStartHourServer || Hour() >= TradingEndHourServer) return;
   if (MarketInfo(Symbol(), MODE_SPREAD) > MaxSpreadPoints) return;
   if (CountOwnPositions(-1) >= MaxOpenPositionsTotal) return;
   if (CountOwnPositionsForSymbol(Symbol()) > 0) return;

   datetime currentBar = iTime(Symbol(), SignalTimeframe, 0);
   if (currentBar <= 0 || currentBar == g_lastBarTime) return;
   g_lastBarTime = currentBar;

   // All signal values use closed bars (shifts 1 and 2).
   double fast1 = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double fast2 = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double slow1 = iMA(Symbol(), SignalTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow2 = iMA(Symbol(), SignalTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double rsi1  = iRSI(Symbol(), SignalTimeframe, RSIPeriod, PRICE_CLOSE, 1);
   double atr1  = iATR(Symbol(), SignalTimeframe, ATRPeriod, 1);

   if (fast1 <= 0 || fast2 <= 0 || slow1 <= 0 || slow2 <= 0 ||
       rsi1 <= 0 || atr1 <= 0 || !IsTradeAllowed()) return;

   bool buySignal  = (fast2 <= slow2 && fast1 > slow1 && rsi1 >= BuyRSIMin);
   bool sellSignal = (fast2 >= slow2 && fast1 < slow1 && rsi1 <= SellRSIMax);
   if (buySignal)  PlaceMarketOrder(OP_BUY, atr1);
   if (sellSignal) PlaceMarketOrder(OP_SELL, atr1);
}

//+------------------------------------------------------------------+
int CountOwnPositions(int ignoredType)
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != MagicNumber) continue;
      if (OrderSymbol() == "" || (OrderType() != OP_BUY && OrderType() != OP_SELL)) continue;
      if (ignoredType >= 0 && OrderType() != ignoredType) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
int CountOwnPositionsForSymbol(string sym)
{
   int count = 0;
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != MagicNumber || OrderSymbol() != sym) continue;
      if (OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

//+------------------------------------------------------------------+
void PlaceMarketOrder(int type, double atr)
{
   RefreshRates();
   double point = MarketInfo(Symbol(), MODE_POINT);
   int digits = (int)MarketInfo(Symbol(), MODE_DIGITS);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * point;
   double entry = (type == OP_BUY) ? Ask : Bid;
   double stopDistance = MathMax(atr * StopATRMultiplier, stopLevel + 2.0 * point);
   if (entry <= 0 || point <= 0 || stopDistance <= 0) return;

   double sl = (type == OP_BUY) ? entry - stopDistance : entry + stopDistance;
   double tpDistance = stopDistance * TakeProfitRiskMultiple;
   double tp = (type == OP_BUY) ? entry + tpDistance : entry - tpDistance;
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   double lots = CalculateLots(stopDistance);
   if (lots <= 0)
   {
      Print("ENTRY_BLOCKED: calculated lot is below broker minimum or risk metadata invalid.");
      return;
   }

   ResetLastError();
   double marginCheck = AccountFreeMarginCheck(Symbol(), type, lots);
   if (marginCheck <= 0)
   {
      Print("ENTRY_BLOCKED: insufficient free margin. error=", GetLastError());
      return;
   }

   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, entry, SlippagePoints, sl, tp,
                          OrderCommentText, MagicNumber, 0, clrNONE);
   if (ticket < 0)
   {
      Print("ORDER_REJECTED: type=", type, " lots=", DoubleToString(lots, 2),
            " error=", GetLastError());
      return;
   }
   Print("ORDER_OPENED: ticket=", ticket, " symbol=", Symbol(),
         " type=", (type == OP_BUY ? "BUY" : "SELL"),
         " lots=", DoubleToString(lots, 2),
         " plannedRiskUSD~=", DoubleToString(ReferenceCapitalUSD * RiskPercent / 100.0, 2),
         " SL=", DoubleToString(sl, digits), " TP=", DoubleToString(tp, digits));
}

//+------------------------------------------------------------------+
double CalculateLots(double stopDistancePrice)
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   double minLot    = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot    = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep   = MarketInfo(Symbol(), MODE_LOTSTEP);

   if (tickValue <= 0 || tickSize <= 0 || minLot <= 0 ||
       maxLot < minLot || lotStep <= 0 || stopDistancePrice <= 0)
      return 0;

   double riskMoney = ReferenceCapitalUSD * RiskPercent / 100.0;
   double lossPerLot = (stopDistancePrice / tickSize) * tickValue;
   if (riskMoney <= 0 || lossPerLot <= 0) return 0;

   double rawLots = riskMoney / lossPerLot;
   // Never round up to minimum lot if that would exceed the planned risk.
   if (rawLots < minLot) return 0;
   double lots = MathFloor(rawLots / lotStep + 1e-8) * lotStep;
   lots = MathMin(lots, maxLot);
   int lotDigits = 2;
   if (lotStep >= 1.0) lotDigits = 0;
   else if (lotStep >= 0.1) lotDigits = 1;
   else if (lotStep < 0.01) lotDigits = 3;
   lots = NormalizeDouble(lots, lotDigits);
   if (lots < minLot) return 0;

   // Final sanity check using broker's tick metadata.
   double estimatedLoss = (stopDistancePrice / tickSize) * tickValue * lots;
   if (estimatedLoss > riskMoney + 0.01) return 0;
   return lots;
}

//+------------------------------------------------------------------+
void CloseOwnPositions()
{
   for (int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if (!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if (OrderMagicNumber() != MagicNumber || OrderSymbol() != Symbol()) continue;
      int type = OrderType();
      if (type != OP_BUY && type != OP_SELL) continue;

      RefreshRates();
      double closePrice = (type == OP_BUY) ? Bid : Ask;
      ResetLastError();
      bool closed = OrderClose(OrderTicket(), OrderLots(), closePrice, SlippagePoints, clrNONE);
      if (!closed)
         Print("DAY_END_CLOSE_FAILED: ticket=", OrderTicket(), " error=", GetLastError());
      else
         Print("DAY_END_CLOSE_OK: ticket=", OrderTicket(), " serverHour=", Hour());
   }
}
//+------------------------------------------------------------------+
