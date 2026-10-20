#property strict
#property version   "1.21"
#property description "Classic Turtle Trading EA - clean breakout, N sizing, pyramiding and audit"

// =============================
// Turtle Trading EA v1.21 CLASSIC
// =============================
// Designed as a clean Turtle implementation.
// Original Turtle rules are daily; set InpTimeframe=PERIOD_D1 for the classic test.
// H1 is available only as an explicit experimental timeframe.

input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_D1;
input int             InpS1EntryPeriod      = 20;
input int             InpS1ExitPeriod       = 10;
input int             InpS2EntryPeriod      = 55;
input int             InpS2ExitPeriod       = 20;
input int             InpATRPeriod          = 20;
input double          InpRiskPercentUnit    = 0.50;
input double          InpStopN              = 2.0;
input double          InpAddN               = 0.50;
input int             InpMaxUnits           = 4;
input bool            InpEnableS1           = true;
input bool            InpEnableS2           = true;
input bool            InpEnableLong         = true;
input bool            InpEnableShort        = true;
input bool            InpUseS1SkipRule      = true;
input bool            InpUsePyramiding      = true;
input bool            InpRequireNewBreakout = true;
input bool            InpUseSpreadFilter    = true;
input double          InpMaxSpreadPoints    = 30.0;
input bool            InpBypassSpreadTester = true;
input double          InpSyntheticSpreadPts = 10.0;
input int             InpSlippagePoints     = 20;
input int             InpMagic              = 1212026;
input bool            InpAuditCSV           = true;
input bool            InpVerbose            = true;

string   g_symbol;
datetime g_lastBarTime = 0;
datetime g_lastEntryTime = 0;
bool     g_skipS1Next = false;
int      g_campaignId = 0;
int      g_campaignSystem = 0; // 1=S1, 2=S2
int      g_campaignDirection = 0; // 1=BUY, -1=SELL

string AuditFileName()
{
   return("Turtle_v1_21_Audit_" + Symbol() + ".csv");
}

void Log(string s)
{
   if(InpVerbose) Print("TURTLE21 ", s);
}

bool IsTesterSpreadBypass()
{
   return(IsTesting() && InpBypassSpreadTester);
}

double EffectiveSpreadPoints()
{
   if(IsTesterSpreadBypass()) return(InpSyntheticSpreadPts);
   return((Ask-Bid)/Point);
}

bool SpreadOK()
{
   if(!InpUseSpreadFilter) return(true);
   if(IsTesterSpreadBypass()) return(true);
   return(EffectiveSpreadPoints() <= InpMaxSpreadPoints);
}

double HighestClosed(int period)
{
   int shift = 1;
   int idx = iHighest(Symbol(), InpTimeframe, MODE_HIGH, period, shift);
   if(idx < 0) return(0.0);
   return(iHigh(Symbol(), InpTimeframe, idx));
}

double LowestClosed(int period)
{
   int shift = 1;
   int idx = iLowest(Symbol(), InpTimeframe, MODE_LOW, period, shift);
   if(idx < 0) return(0.0);
   return(iLow(Symbol(), InpTimeframe, idx));
}

double ATR_N()
{
   return(iATR(Symbol(), InpTimeframe, InpATRPeriod, 1));
}

int CountOpen(int direction, int system)
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(direction==1 && OrderType()!=OP_BUY) continue;
      if(direction==-1 && OrderType()!=OP_SELL) continue;
      if(system>0 && StringFind(OrderComment(), "S"+IntegerToString(system)+" ", 0) < 0) continue;
      count++;
   }
   return(count);
}

int CountOpenAll()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()!=OP_BUY && OrderType()!=OP_SELL) continue;
      count++;
   }
   return(count);
}

bool HasOpenCampaign(int direction, int system)
{
   return(CountOpen(direction,system)>0);
}

double NormalizeLots(double lots)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0.0) step=0.01;
   if(lots<minLot) lots=minLot;
   if(lots>maxLot) lots=maxLot;
   lots=MathFloor(lots/step+1e-8)*step;
   if(lots<minLot) lots=minLot;
   int digits=2;
   if(step>=1.0) digits=0;
   else if(step>=0.1) digits=1;
   return(NormalizeDouble(lots,digits));
}

double CalculateUnitLots(double n)
{
   double equity=AccountEquity();
   double riskMoney=equity*(InpRiskPercentUnit/100.0);
   double stopDistance=n*InpStopN;
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tickValue<=0.0 || tickSize<=0.0 || stopDistance<=0.0) return(0.0);
   double riskPerLot=(stopDistance/tickSize)*tickValue;
   if(riskPerLot<=0.0) return(0.0);
   return(NormalizeLots(riskMoney/riskPerLot));
}

int GetSystemForNewSignal(double bid,double ask,double s1h,double s1l,double s2h,double s2l)
{
   // S1 has priority. If S1 is skipped, allow S2 independently.
   if(InpEnableS1)
   {
      bool longSignal=InpEnableLong && ask>=s1h;
      bool shortSignal=InpEnableShort && bid<=s1l;
      if(longSignal || shortSignal)
      {
         if(!InpUseS1SkipRule || !g_skipS1Next) return(1);
         // Consume the skip only when an actual S1 signal appears.
         g_skipS1Next=false;
      }
   }
   if(InpEnableS2)
   {
      bool longSignal=InpEnableLong && ask>=s2h;
      bool shortSignal=InpEnableShort && bid<=s2l;
      if(longSignal || shortSignal) return(2);
   }
   return(0);
}

void WriteAudit(string eventName,string systemName,string direction,int ticket,int unit,double price,double n,double lots,double stop,string reason,double profit,double r)
{
   if(!InpAuditCSV) return;
   int h=FileOpen(AuditFileName(),FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
   {
      FileWrite(h,"time","symbol","tf","event","system","direction","ticket","campaign","unit","price","N","lots","stop","spread_points","equity","profit","R","reason");
   }
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),IntegerToString(InpTimeframe),eventName,systemName,direction,ticket,g_campaignId,unit,DoubleToString(price,Digits),DoubleToString(n,Digits),DoubleToString(lots,2),DoubleToString(stop,Digits),DoubleToString(EffectiveSpreadPoints(),1),DoubleToString(AccountEquity(),2),DoubleToString(profit,2),DoubleToString(r,3),reason);
   FileClose(h);
}

bool OpenUnit(int system,int direction,int unit,double n,string reason)
{
   if(!SpreadOK())
   {
      Log("ENTRY BLOCKED spread="+DoubleToString(EffectiveSpreadPoints(),1));
      return(false);
   }
   if(n<=0.0) return(false);

   double lots=CalculateUnitLots(n);
   if(lots<=0.0) return(false);

   double price=(direction==1 ? Ask : Bid);
   double stop=(direction==1 ? price-InpStopN*n : price+InpStopN*n);
   stop=NormalizeDouble(stop,Digits);

   int type=(direction==1 ? OP_BUY : OP_SELL);
   string sys="S"+IntegerToString(system)+" ";
   string dir=(direction==1 ? "BUY" : "SELL");
   string comment=sys+dir+" C"+IntegerToString(g_campaignId)+" U"+IntegerToString(unit);

   ResetLastError();
   int ticket=OrderSend(Symbol(),type,lots,price,InpSlippagePoints,stop,0,comment,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      Log("OrderSend failed err="+IntegerToString(GetLastError()));
      return(false);
   }

   WriteAudit("ENTRY", "S"+IntegerToString(system), dir, ticket, unit, price, n, lots, stop, reason, 0.0, 0.0);
   Log("ENTRY S"+IntegerToString(system)+" "+dir+" ticket="+IntegerToString(ticket)+" unit="+IntegerToString(unit)+" lots="+DoubleToString(lots,2)+" N="+DoubleToString(n,Digits)+" reason="+reason);
   g_lastEntryTime=TimeCurrent();
   return(true);
}

int OpenUnitCountForCampaign(int direction,int system)
{
   return(CountOpen(direction,system));
}

double LastEntryPrice(int direction,int system)
{
   double latest=0.0;
   datetime latestTime=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(direction==1 && OrderType()!=OP_BUY) continue;
      if(direction==-1 && OrderType()!=OP_SELL) continue;
      if(StringFind(OrderComment(),"S"+IntegerToString(system)+" ",0)<0) continue;
      if(OrderOpenTime()>=latestTime)
      {
         latestTime=OrderOpenTime();
         latest=OrderOpenPrice();
      }
   }
   return(latest);
}

void ManageExits(int system,int direction,double n)
{
   if(!HasOpenCampaign(direction,system)) return;

   int period=(system==1 ? InpS1ExitPeriod : InpS2ExitPeriod);
   double exitHigh=HighestClosed(period);
   double exitLow=LowestClosed(period);
   bool exit=false;
   string reason="";

   if(direction==1 && Bid<=exitLow)
   {
      exit=true; reason="EXIT_CHANNEL_LOW";
   }
   if(direction==-1 && Ask>=exitHigh)
   {
      exit=true; reason="EXIT_CHANNEL_HIGH";
   }

   if(!exit) return;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(direction==1 && OrderType()!=OP_BUY) continue;
      if(direction==-1 && OrderType()!=OP_SELL) continue;
      if(StringFind(OrderComment(),"S"+IntegerToString(system)+" ",0)<0) continue;

      double closePrice=(direction==1 ? Bid : Ask);
      double profitBefore=OrderProfit()+OrderSwap()+OrderCommission();
      double riskMoney=OrderLots()*((n*InpStopN)/MarketInfo(Symbol(),MODE_TICKSIZE))*MarketInfo(Symbol(),MODE_TICKVALUE);
      double r=(riskMoney>0.0 ? profitBefore/riskMoney : 0.0);
      int ticket=OrderTicket();
      double lots=OrderLots();
      double openPrice=OrderOpenPrice();

      ResetLastError();
      bool ok=OrderClose(ticket,lots,closePrice,InpSlippagePoints,clrNONE);
      if(ok)
      {
         WriteAudit("EXIT","S"+IntegerToString(system),(direction==1?"BUY":"SELL"),ticket,0,closePrice,n,lots,OrderStopLoss(),reason,profitBefore,r);
         Log("EXIT ticket="+IntegerToString(ticket)+" profit="+DoubleToString(profitBefore,2)+" R="+DoubleToString(r,2));
         if(system==1 && InpUseS1SkipRule && profitBefore>0.0) g_skipS1Next=true;
      }
      else Log("OrderClose failed ticket="+IntegerToString(ticket)+" err="+IntegerToString(GetLastError()));
   }
}

void ManagePyramiding(int system,int direction,double n)
{
   if(!InpUsePyramiding) return;
   int units=OpenUnitCountForCampaign(direction,system);
   if(units<=0 || units>=InpMaxUnits) return;

   double last=LastEntryPrice(direction,system);
   if(last<=0.0) return;

   bool add=(direction==1 ? Ask>=last+InpAddN*n : Bid<=last-InpAddN*n);
   if(!add) return;

   OpenUnit(system,direction,units+1,n,"PYRAMID_"+IntegerToString(units+1));
}

void ProcessNewSignals(double n)
{
   if(CountOpenAll()>0) return;
   if(TimeCurrent()==g_lastEntryTime) return;
   if(!SpreadOK()) return;

   double s1h=HighestClosed(InpS1EntryPeriod);
   double s1l=LowestClosed(InpS1EntryPeriod);
   double s2h=HighestClosed(InpS2EntryPeriod);
   double s2l=LowestClosed(InpS2EntryPeriod);
   if(s1h<=0 || s1l<=0 || s2h<=0 || s2l<=0) return;

   // S1 signal. S1 skip is applied only to S1; S2 remains available.
   if(InpEnableS1)
   {
      if(InpEnableLong && Ask>=s1h)
      {
         if(g_skipS1Next)
         {
            g_skipS1Next=false;
            Log("S1 LONG skipped by skip rule");
         }
         else
         {
            g_campaignId++;
            g_campaignSystem=1; g_campaignDirection=1;
            OpenUnit(1,1,1,n,"S1_BREAKOUT");
            return;
         }
      }
      if(InpEnableShort && Bid<=s1l)
      {
         if(g_skipS1Next)
         {
            g_skipS1Next=false;
            Log("S1 SHORT skipped by skip rule");
         }
         else
         {
            g_campaignId++;
            g_campaignSystem=1; g_campaignDirection=-1;
            OpenUnit(1,-1,1,n,"S1_BREAKOUT");
            return;
         }
      }
   }

   if(InpEnableS2)
   {
      if(InpEnableLong && Ask>=s2h)
      {
         g_campaignId++;
         g_campaignSystem=2; g_campaignDirection=1;
         OpenUnit(2,1,1,n,"S2_BREAKOUT");
         return;
      }
      if(InpEnableShort && Bid<=s2l)
      {
         g_campaignId++;
         g_campaignSystem=2; g_campaignDirection=-1;
         OpenUnit(2,-1,1,n,"S2_BREAKOUT");
         return;
      }
   }
}

void Process()
{
   if(iBars(Symbol(),InpTimeframe)<InpS2EntryPeriod+InpATRPeriod+10) return;
   double n=ATR_N();
   if(n<=0.0) return;

   ManageExits(1,1,n);
   ManageExits(1,-1,n);
   ManageExits(2,1,n);
   ManageExits(2,-1,n);

   ManagePyramiding(1,1,n);
   ManagePyramiding(1,-1,n);
   ManagePyramiding(2,1,n);
   ManagePyramiding(2,-1,n);

   ProcessNewSignals(n);
}

int OnInit()
{
   g_symbol=Symbol();
   g_lastBarTime=0;
   g_lastEntryTime=0;
   g_skipS1Next=false;
   g_campaignId=0;

   Log("INIT symbol="+Symbol()+" timeframe="+IntegerToString(InpTimeframe)+" classic=true");
   Log("S1="+IntegerToString(InpS1EntryPeriod)+"/"+IntegerToString(InpS1ExitPeriod)+" S2="+IntegerToString(InpS2EntryPeriod)+"/"+IntegerToString(InpS2ExitPeriod)+" ATR="+IntegerToString(InpATRPeriod));
   Log("risk/unit="+DoubleToString(InpRiskPercentUnit,2)+"% stop="+DoubleToString(InpStopN,2)+"N add="+DoubleToString(InpAddN,2)+"N maxUnits="+IntegerToString(InpMaxUnits));
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   // Evaluate exits and breakout conditions on every tick.
   // Channel values always use completed bars (shift 1), avoiding look-ahead.
   Process();
}
