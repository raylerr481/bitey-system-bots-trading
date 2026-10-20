//+------------------------------------------------------------------+
//| Turtle_Trading_EA_v1_10.mq4                                    |
//| Classic Turtle-inspired System 1 + System 2 for MT4             |
//| Designed for D1 first. Lower TFs change the meaning of periods. |
//+------------------------------------------------------------------+
#property strict
#property version "1.20"

input bool   UseSystem1            = true;
input bool   UseSystem2            = true;
input double RiskPercentPerUnit    = 1.0;
input int    NPeriod               = 20;
input int    MaxUnits              = 4;
input double AddEveryN             = 0.5;
input double StopN                 = 2.0;
input bool   UseLastTradeFilter    = true;
input bool   UseTrailing2N         = false;
input bool   AllowLong             = true;
input bool   AllowShort            = true;
input double MaxSpreadPoints       = 200.0;
input bool   DisableSpreadFilterInTester = true;
input bool   UseCloseConfirmationInTester = false;
input int    SlippagePoints        = 30;
input int    MagicNumber            = 26100401;
input bool   WriteCSV              = true;
input string CSVFileName           = "Turtle_EA_Audit.csv";
input bool   VerboseLog            = true;

// System 1: 20 entry / 10 exit. System 2: 55 entry / 20 exit.
#define S1_ENTRY 20
#define S1_EXIT  10
#define S2_ENTRY 55
#define S2_EXIT  20

datetime g_lastBar = 0;
datetime g_lastActionBar = 0;

string GVPrefix()
{
   return("TURTLE_" + Symbol() + "_" + IntegerToString(Period()) + "_" + IntegerToString(MagicNumber) + "_");
}

string GVLastS1Long()  { return(GVPrefix()+"LAST_S1_LONG"); }
string GVLastS1Short() { return(GVPrefix()+"LAST_S1_SHORT"); }
string GVPrevS1Long()  { return(GVPrefix()+"PREV_S1_LONG"); }
string GVPrevS1Short() { return(GVPrefix()+"PREV_S1_SHORT"); }
string GVS1LongWin()   { return(GVPrefix()+"S1_LONG_WIN"); }
string GVS1ShortWin()  { return(GVPrefix()+"S1_SHORT_WIN"); }

bool NewBar()
{
   datetime t=iTime(Symbol(),Period(),0);
   if(t!=g_lastBar){ g_lastBar=t; return(true); }
   return(false);
}

bool SpreadOK()
{
   double sp=(Ask-Bid)/Point;
   if(IsTesting() && DisableSpreadFilterInTester) return(true);
   return(sp <= MaxSpreadPoints);
}

void SpreadDiagnostic()
{
   static datetime last=0;
   datetime now=iTime(Symbol(),Period(),0);
   if(now==last) return;
   last=now;
   double sp=(Ask-Bid)/Point;
   if(VerboseLog) Print("TURTLE DIAG spread=",DoubleToString(sp,1),
                         " max=",DoubleToString(MaxSpreadPoints,1),
                         " tester=",IsTesting());
}

bool CanAct()
{
   return(g_lastActionBar != iTime(Symbol(),Period(),0));
}

void MarkAction(){ g_lastActionBar=iTime(Symbol(),Period(),0); }

int HighestIndex(int period,int shift)
{
   return(iHighest(Symbol(),Period(),MODE_HIGH,period,shift));
}

int LowestIndex(int period,int shift)
{
   return(iLowest(Symbol(),Period(),MODE_LOW,period,shift));
}

double Highest(int period,int shift)
{
   int i=HighestIndex(period,shift);
   if(i<0) return(0.0);
   return(iHigh(Symbol(),Period(),i));
}

double Lowest(int period,int shift)
{
   int i=LowestIndex(period,shift);
   if(i<0) return(0.0);
   return(iLow(Symbol(),Period(),i));
}

double NValue()
{
   return(iATR(Symbol(),Period(),NPeriod,1));
}

int CountOrders(int type=-1)
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      if(type<0 || OrderType()==type) n++;
   }
   return(n);
}

double LastEntry(int type)
{
   datetime latest=0;
   double p=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      if(OrderType()!=type) continue;
      if(OrderOpenTime()>=latest){ latest=OrderOpenTime(); p=OrderOpenPrice(); }
   }
   return(p);
}

double MoneyPerPriceUnitPerLot()
{
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE);
   double ts=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tv<=0 || ts<=0) return(0);
   return(tv/ts);
}

double UnitLots(double N)
{
   if(N<=0) return(0);
   double equity=AccountEquity();
   double riskMoney=equity*RiskPercentPerUnit/100.0;
   double moneyRiskPerLot=StopN*N*MoneyPerPriceUnitPerLot();
   if(moneyRiskPerLot<=0) return(0);
   double raw=riskMoney/moneyRiskPerLot;
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(step<=0) step=0.01;
   raw=MathFloor(raw/step)*step;
   if(raw<minLot) return(0);
   if(raw>maxLot) raw=maxLot;
   return(NormalizeDouble(raw,2));
}

bool GVBool(string name)
{
   if(!GlobalVariableCheck(name)) return(false);
   return(GlobalVariableGet(name)>0.5);
}

void SetGVBool(string name,bool value)
{
   GlobalVariableSet(name,value?1.0:0.0);
}

void UpdateS1Filter(int type,bool won)
{
   if(type==OP_BUY)
   {
      SetGVBool(GVS1LongWin(),won);
      GlobalVariableSet(GVPrevS1Long(),GlobalVariableCheck(GVLastS1Long())?GlobalVariableGet(GVLastS1Long()):0);
      GlobalVariableSet(GVLastS1Long(),TimeCurrent());
   }
   else if(type==OP_SELL)
   {
      SetGVBool(GVS1ShortWin(),won);
      GlobalVariableSet(GVPrevS1Short(),GlobalVariableCheck(GVLastS1Short())?GlobalVariableGet(GVLastS1Short()):0);
      GlobalVariableSet(GVLastS1Short(),TimeCurrent());
   }
}

bool S1Blocked(int type)
{
   if(!UseLastTradeFilter) return(false);
   bool blocked=false;
   if(type==OP_BUY) blocked=GVBool(GVS1LongWin());
   if(type==OP_SELL) blocked=GVBool(GVS1ShortWin());
   if(blocked)
   {
      // Turtle System 1 skips only the next qualifying breakout after a win.
      if(type==OP_BUY) SetGVBool(GVS1LongWin(),false);
      if(type==OP_SELL) SetGVBool(GVS1ShortWin(),false);
      Audit("S1_SKIP","PREVIOUS_TRADE_WIN",(type==OP_BUY?Ask:Bid),0,NValue(),1,type);
      return(true);
   }
   return(false);
}

void Audit(string event,string detail,double price,double lots,double N,int system,int type)
{
   string side=(type==OP_BUY?"BUY":(type==OP_SELL?"SELL":"-"));
   string line=TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+","+Symbol()+","+IntegerToString(Period())+","+
               event+","+IntegerToString(system)+","+side+","+
               DoubleToString(price,Digits)+","+DoubleToString(lots,2)+","+
               DoubleToString(N,Digits)+","+detail;
   if(VerboseLog) Print("TURTLE ",line);
   if(!WriteCSV) return;
   int h=FileOpen(CSVFileName,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(h<0) return;
   if(FileSize(h)==0) FileWrite(h,"time","symbol","period","event","system","side","price","lots","N","detail");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),Period(),event,system,side,
             DoubleToString(price,Digits),DoubleToString(lots,2),DoubleToString(N,Digits),detail);
   FileClose(h);
}

bool CloseType(int type,int reasonSystem)
{
   bool any=false;
   RefreshRates();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber || OrderType()!=type) continue;
      double cp=(type==OP_BUY?Bid:Ask);
      double profit=OrderProfit()+OrderSwap()+OrderCommission();
      bool ok=OrderClose(OrderTicket(),OrderLots(),cp,SlippagePoints,clrNONE);
      if(ok)
      {
         any=true;
         // System is recovered from the order comment when possible.
         string c=OrderComment();
         bool s1=(StringFind(c,"Turtle S1",0)>=0);
         if(s1) UpdateS1Filter(type,profit>0.0);
         Audit("EXIT",(profit>0?"WIN":"LOSS"),cp,OrderLots(),NValue(),s1?1:2,type);
      }
      else if(VerboseLog) Print("TURTLE close error ",GetLastError());
   }
   return(any);
}

bool OpenUnit(int type,int system,double N,string reason)
{
   if(N<=0 || !SpreadOK() || !CanAct()) return(false);
   if(CountOrders(type)>=MaxUnits) return(false);
   if(CountOrders(type==OP_BUY?OP_SELL:OP_BUY)>0) return(false);

   double lots=UnitLots(N);
   if(lots<=0)
   {
      Audit("REJECT","LOT_SIZE_ZERO",(type==OP_BUY?Ask:Bid),0,N,system,type);
      return(false);
   }

   RefreshRates();
   double price=(type==OP_BUY?Ask:Bid);
   double sl=(type==OP_BUY?price-StopN*N:price+StopN*N);
   double minStop=MarketInfo(Symbol(),MODE_STOPLEVEL)*Point;
   if(minStop>0)
   {
      if(type==OP_BUY && price-sl<minStop) sl=price-minStop;
      if(type==OP_SELL && sl-price<minStop) sl=price+minStop;
   }
   price=NormalizeDouble(price,Digits);
   sl=NormalizeDouble(sl,Digits);

   string comment=(system==1?"Turtle S1":"Turtle S2");
   int ticket=OrderSend(Symbol(),type,lots,price,SlippagePoints,sl,0,comment,MagicNumber,0,clrNONE);
   if(ticket<0)
   {
      Audit("REJECT","ORDERSEND_"+IntegerToString(GetLastError()),price,lots,N,system,type);
      return(false);
   }
   MarkAction();
   Audit("ENTRY",reason,price,lots,N,system,type);
   return(true);
}

void ManageStops(double N)
{
   if(!UseTrailing2N || N<=0) return;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=MagicNumber) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      double newSL=(type==OP_BUY?Bid-StopN*N:Ask+StopN*N);
      newSL=NormalizeDouble(newSL,Digits);
      bool improve=(type==OP_BUY?(OrderStopLoss()==0 || newSL>OrderStopLoss()):(OrderStopLoss()==0 || newSL<OrderStopLoss()));
      if(improve)
      {
         if(!OrderModify(OrderTicket(),OrderOpenPrice(),newSL,OrderTakeProfit(),0,clrNONE) && VerboseLog)
            Print("TURTLE stop modify error ",GetLastError());
      }
   }
}

void ManageExits(double N)
{
   if(CountOrders(OP_BUY)>0)
   {
      bool s1=false;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber && OrderType()==OP_BUY)
            if(StringFind(OrderComment(),"Turtle S1",0)>=0) s1=true;
      }
      int p=s1?S1_EXIT:S2_EXIT;
      if(Bid<Lowest(p,1)) CloseType(OP_BUY,s1?1:2);
   }
   if(CountOrders(OP_SELL)>0)
   {
      bool s1=false;
      for(int j=OrdersTotal()-1;j>=0;j--)
      {
         if(OrderSelect(j,SELECT_BY_POS,MODE_TRADES) && OrderSymbol()==Symbol() && OrderMagicNumber()==MagicNumber && OrderType()==OP_SELL)
            if(StringFind(OrderComment(),"Turtle S1",0)>=0) s1=true;
      }
      int p=s1?S1_EXIT:S2_EXIT;
      if(Ask>Highest(p,1)) CloseType(OP_SELL,s1?1:2);
   }
}

void ManageEntries(double N)
{
   if(!CanAct() || !SpreadOK() || N<=0) return;

   // If already positioned, only pyramiding is allowed here.
   if(CountOrders(OP_BUY)>0 || CountOrders(OP_SELL)>0) return;

   double s1High=Highest(S1_ENTRY,1);
   double s1Low =Lowest(S1_ENTRY,1);
   double s2High=Highest(S2_ENTRY,1);
   double s2Low =Lowest(S2_ENTRY,1);

   if(VerboseLog)
      Print("TURTLE SIGNAL CHECK bid=",DoubleToString(Bid,Digits),
            " ask=",DoubleToString(Ask,Digits),
            " S1H=",DoubleToString(s1High,Digits),
            " S1L=",DoubleToString(s1Low,Digits),
            " S2H=",DoubleToString(s2High,Digits),
            " S2L=",DoubleToString(s2Low,Digits),
            " N=",DoubleToString(N,Digits));

   // On a live tick, breakout is a price crossing, not a close confirmation.
   if(UseSystem1 && AllowLong && Ask>s1High && !S1Blocked(OP_BUY))
   {
      if(OpenUnit(OP_BUY,1,N,"20D_BREAKOUT")) return;
   }
   if(UseSystem1 && AllowShort && Bid<s1Low && !S1Blocked(OP_SELL))
   {
      if(OpenUnit(OP_SELL,1,N,"20D_BREAKOUT")) return;
   }

   // System 2 is the failsafe and is never filtered.
   if(UseSystem2 && AllowLong && Ask>s2High)
   {
      OpenUnit(OP_BUY,2,N,"55D_BREAKOUT");
      return;
   }
   if(UseSystem2 && AllowShort && Bid<s2Low)
   {
      OpenUnit(OP_SELL,2,N,"55D_BREAKOUT");
      return;
   }
}

void ManagePyramiding(double N)
{
   if(!CanAct() || !SpreadOK() || N<=0) return;
   int buys=CountOrders(OP_BUY);
   int sells=CountOrders(OP_SELL);

   if(buys>0 && buys<MaxUnits)
   {
      double last=LastEntry(OP_BUY);
      if(last>0 && Ask>=last+AddEveryN*N)
         OpenUnit(OP_BUY,1,N,"PYRAMID_"+IntegerToString(buys+1));
   }
   if(sells>0 && sells<MaxUnits)
   {
      double last=LastEntry(OP_SELL);
      if(last>0 && Bid<=last-AddEveryN*N)
         OpenUnit(OP_SELL,1,N,"PYRAMID_"+IntegerToString(sells+1));
   }
}

int OnInit()
{
   if(NPeriod<2 || MaxUnits<1 || RiskPercentPerUnit<=0 || StopN<=0 || AddEveryN<=0)
      return(INIT_PARAMETERS_INCORRECT);
   Print("Turtle EA v1.10 initialized. Recommended first test: EURUSD D1.");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   if(Bars<MathMax(100,S2_ENTRY+NPeriod+10)) return;
   SpreadDiagnostic();
   double N=NValue();
   if(N<=0) return;

   // Manage exits/stops every tick so intrabar breakout/stop behavior is preserved.
   ManageExits(N);
   ManageStops(N);

   // Entries and pyramiding are allowed on every tick, but one action per bar
   // prevents repeated additions in the same bar.
   ManageEntries(N);
   ManagePyramiding(N);
}
//+------------------------------------------------------------------+
