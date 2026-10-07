#property strict
#property version   "1.02"
#property description "Bitey SBT Evidence Lab v1.02 - consolidated research telemetry with always-on execution"

enum StrategyMode
{
   ORB=0,
   TREND_PULLBACK=1,
   MEAN_REVERSION=2,
   TURTLE_INTRADAY=3,
   ENSEMBLE=4
};

input StrategyMode InpStrategy=ENSEMBLE;
input ENUM_TIMEFRAMES InpTF=PERIOD_M15;

// SBT operational capital is fixed at USD 500. The MT4 account balance may be larger.
#define SBT_OPERATIONAL_CAPITAL_USD 500.0
input double RiskPct=0.25;
input double MaxDailyLossPct=2.0;
input int    MaxTradesDay=3;
input int    MaxOpenTrades=1;
input double MaxSpreadPoints=25;
input int    SlippagePoints=20;
input int    Magic=5102026;

// Strategy parameters.
input int FastEMA=20;
input int SlowEMA=50;
input int ADXPeriod=14;
input double MinADX=20;
input double MaxADXRange=18;
input int RSIPeriod=14;
input double RSILow=30;
input double RSIHigh=70;
input int BBPeriod=20;
input double BBDev=2.0;
input int ATRPeriod=14;
input int TurtleEntry=20;
input int TurtleExit=10;
input double StopATR=1.2;
input double TargetR=1.8;
input int ORBMinutes=30;
input int SessionStartHour=7;
input int SessionEndHour=20;
input int MaxBarsInTrade=16;

// Consolidated SBT telemetry.
input bool   SBTEnabled=true;
input string SBTURL="https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";
input string SBTToken="";
input int    SBTTimeoutMs=5000;
input int    TelemetryIntervalSec=30;
input int    BaseBackoffSec=30;
input int    MaxBackoffSec=300;

int tradesToday=0;
datetime day0=0,lastBar=0,lastTelemetry=0,nextTelemetryAllowed=0;
double dayEquity=0;

long barsObserved=0,signalCount=0,buySignals=0,sellSignals=0;
long blockSession=0,blockSpread=0,blockDailyDD=0,blockTradeLimit=0;
int telemetryFailures=0,lastHttpStatus=0;
string telemetryStatus="INIT";
string accountMode="REAL_VIRTUAL";
bool researchActive=true;
string promotionPolicy="MANUAL_MT4_ACCOUNT_SWITCH";
string previousSignal="NONE",lastChange="INIT";
string proposedAction="OBSERVE",nextAction="WAIT_FOR_EVIDENCE";
string lastStrategy="NONE",lastSignal="NONE";

string TFName(ENUM_TIMEFRAMES tf)
{
   if(tf==PERIOD_M1) return "M1";
   if(tf==PERIOD_M5) return "M5";
   if(tf==PERIOD_M15) return "M15";
   if(tf==PERIOD_M30) return "M30";
   if(tf==PERIOD_H1) return "H1";
   if(tf==PERIOD_H4) return "H4";
   if(tf==PERIOD_D1) return "D1";
   if(tf==PERIOD_W1) return "W1";
   if(tf==PERIOD_MN1) return "MN1";
   return IntegerToString((int)tf);
}

string StrategyName()
{
   if(InpStrategy==ORB) return "ORB";
   if(InpStrategy==TREND_PULLBACK) return "TREND_PULLBACK";
   if(InpStrategy==MEAN_REVERSION) return "MEAN_REVERSION";
   if(InpStrategy==TURTLE_INTRADAY) return "TURTLE_INTRADAY";
   return "ENSEMBLE";
}

string ExperimentId()
{
   return "INTRADAY-"+Symbol()+"-"+StrategyName()+"-"+TFName(InpTF);
}

string JsonEscape(string value)
{
   StringReplace(value,"\\","\\\\");
   StringReplace(value,"\"","\\\"");
   StringReplace(value,"\r","\\r");
   StringReplace(value,"\n","\\n");
   return value;
}

void ResetDay()
{
   datetime d=iTime(Symbol(),PERIOD_D1,0);
   if(d!=day0)
   {
      day0=d;
      dayEquity=AccountEquity();
      tradesToday=0;
   }
}

bool NewBar()
{
   datetime t=iTime(Symbol(),InpTF,0);
   if(t!=lastBar)
   {
      lastBar=t;
      return true;
   }
   return false;
}

double Spread()
{
   return (Ask-Bid)/Point;
}

int OpenCount()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
         if(OrderSymbol()==Symbol() && OrderMagicNumber()==Magic)
            n++;
   }
   return n;
}

double DD()
{
   if(dayEquity<=0) return 0;
   return MathMax(0,(dayEquity-AccountEquity())/dayEquity*100.0);
}

bool Session()
{
   int h=TimeHour(TimeCurrent());
   if(SessionStartHour==SessionEndHour) return true;
   if(SessionStartHour<SessionEndHour)
      return h>=SessionStartHour && h<SessionEndHour;
   return h>=SessionStartHour || h<SessionEndHour;
}

double ATR(int s=1)
{
   return iATR(Symbol(),InpTF,ATRPeriod,s);
}

double EMA(int p,int s)
{
   return iMA(Symbol(),InpTF,p,0,MODE_EMA,PRICE_CLOSE,s);
}

double ADX(int s=1)
{
   return iADX(Symbol(),InpTF,ADXPeriod,PRICE_CLOSE,MODE_MAIN,s);
}

double RSI(int s=1)
{
   return iRSI(Symbol(),InpTF,RSIPeriod,PRICE_CLOSE,s);
}

double BB(int mode,int s=1)
{
   return iBands(Symbol(),InpTF,BBPeriod,BBDev,0,PRICE_CLOSE,mode,s);
}

double Highest(int n)
{
   int sh=iHighest(Symbol(),InpTF,MODE_HIGH,n,1);
   if(sh<0) return 0;
   return iHigh(Symbol(),InpTF,sh);
}

double Lowest(int n)
{
   int sh=iLowest(Symbol(),InpTF,MODE_LOW,n,1);
   if(sh<0) return 0;
   return iLow(Symbol(),InpTF,sh);
}

bool Signal(int &dir,double &a,string &str,string &why)
{
   dir=0;
   a=ATR();
   str="NONE";
   why="NONE";

   double c=iClose(Symbol(),InpTF,1);
   double p=iClose(Symbol(),InpTF,2);
   double e20=EMA(FastEMA,1);
   double e50=EMA(SlowEMA,1);
   double ad=ADX(1);
   double r=RSI(1);
   double up=BB(MODE_UPPER,1);
   double lo=BB(MODE_LOWER,1);

   if(InpStrategy==ORB || InpStrategy==ENSEMBLE)
   {
      datetime d=iTime(Symbol(),PERIOD_D1,0);
      datetime st=d+SessionStartHour*3600;
      datetime en=st+ORBMinutes*60;

      if(TimeCurrent()>=en)
      {
         double hi=-1e10,l=1e10;
         for(int s=1;s<iBars(Symbol(),InpTF);s++)
         {
            datetime t=iTime(Symbol(),InpTF,s);
            if(t<st) break;
            if(t<en)
            {
               hi=MathMax(hi,iHigh(Symbol(),InpTF,s));
               l=MathMin(l,iLow(Symbol(),InpTF,s));
            }
         }

         if(hi>l)
         {
            if(c>hi && p<=hi)
            {
               dir=OP_BUY;
               str="ORB";
               why="OPENING_RANGE_BREAKOUT";
               return true;
            }
            if(c<l && p>=l)
            {
               dir=OP_SELL;
               str="ORB";
               why="OPENING_RANGE_BREAKOUT";
               return true;
            }
         }
      }
   }

   if(InpStrategy==TREND_PULLBACK || InpStrategy==ENSEMBLE)
   {
      if(ad>=MinADX)
      {
         if(e20>e50 && iLow(Symbol(),InpTF,2)<=EMA(FastEMA,2) && c>e20)
         {
            dir=OP_BUY;
            str="TREND_PULLBACK";
            why="EMA_PULLBACK_TREND";
            return true;
         }
         if(e20<e50 && iHigh(Symbol(),InpTF,2)>=EMA(FastEMA,2) && c<e20)
         {
            dir=OP_SELL;
            str="TREND_PULLBACK";
            why="EMA_PULLBACK_TREND";
            return true;
         }
      }
   }

   if(InpStrategy==MEAN_REVERSION || InpStrategy==ENSEMBLE)
   {
      if(ad<=MaxADXRange)
      {
         if(c<lo && r<=RSILow)
         {
            dir=OP_BUY;
            str="MEAN_REVERSION";
            why="BB_RSI_EXTREME";
            return true;
         }
         if(c>up && r>=RSIHigh)
         {
            dir=OP_SELL;
            str="MEAN_REVERSION";
            why="BB_RSI_EXTREME";
            return true;
         }
      }
   }

   if(InpStrategy==TURTLE_INTRADAY || InpStrategy==ENSEMBLE)
   {
      double hi=Highest(TurtleEntry);
      double l=Lowest(TurtleEntry);

      if(c>hi && p<=hi)
      {
         dir=OP_BUY;
         str="TURTLE_INTRADAY";
         why="DONCHIAN_BREAKOUT";
         return true;
      }
      if(c<l && p>=l)
      {
         dir=OP_SELL;
         str="TURTLE_INTRADAY";
         why="DONCHIAN_BREAKOUT";
         return true;
      }
   }

   return false;
}

double RiskBudgetUSD()
{
   return SBT_OPERATIONAL_CAPITAL_USD*RiskPct/100.0;
}

double LotsForRisk(double stopDistance)
{
   if(stopDistance<=0) return 0;

   double riskMoney=RiskBudgetUSD();
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE);
   double ts=MarketInfo(Symbol(),MODE_TICKSIZE);

   if(tv<=0 || ts<=0) return 0;

   double lossPerLot=(stopDistance/ts)*tv;
   if(lossPerLot<=0) return 0;

   double lot=riskMoney/lossPerLot;
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double mn=MarketInfo(Symbol(),MODE_MINLOT);
   double mx=MarketInfo(Symbol(),MODE_MAXLOT);

   if(step<=0) step=(mn>0?mn:0.01);

   lot=MathFloor(lot/step)*step;
   // Never force the broker minimum lot when it would exceed the $500 risk budget.
   if(lot<mn) return 0;
   lot=MathMin(mx,lot);

   return NormalizeDouble(lot,2);
}

int BackoffSeconds(int status)
{
   int base=BaseBackoffSec;

   if(status==429) base=120;
   else if(status==502 || status==503 || status==504) base=90;
   else if(status>=400) base=60;

   int n=telemetryFailures;
   if(n<1) n=1;

   for(int i=1;i<n && base<MaxBackoffSec;i++)
      base=MathMin(base*2,MaxBackoffSec);

   return MathMin(base,MaxBackoffSec);
}

bool TelemetryCanSend()
{
   if(!SBTEnabled) return false;
   if(nextTelemetryAllowed==0) return true;
   return TimeCurrent()>=nextTelemetryAllowed;
}

bool SendTelemetry(string payload)
{
   if(!TelemetryCanSend()) return false;

   char data[],res[];
   int n=StringToCharArray(payload,data,0,-1,CP_UTF8);
   if(n>0 && data[n-1]==0) ArrayResize(data,n-1);

   string headers="Content-Type: application/json\r\n";
   if(SBTToken!="")
      headers+="X-MT4-Token: "+SBTToken+"\r\n";

   ResetLastError();

   string responseHeaders;
   int status=WebRequest("POST",SBTURL,headers,SBTTimeoutMs,data,res,responseHeaders);

   lastHttpStatus=status;

   if(status>=200 && status<300)
   {
      telemetryFailures=0;
      nextTelemetryAllowed=0;
      telemetryStatus="OK";
      return true;
   }

   telemetryFailures++;
   int waitSec=BackoffSeconds(status);
   nextTelemetryAllowed=TimeCurrent()+waitSec;

   if(status==429) telemetryStatus="BACKOFF_429";
   else if(status==502 || status==503 || status==504) telemetryStatus="BACKOFF_SERVER";
   else telemetryStatus="BACKOFF_ERROR";

   Print("Evidence Lab telemetry HTTP=",status,
         " err=",GetLastError(),
         " retry_in=",waitSec,"s",
         " status=",telemetryStatus);

   return false;
}

void Telemetry()
{
   if(!TelemetryCanSend()) return;

   lastTelemetry=TimeCurrent();

   accountMode=IsDemo() ? "REAL_VIRTUAL" : "REAL";
   string mode=accountMode;
   string strategy=StrategyName();
   string strategyTF=TFName(InpTF);
   string chartTF=TFName((ENUM_TIMEFRAMES)Period());
   string experiment=ExperimentId();

   string p="{";
   p+="\"schema\":\"sbt.evidence_lab.telemetry.v1\",";
   p+="\"source\":\"MT4_INTRADAY_EVIDENCE_LAB\",";
   p+="\"lab_version\":\"1.02\",";
   p+="\"mode\":\"CONSOLIDATED\",";
   p+="\"execution_enabled\":true,";
   p+="\"trading_contract\":\"AUTHORIZED_MT4_EXECUTION\",";
   p+="\"research_active\":true,";
   p+="\"research_mode\":\"CONTINUOUS\",";
   p+="\"promotion_policy\":\"MANUAL_MT4_ACCOUNT_SWITCH\",";
   p+="\"account_mode\":\""+mode+"\",";
   p+="\"symbol\":\""+JsonEscape(Symbol())+"\",";
   p+="\"strategy\":\""+JsonEscape(strategy)+"\",";
   p+="\"strategy_timeframe\":\""+strategyTF+"\",";
   p+="\"chart_timeframe\":\""+chartTF+"\",";
   p+="\"experiment_id\":\""+JsonEscape(experiment)+"\",";
   p+="\"capital\":{";
   p+="\"reference_usd\":"+DoubleToString(SBT_OPERATIONAL_CAPITAL_USD,2)+",";
   p+="\"risk_pct\":"+DoubleToString(RiskPct,3)+",";
   p+="\"risk_budget_usd\":"+DoubleToString(RiskBudgetUSD(),2)+"},";
   p+="\"state\":{";
   p+="\"current\":\""+JsonEscape(lastSignal)+"\",";
   p+="\"previous\":\""+JsonEscape(previousSignal)+"\",";
   p+="\"change\":\""+JsonEscape(lastChange)+"\",";
   p+="\"position_count\":"+IntegerToString(OpenCount())+",";
   p+="\"spread_points\":"+DoubleToString(Spread(),1)+",";
   p+="\"daily_drawdown_pct\":"+DoubleToString(DD(),3)+",";
   p+="\"trades_today\":"+IntegerToString(tradesToday)+"},";
   p+="\"risk\":{";
   p+="\"max_daily_loss_pct\":"+DoubleToString(MaxDailyLossPct,3)+",";
   p+="\"max_spread_points\":"+DoubleToString(MaxSpreadPoints,1)+",";
   p+="\"max_trades_day\":"+IntegerToString(MaxTradesDay)+",";
   p+="\"max_open_trades\":"+IntegerToString(MaxOpenTrades)+"},";
   p+="\"learning\":{";
   p+="\"continuous_research\":true,";
   p+="\"monthly_stability_gate\":\"REQUIRED_BEFORE_REAL\",";
   p+="\"live_promotion\":\"MANUAL_ONLY\",
   p+="\"proposed_action\":\""+JsonEscape(proposedAction)+"\",";
   p+="\"next_action\":\""+JsonEscape(nextAction)+"\",";
   p+="\"evidence_status\":\"LIVE_EVIDENCE\",";
   p+="\"execution_boundary\":\"MT4_ACCOUNT\"},";
   p+="\"telemetry\":{";
   p+="\"http_status\":"+IntegerToString(lastHttpStatus)+",";
   p+="\"status\":\""+JsonEscape(telemetryStatus)+"\",";
   p+="\"failures\":"+IntegerToString(telemetryFailures)+"},";
   p+="\"counters\":{";
   p+="\"bars_observed\":"+IntegerToString((int)barsObserved)+",";
   p+="\"signals\":"+IntegerToString((int)signalCount)+",";
   p+="\"buy_signals\":"+IntegerToString((int)buySignals)+",";
   p+="\"sell_signals\":"+IntegerToString((int)sellSignals)+",";
   p+="\"block_session\":"+IntegerToString((int)blockSession)+",";
   p+="\"block_spread\":"+IntegerToString((int)blockSpread)+",";
   p+="\"block_daily_dd\":"+IntegerToString((int)blockDailyDD)+",";
   p+="\"block_trade_limit\":"+IntegerToString((int)blockTradeLimit)+"},";
   p+="\"bot\":{";
   p+="\"id\":\""+JsonEscape(experiment)+"\",";
   p+="\"strategy\":\""+JsonEscape(strategy)+"\",";
   p+="\"version\":\"1.02\",";
   p+="\"magic\":"+IntegerToString(Magic)+"}";
   p+="}";

   SendTelemetry(p);
}

void Enter(int dir,double atr,string str,string why)
{
   double dist=atr*StopATR;
   double px=(dir==OP_BUY ? Ask : Bid);
   double sl=(dir==OP_BUY ? px-dist : px+dist);
   double tp=(dir==OP_BUY ? px+dist*TargetR : px-dist*TargetR);

   double lot=LotsForRisk(dist);
   if(lot<=0)
   {
      Print("Evidence Lab: risk calculation returned zero; trade blocked to preserve the $500 operational risk contract.");
      return;
   }

   ResetLastError();

   int tk=OrderSend(Symbol(),dir,lot,px,SlippagePoints,
                    NormalizeDouble(sl,Digits),
                    NormalizeDouble(tp,Digits),
                    "Bitey:"+str,Magic,0,clrNONE);

   if(tk>0)
   {
      tradesToday++;
      lastStrategy=str;
      lastSignal=why;

      Print("OPEN ticket=",tk,
            " strategy=",str,
            " reason=",why,
            " lots=",DoubleToString(lot,2),
            " reference_capital=$",DoubleToString(SBT_OPERATIONAL_CAPITAL_USD,2),
            " risk_budget=$",DoubleToString(RiskBudgetUSD(),2),
            " SL=",DoubleToString(sl,Digits),
            " TP=",DoubleToString(tp,Digits));
   }
   else
   {
      Print("OrderSend error=",GetLastError());
   }
}

void TimeExit()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES) &&
         OrderSymbol()==Symbol() &&
         OrderMagicNumber()==Magic)
      {
         int sh=iBarShift(Symbol(),InpTF,OrderOpenTime(),false);
         if(sh>=MaxBarsInTrade)
         {
            double px=(OrderType()==OP_BUY ? Bid : Ask);
            ResetLastError();
            OrderClose(OrderTicket(),OrderLots(),px,SlippagePoints,clrNONE);
         }
      }
   }
}

int OnInit()
{
   ResetDay();
   lastBar=iTime(Symbol(),InpTF,0);

   Print("Bitey SBT Evidence Lab v1.02 initialized.");
   Print("Trading contract=AUTHORIZED_MT4_EXECUTION; account mode=",IsDemo() ? "REAL_VIRTUAL" : "REAL");
   Print("Continuous research=ON; live promotion=MANUAL_MT4_ACCOUNT_SWITCH; monthly stability gate=REQUIRED_BEFORE_REAL.");
   Print("Reference capital=$",DoubleToString(SBT_OPERATIONAL_CAPITAL_USD,2),
         " risk=",DoubleToString(RiskPct,3),
         "% budget=$",DoubleToString(RiskBudgetUSD(),2),
         " strategyTF=",TFName(InpTF),
         " chartTF=",TFName((ENUM_TIMEFRAMES)Period()));

   return INIT_SUCCEEDED;
}

void OnTick()
{
   ResetDay();
   barsObserved++;

   if(!Session()) blockSession++;
   if(Spread()>MaxSpreadPoints) blockSpread++;
   if(DD()>=MaxDailyLossPct) blockDailyDD++;
   if(tradesToday>=MaxTradesDay || OpenCount()>=MaxOpenTrades) blockTradeLimit++;

   TimeExit();

   if(NewBar())
   {
      int dir;
      double a;
      string s,w;

      if(Signal(dir,a,s,w))
      {
         previousSignal=lastSignal;
         lastSignal=w;
         lastStrategy=s;
         signalCount++;

         if(dir==OP_BUY) buySignals++;
         if(dir==OP_SELL) sellSignals++;

         lastChange="SIGNAL_"+w;
         proposedAction="EXECUTE_CANDIDATE";
         nextAction="MONITOR_OUTCOME";
      }
      else
      {
         previousSignal=lastSignal;
         lastSignal="NONE";
         lastChange="NO_SIGNAL";
         proposedAction="OBSERVE";
         nextAction="WAIT_FOR_NEW_SIGNAL";
      }
   }

   Telemetry();

   // Permanent contract: no EnableTrading switch, no ResearchOnly gate,
   // no IsDemo gate. MT4's currently connected account determines execution.
   if(!Session()) return;
   if(DD()>=MaxDailyLossPct) return;
   if(Spread()>MaxSpreadPoints) return;
   if(tradesToday>=MaxTradesDay) return;
   if(OpenCount()>=MaxOpenTrades) return;

   int dir;
   double a;
   string s,w;

   if(Signal(dir,a,s,w))
      Enter(dir,a,s,w);
}
