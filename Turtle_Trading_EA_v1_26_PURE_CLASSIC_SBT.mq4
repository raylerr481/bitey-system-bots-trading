#property strict
#property version   "1.26"
#property description "Classic Turtle Trading EA - Pure Classic diagnostic and MCP-ready audit"

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
// v1.25 PURE CLASSIC: no extra breakout acceptance filter.
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
input bool   InpMcpStateExport   = true;
input int    InpMcpExportSeconds = 2;

// ---------- SBT telemetry (read-only advisory channel) ----------
input bool   InpSbtEnabled         = true;
input string InpSbtURL             = "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";
input string InpSbtToken            = "";
input int    InpSbtTimeoutMs        = 5000;
input int    InpSbtExportSeconds    = 10;

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
bool   g_s1SkipLatched = false;
datetime g_lastDiagnosticBar = 0;
int    g_nextCampaignId = 1;
datetime g_lastSignalBar = 0;
datetime g_lastManageBar = 0;
string g_auditFile = "";
string g_mcpStateFile = "Turtle_MCP_state.json";

// Diagnostic counters
int g_s1BuySignals=0, g_s1SellSignals=0;
int g_s2BuySignals=0, g_s2SellSignals=0;
int g_s1BuyExecuted=0, g_s1SellExecuted=0;
int g_s2BuyExecuted=0, g_s2SellExecuted=0;
int g_s1Skipped=0, g_spreadRejected=0, g_campaignBlocked=0;
int g_historyBlocked=0, g_noNBlocked=0, g_orderErrors=0;

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
   bool ok=(EffectiveSpreadPoints() <= InpMaxSpreadPoints);
   if(!ok) g_spreadRejected++;
   return ok;
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
   int h=FileOpen(g_auditFile,FILE_COMMON|FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
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

bool S1SkipSignal(int dir)
{
   if(!InpEnableS1Skip) return false;
   bool activeSignal=S1SignalExists(dir);
   if(!activeSignal)
   {
      // The skipped breakout has ended; the next genuine S1 signal may be considered.
      g_s1SkipLatched=false;
      return false;
   }

   if(g_s1SkipLatched)
      return true;

   if(!g_skipS1Next) return false;

   g_skipS1Next=false;
   g_s1SkipLatched=true;
   Audit("S1_SKIP",1,dir,-1,0,(dir>0?Ask:Bid),NValue(),0,0,0,0,"PREVIOUS_S1_WINNER");
   if(InpVerbose) Print("Turtle S1 skipped for current breakout after previous S1 winner.");
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
      g_orderErrors++;
      if(InpVerbose) Print("Turtle OrderSend failed ",GetLastError()," reason=",reason);
      return false;
   }

   if(sys==1 && dir>0) g_s1BuyExecuted++;
   if(sys==1 && dir<0) g_s1SellExecuted++;
   if(sys==2 && dir>0) g_s2BuyExecuted++;
   if(sys==2 && dir<0) g_s2SellExecuted++;

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
   if(!EnoughHistory()) { g_historyBlocked++; return; }
   if(OpenOrderCount()>0) { g_campaignBlocked++; return; }
   if(!SpreadOK()) return;

   double n=NValue();
   if(n<=0) { g_noNBlocked++; return; }

   bool s1Buy  = InpEnableLong  && S1SignalExists(1);
   bool s1Sell = InpEnableShort && S1SignalExists(-1);
   bool s2Buy  = InpEnableLong  && S2SignalExists(1);
   bool s2Sell = InpEnableShort && S2SignalExists(-1);

   // Count signal state once per calculation timeframe bar, not once per tick.
   datetime bar=iTime(Symbol(),InpTimeframe,0);
   if(bar!=g_lastDiagnosticBar)
   {
      if(s1Buy)  g_s1BuySignals++;
      if(s1Sell) g_s1SellSignals++;
      if(s2Buy)  g_s2BuySignals++;
      if(s2Sell) g_s2SellSignals++;
      g_lastDiagnosticBar=bar;
   }

   // PURE CLASSIC: price breaks the prior completed-bar Donchian channel.
   // No additional NewBreakoutAccepted filter is applied.
   if(S1Allowed())
   {
      if(s1Buy)
      {
         if(!S1SkipSignal(1))
         {
            if(OpenUnit(1,1,n,"S1_BREAKOUT")) return;
         }
         else return;
      }
      else if(s1Sell)
      {
         if(!S1SkipSignal(-1))
         {
            if(OpenUnit(1,-1,n,"S1_BREAKOUT")) return;
         }
         else return;
      }
   }

   if(S2Allowed())
   {
      if(s2Buy)
      {
         if(OpenUnit(2,1,n,"S2_BREAKOUT")) return;
      }
      if(s2Sell)
      {
         if(OpenUnit(2,-1,n,"S2_BREAKOUT")) return;
      }
   }
}
void ProcessPyramid()
{
   if(OpenOrderCount()<=0) return;
   if(!g_campaign.active) RebuildCampaignFromOpenOrders();
   AddPyramidUnit();
}



void PrintDiagnosticSummary()
{
   Print("=================================================");
   Print("Turtle v1.25 PURE CLASSIC DIAGNOSTIC SUMMARY");
   Print("Symbol=",Symbol()," TF=",TfName()," Magic=",InpMagic);
   Print("S1 signals BUY=",g_s1BuySignals," SELL=",g_s1SellSignals);
   Print("S2 signals BUY=",g_s2BuySignals," SELL=",g_s2SellSignals);
   Print("Executed S1 BUY=",g_s1BuyExecuted," SELL=",g_s1SellExecuted,
         " | S2 BUY=",g_s2BuyExecuted," SELL=",g_s2SellExecuted);
   Print("S1 skipped=",g_s1Skipped,
         " spread rejected=",g_spreadRejected,
         " campaign blocked=",g_campaignBlocked,
         " history blocked=",g_historyBlocked,
         " no-N blocked=",g_noNBlocked,
         " order errors=",g_orderErrors);
   Print("=================================================");
}
void WriteMcpState()
{
   if(!InpMcpStateExport) return;
   static datetime lastWrite=0;
   if(lastWrite>0 && (TimeCurrent()-lastWrite)<MathMax(1,InpMcpExportSeconds)) return;
   lastWrite=TimeCurrent();

   int h=FileOpen(g_mcpStateFile,FILE_COMMON|FILE_TXT|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
   if(h==INVALID_HANDLE) return;

   string json="{";
   json += "\"time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",";
   json += "\"symbol\":\""+Symbol()+"\",";
   json += "\"timeframe\":\""+TfName()+"\",";
   json += "\"bid\":"+DoubleToString(Bid,Digits)+",";
   json += "\"ask\":"+DoubleToString(Ask,Digits)+",";
   json += "\"spread_points\":"+DoubleToString((Ask-Bid)/Point,1)+",";
   json += "\"equity\":"+DoubleToString(AccountEquity(),2)+",";
   json += "\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   json += "\"free_margin\":"+DoubleToString(AccountFreeMargin(),2)+",";
   json += "\"open_orders\":"+IntegerToString(OpenOrderCount())+",";
   json += "\"campaign_active\":"+(g_campaign.active?"true":"false")+",";
   json += "\"campaign_id\":"+IntegerToString(g_campaign.id)+",";
   json += "\"campaign_system\":"+IntegerToString(g_campaign.system)+",";
   json += "\"campaign_direction\":"+IntegerToString(g_campaign.direction)+",";
   json += "\"campaign_units\":"+IntegerToString(g_campaign.units)+",";
   json += "\"s1_skip_next\":"+(g_skipS1Next?"true":"false")+",";
   json += "\"s1_skip_latched\":"+(g_s1SkipLatched?"true":"false");
   json += "}";
   FileWriteString(h,json);
   FileClose(h);
}


// ---------- SBT telemetry ---------------------------------------
string SbtJsonEscape(string s)
{
   StringReplace(s,"\\","\\\\");
   StringReplace(s,"\"","\\\"");
   StringReplace(s,"\r","\\r");
   StringReplace(s,"\n","\\n");
   return s;
}

string SbtAccountMode()
{
   if(IsDemo()) return "DEMO";
   return "REAL";
}

string BuildSbtPayload()
{
   RefreshRates();
   string j="{";
   j += "\"source\":\"MT4_DESKTOP\",";
   j += "\"symbol\":\""+SbtJsonEscape(Symbol())+"\",";
   j += "\"timeframe\":\""+SbtJsonEscape(TfName())+"\",";
   j += "\"timestamp\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",";
   j += "\"mode\":\""+SbtAccountMode()+"\",";
   j += "\"execution_enabled\":"+(IsTradeAllowed()?"true":"false")+",";
   j += "\"bot\":{";
   j += "\"name\":\"Turtle_Trading_EA_v1_25_PURE_CLASSIC_DIAGNOSTIC\",";
   j += "\"strategy\":\"TURTLE_CLASSIC\",";
   j += "\"version\":\"1.26\",";
   j += "\"magic\":"+IntegerToString(InpMagic)+",";
   j += "\"timeframe\":\""+SbtJsonEscape(TfName())+"\"},";
   j += "\"account\":{";
   j += "\"broker\":\""+SbtJsonEscape(AccountCompany())+"\",";
   j += "\"server\":\""+SbtJsonEscape(AccountServer())+"\",";
   j += "\"mode\":\""+SbtAccountMode()+"\",";
   j += "\"currency\":\""+SbtJsonEscape(AccountCurrency())+"\",";
   j += "\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   j += "\"equity\":"+DoubleToString(AccountEquity(),2)+"},";
   j += "\"market\":{";
   j += "\"bid\":"+DoubleToString(Bid,Digits)+",";
   j += "\"ask\":"+DoubleToString(Ask,Digits)+",";
   j += "\"spread_points\":"+DoubleToString((Ask-Bid)/Point,1)+"},";
   j += "\"terminal\":{";
   j += "\"build\":"+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD))+",";
   j += "\"expert_name\":\""+SbtJsonEscape(MQLInfoString(MQL_PROGRAM_NAME))+"\",";
   j += "\"trade_allowed\":"+(IsTradeAllowed()?"true":"false")+"},";
   j += "\"turtle\":{";
   j += "\"system\":\""+SbtJsonEscape(InpSystem==SYSTEM_BOTH?"BOTH":SystemName(InpSystem))+"\",";
   j += "\"magic\":"+IntegerToString(InpMagic)+",";
   j += "\"s1_entry_days\":"+IntegerToString(InpS1EntryDays)+",";
   j += "\"s1_exit_days\":"+IntegerToString(InpS1ExitDays)+",";
   j += "\"s2_entry_days\":"+IntegerToString(InpS2EntryDays)+",";
   j += "\"s2_exit_days\":"+IntegerToString(InpS2ExitDays)+",";
   j += "\"n_period\":"+IntegerToString(InpNPeriod)+",";
   j += "\"n\":"+DoubleToString(NValue(),Digits)+",";
   j += "\"stop_n\":"+DoubleToString(InpStopN,2)+",";
   j += "\"pyramid_n\":"+DoubleToString(InpPyramidN,2)+",";
   j += "\"max_units\":"+IntegerToString(InpMaxUnits)+",";
   j += "\"campaign_active\":"+(g_campaign.active?"true":"false")+",";
   j += "\"campaign_id\":"+IntegerToString(g_campaign.id)+",";
   j += "\"campaign_direction\":"+IntegerToString(g_campaign.direction)+",";
   j += "\"campaign_units\":"+IntegerToString(g_campaign.units)+"},";
   j += "\"metrics\":{";
   j += "\"positions_open\":"+IntegerToString(OpenOrderCount())+",";
   j += "\"history_total\":"+IntegerToString(OrdersHistoryTotal())+",";
   j += "\"s1_buy_signals\":"+IntegerToString(g_s1BuySignals)+",";
   j += "\"s1_sell_signals\":"+IntegerToString(g_s1SellSignals)+",";
   j += "\"s2_buy_signals\":"+IntegerToString(g_s2BuySignals)+",";
   j += "\"s2_sell_signals\":"+IntegerToString(g_s2SellSignals)+",";
   j += "\"s1_buy_executed\":"+IntegerToString(g_s1BuyExecuted)+",";
   j += "\"s1_sell_executed\":"+IntegerToString(g_s1SellExecuted)+",";
   j += "\"s2_buy_executed\":"+IntegerToString(g_s2BuyExecuted)+",";
   j += "\"s2_sell_executed\":"+IntegerToString(g_s2SellExecuted)+",";
   j += "\"s1_skipped\":"+IntegerToString(g_s1Skipped)+",";
   j += "\"spread_rejected\":"+IntegerToString(g_spreadRejected)+",";
   j += "\"campaign_blocked\":"+IntegerToString(g_campaignBlocked)+",";
   j += "\"history_blocked\":"+IntegerToString(g_historyBlocked)+",";
   j += "\"no_n_blocked\":"+IntegerToString(g_noNBlocked)+",";
   j += "\"order_errors\":"+IntegerToString(g_orderErrors)+"}";
   j += "}";
   return j;
}

bool SendSbtTelemetry(string payload)
{
   if(!InpSbtEnabled || StringLen(InpSbtURL)<10) return false;
   char data[];
   char result[];
   string result_headers="";
   string headers="Content-Type: application/json\r\n";
   if(StringLen(InpSbtToken)>0)
      headers += "x-mt4-token: "+InpSbtToken+"\r\n";

   int payload_len=StringLen(payload);
   if(payload_len<=0) return false;
   int data_size=StringToCharArray(payload,data,0,payload_len,CP_UTF8);
   if(data_size!=payload_len)
   {
      Print("Turtle SBT telemetry not sent: encoding mismatch expected=",payload_len," actual=",data_size);
      return false;
   }

   int first_non_ws=0;
   while(first_non_ws<data_size && (data[first_non_ws]==' ' || data[first_non_ws]=='\t' || data[first_non_ws]=='\r' || data[first_non_ws]=='\n')) first_non_ws++;
   int last_non_ws=data_size-1;
   while(last_non_ws>=first_non_ws && (data[last_non_ws]==' ' || data[last_non_ws]=='\t' || data[last_non_ws]=='\r' || data[last_non_ws]=='\n')) last_non_ws--;
   if(first_non_ws>=data_size || data[first_non_ws]!='{' || data[last_non_ws]!='}')
   {
      Print("Turtle SBT telemetry not sent: malformed JSON boundaries size=",data_size);
      return false;
   }

   ResetLastError();
   int code=WebRequest("POST",InpSbtURL,headers,InpSbtTimeoutMs,data,result,result_headers);
   int err=GetLastError();
   if(code>=200 && code<300)
   {
      Print("Turtle SBT telemetry sent: HTTP ",code);
      return true;
   }
   if(code==-1)
      Print("Turtle SBT WebRequest failed: terminal_error=",err," url=",InpSbtURL);
   else
      Print("Turtle SBT telemetry rejected: HTTP ",code," terminal_error=",err," response=",CharArrayToString(result));
   return false;
}

void ExportSbtTelemetry()
{
   static datetime lastSend=0;
   datetime now=TimeCurrent();
   if(lastSend>0 && (now-lastSend)<MathMax(1,InpSbtExportSeconds)) return;
   lastSend=now;
   SendSbtTelemetry(BuildSbtPayload());
}

int OnInit()
{
   if(InpS1EntryDays<2 || InpS2EntryDays<2 || InpNPeriod<2 || InpMaxUnits<1)
      return INIT_PARAMETERS_INCORRECT;
   if(InpStopN<=0 || InpPyramidN<=0)
      return INIT_PARAMETERS_INCORRECT;

   ResetCampaign();
   g_auditFile="Turtle_v1_23_Audit_"+Symbol()+"_"+TfName()+"_"+IntegerToString(InpMagic)+".csv";
   if(InpWriteAuditCSV)
   {
      int h=FileOpen(g_auditFile,FILE_COMMON|FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
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
      Print("Turtle Trading EA v1.25 PURE CLASSIC DIAGNOSTIC");
      Print("TF=",TfName()," System=",(InpSystem==0?"BOTH":SystemName(InpSystem)));
      Print("S1 ",InpS1EntryDays,"/",InpS1ExitDays," | S2 ",InpS2EntryDays,"/",InpS2ExitDays," | N=",InpNPeriod);
      Print("Stop=",DoubleToString(InpStopN,2),"N Pyramid=",DoubleToString(InpPyramidN,2),"N MaxUnits=",InpMaxUnits);
      Print("Risk/unit=",DoubleToString(InpRiskPerUnitPct,2),"% FixedLots=",(InpUseFixedLots?"true":"false"));
      Print("CampaignStop=",(InpUseCampaignStop?"true":"false")," S1Skip=",(InpEnableS1Skip?"true":"false"));
      Print("=================================================");
   }
   EventSetTimer(MathMax(1,InpMcpExportSeconds));
   WriteMcpState();
   ExportSbtTelemetry();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(InpVerbose) Print("Turtle v1.26 stopped. reason=",reason);
   PrintDiagnosticSummary();
}

void OnTimer()
{
   WriteMcpState();
   ExportSbtTelemetry();
}

void OnTick()
{
   if(!EnoughHistory()) return;
   CheckStopDrivenClosure();
   ManageExits();
   if(OpenOrderCount()>0)
   {
      // Pyramiding is evaluated intrabar at each 0.5N threshold.
      ProcessPyramid();
   }
   else
   {
      // D1 channels are calculated from completed bars, but the actual
      // breakout may occur at any tick while the MT4 chart is H1 or lower.
      ProcessNewSignals();
   }
}
