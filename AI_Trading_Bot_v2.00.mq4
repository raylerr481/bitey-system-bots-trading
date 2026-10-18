//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.00.mq4                                        |
//| Diagnostic trend/pullback EA for MetaTrader 4                    |
//| Designed for controlled backtesting and iterative optimization   |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Diagnostic trend/pullback EA with ATR risk management."

//------------------------- General ----------------------------------
input int      MagicNumber            = 26093001;
input bool     AllowBuy               = true;
input bool     AllowSell              = true;
input bool     OnePositionOnly        = true;
input bool     TradeOnNewBarOnly      = true;

//------------------------- Signal -----------------------------------
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_H1;
input int      FastEMA                 = 50;
input int      SlowEMA                 = 200;
input int      RSIPeriod               = 14;
input double   BuyRSIMin               = 48.0;
input double   BuyRSIMax               = 68.0;
input double   SellRSIMin              = 32.0;
input double   SellRSIMax              = 52.0;
input int      ATRPeriod               = 14;
input double   MinATRPoints            = 25.0;
input double   PullbackATR             = 0.75;
input bool     RequireEMASlope         = true;

//------------------------- Risk ------------------------------------
input bool     UseRiskPercent          = true;
input double   RiskPercent             = 1.0;
input double   FixedLots               = 0.01;
input double   SL_ATR                  = 1.8;
input double   TP_ATR                  = 2.7;
input bool     UseTrailingStop         = true;
input double   TrailStartATR           = 1.2;
input double   TrailATR                = 1.0;

//------------------------- Filters ----------------------------------
input double   MaxSpreadPoints         = 35.0;
input bool     UseSessionFilter        = false;
input int      SessionStartHour        = 7;
input int      SessionEndHour          = 20;
input int      MaxBarsInTrade          = 0;

//------------------------- Diagnostics ------------------------------
input bool     DebugMode               = true;
input bool     CommentOnChart          = true;
input bool     PrintEveryBar           = false;

//------------------------- State -----------------------------------
datetime g_lastBarTime = 0;
datetime g_lastSignalBar = 0;
int      g_buyCandidates = 0;
int      g_sellCandidates = 0;
int      g_buyExecuted = 0;
int      g_sellExecuted = 0;
int      g_rejectedSpread = 0;
int      g_rejectedSession = 0;
int      g_rejectedPosition = 0;
int      g_rejectedSignal = 0;

//+------------------------------------------------------------------+
//| Utility                                                          |
//+------------------------------------------------------------------+
void D(string msg)
{
   if(DebugMode) Print("[AI-BOT] ", msg);
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, Digits);
}

double CurrentSpreadPoints()
{
   return (Ask - Bid) / Point;
}

bool IsNewBar()
{
   datetime t = iTime(Symbol(), SignalTimeframe, 0);
   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

bool SessionAllowed()
{
   if(!UseSessionFilter) return true;

   int h = TimeHour(TimeCurrent());

   if(SessionStartHour < SessionEndHour)
      return (h >= SessionStartHour && h < SessionEndHour);

   return (h >= SessionStartHour || h < SessionEndHour);
}

int CountOpenPositions()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() == Symbol() &&
         OrderMagicNumber() == MagicNumber &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL))
         count++;
   }

   return count;
}

double LotDigits()
{
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(step >= 1.0)   return 0;
   if(step >= 0.1)   return 1;
   if(step >= 0.01)  return 2;
   return 3;
}

double CalculateLots(double stopDistancePrice)
{
   if(!UseRiskPercent)
      return NormalizeDouble(FixedLots, (int)LotDigits());

   if(stopDistancePrice <= 0)
      return NormalizeDouble(FixedLots, (int)LotDigits());

   double riskMoney = AccountBalance() * RiskPercent / 100.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickValue <= 0 || tickSize <= 0)
      return NormalizeDouble(FixedLots, (int)LotDigits());

   double moneyPerLot = (stopDistancePrice / tickSize) * tickValue;

   if(moneyPerLot <= 0)
      return NormalizeDouble(FixedLots, (int)LotDigits());

   double lots = riskMoney / moneyPerLot;

   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step   = MarketInfo(Symbol(), MODE_LOTSTEP);

   lots = MathMax(minLot, MathMin(maxLot, lots));

   if(step > 0)
      lots = MathFloor(lots / step) * step;

   lots = MathMax(minLot, lots);

   return NormalizeDouble(lots, (int)LotDigits());
}

bool StopsValid(int type, double openPrice, double sl, double tp)
{
   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   double minDistance = stopLevel * Point;

   if(type == OP_BUY)
   {
      if(openPrice - sl < minDistance) return false;
      if(tp - openPrice < minDistance) return false;
   }
   else if(type == OP_SELL)
   {
      if(sl - openPrice < minDistance) return false;
      if(openPrice - tp < minDistance) return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Signal engine                                                    |
//+------------------------------------------------------------------+
bool BuySignal(int shift, string &reason)
{
   reason = "";

   double fast = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(Symbol(), SignalTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, shift);

   double fastPrev = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, shift + 1);

   double close = iClose(Symbol(), SignalTimeframe, shift);
   double low   = iLow(Symbol(), SignalTimeframe, shift);
   double rsi   = iRSI(Symbol(), SignalTimeframe, RSIPeriod, PRICE_CLOSE, shift);
   double atr   = iATR(Symbol(), SignalTimeframe, ATRPeriod, shift);

   if(fast <= slow)
   {
      reason = "BUY_REJECT_TREND";
      return false;
   }

   if(RequireEMASlope && fast <= fastPrev)
   {
      reason = "BUY_REJECT_EMA_SLOPE";
      return false;
   }

   if(rsi < BuyRSIMin || rsi > BuyRSIMax)
   {
      reason = "BUY_REJECT_RSI";
      return false;
   }

   if(atr <= 0 || atr / Point < MinATRPoints)
   {
      reason = "BUY_REJECT_ATR";
      return false;
   }

   // Pullback/reclaim: price is near or above the fast EMA.
   if(close < fast - PullbackATR * atr)
   {
      reason = "BUY_REJECT_PULLBACK";
      return false;
   }

   // The previous candle must not be deeply bearish.
   double prevOpen  = iOpen(Symbol(), SignalTimeframe, shift);
   double prevClose = iClose(Symbol(), SignalTimeframe, shift);

   if(prevClose < prevOpen && close <= fast)
   {
      reason = "BUY_REJECT_CANDLE";
      return false;
   }

   return true;
}

bool SellSignal(int shift, string &reason)
{
   reason = "";

   double fast = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, shift);
   double slow = iMA(Symbol(), SignalTimeframe, SlowEMA, 0, MODE_EMA, PRICE_CLOSE, shift);

   double fastPrev = iMA(Symbol(), SignalTimeframe, FastEMA, 0, MODE_EMA, PRICE_CLOSE, shift + 1);

   double close = iClose(Symbol(), SignalTimeframe, shift);
   double rsi   = iRSI(Symbol(), SignalTimeframe, RSIPeriod, PRICE_CLOSE, shift);
   double atr   = iATR(Symbol(), SignalTimeframe, ATRPeriod, shift);

   if(fast >= slow)
   {
      reason = "SELL_REJECT_TREND";
      return false;
   }

   if(RequireEMASlope && fast >= fastPrev)
   {
      reason = "SELL_REJECT_EMA_SLOPE";
      return false;
   }

   if(rsi < SellRSIMin || rsi > SellRSIMax)
   {
      reason = "SELL_REJECT_RSI";
      return false;
   }

   if(atr <= 0 || atr / Point < MinATRPoints)
   {
      reason = "SELL_REJECT_ATR";
      return false;
   }

   if(close > fast + PullbackATR * atr)
   {
      reason = "SELL_REJECT_PULLBACK";
      return false;
   }

   double prevOpen  = iOpen(Symbol(), SignalTimeframe, shift);
   double prevClose = iClose(Symbol(), SignalTimeframe, shift);

   if(prevClose > prevOpen && close >= fast)
   {
      reason = "SELL_REJECT_CANDLE";
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Execution                                                        |
//+------------------------------------------------------------------+
bool OpenTrade(int type, double atr)
{
   RefreshRates();

   double price = (type == OP_BUY) ? Ask : Bid;

   double slDistance = atr * SL_ATR;
   double tpDistance = atr * TP_ATR;

   double sl = 0;
   double tp = 0;

   if(type == OP_BUY)
   {
      sl = NormalizePrice(price - slDistance);
      tp = NormalizePrice(price + tpDistance);
   }
   else
   {
      sl = NormalizePrice(price + slDistance);
      tp = NormalizePrice(price - tpDistance);
   }

   if(!StopsValid(type, price, sl, tp))
   {
      D("ENTRY REJECTED: broker stop-level too large.");
      return false;
   }

   double lots = CalculateLots(slDistance);

   ResetLastError();

   int ticket = OrderSend(
      Symbol(),
      type,
      lots,
      price,
      10,
      sl,
      tp,
      "AI_BOT_v2",
      MagicNumber,
      0,
      (type == OP_BUY ? clrBlue : clrRed)
   );

   if(ticket < 0)
   {
      int err = GetLastError();
      D(StringFormat("OrderSend failed. type=%d error=%d lots=%.2f price=%.*f sl=%.*f tp=%.*f",
                     type, err, lots, Digits, price, Digits, sl, Digits, tp));
      return false;
   }

   if(type == OP_BUY) g_buyExecuted++;
   else g_sellExecuted++;

   D(StringFormat("ENTRY EXECUTED ticket=%d type=%s lots=%.2f SL=%.*f TP=%.*f",
                  ticket,
                  type == OP_BUY ? "BUY" : "SELL",
                  lots,
                  Digits, sl,
                  Digits, tp));

   return true;
}

//+------------------------------------------------------------------+
//| Position management                                               |
//+------------------------------------------------------------------+
void ManagePositions()
{
   double atr = iATR(Symbol(), SignalTimeframe, ATRPeriod, 1);
   if(atr <= 0) return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol() ||
         OrderMagicNumber() != MagicNumber)
         continue;

      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      if(MaxBarsInTrade > 0)
      {
         int barsHeld = iBarShift(Symbol(), SignalTimeframe, OrderOpenTime(), false);

         if(barsHeld >= MaxBarsInTrade)
         {
            RefreshRates();

            bool closed = false;

            if(OrderType() == OP_BUY)
               closed = OrderClose(OrderTicket(), OrderLots(), Bid, 10, clrOrange);
            else
               closed = OrderClose(OrderTicket(), OrderLots(), Ask, 10, clrOrange);

            if(closed)
               D("Position closed by MaxBarsInTrade.");

            continue;
         }
      }

      if(!UseTrailingStop)
         continue;

      RefreshRates();

      double profitDistance = 0;
      double newSL = 0;

      if(OrderType() == OP_BUY)
      {
         profitDistance = Bid - OrderOpenPrice();

         if(profitDistance < TrailStartATR * atr)
            continue;

         newSL = NormalizePrice(Bid - TrailATR * atr);

         if(newSL > OrderStopLoss() && newSL < Bid)
         {
            if(!OrderModify(OrderTicket(),
                            OrderOpenPrice(),
                            newSL,
                            OrderTakeProfit(),
                            0,
                            clrBlue))
            {
               D(StringFormat("BUY trailing failed error=%d", GetLastError()));
            }
         }
      }
      else
      {
         profitDistance = OrderOpenPrice() - Ask;

         if(profitDistance < TrailStartATR * atr)
            continue;

         newSL = NormalizePrice(Ask + TrailATR * atr);

         if((OrderStopLoss() == 0 || newSL < OrderStopLoss()) && newSL > Ask)
         {
            if(!OrderModify(OrderTicket(),
                            OrderOpenPrice(),
                            newSL,
                            OrderTakeProfit(),
                            0,
                            clrRed))
            {
               D(StringFormat("SELL trailing failed error=%d", GetLastError()));
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Diagnostics                                                      |
//+------------------------------------------------------------------+
void UpdateChartComment(string buyReason, string sellReason)
{
   if(!CommentOnChart) return;

   string txt = "";
   txt += "AI Trading Bot v2.00\n";
   txt += "Symbol: " + Symbol() + " TF: H1\n";
   txt += "Spread: " + DoubleToString(CurrentSpreadPoints(), 1) + " pts\n";
   txt += "BUY candidates: " + IntegerToString(g_buyCandidates) +
          " executed: " + IntegerToString(g_buyExecuted) + "\n";
   txt += "SELL candidates: " + IntegerToString(g_sellCandidates) +
          " executed: " + IntegerToString(g_sellExecuted) + "\n";
   txt += "Rejected spread: " + IntegerToString(g_rejectedSpread) + "\n";
   txt += "Rejected session: " + IntegerToString(g_rejectedSession) + "\n";
   txt += "Rejected position: " + IntegerToString(g_rejectedPosition) + "\n";
   txt += "Last BUY: " + buyReason + "\n";
   txt += "Last SELL: " + sellReason + "\n";
   txt += "Balance: " + DoubleToString(AccountBalance(), 2) +
          " Equity: " + DoubleToString(AccountEquity(), 2);

   Comment(txt);
}

//+------------------------------------------------------------------+
//| Main signal evaluation                                           |
//+------------------------------------------------------------------+
void EvaluateSignals()
{
   if(iBars(Symbol(), SignalTimeframe) < SlowEMA + 20)
      return;

   string buyReason = "";
   string sellReason = "";

   bool buy = false;
   bool sell = false;

   int shift = 1; // closed candle

   if(AllowBuy)
   {
      buy = BuySignal(shift, buyReason);
      if(buy) g_buyCandidates++;
   }

   if(AllowSell)
   {
      sell = SellSignal(shift, sellReason);
      if(sell) g_sellCandidates++;
   }

   if(PrintEveryBar)
   {
      D(StringFormat("BAR %s BUY=%s [%s] SELL=%s [%s]",
                     TimeToString(iTime(Symbol(), SignalTimeframe, shift)),
                     buy ? "YES" : "NO", buyReason,
                     sell ? "YES" : "NO", sellReason));
   }

   if(!buy && !sell)
   {
      g_rejectedSignal++;
      UpdateChartComment(buyReason, sellReason);
      return;
   }

   if(!SessionAllowed())
   {
      g_rejectedSession++;
      D("SIGNAL REJECTED: session filter.");
      UpdateChartComment(buyReason, sellReason);
      return;
   }

   double spread = CurrentSpreadPoints();

   if(spread > MaxSpreadPoints)
   {
      g_rejectedSpread++;
      D(StringFormat("SIGNAL REJECTED: spread %.1f > %.1f points",
                     spread, MaxSpreadPoints));
      UpdateChartComment(buyReason, sellReason);
      return;
   }

   if(OnePositionOnly && CountOpenPositions() > 0)
   {
      g_rejectedPosition++;
      D("SIGNAL REJECTED: position already open.");
      UpdateChartComment(buyReason, sellReason);
      return;
   }

   double atr = iATR(Symbol(), SignalTimeframe, ATRPeriod, shift);

   if(atr <= 0)
      return;

   // If both conditions somehow occur, choose the stronger RSI distance
   // from the neutral 50 level.
   if(buy && sell)
   {
      double rsi = iRSI(Symbol(), SignalTimeframe, RSIPeriod, PRICE_CLOSE, shift);

      if(rsi >= 50)
         sell = false;
      else
         buy = false;
   }

   if(buy)
   {
      g_lastSignalBar = iTime(Symbol(), SignalTimeframe, shift);
      OpenTrade(OP_BUY, atr);
   }
   else if(sell)
   {
      g_lastSignalBar = iTime(Symbol(), SignalTimeframe, shift);
      OpenTrade(OP_SELL, atr);
   }

   UpdateChartComment(buyReason, sellReason);
}

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   g_lastBarTime = 0;

   D("==========================================");
   D("AI Trading Bot v2.00 initialized.");
   D("Diagnostic trend/pullback strategy.");
   D(StringFormat("EMA=%d/%d RSI=%d ATR=%d",
                  FastEMA, SlowEMA, RSIPeriod, ATRPeriod));
   D(StringFormat("SL=%.2f ATR TP=%.2f ATR Risk=%.2f%%",
                  SL_ATR, TP_ATR, RiskPercent));
   D("==========================================");

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
   D(StringFormat("FINAL STATS: BUY candidates=%d executed=%d | SELL candidates=%d executed=%d | spread rejects=%d | session rejects=%d | position rejects=%d",
                  g_buyCandidates, g_buyExecuted,
                  g_sellCandidates, g_sellExecuted,
                  g_rejectedSpread, g_rejectedSession,
                  g_rejectedPosition));
}

//+------------------------------------------------------------------+
//| Expert tick                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();

   if(TradeOnNewBarOnly)
   {
      if(!IsNewBar())
         return;
   }

   EvaluateSignals();
}
//+------------------------------------------------------------------+
