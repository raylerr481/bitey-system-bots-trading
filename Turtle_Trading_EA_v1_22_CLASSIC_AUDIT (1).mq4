#property strict
#property version   "1.22"
#property description "Classic Turtle Trading EA - S1/S2, Donchian, ATR N, pyramiding and campaign audit"

// ================================================================
// CLASSIC TURTLE TRADING EA v1.22
// Defaults are intended for classic D1 validation, not optimization.
// No RSI/EMA/ADX/AI filters are used.
// ================================================================

input ENUM_TIMEFRAMES InpTimeframe = PERIOD_D1;

enum TurtleSystem
{
   SYSTEM_BOTH = 0,
   SYSTEM_S1   = 1,
   SYSTEM_S2   = 2
};
input TurtleSystem InpSystem = SYSTEM_BOTH;

input int    InpS1EntryDays = 20;
input int    InpS1ExitDays  = 10;
input int    InpS2EntryDays = 55;
input int    InpS2ExitDays  = 20;
input int    InpNPeriod     = 20;

input double InpRiskPerUnitPct = 0.50;
input bool   InpUseFixedLots   = false;
input double InpFixedLots      = 0.01;

input double InpStopN       = 2.0;
input double InpPyramidN    = 0.50;
input int    InpMaxUnits    = 4;
input bool   InpEnablePyramid = true;

input bool   InpEnableS1Skip = true;
input bool   InpRequireNewBreakout = true;
input bool   InpEnableLong  = true;
input bool   InpEnableShort = true;

// Classic Turtle campaigns commonly manage the campaign stop from the
// most recently added unit. Disabled by default for strict comparison with v1.21.
input bool   InpUseCampaignStop = false;

input bool   InpEnableSpreadFilter = true;
input double InpMaxSpreadPoints = 30.0;
input bool   InpBypassSpreadInTester = true;
input double InpSyntheticSpreadPoints = 10.0;
input int    InpSlippagePoints = 20;

input int    InpMagic = 1222026;
input bool   InpWriteAuditCSV = true;
input bool   InpVerbose = true;

struct CampaignState
{
   int    id;
   int    system;
   int    direction;
   int    units;
   double lastEntry;
   double n;
   bool   active;
};

CampaignState g_campaign;
bool   g_skipS1Next = false;
int    g_nextCampaignId = 1;
datetime g_lastSignalBar = 0;
datetime g_lastManageBar = 0;
string g_auditFile = "";

// ---------- utility ----------
string TfName()
{
   if(InpTimeframe==PERIOD_M1) return "M1";
   if(InpTimeframe==PERIOD_M5) return "M5";
   if(InpTimeframe==PERIOD_M15) return "M15";
   if(InpTimeframe==PERIOD_M30) return "M30";
   if(InpTimeframe==PERIOD_H1) return "H1";
   if(InpTimeframe==PERIOD_H4) return "H4";
   if(InpTimeframe==PERIOD_D1) return "D1";
   if(InpTimeframe==PERIOD_W1) return "W1";
   return IntegerToString(InpTimeframe);
}

bool IsTester()
{
   return IsTesting() || IsOptimization();
}

double EffectiveSpreadPoints()
{
   if(IsTester() && InpBypassSpreadInTester)
      return InpSyntheticSpreadPoints;
   return (Ask-Bid)/Point;
}

bool SpreadOK()
{
   if(!InpEnableSpreadFilter) return true;
   return EffectiveSpreadPoints() <= InpMaxSpreadPoints;
}

int DigitsForLots()
{
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step>=1.0) return 0;
   if(step>=0.1) return 1;
   if(step>=0.01) return 2;
   return 3;
}

double NormalizeLots(double lots)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   if(step<=0) step=0.01;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   lots=MathFloor(lots/step+1e-8)*step;
   if(lots<minLot) lots=minLot;
   return NormalizeDouble(lots,DigitsForLots());
}

double HighestClosed(int days)
{
   int shift=1;
   int idx=iHighest(Symbol(),InpTimeframe,MODE_HIGH,days,shift);
   if(idx<0) return 0.0;
   return iHigh(Symbol(),InpTimeframe,idx);
}

double LowestClosed(int days)
{
   int shift=1;
   int idx=iLowest(Symbol(),InpTimeframe,MODE_LOW,days,shift);
   if(idx<0) return 0.0;
   return iLow(Symbol(),InpTimeframe,idx);
}

double NValue()
{
   return iATR(Symbol(),InpTimeframe,InpNPeriod,1);
}

bool EnoughHistory()
{
   int need=MathMax(MathMax(InpS1EntryDays,InpS2EntryDays),MathMax(InpS1ExitDays,InpS2ExitDays))+InpNPeriod+10;
   return iBars(Symbol(),InpTimeframe)>need;
}

string DirectionName(int dir)
{
   return dir>0 ? "BUY" : "SELL";
}

string SystemName(int sys)
{
   return sys==1 ? "S1" : "S2";
}

void Audit(string eventName,int sys,int dir,int ticket,int unit,double price,double n,double lots,double stop,double profit,double r,string reason)
{
   if(!InpWriteAuditCSV) return;
   int h=FileOpen(g_auditFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   FileSeek(h,0,SEEK_END);
   FileWrite(h,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
      Symbol(),TfName(),eventName,SystemName(sys),DirectionName(dir),
      ticket,g_campaign.id,unit,
      DoubleToString(price,Digits),DoubleToString(n,Digits),
      DoubleToString(lots,2),DoubleToString(stop,Digits),
      DoubleToString(AccountEquity(),2),DoubleToString(profit,2),
      DoubleToString(r,3),reason);
   FileClose(h);
}

void ResetCampaign()
{
   g_campaign.id=0;
   g_campaign.system=0;
   g_campaign.direction=0;
   g_campaign.units=0;
   g_campaign.lastEntry=0;
   g_campaign.n=0;
   g_campaign.active=false;
}

int OpenOrderCount()
{
   int count=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type==OP_BUY || type==OP_SELL) count++;
   }
   return count;
}

bool SelectOpenOrder(int index)
{
   if(!OrderSelect(index,SELECT_BY_POS,MODE_TRADES)) return false;
   if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) return false;
   return (OrderType()==OP_BUY || OrderType()==OP_SELL);
}

void RebuildCampaignFromOpenOrders()
{
   ResetCampaign();
   int count=0;
   datetime latest=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!SelectOpenOrder(i)) continue;
      count++;
      int type=OrderType();
      string c=OrderComment();
      int sys=0;
      if(StringFind(c,"S1",0)>=0) sys=1;
      if(StringFind(c,"S2",0)>=0) sys=2;
      if(g_campaign.system==0) g_campaign.system=sys;
      if(OrderOpenTime()>=latest)
      {
         latest=OrderOpenTime();
         g_campaign.lastEntry=OrderOpenPrice();
         g_campaign.n=MathAbs(OrderOpenPrice()-OrderStopLoss())/InpStopN;
         g_campaign.direction=(type==OP_BUY?1:-1);
      }
   }
   if(count>0)
   {
      g_campaign.active=true;
      g_campaign.units=count;
      if(g_campaign.n<=0) g_campaign.n=NValue();
      g_campaign.id=1;
   }
}

bool IsNewBar()
{
   datetime t=iTime(Symbol(),InpTimeframe,0);
   if(t==0) return false;
   if(t!=g_lastSignalBar)
   {
      g_lastSignalBar=t;
      return true;
   }
   return false;
}

bool HasEnoughMargin(double lots,int cmd)
{
   double fm=AccountFreeMarginCheck(Symbol(),cmd,lots);
   return fm>0;
}

double LotsForRisk(double n)
{
   if(InpUseFixedLots) return NormalizeLots(InpFixedLots);
   if(n<=0 || InpStopN<=0) return 0;
   double riskMoney=AccountEquity()*InpRiskPerUnitPct/100.0;
   double stopDistance=n*InpStopN;
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tickValue<=0 || tickSize<=0 || stopDistance<=0) return NormalizeLots(InpFixedLots);
   double lossPerLot=stopDistance/tickSize*tickValue;
   if(lossPerLot<=0) return NormalizeLots(InpFixedLots);
   return NormalizeLots(riskMoney/lossPerLot);
}

bool S1Allowed()
{
   return (InpSystem==SYSTEM_BOTH || InpSystem==SYSTEM_S1);
}

bool S2Allowed()
{
   return (InpSystem==SYSTEM_BOTH || InpSystem==SYSTEM_S2);
}

bool S1SignalExists(int dir)
{
   double hi=HighestClosed(InpS1EntryDays);
   double lo=LowestClosed(InpS1EntryDays);
   if(dir>0) return Ask>=hi;
   return Bid<=lo;
}

bool S2SignalExists(int dir)
{
   double hi=HighestClosed(InpS2EntryDays);
   double lo=LowestClosed(InpS2EntryDays);
   if(dir>0) return Ask>=hi;
   return Bid<=lo;
}

bool NewBreakoutAccepted(int sys,int dir)
{
   if(!InpRequireNewBreakout) return true;
   int days=(sys==1?InpS1EntryDays:InpS2EntryDays);
   double level=(dir>0?HighestClosed(days):LowestClosed(days));
   double previous=(dir>0?iHigh(Symbol(),InpTimeframe,2):iLow(Symbol(),InpTimeframe,2));
   if(dir>0) return level>previous;
   return level<previous;
}

bool S1SkipSignal(int dir)
{
   if(!InpEnableS1Skip || !g_skipS1Next) return false;
   if(!S1SignalExists(dir)) return false;
   g_skipS1Next=false;
   Audit("S1_SKIP",1,dir,-1,0,(dir>0?Ask:Bid),NValue(),0,0,0,0,"PREVIOUS_S1_WINNER");
   if(InpVerbose) Print("Turtle S1 skipped after previous S1 winner.");
   return true;
}

int FindExistingDirection()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!SelectOpenOrder(i)) continue;
      return OrderType()==OP_BUY ? 1 : -1;
   }
   return 0;
}

bool OpenUnit(int sys,int dir,double n,string reason)
{
   if(!SpreadOK()) return false;
   if(!EnoughHistory()) return false;
   if(n<=0) return false;
   if(OpenOrderCount()>0 && !g_campaign.active) RebuildCampaignFromOpenOrders();

   double lots=LotsForRisk(n);
   if(lots<=0) return false;
   int cmd=(dir>0?OP_BUY:OP_SELL);
   if(!HasEnoughMargin(lots,cmd))
   {
      if(InpVerbose) Print("Turtle: insufficient margin for ",DoubleToString(lots,2));
      return false;
   }

   RefreshRates();
   double price=(dir>0?Ask:Bid);
   double stop=(dir>0 ? price-InpStopN*n : price+InpStopN*n);
   stop=NormalizeDouble(stop,Digits);
   int campaignIdForOrder=g_campaign.active ? g_campaign.id : g_nextCampaignId;
   string comment=StringFormat("Turtle %s %s C%d U%d",SystemName(sys),DirectionName(dir),campaignIdForOrder,g_campaign.units+1);
   int ticket=OrderSend(Symbol(),cmd,lots,price,InpSlippagePoints,stop,0,comment,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      if(InpVerbose) Print("Turtle OrderSend failed ",GetLastError()," reason=",reason);
      return false;
   }

   if(!g_campaign.active)
   {
      g_campaign.id=g_nextCampaignId++;
      g_campaign.system=sys;
      g_campaign.direction=dir;
      g_campaign.units=0;
      g_campaign.active=true;
   }
   g_campaign.units++;
   g_campaign.lastEntry=price;
   g_campaign.n=n;
   Audit("ENTRY",sys,dir,ticket,g_campaign.units,price,n,lots,stop,0,0,reason);
   if(InpVerbose) Print("Turtle ENTRY ",SystemName(sys)," ",DirectionName(dir)," U",g_campaign.units," lots=",DoubleToString(lots,2)," price=",DoubleToString(price,Digits)," N=",DoubleToString(n,Digits));

   if(InpUseCampaignStop) UpdateCampaignStops(n);
   return true;
}

bool AddPyramidUnit()
{
   if(!InpEnablePyramid || !g_campaign.active) return false;
   if(g_campaign.units>=InpMaxUnits) return false;
   if(OpenOrderCount()<=0) return false;
   int dir=g_campaign.direction;
   double n=g_campaign.n;
   if(n<=0) n=NValue();
   if(n<=0) return false;
   RefreshRates();
   double trigger=(dir>0?g_campaign.lastEntry+InpPyramidN*n:g_campaign.lastEntry-InpPyramidN*n);
   if((dir>0 && Ask<trigger) || (dir<0 && Bid>trigger)) return false;
   return OpenUnit(g_campaign.system,dir,n,"PYRAMID");
}

void UpdateCampaignStops(double n)
{
   if(!InpUseCampaignStop || !g_campaign.active || n<=0) return;
   double anchor=g_campaign.lastEntry;
   double stop=(g_campaign.direction>0?anchor-InpStopN*n:anchor+InpStopN*n);
   stop=NormalizeDouble(stop,Digits);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!SelectOpenOrder(i)) continue;
      bool ok=OrderModify(OrderTicket(),OrderOpenPrice(),stop,OrderTakeProfit(),0,clrNONE);
      if(!ok && InpVerbose) Print("Turtle OrderModify failed ",GetLastError());
   }
}

bool CloseTicket(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET)) return false;
   if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) return false;
   int type=OrderType();
   if(type!=OP_BUY && type!=OP_SELL) return false;
   RefreshRates();
   double price=(type==OP_BUY?Bid:Ask);
   double profit=OrderProfit()+OrderSwap()+OrderCommission();
   double n=g_campaign.n;
   double riskMoney=0;
   if(n>0) riskMoney=n*InpStopN/MarketInfo(Symbol(),MODE_TICKSIZE)*MarketInfo(Symbol(),MODE_TICKVALUE)*OrderLots();
   double r=(riskMoney>0?profit/riskMoney:0);
   bool ok=OrderClose(ticket,OrderLots(),price,InpSlippagePoints,clrNONE);
   if(ok)
   {
      Audit("EXIT",g_campaign.system,g_campaign.direction,ticket,g_campaign.units,price,n,OrderLots(),OrderStopLoss(),profit,r,reason);
      if(InpVerbose) Print("Turtle EXIT ticket=",ticket," profit=",DoubleToString(profit,2)," reason=",reason);
   }
   return ok;
}

void ManageExits()
{
   if(OpenOrderCount()<=0) return;
   int dir=FindExistingDirection();
   if(dir==0) return;
   int sys=g_campaign.system;
   if(sys==0) sys=1;
   int exitDays=(sys==1?InpS1ExitDays:InpS2ExitDays);
   double level=(dir>0?LowestClosed(exitDays):HighestClosed(exitDays));
   RefreshRates();
   bool exitNow=(dir>0?Bid<=level:Ask>=level);
   if(!exitNow) return;

   bool campaignWasS1=(g_campaign.system==1);
   int tickets[100];
   ArrayInitialize(tickets,0);
   int count=0;
   for(int i=OrdersTotal()-1;i>=0 && count<100;i--)
   {
      if(!SelectOpenOrder(i)) continue;
      tickets[count++]=OrderTicket();
   }
   bool anyProfit=false;
   for(int j=0;j<count;j++)
   {
      if(!OrderSelect(tickets[j],SELECT_BY_TICKET)) continue;
      double p=OrderProfit()+OrderSwap()+OrderCommission();
      if(p>0) anyProfit=true;
   }
   for(int k=0;k<count;k++) CloseTicket(tickets[k],"DONCHIAN_EXIT");
   if(campaignWasS1 && InpEnableS1Skip && anyProfit) g_skipS1Next=true;
   ResetCampaign();
}

void CheckStopDrivenClosure()
{
   // MT4 closes SL automatically. Rebuild/clear state when no orders remain.
   if(OpenOrderCount()==0 && g_campaign.active)
   {
      ResetCampaign();
   }
}

void ProcessNewSignals()
{
   if(!EnoughHistory() || OpenOrderCount()>0) return;
   if(!SpreadOK()) return;

   double n=NValue();
   if(n<=0) return;

   // S1 has priority when BOTH is selected. S1 skip is consumed only when a real S1 breakout occurs.
   if(S1Allowed())
   {
      if(S1SignalExists(1) && NewBreakoutAccepted(1,1))
      {
         if(!S1SkipSignal(1))
         {
            OpenUnit(1,1,n,"S1_BREAKOUT");
            return;
         }
      }
      if(S1SignalExists(-1) && NewBreakoutAccepted(1,-1))
      {
         if(!S1SkipSignal(-1))
         {
            OpenUnit(1,-1,n,"S1_BREAKOUT");
            return;
         }
      }
   }

   if(S2Allowed())
   {
      if(S2SignalExists(1) && NewBreakoutAccepted(2,1))
      {
         OpenUnit(2,1,n,"S2_BREAKOUT");
         return;
      }
      if(S2SignalExists(-1) && NewBreakoutAccepted(2,-1))
      {
         OpenUnit(2,-1,n,"S2_BREAKOUT");
         return;
      }
   }
}

void ProcessPyramid()
{
   if(OpenOrderCount()<=0) return;
   if(!g_campaign.active) RebuildCampaignFromOpenOrders();
   AddPyramidUnit();
}

int OnInit()
{
   if(InpS1EntryDays<2 || InpS2EntryDays<2 || InpNPeriod<2 || InpMaxUnits<1)
      return INIT_PARAMETERS_INCORRECT;
   if(InpStopN<=0 || InpPyramidN<=0)
      return INIT_PARAMETERS_INCORRECT;

   ResetCampaign();
   g_auditFile="Turtle_v1_22_Audit_"+Symbol()+"_"+TfName()+"_"+IntegerToString(InpMagic)+".csv";
   if(InpWriteAuditCSV)
   {
      int h=FileOpen(g_auditFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
      if(h!=INVALID_HANDLE)
      {
         if(FileSize(h)==0)
            FileWrite(h,"Time","Symbol","TF","Event","System","Direction","Ticket","Campaign","Unit","Price","N","Lots","Stop","Equity","Profit","R","Reason");
         FileClose(h);
      }
   }
   if(InpVerbose)
   {
      Print("=================================================");
      Print("Turtle Trading EA v1.22 CLASSIC AUDIT");
      Print("TF=",TfName()," System=",(InpSystem==0?"BOTH":SystemName(InpSystem)));
      Print("S1 ",InpS1EntryDays,"/",InpS1ExitDays," | S2 ",InpS2EntryDays,"/",InpS2ExitDays," | N=",InpNPeriod);
      Print("Stop=",DoubleToString(InpStopN,2),"N Pyramid=",DoubleToString(InpPyramidN,2),"N MaxUnits=",InpMaxUnits);
      Print("Risk/unit=",DoubleToString(InpRiskPerUnitPct,2),"% FixedLots=",(InpUseFixedLots?"true":"false"));
      Print("CampaignStop=",(InpUseCampaignStop?"true":"false")," S1Skip=",(InpEnableS1Skip?"true":"false"));
      Print("=================================================");
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpVerbose) Print("Turtle v1.22 stopped. reason=",reason);
}

void OnTick()
{
   if(!EnoughHistory()) return;
   CheckStopDrivenClosure();
   ManageExits();
   if(IsNewBar())
   {
      if(OpenOrderCount()>0)
         ProcessPyramid();
      else
         ProcessNewSignals();
   }
   else if(OpenOrderCount()>0)
   {
      // Breakouts and pyramid triggers are allowed intrabar.
      ProcessPyramid();
      if(OpenOrderCount()==0) ProcessNewSignals();
   }
}
