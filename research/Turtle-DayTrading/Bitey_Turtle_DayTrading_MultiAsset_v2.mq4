//+------------------------------------------------------------------+
//| Bitey_Turtle_DayTrading_MultiAsset_v2.mq4                         |
//| Independent research EA. Multi-symbol intraday breakout system.  |
//| Compile in MetaEditor; validate contract metadata and demo first. |
//+------------------------------------------------------------------+
#property strict
#property version "2.00"
#property description "Multi-asset intraday Donchian breakout with H1 trend filter, ATR SL, R-multiple TP and trailing protection."

input string SymbolsCSV = "EURUSD,GBPUSD,USDJPY,XAUUSD";
input ENUM_TIMEFRAMES SignalTimeframe = PERIOD_M15;
input ENUM_TIMEFRAMES TrendTimeframe = PERIOD_H1;
input int EntryChannelBars = 20;
input int ATRPeriod = 14;
input int FastEMA = 50;
input int SlowEMA = 200;
input double StopATRMultiple = 1.5;
input double TakeProfitRMultiple = 2.0;
input double TrailATRMultiple = 1.0;
input double BreakEvenAtR = 1.0;
input double ReferenceCapitalUSD = 500.0;
input double RiskBudgetUSD = 1.25;
input double DailyLossLimitUSD = 10.0;
input int MaxOpenPositionsTotal = 3;
input int MaxTradesPerDay = 6;
input int MagicNumber = 20261022;
input int MaxSpreadPoints = 80;
input int MaxQuoteAgeSeconds = 120;
input int SlippagePoints = 5;
input bool EnableTrading = true;
input bool CloseAtSessionEnd = true;
input int SessionEndHour = 22;   // Broker server time
input int SessionEndMinute = 45; // Broker server time
input bool AllowNewTradesAfterSessionEnd = false;
input double RoundTurnCommissionPerLotUSD = 0.0; // Zero = unknown/not included
input double ExpectedSwapCostPerLotUSD = 0.0;    // Zero = unknown/not included
input string OrderCommentText = "Bitey DayTrading v2";

string g_symbols[];
datetime g_lastBar[];
int g_symbolCount = 0;
int g_lastDayKey = -1;

int OnInit()
{
   if(ReferenceCapitalUSD <= 0 || RiskBudgetUSD <= 0 || DailyLossLimitUSD <= 0 ||
      MaxOpenPositionsTotal < 1 || MaxTradesPerDay < 1 || EntryChannelBars < 2 ||
      ATRPeriod < 2 || StopATRMultiple <= 0 || TakeProfitRMultiple <= 0 ||
      TrailATRMultiple <= 0 || FastEMA < 2 || SlowEMA <= FastEMA ||
      MaxSpreadPoints < 1 || MaxQuoteAgeSeconds < 1 ||
      SessionEndHour < 0 || SessionEndHour > 23 ||
      SessionEndMinute < 0 || SessionEndMinute > 59)
   {
      Print("INIT_FAILED | reason=INVALID_INPUTS");
      return(INIT_PARAMETERS_INCORRECT);
   }

   g_symbolCount = StringSplit(SymbolsCSV, ',', g_symbols);
   if(g_symbolCount < 1)
   {
      Print("INIT_FAILED | reason=EMPTY_SYMBOL_LIST");
      return(INIT_PARAMETERS_INCORRECT);
   }
   ArrayResize(g_lastBar, g_symbolCount);
   ArrayInitialize(g_lastBar, 0);
   for(int i=0; i<g_symbolCount; i++)
   {
      StringTrimLeft(g_symbols[i]);
      StringTrimRight(g_symbols[i]);
      if(StringLen(g_symbols[i]) == 0) continue;
      bool selected = SymbolSelect(g_symbols[i], true);
      Print("SYMBOL_CONFIG | symbol=", g_symbols[i], " selected=", selected,
            " | broker suffixes/prefixes must match SymbolsCSV exactly");
   }
   EventSetTimer(5);
   Print("BITEY_DAYTRADING_INIT | version=2.00 | enabled=", EnableTrading,
         " | symbols=", SymbolsCSV, " | signalTF=", EnumToString(SignalTimeframe),
         " | trendTF=", EnumToString(TrendTimeframe),
         " | capitalUSD=", DoubleToString(ReferenceCapitalUSD,2),
         " | riskPerTradeUSD=", DoubleToString(RiskBudgetUSD,2),
         " | dailyLossLimitUSD=", DoubleToString(DailyLossLimitUSD,2),
         " | maxPositions=", MaxOpenPositionsTotal,
         " | endSession=", SessionEndHour, ":", SessionEndMinute,
         " | account type is not a gate");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick() { RunScanner(); }
void OnTimer() { RunScanner(); }

void RunScanner()
{
   int dayKey = TimeYear(TimeCurrent())*10000 + TimeMonth(TimeCurrent())*100 + TimeDay(TimeCurrent());
   if(dayKey != g_lastDayKey) g_lastDayKey = dayKey;

   if(CloseAtSessionEnd && IsPastSessionEnd())
   {
      if(!AllowNewTradesAfterSessionEnd)
      {
         CloseAllOwnPositions("SESSION_END");
         return;
      }
   }

   ManageOpenPositions();
   if(!EnableTrading) return;
   if(!IsTradeAllowed())
   {
      PrintGateOnce("MT4_OR_EA_TRADING_NOT_ALLOWED");
      return;
   }
   if(IsPastSessionEnd() && !AllowNewTradesAfterSessionEnd) return;
   if(TodayNetUSD() <= -DailyLossLimitUSD)
   {
      PrintGateOnce("DAILY_LOSS_LIMIT");
      return;
   }
   if(TodayEntryCount() >= MaxTradesPerDay)
   {
      PrintGateOnce("MAX_TRADES_PER_DAY");
      return;
   }
   if(CountOwnPositionsTotal() >= MaxOpenPositionsTotal) return;

   for(int i=0; i<g_symbolCount; i++)
   {
      string sym = g_symbols[i];
      if(StringLen(sym) == 0 || !SymbolSelect(sym,true)) continue;
      datetime bar = iTime(sym, SignalTimeframe, 0);
      if(bar <= 0) { PrintSymbolGate(sym,"NO_HISTORY_OR_SYMBOL_UNAVAILABLE"); continue; }
      if(bar == g_lastBar[i]) continue;
      g_lastBar[i] = bar;
      if(FindOwnPosition(sym) > 0) continue;
      if(CountOwnPositionsTotal() >= MaxOpenPositionsTotal) return;
      if(TodayEntryCount() >= MaxTradesPerDay) return;
      if(TodayNetUSD() <= -DailyLossLimitUSD) return;
      EvaluateSymbol(sym);
   }
}

void EvaluateSymbol(string sym)
{
   int bars = iBars(sym, SignalTimeframe);
   if(bars < EntryChannelBars + ATRPeriod + 10 ||
      iBars(sym,TrendTimeframe) < SlowEMA + 10)
   {
      PrintSymbolGate(sym,"INSUFFICIENT_HISTORY");
      return;
   }

   double close1 = iClose(sym,SignalTimeframe,1);
   double atr = iATR(sym,SignalTimeframe,ATRPeriod,1);
   int hiShift = iHighest(sym,SignalTimeframe,MODE_HIGH,EntryChannelBars,2);
   int loShift = iLowest(sym,SignalTimeframe,MODE_LOW,EntryChannelBars,2);
   if(close1 <= 0 || atr <= 0 || hiShift < 0 || loShift < 0)
   {
      PrintSymbolGate(sym,"INVALID_SIGNAL_DATA");
      return;
   }
   double channelHigh = iHigh(sym,SignalTimeframe,hiShift);
   double channelLow = iLow(sym,SignalTimeframe,loShift);
   double emaFast = iMA(sym,TrendTimeframe,FastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double emaSlow = iMA(sym,TrendTimeframe,SlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   bool buyBreak = close1 > channelHigh && emaFast > emaSlow;
   bool sellBreak = close1 < channelLow && emaFast < emaSlow;
   if(!buyBreak && !sellBreak)
   {
      Print("NO_ENTRY | reason=NO_BREAKOUT_OR_H1_TREND_NOT_CONFIRMED | symbol=",sym,
            " close1=",DoubleToString(close1,(int)MarketInfo(sym,MODE_DIGITS)),
            " channelHigh=",DoubleToString(channelHigh,(int)MarketInfo(sym,MODE_DIGITS)),
            " channelLow=",DoubleToString(channelLow,(int)MarketInfo(sym,MODE_DIGITS)),
            " emaFast=",DoubleToString(emaFast,5)," emaSlow=",DoubleToString(emaSlow,5));
      return;
   }

   double spread = MarketInfo(sym,MODE_SPREAD);
   datetime quoteTime = (datetime)MarketInfo(sym,MODE_TIME);
   int quoteAge = (quoteTime > 0 ? (int)(TimeCurrent()-quoteTime) : 2147483647);
   if(spread < 0 || spread > MaxSpreadPoints)
   {
      PrintSymbolGate(sym,"SPREAD_LIMIT");
      return;
   }
   if(quoteTime <= 0 || quoteAge < 0 || quoteAge > MaxQuoteAgeSeconds)
   {
      PrintSymbolGate(sym,"STALE_OR_INVALID_QUOTE");
      return;
   }
   PlaceOrder(sym,buyBreak ? OP_BUY : OP_SELL,atr,close1,channelHigh,channelLow);
}

void PlaceOrder(string sym,int type,double atr,double signalClose,double channelHigh,double channelLow)
{
   RefreshRates();
   double ask=MarketInfo(sym,MODE_ASK), bid=MarketInfo(sym,MODE_BID);
   double point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double tickSizePoints=MarketInfo(sym,MODE_TICKSIZE);
   double tickValue=MarketInfo(sym,MODE_TICKVALUE);
   double minLot=MarketInfo(sym,MODE_MINLOT), maxLot=MarketInfo(sym,MODE_MAXLOT);
   double lotStep=MarketInfo(sym,MODE_LOTSTEP);
   double stopLevel=MarketInfo(sym,MODE_STOPLEVEL)*point;
   if(ask<=0 || bid<=0 || point<=0 || tickSizePoints<=0 || tickValue<=0 ||
      minLot<=0 || maxLot<minLot || lotStep<=0)
   {
      PrintSymbolGate(sym,"INVALID_BROKER_RISK_METADATA");
      return;
   }

   double entry=(type==OP_BUY ? ask : bid);
   double tickSizePrice=tickSizePoints*point;
   double stopDistance=MathMax(atr*StopATRMultiple,stopLevel+2*point);
   double rawSL=(type==OP_BUY ? entry-stopDistance : entry+stopDistance);
   double sl=NormalizeDouble(MathRound(rawSL/tickSizePrice)*tickSizePrice,digits);
   double actualDistance=MathAbs(entry-sl);
   double rawTP=(type==OP_BUY ? entry+actualDistance*TakeProfitRMultiple :
                                entry-actualDistance*TakeProfitRMultiple);
   double tp=NormalizeDouble(MathRound(rawTP/tickSizePrice)*tickSizePrice,digits);
   double lossPerLot=(actualDistance/tickSizePrice)*tickValue;
   double costsPerLot=RoundTurnCommissionPerLotUSD+ExpectedSwapCostPerLotUSD;
   if(RoundTurnCommissionPerLotUSD<0 || ExpectedSwapCostPerLotUSD<0 || lossPerLot<=0)
   {
      PrintSymbolGate(sym,"INVALID_COST_OR_RISK_ESTIMATE");
      return;
   }
   double totalRiskPerLot=lossPerLot+costsPerLot;
   double rawLots=RiskBudgetUSD/totalRiskPerLot;
   if(rawLots<minLot)
   {
      Print("ENTRY_BLOCKED | reason=MINIMUM_LOT_EXCEEDS_RISK_BUDGET | symbol=",sym,
            " riskBudgetUSD=",DoubleToString(RiskBudgetUSD,2),
            " estimatedMinLotRiskUSD=",DoubleToString(totalRiskPerLot*minLot,2));
      return;
   }
   double lots=MathMin(maxLot,MathFloor(rawLots/lotStep+1e-8)*lotStep);
   int lotDigits=(lotStep>=1?0:(lotStep>=0.1?1:(lotStep>=0.01?2:3)));
   lots=NormalizeDouble(lots,lotDigits);
   double estimatedRisk=lots*totalRiskPerLot;
   if(lots<minLot || estimatedRisk>RiskBudgetUSD+0.01)
   {
      PrintSymbolGate(sym,"RISK_BUDGET_OR_LOT_STEP");
      return;
   }
   ResetLastError();
   double marginAfter=AccountFreeMarginCheck(sym,type,lots);
   if(marginAfter<=0)
   {
      Print("ENTRY_BLOCKED | reason=INSUFFICIENT_MARGIN | symbol=",sym," error=",GetLastError());
      return;
   }
   ResetLastError();
   int ticket=OrderSend(sym,type,lots,entry,SlippagePoints,sl,tp,OrderCommentText,
                        MagicNumber,0,clrNONE);
   if(ticket<0)
   {
      Print("ORDER_REJECTED | symbol=",sym," side=",(type==OP_BUY?"BUY":"SELL"),
            " lots=",DoubleToString(lots,lotDigits)," error=",GetLastError());
      return;
   }
   Print("ORDER_OPENED | version=2.00 | ticket=",ticket," symbol=",sym,
         " side=",(type==OP_BUY?"BUY":"SELL")," lots=",DoubleToString(lots,lotDigits),
         " capitalReferenceUSD=",DoubleToString(ReferenceCapitalUSD,2),
         " riskBudgetUSD=",DoubleToString(RiskBudgetUSD,2),
         " estimatedRiskUSD=",DoubleToString(estimatedRisk,2),
         " entry=",DoubleToString(entry,digits)," SL=",DoubleToString(sl,digits),
         " TP=",DoubleToString(tp,digits)," TP_R=",DoubleToString(TakeProfitRMultiple,2),
         " ATR=",DoubleToString(atr,digits+2)," signalClose=",DoubleToString(signalClose,digits),
         " channelHigh=",DoubleToString(channelHigh,digits),
         " channelLow=",DoubleToString(channelLow,digits));
}

void ManageOpenPositions()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber ||
         (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      string sym=OrderSymbol();
      if(CloseAtSessionEnd && IsPastSessionEnd())
      {
         CloseTicket(OrderTicket(),"SESSION_END");
         continue;
      }
      double atr=iATR(sym,SignalTimeframe,ATRPeriod,1);
      if(atr<=0) continue;
      double point=MarketInfo(sym,MODE_POINT);
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double tickSizePoints=MarketInfo(sym,MODE_TICKSIZE);
      if(point<=0 || tickSizePoints<=0) continue;
      double tickSizePrice=tickSizePoints*point;
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      double mark=(OrderType()==OP_BUY?bid:ask);
      if(mark<=0) continue;
      double initialRisk=MathAbs(OrderOpenPrice()-OrderStopLoss());
      if(initialRisk<=0) continue;
      double favorable=(OrderType()==OP_BUY?mark-OrderOpenPrice():OrderOpenPrice()-mark);
      double newSL=OrderStopLoss();
      if(favorable>=BreakEvenAtR*initialRisk)
      {
         double be=OrderOpenPrice();
         if(OrderType()==OP_BUY && (newSL<be || newSL==0)) newSL=be;
         if(OrderType()==OP_SELL && (newSL>be || newSL==0)) newSL=be;
      }
      double trail=(OrderType()==OP_BUY?mark-atr*TrailATRMultiple:mark+atr*TrailATRMultiple);
      if(OrderType()==OP_BUY && trail>newSL && trail<mark) newSL=trail;
      if(OrderType()==OP_SELL && (newSL==0 || trail<newSL) && trail>mark) newSL=trail;
      newSL=NormalizeDouble(MathRound(newSL/tickSizePrice)*tickSizePrice,digits);
      bool improve=(OrderType()==OP_BUY?newSL>OrderStopLoss()+point/2:
                                         (OrderStopLoss()==0 || newSL<OrderStopLoss()-point/2));
      double stopLevel=MarketInfo(sym,MODE_STOPLEVEL)*point;
      if(improve && MathAbs(mark-newSL)>stopLevel)
      {
         ResetLastError();
         if(!OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE))
            Print("TRAIL_MODIFY_FAILED | ticket=",OrderTicket()," symbol=",sym," error=",GetLastError());
         else
            Print("PROFIT_PROTECTION_UPDATED | ticket=",OrderTicket()," symbol=",sym,
                  " newSL=",DoubleToString(newSL,digits)," favorableMove=",DoubleToString(favorable,digits));
      }
   }
}

void CloseAllOwnPositions(string reason)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==MagicNumber &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) CloseTicket(OrderTicket(),reason);
   }
}

void CloseTicket(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return;
   string sym=OrderSymbol();
   int type=OrderType();
   if(type!=OP_BUY && type!=OP_SELL) return;
   double price=(type==OP_BUY?MarketInfo(sym,MODE_BID):MarketInfo(sym,MODE_ASK));
   ResetLastError();
   if(price<=0 || !OrderClose(ticket,OrderLots(),price,SlippagePoints,clrNONE))
      Print("CLOSE_FAILED | ticket=",ticket," symbol=",sym," reason=",reason," error=",GetLastError());
   else
      Print("POSITION_CLOSED | ticket=",ticket," symbol=",sym," reason=",reason);
}

int FindOwnPosition(string sym)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==MagicNumber && OrderSymbol()==sym &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) return(OrderTicket());
   }
   return(-1);
}

int CountOwnPositionsTotal()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==MagicNumber &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   return(count);
}

double TodayNetUSD()
{
   datetime start=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   double net=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=MagicNumber || OrderCloseTime()<start) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber ||
         (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return(net);
}

int TodayEntryCount()
{
   datetime start=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   int count=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()==MagicNumber && OrderOpenTime()>=start &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==MagicNumber && OrderOpenTime()>=start &&
         (OrderType()==OP_BUY || OrderType()==OP_SELL)) count++;
   }
   return(count);
}

bool IsPastSessionEnd()
{
   int nowMinutes=TimeHour(TimeCurrent())*60+TimeMinute(TimeCurrent());
   int endMinutes=SessionEndHour*60+SessionEndMinute;
   return(nowMinutes>=endMinutes);
}

void PrintGateOnce(string reason)
{
   static datetime lastLog=0;
   datetime currentBar=iTime(Symbol(),SignalTimeframe,0);
   if(currentBar<=0) currentBar=TimeCurrent();
   if(currentBar==lastLog) return;
   lastLog=currentBar;
   Print("ENTRY_GATE | reason=",reason," | freeMargin=",DoubleToString(AccountFreeMargin(),2),
         " | dailyNet=",DoubleToString(TodayNetUSD(),2),
         " | entriesToday=",TodayEntryCount());
}

void PrintSymbolGate(string sym,string reason)
{
   Print("SYMBOL_GATE | symbol=",sym," reason=",reason);
}
//+------------------------------------------------------------------+
