//+------------------------------------------------------------------+
//| Bitey_Range_Trader_v1_2_0_DayTrading.mq4                                   |
//| Standalone intraday range + confirmed breakout EA for MetaTrader 4                    |
//| Research/demo first. Trading is DISABLED by default.              |
//+------------------------------------------------------------------+
#property strict
#property version   "1.20"
#property description "Intraday: range rejection and confirmed breakout continuation, BUY/SELL."
#property description "All-day operation; M15 context, M5 breakout confirmation and intraday exits."

input bool            EnableTrading       = false;     // Explicitly enable only after testing
input int             MagicNumber         = 29102601;
input ENUM_TIMEFRAMES SignalTimeframe     = PERIOD_M15;
input ENUM_TIMEFRAMES BreakoutConfirmTF   = PERIOD_M5;
input bool            EnableBreakoutTrades = true;
input int             RangeLookback       = 30;        // Closed candles used to define range
input int             ATRPeriod           = 14;
input int             RSIPeriod           = 14;
input double          EdgeFraction        = 0.20;      // Entry zone as fraction of range width
input double          MinRangeATR          = 1.50;      // Ignore ranges too narrow vs ATR
input double          MaxRangeATR          = 6.00;      // Ignore trends/oversized ranges
input double          BreakoutBufferATR    = 0.20;      // Close beyond edge invalidates range
input double          StopBufferATR        = 0.25;
input double          RiskPercent          = 0.25;      // Percent of balance at risk per trade
input double          RewardRisk           = 1.20;
input double          MaxSpreadPoints      = 30;
input int             SlippagePoints       =  3;
input int             MaxTradesPerDay      = 3;
input double          DailyLossLimitPct    = 2.0;       // Stop new entries after realized daily loss
input bool            UseRSIFilter         = true;
input int             BuyRSIMax            = 45;
input int             SellRSIMin           = 55;
input bool            CloseAtMidline       = false;     // If true, TP at range midpoint
input bool            OneTradePerSymbol    = true;
input bool            UseNetProfitLock     = true;
input double          NetProfitLockTrigger = 1.00;  // Account currency, after commission and swap
input double          NetProfitLockFloor   = 0.20;  // Minimum protected net profit, account currency
input int             LockRetrySeconds     = 5;
input int             MaxHoldingHours      = 8;
input bool            CloseBeforeDayEnd    = true;
input int             MinutesBeforeDayEnd  = 10;

datetime g_lastBarTime = 0;
int      g_dayKey = -1;
double   g_dayStartEquity = 0.0;
bool     g_dailyBlocked = false;

//+------------------------------------------------------------------+
int OnInit()
{
   if(RangeLookback < 10 || EdgeFraction <= 0.0 || EdgeFraction >= 0.5 ||
      RiskPercent <= 0.0 || RewardRisk <= 0.0)
   {
      Print("BITEY_RANGE_INIT_ERROR invalid inputs");
      return(INIT_PARAMETERS_INCORRECT);
   }
   ResetDailyState();
   Print("BITEY_RANGE_INIT symbol=", Symbol(),
         " tf=", EnumToString(SignalTimeframe),
         " trading=", (EnableTrading ? "ON" : "OFF"),
         " riskPct=", DoubleToString(RiskPercent, 2),
         " lookback=", RangeLookback,
         " breakoutTF=", EnumToString(BreakoutConfirmTF),
         " breakout=", (EnableBreakoutTrades ? "ON" : "OFF"),
         " maxHoldHours=", MaxHoldingHours,
         " closeBeforeDayEnd=", (CloseBeforeDayEnd ? "ON" : "OFF"));
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
   UpdateDailyState();
   ManageIntradayExit(); // Enforce intraday holding limit on every tick.
   ManageOpenPositions(); // Run protection on every tick.
   if(!IsNewSignalBar()) return;

   if(!EnableTrading)
   {
      Print("BITEY_RANGE_BLOCK reason=TRADING_DISABLED");
      return;
   }
   if(!IsTradeAllowed())
   {
      Print("BITEY_RANGE_BLOCK reason=TERMINAL_OR_ACCOUNT_TRADE_NOT_ALLOWED");
      return;
   }
   if(g_dailyBlocked)
   {
      Print("BITEY_RANGE_BLOCK reason=DAILY_LOSS_LIMIT");
      return;
   }
   if(GetSpreadPoints() > MaxSpreadPoints)
   {
      Print("BITEY_RANGE_BLOCK reason=SPREAD spreadPts=", DoubleToString(GetSpreadPoints(), 1));
      return;
   }
   if(CountTradesToday() >= MaxTradesPerDay)
   {
      Print("BITEY_RANGE_BLOCK reason=MAX_TRADES_PER_DAY");
      return;
   }
   if(OneTradePerSymbol && HasOpenPosition())
   {
      Print("BITEY_RANGE_BLOCK reason=POSITION_ALREADY_OPEN");
      return;
   }

   EvaluateRangeSignal();
}

//+------------------------------------------------------------------+
bool IsNewSignalBar()
{
   datetime t = iTime(Symbol(), SignalTimeframe, 0);
   if(t <= 0 || t == g_lastBarTime) return(false);
   g_lastBarTime = t;
   return(true);
}

void ResetDailyState()
{
   datetime now = TimeCurrent();
   g_dayKey = TimeYear(now) * 1000 + TimeDayOfYear(now);
   g_dayStartEquity = AccountEquity();
   g_dailyBlocked = false;
}

void UpdateDailyState()
{
   datetime now = TimeCurrent();
   int key = TimeYear(now) * 1000 + TimeDayOfYear(now);
   if(key != g_dayKey) ResetDailyState();

   double lossLimit = g_dayStartEquity * DailyLossLimitPct / 100.0;
   if(g_dayStartEquity > 0 && (g_dayStartEquity - AccountEquity()) >= lossLimit)
      g_dailyBlocked = true;
}

double GetSpreadPoints()
{
   RefreshRates();
   if(Point <= 0) return(999999);
   return((Ask - Bid) / Point);
}

bool HasOpenPosition()
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL)) return(true);
   }
   return(false);
}

int CountTradesToday()
{
   datetime dayStart = StrToTime(TimeToString(TimeCurrent(), TIME_DATE));
   int count = 0;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      if(OrderCloseTime() >= dayStart && (OrderType() == OP_BUY || OrderType() == OP_SELL)) count++;
   }
   for(int j=OrdersTotal()-1; j>=0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() == Symbol() && OrderMagicNumber() == MagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) &&
         OrderOpenTime() >= dayStart) count++;
   }
   return(count);
}

void EvaluateRangeSignal()
{
   int bars = iBars(Symbol(), SignalTimeframe);
   if(bars < RangeLookback + 5)
   {
      Print("BITEY_RANGE_BLOCK reason=INSUFFICIENT_HISTORY bars=", bars);
      return;
   }

   // Use completed candles only; exclude candle 1 from the range calculation
   // so the signal candle can test/reject a boundary without defining it.
   int hiIndex = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, RangeLookback, 2);
   int loIndex = iLowest(Symbol(), SignalTimeframe, MODE_LOW, RangeLookback, 2);
   if(hiIndex < 0 || loIndex < 0) return;

   double rangeHigh = iHigh(Symbol(), SignalTimeframe, hiIndex);
   double rangeLow  = iLow(Symbol(), SignalTimeframe, loIndex);
   double width = rangeHigh - rangeLow;
   double atr = iATR(Symbol(), SignalTimeframe, ATRPeriod, 1);
   if(width <= 0 || atr <= 0) return;

   double close1 = iClose(Symbol(), SignalTimeframe, 1);
   double open1  = iOpen(Symbol(), SignalTimeframe, 1);
   double high1  = iHigh(Symbol(), SignalTimeframe, 1);
   double low1   = iLow(Symbol(), SignalTimeframe, 1);
   double rsi    = iRSI(Symbol(), SignalTimeframe, RSIPeriod, PRICE_CLOSE, 1);

   // Confirmed breakout continuation: completed M15 close beyond range and M5 agreement.
   bool bullishBreakout = (close1 > rangeHigh + atr * BreakoutBufferATR);
   bool bearishBreakout = (close1 < rangeLow - atr * BreakoutBufferATR);
   if(bullishBreakout || bearishBreakout)
   {
      if(!EnableBreakoutTrades) { Print("BITEY_RANGE_BLOCK reason=BREAKOUT_TRADES_DISABLED"); return; }
      double m5Open = iOpen(Symbol(), BreakoutConfirmTF, 1);
      double m5Close = iClose(Symbol(), BreakoutConfirmTF, 1);
      if(m5Open <= 0 || m5Close <= 0) { Print("BITEY_RANGE_BLOCK reason=INSUFFICIENT_M5_CONFIRMATION_HISTORY"); return; }
      if(bullishBreakout && m5Close > m5Open)
      {
         double breakoutSL = NormalizeDouble(rangeHigh - atr * StopBufferATR, Digits);
         double breakoutRisk = Ask - breakoutSL;
         if(breakoutRisk > 0) SendEntry(OP_BUY, breakoutSL, NormalizeDouble(Ask + breakoutRisk * RewardRisk, Digits), rangeHigh, rangeLow, rsi);
         return;
      }
      if(bearishBreakout && m5Close < m5Open)
      {
         double breakoutSL = NormalizeDouble(rangeLow + atr * StopBufferATR, Digits);
         double breakoutRisk = breakoutSL - Bid;
         if(breakoutRisk > 0) SendEntry(OP_SELL, breakoutSL, NormalizeDouble(Bid - breakoutRisk * RewardRisk, Digits), rangeHigh, rangeLow, rsi);
         return;
      }
      Print("BITEY_RANGE_BLOCK reason=BREAKOUT_WITHOUT_M5_CONFIRMATION");
      return;
   }

   if(width < atr * MinRangeATR || width > atr * MaxRangeATR)
   {
      Print("BITEY_RANGE_BLOCK reason=RANGE_WIDTH widthATR=", DoubleToString(width/atr, 2));
      return;
   }

   double buyZoneTop = rangeLow + width * EdgeFraction;
   double sellZoneBottom = rangeHigh - width * EdgeFraction;

   bool bullishRejection = (low1 <= buyZoneTop && close1 > open1 && close1 > rangeLow);
   bool bearishRejection = (high1 >= sellZoneBottom && close1 < open1 && close1 < rangeHigh);

   if(UseRSIFilter)
   {
      bullishRejection = bullishRejection && rsi <= BuyRSIMax;
      bearishRejection = bearishRejection && rsi >= SellRSIMin;
   }

   if(bullishRejection && !bearishRejection)
   {
      double sl = NormalizeDouble(rangeLow - atr * StopBufferATR, Digits);
      double entry = Ask;
      double riskDist = entry - sl;
      if(riskDist <= 0) return;
      double tp = CloseAtMidline ? (rangeLow + rangeHigh) / 2.0 : entry + riskDist * RewardRisk;
      if(tp <= entry) return;
      SendEntry(OP_BUY, sl, NormalizeDouble(tp, Digits), rangeHigh, rangeLow, rsi);
      return;
   }

   if(bearishRejection && !bullishRejection)
   {
      double sl = NormalizeDouble(rangeHigh + atr * StopBufferATR, Digits);
      double entry = Bid;
      double riskDist = sl - entry;
      if(riskDist <= 0) return;
      double tp = CloseAtMidline ? (rangeLow + rangeHigh) / 2.0 : entry - riskDist * RewardRisk;
      if(tp >= entry) return;
      SendEntry(OP_SELL, sl, NormalizeDouble(tp, Digits), rangeHigh, rangeLow, rsi);
      return;
   }

   Print("BITEY_RANGE_SIGNAL action=HOLD reason=NO_CONFIRMED_EDGE_REJECTION",
         " rangeHigh=", DoubleToString(rangeHigh, Digits),
         " rangeLow=", DoubleToString(rangeLow, Digits),
         " rsi=", DoubleToString(rsi, 1));
}

//+------------------------------------------------------------------+
void SendEntry(int type, double sl, double tp, double rangeHigh, double rangeLow, double rsi)
{
   RefreshRates();
   double entry = (type == OP_BUY) ? Ask : Bid;
   double stopDistance = MathAbs(entry - sl);
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   if(stopDistance <= stopLevel || MathAbs(tp-entry) <= stopLevel)
   {
      Print("BITEY_RANGE_BLOCK reason=STOP_LEVEL_TOO_CLOSE");
      return;
   }

   double lots = CalculateLots(stopDistance);
   if(lots <= 0)
   {
      Print("BITEY_RANGE_BLOCK reason=LOT_SIZE_INVALID");
      return;
   }

   string side = (type == OP_BUY) ? "BUY" : "SELL";
   string comment = "BiteyRange_v1.2";
   ResetLastError();
   int ticket = OrderSend(Symbol(), type, lots, entry, SlippagePoints, sl, tp,
                          comment, MagicNumber, 0, clrNONE);
   if(ticket < 0)
   {
      Print("BITEY_RANGE_ORDER_ERROR side=", side, " err=", GetLastError(),
            " lots=", DoubleToString(lots, 2));
      return;
   }

   Print("BITEY_RANGE_ORDER side=", side, " ticket=", ticket,
         " lots=", DoubleToString(lots, 2),
         " entry=", DoubleToString(entry, Digits),
         " sl=", DoubleToString(sl, Digits),
         " tp=", DoubleToString(tp, Digits),
         " rangeHigh=", DoubleToString(rangeHigh, Digits),
         " rangeLow=", DoubleToString(rangeLow, Digits),
         " rsi=", DoubleToString(rsi, 1));
}

double CalculateLots(double stopDistance)
{
   double riskMoney = AccountBalance() * RiskPercent / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(riskMoney <= 0 || tickValue <= 0 || tickSize <= 0 || stopDistance <= 0) return(0);

   double lossPerLot = (stopDistance / tickSize) * tickValue;
   if(lossPerLot <= 0) return(0);
   double rawLots = riskMoney / lossPerLot;

   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);
   if(lotStep <= 0) return(0);

   // Never round upward beyond calculated risk.
   double lots = MathFloor(rawLots / lotStep) * lotStep;
   lots = MathMin(lots, maxLot);
   if(lots < minLot) return(0);

   int lotDigits = 2;
   if(lotStep >= 1.0) lotDigits = 0;
   else if(lotStep >= 0.1) lotDigits = 1;
   else if(lotStep < 0.01) lotDigits = 3;
   return(NormalizeDouble(lots, lotDigits));
}

void ManageIntradayExit()
{
   datetime now = TimeCurrent();
   datetime dayStart = StrToTime(TimeToString(now, TIME_DATE));
   int secondsRemaining = 86400 - (int)(now - dayStart);
   bool dayEndExit = (CloseBeforeDayEnd && MinutesBeforeDayEnd > 0 && secondsRemaining <= MinutesBeforeDayEnd * 60);
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;
      bool holdingLimit = (MaxHoldingHours > 0 && (now - OrderOpenTime()) >= MaxHoldingHours * 3600);
      if(!dayEndExit && !holdingLimit) continue;
      RefreshRates();
      double closePrice = (type == OP_BUY) ? Bid : Ask;
      ResetLastError();
      if(!OrderClose(OrderTicket(), OrderLots(), closePrice, SlippagePoints, clrNONE))
         Print("BITEY_RANGE_INTRADAY_EXIT_ERROR ticket=", OrderTicket(), " err=", GetLastError());
      else Print("BITEY_RANGE_INTRADAY_EXIT ticket=", OrderTicket(), " reason=", (dayEndExit ? "SERVER_DAY_END" : "MAX_HOLDING_HOURS"));
   }
}

void ManageOpenPositions()
{
   if(!UseNetProfitLock || NetProfitLockTrigger <= 0.0 || NetProfitLockFloor < 0.0) return;
   static datetime lastAttempt = 0;
   if(TimeCurrent() - lastAttempt < LockRetrySeconds) return;

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != MagicNumber) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      double netNow = OrderProfit() + OrderSwap() + OrderCommission();
      if(netNow < NetProfitLockTrigger) continue;

      double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
      double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
      if(tickValue <= 0.0 || tickSize <= 0.0) continue;

      double requiredGross = NetProfitLockFloor - OrderSwap() - OrderCommission();
      double moneyPerPriceUnit = (tickValue / tickSize) * OrderLots();
      if(moneyPerPriceUnit <= 0.0) continue;
      double priceDistance = requiredGross / moneyPerPriceUnit;
      double candidate = (type == OP_BUY)
                         ? OrderOpenPrice() + priceDistance
                         : OrderOpenPrice() - priceDistance;

      RefreshRates();
      double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
      candidate = NormalizeDouble(candidate, Digits);

      if(type == OP_BUY)
      {
         if(candidate <= OrderStopLoss() || candidate >= Bid - stopLevel) continue;
      }
      else
      {
         if(OrderStopLoss() > 0.0 && candidate >= OrderStopLoss()) continue;
         if(candidate <= Ask + stopLevel) continue;
      }

      lastAttempt = TimeCurrent();
      ResetLastError();
      if(!OrderModify(OrderTicket(), OrderOpenPrice(), candidate, OrderTakeProfit(), 0, clrNONE))
         Print("BITEY_RANGE_LOCK_ERROR ticket=", OrderTicket(), " err=", GetLastError());
      else
         Print("BITEY_RANGE_NET_LOCK ticket=", OrderTicket(),
               " netNow=", DoubleToString(netNow, 2),
               " protectedFloor=", DoubleToString(NetProfitLockFloor, 2),
               " newSL=", DoubleToString(candidate, Digits));
   }
}
//+------------------------------------------------------------------+
