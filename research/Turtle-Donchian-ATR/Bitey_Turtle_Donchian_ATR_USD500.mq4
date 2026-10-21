//+------------------------------------------------------------------+
//| Bitey_Turtle_Donchian_ATR_USD500.mq4                              |
//| Independent, conservative Turtle-inspired research EA for MT4.   |
//| Not an official Turtle Traders or EA31337 release.                |
//| No martingale, grid, averaging down, or forced minimum lot.       |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Donchian breakout with ATR stop and fixed USD risk; research build, trading disabled by default."

input double ReferenceCapitalUSD       = 500.00;
input double RiskBudgetUSD             = 1.25;
input double DailyLossLimitUSD         = 10.00;
input int    MaxOpenPositionsTotal     = 1;
input int    MagicNumber               = 20261021;
input ENUM_TIMEFRAMES SignalTimeframe  = PERIOD_H1;
input int    EntryChannelBars          = 20;
input int    ExitChannelBars           = 10;
input int    ATRPeriod                 = 20;
input double StopATRMultiple           = 2.0;
input int    MaxSpreadPoints           = 80;
input int    MaxQuoteAgeSeconds        = 120;
input int    SlippagePoints             = 5;
input bool   RequireUSDAccount         = true;
input bool   EnableTrading             = false;
input string OrderCommentText          = "Bitey Turtle Donchian ATR";

datetime g_lastSignalBar = 0;

int OnInit()
{
   if(ReferenceCapitalUSD <= 0.0 || RiskBudgetUSD <= 0.0 ||
      DailyLossLimitUSD <= 0.0 || MaxOpenPositionsTotal < 1 ||
      EntryChannelBars < 2 || ExitChannelBars < 2 ||
      ATRPeriod < 2 || StopATRMultiple <= 0.0 ||
      MaxSpreadPoints < 1 || MaxQuoteAgeSeconds < 1)
   {
      Print("INIT_FAILED | reason=INVALID_INPUTS");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(RequireUSDAccount && AccountCurrency() != "USD")
   {
      Print("SAFETY_BLOCK | reason=ACCOUNT_CURRENCY_NOT_USD | currency=", AccountCurrency());
      return(INIT_FAILED);
   }
   Print("BITEY_TURTLE_INIT | version=1.00 | mode=",
         (EnableTrading ? "ENABLED" : "SAFE_DISABLED"),
         " | strategy=DONCHIAN_BREAKOUT_ATR | capitalUSD=", DoubleToString(ReferenceCapitalUSD,2),
         " | riskBudgetUSD=", DoubleToString(RiskBudgetUSD,2),
         " | dailyLossLimitUSD=", DoubleToString(DailyLossLimitUSD,2),
         " | entryBars=", EntryChannelBars, " | exitBars=", ExitChannelBars,
         " | timeframe=", EnumToString(SignalTimeframe),
         " | tradingEnabled=", (EnableTrading ? "true" : "false"));
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(!EnableTrading) return;
   if(RequireUSDAccount && AccountCurrency() != "USD") return;
   if(!IsTradeAllowed() || IsTradeContextBusy()) return;

   if(Bars(Symbol(), SignalTimeframe) < MathMax(EntryChannelBars, ExitChannelBars) + ATRPeriod + 10)
      return;

   datetime barTime = iTime(Symbol(), SignalTimeframe, 0);
   if(barTime <= 0 || barTime == g_lastSignalBar) return;
   g_lastSignalBar = barTime;

   // Signal and channel values use closed bars; channel starts at shift 2.
   double close1 = iClose(Symbol(), SignalTimeframe, 1);
   double atr1 = iATR(Symbol(), SignalTimeframe, ATRPeriod, 1);
   int entryHighShift = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, EntryChannelBars, 2);
   int entryLowShift  = iLowest(Symbol(), SignalTimeframe, MODE_LOW, EntryChannelBars, 2);
   int exitHighShift  = iHighest(Symbol(), SignalTimeframe, MODE_HIGH, ExitChannelBars, 2);
   int exitLowShift   = iLowest(Symbol(), SignalTimeframe, MODE_LOW, ExitChannelBars, 2);
   if(close1 <= 0 || atr1 <= 0 || entryHighShift < 0 || entryLowShift < 0 ||
      exitHighShift < 0 || exitLowShift < 0)
   {
      Print("SIGNAL_BLOCKED | reason=INVALID_HISTORY_OR_INDICATOR");
      return;
   }

   double entryHigh = iHigh(Symbol(), SignalTimeframe, entryHighShift);
   double entryLow  = iLow(Symbol(), SignalTimeframe, entryLowShift);
   double exitHigh  = iHigh(Symbol(), SignalTimeframe, exitHighShift);
   double exitLow   = iLow(Symbol(), SignalTimeframe, exitLowShift);

   int ownTicket = FindOwnPosition(Symbol());
   if(ownTicket > 0)
   {
      if(!OrderSelect(ownTicket, SELECT_BY_TICKET)) return;
      int type = OrderType();
      bool exitBuy = (type == OP_BUY && close1 < exitLow);
      bool exitSell = (type == OP_SELL && close1 > exitHigh);
      if(exitBuy || exitSell) CloseOwnTicket(ownTicket);
      return;
   }

   if(CountOwnPositionsTotal() >= MaxOpenPositionsTotal)
   {
      Print("ENTRY_BLOCKED | reason=MAX_OPEN_POSITIONS | count=", CountOwnPositionsTotal());
      return;
   }

   double spread = MarketInfo(Symbol(), MODE_SPREAD);
   datetime quoteTime = (datetime)MarketInfo(Symbol(), MODE_TIME);
   int quoteAge = (quoteTime > 0 ? (int)(TimeCurrent() - quoteTime) : 2147483647);
   if(spread < 0 || spread > MaxSpreadPoints)
   {
      Print("ENTRY_BLOCKED | reason=SPREAD_LIMIT | spreadPoints=", DoubleToString(spread,1),
            " limit=", MaxSpreadPoints);
      return;
   }
   if(quoteTime <= 0 || quoteAge < 0 || quoteAge > MaxQuoteAgeSeconds)
   {
      Print("ENTRY_BLOCKED | reason=STALE_OR_INVALID_QUOTE | quoteAgeSeconds=", quoteAge);
      return;
   }
   if(RoundTurnCommissionPerLotUSD < 0.0 || ExpectedSwapCostPerLotUSD < 0.0)
   {
      Print("ENTRY_BLOCKED | reason=UNKNOWN_COMMISSION_OR_SWAP_COST | set verified non-negative costs before testing");
      return;
   }
   double dailyNet = TodayNetForMagic();
   if(dailyNet <= -DailyLossLimitUSD)
   {
      Print("ENTRY_BLOCKED | reason=DAILY_LOSS_LIMIT | dailyNetUSD=", DoubleToString(dailyNet,2),
            " limitUSD=", DoubleToString(DailyLossLimitUSD,2));
      return;
   }

   bool buySignal = (close1 > entryHigh);
   bool sellSignal = (close1 < entryLow);
   if(buySignal && sellSignal)
   {
      Print("ENTRY_BLOCKED | reason=CONFLICTING_BREAKOUT");
      return;
   }
   if(!buySignal && !sellSignal) return;

   PlaceBreakoutOrder(buySignal ? OP_BUY : OP_SELL, atr1, close1, entryHigh, entryLow);
}

int FindOwnPosition(string sym)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber || OrderSymbol()!=sym) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) return(OrderTicket());
   }
   return(-1);
}

int CountOwnPositionsTotal()
{
   int count=0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) count++;
   }
   return(count);
}

double TodayNetForMagic()
{
   datetime dayStart = StrToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double net=0.0;
   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=MagicNumber || OrderCloseTime()<dayStart) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      net += OrderProfit() + OrderSwap() + OrderCommission();
   }
   for(int j=OrdersTotal()-1; j>=0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      net += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(net);
}

void PlaceBreakoutOrder(int type, double atr, double close1, double entryHigh, double entryLow)
{
   RefreshRates();
   double point=MarketInfo(Symbol(), MODE_POINT);
   int digits=(int)MarketInfo(Symbol(), MODE_DIGITS);
   double tickSizePoints=MarketInfo(Symbol(), MODE_TICKSIZE);
   double tickValue=MarketInfo(Symbol(), MODE_TICKVALUE);
   double minLot=MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep=MarketInfo(Symbol(), MODE_LOTSTEP);
   double stopLevel=MarketInfo(Symbol(), MODE_STOPLEVEL)*point;

   if(point<=0 || tickSizePoints<=0 || tickValue<=0 || minLot<=0 ||
      maxLot<minLot || lotStep<=0 || atr<=0)
   {
      Print("ENTRY_BLOCKED | reason=INVALID_BROKER_RISK_METADATA | tickValue=",
            DoubleToString(tickValue,8), " tickSizePoints=", DoubleToString(tickSizePoints,8),
            " minLot=", DoubleToString(minLot,4), " lotStep=", DoubleToString(lotStep,4));
      return;
   }

   double entry=(type==OP_BUY ? Ask : Bid);
   if(entry<=0) return;
   double stopDistance=MathMax(atr*StopATRMultiple, stopLevel+2.0*point);
   double rawSL=(type==OP_BUY ? entry-stopDistance : entry+stopDistance);
   double tickSizePrice=tickSizePoints*point;
   double sl=NormalizeDouble(MathRound(rawSL/tickSizePrice)*tickSizePrice, digits);
   double actualStopDistance=MathAbs(entry-sl);
   if(sl<=0 || actualStopDistance<stopLevel+point)
   {
      Print("ENTRY_BLOCKED | reason=INVALID_STOP_DISTANCE | stopDistance=", DoubleToString(actualStopDistance,digits),
            " stopLevel=", DoubleToString(stopLevel,digits));
      return;
   }

   double lossPerLot=(actualStopDistance/tickSizePrice)*tickValue;
   double estimatedCostsPerLot=RoundTurnCommissionPerLotUSD+ExpectedSwapCostPerLotUSD;
   double totalRiskPerLot=lossPerLot+estimatedCostsPerLot;
   if(lossPerLot<=0 || totalRiskPerLot<=0) return;
   double rawLots=RiskBudgetUSD/totalRiskPerLot;
   if(rawLots<minLot)
   {
      Print("ENTRY_BLOCKED | reason=MINIMUM_LOT_EXCEEDS_RISK_BUDGET | riskBudgetUSD=",
            DoubleToString(RiskBudgetUSD,2), " estimatedMinLotRiskUSD=",
            DoubleToString(totalRiskPerLot*minLot,2), " minLot=", DoubleToString(minLot,4));
      return;
   }
   double lots=MathFloor(rawLots/lotStep+1e-8)*lotStep;
   lots=MathMin(lots,maxLot);
   int lotDigits=2;
   if(lotStep>=1.0) lotDigits=0;
   else if(lotStep>=0.1) lotDigits=1;
   else if(lotStep<0.01) lotDigits=3;
   lots=NormalizeDouble(lots,lotDigits);
   if(lots<minLot) return;
   double estimatedRisk=totalRiskPerLot*lots;
   if(estimatedRisk>RiskBudgetUSD+0.01)
   {
      Print("ENTRY_BLOCKED | reason=ESTIMATED_RISK_OVER_BUDGET | estimatedRiskUSD=",
            DoubleToString(estimatedRisk,2), " budgetUSD=", DoubleToString(RiskBudgetUSD,2));
      return;
   }

   ResetLastError();
   double marginAfter=AccountFreeMarginCheck(Symbol(),type,lots);
   if(marginAfter<=0)
   {
      Print("ENTRY_BLOCKED | reason=INSUFFICIENT_MARGIN | error=", GetLastError());
      return;
   }
   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,entry,SlippagePoints,sl,0,
                        OrderCommentText,MagicNumber,0,clrNONE);
   if(ticket<0)
   {
      Print("ORDER_REJECTED | side=",(type==OP_BUY?"BUY":"SELL"),
            " lots=",DoubleToString(lots,lotDigits)," error=",GetLastError(),
            " | no blind same-bar retry");
      return;
   }
   Print("ORDER_OPENED | ticket=",ticket," symbol=",Symbol(),
         " side=",(type==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,lotDigits),
         " referenceCapitalUSD=",DoubleToString(ReferenceCapitalUSD,2),
         " riskBudgetUSD=",DoubleToString(RiskBudgetUSD,2),
         " estimatedStopRiskAndCostsUSD=",DoubleToString(estimatedRisk,2),
         " commissionPerLotUSD=",DoubleToString(RoundTurnCommissionPerLotUSD,2),
         " expectedSwapPerLotUSD=",DoubleToString(ExpectedSwapCostPerLotUSD,2),
         " entry=",DoubleToString(entry,digits)," SL=",DoubleToString(sl,digits),
         " TP=NONE exit=DONCHIAN_CHANNEL",
         " atr=",DoubleToString(atr,digits+2),
         " entryChannelBars=",EntryChannelBars," exitChannelBars=",ExitChannelBars,
         " signalClose=",DoubleToString(close1,digits),
         " priorHigh=",DoubleToString(entryHigh,digits),
         " priorLow=",DoubleToString(entryLow,digits));
}

void CloseOwnTicket(int ticket)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET)) return;
   int type=OrderType();
   if(type!=OP_BUY && type!=OP_SELL) return;
   string sym=OrderSymbol();
   double lots=OrderLots();
   RefreshRates();
   double closePrice=(type==OP_BUY ? MarketInfo(sym,MODE_BID) : MarketInfo(sym,MODE_ASK));
   ResetLastError();
   bool closed=OrderClose(ticket,lots,closePrice,SlippagePoints,clrNONE);
   if(!closed)
      Print("CHANNEL_EXIT_FAILED | ticket=",ticket," error=",GetLastError(),
            " | protective server-side SL remains the primary stop");
   else
      Print("CHANNEL_EXIT_OK | ticket=",ticket," symbol=",sym,
            " side=",(type==OP_BUY?"BUY":"SELL"),
            " reason=DONCHIAN_EXIT");
}
//+------------------------------------------------------------------+
