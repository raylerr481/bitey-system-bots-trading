#property strict
#property version   "1.02"
#property description "Bitey SBT Intraday Evidence Lab v1.02 - consolidated execution and research telemetry"

// ============================================================
// Bitey SBT Intraday Evidence Lab v1.02
// ============================================================
// Purpose:
// - Intraday evidence/research EA
// - ORB
// - Trend Pullback
// - Mean Reversion
// - Turtle Intraday
// - Ensemble
// - Trading enabled by default
// - MT4 account determines DEMO/REAL mode
// - Consolidated telemetry to Bitey SBT
// - HTTP 429 exponential backoff
//
// IMPORTANT:
// The EA does NOT switch DEMO/REAL accounts.
// MT4 determines whether the attached account is DEMO or REAL.
// ============================================================

enum StrategyMode
{
   ORB=0,
   TREND_PULLBACK=1,
   MEAN_REVERSION=2,
   TURTLE_INTRADAY=3,
   ENSEMBLE=4
};

// ============================================================
// GENERAL
// ============================================================

input StrategyMode InpStrategy=ENSEMBLE;
input ENUM_TIMEFRAMES InpTF=PERIOD_M15;

// ============================================================
// EXECUTION / RISK
// ============================================================

input double RiskPct=0.25;
input double MaxDailyLossPct=2.0;

input int MaxTradesDay=3;
input int MaxOpenTrades=1;

input double MaxSpreadPoints=25;
input int SlippagePoints=20;

input int Magic=5102026;

// Trading is intentionally enabled.
// MT4 account type determines DEMO or REAL.
input bool EnableTrading=true;

// ============================================================
// SIGNAL PARAMETERS
// ============================================================

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

// ============================================================
// SBT TELEMETRY
// ============================================================

input bool SBTEnabled=true;

input string SBTURL=
   "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";

input string SBTToken="";

input int SBTTimeoutMs=5000;

input int TelemetryIntervalSec=30;

input int HTTP429BaseBackoffSec=60;
input int HTTPMaxBackoffSec=900;

// ============================================================
// STATE
// ============================================================

int tradesToday=0;

datetime day0=0;
datetime lastBar=0;
datetime lastTelemetry=0;

double dayEquity=0;

string lastStrategy="NONE";
string lastSignal="NONE";
string lastReject="NONE";

int lastHTTPCode=0;
int lastHTTPError=0;

int telemetryBackoffSec=0;

datetime telemetryBlockedUntil=0;

int telemetryOK=0;
int telemetryFail=0;


// ============================================================
// RESET DAILY STATE
// ============================================================

void ResetDay()
{
   datetime d=iTime(Symbol(),PERIOD_D1,0);

   if(d!=day0)
   {
      day0=d;

      dayEquity=AccountEquity();

      tradesToday=0;

      lastStrategy="NONE";
      lastSignal="NONE";
      lastReject="NONE";

      Print(
         "New trading day. Equity baseline=",
         DoubleToString(dayEquity,2)
      );
   }
}


// ============================================================
// NEW BAR
// ============================================================

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


// ============================================================
// SPREAD
// ============================================================

double Spread()
{
   return (Ask-Bid)/Point;
}


// ============================================================
// OPEN TRADES
// ============================================================

int OpenCount()
{
   int n=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))
      {
         if(OrderSymbol()==Symbol() &&
            OrderMagicNumber()==Magic)
         {
            n++;
         }
      }
   }

   return n;
}


// ============================================================
// DAILY DRAWDOWN
// ============================================================

double DD()
{
   if(dayEquity<=0)
      return 0;

   double dd=(dayEquity-AccountEquity())/dayEquity*100.0;

   if(dd<0)
      dd=0;

   return dd;
}


// ============================================================
// SESSION
// ============================================================

bool Session()
{
   int h=TimeHour(TimeCurrent());

   if(SessionStartHour<=SessionEndHour)
   {
      return(
         h>=SessionStartHour &&
         h<SessionEndHour
      );
   }

   // Overnight session
   return(
      h>=SessionStartHour ||
      h<SessionEndHour
   );
}


// ============================================================
// INDICATORS
// ============================================================

double ATR(int shift=1)
{
   return iATR(
      Symbol(),
      InpTF,
      ATRPeriod,
      shift
   );
}


double EMA(int period,int shift)
{
   return iMA(
      Symbol(),
      InpTF,
      period,
      0,
      MODE_EMA,
      PRICE_CLOSE,
      shift
   );
}


double ADX(int shift)
{
   return iADX(
      Symbol(),
      InpTF,
      ADXPeriod,
      PRICE_CLOSE,
      MODE_MAIN,
      shift
   );
}


double RSI(int shift)
{
   return iRSI(
      Symbol(),
      InpTF,
      RSIPeriod,
      PRICE_CLOSE,
      shift
   );
}


double BB(int mode,int shift)
{
   return iBands(
      Symbol(),
      InpTF,
      BBPeriod,
      BBDev,
      0,
      PRICE_CLOSE,
      mode,
      shift
   );
}


// ============================================================
// HIGHEST / LOWEST
// ============================================================

double Highest(int n)
{
   int sh=iHighest(
      Symbol(),
      InpTF,
      MODE_HIGH,
      n,
      1
   );

   if(sh<0)
      return 0;

   return iHigh(
      Symbol(),
      InpTF,
      sh
   );
}


double Lowest(int n)
{
   int sh=iLowest(
      Symbol(),
      InpTF,
      MODE_LOW,
      n,
      1
   );

   if(sh<0)
      return 0;

   return iLow(
      Symbol(),
      InpTF,
      sh
   );
}


// ============================================================
// STRATEGY NAME
// ============================================================

string StrategyModeName()
{
   if(InpStrategy==ORB)
      return "ORB";

   if(InpStrategy==TREND_PULLBACK)
      return "TREND_PULLBACK";

   if(InpStrategy==MEAN_REVERSION)
      return "MEAN_REVERSION";

   if(InpStrategy==TURTLE_INTRADAY)
      return "TURTLE_INTRADAY";

   return "ENSEMBLE";
}


// ============================================================
// SIGNAL ENGINE
// ============================================================

bool Signal(
   int &dir,
   double &a,
   string &str,
   string &why
)
{
   dir=0;

   a=ATR();

   str="NONE";
   why="NONE";

   if(a<=0)
      return false;

   double c=iClose(
      Symbol(),
      InpTF,
      1
   );

   double p=iClose(
      Symbol(),
      InpTF,
      2
   );

   double e20=EMA(
      FastEMA,
      1
   );

   double e50=EMA(
      SlowEMA,
      1
   );

   double ad=ADX(1);

   double r=RSI(1);

   double up=BB(
      MODE_UPPER,
      1
   );

   double lo=BB(
      MODE_LOWER,
      1
   );

   // =========================================================
   // ORB
   // =========================================================

   if(
      InpStrategy==ORB ||
      InpStrategy==ENSEMBLE
   )
   {
      datetime d=iTime(
         Symbol(),
         PERIOD_D1,
         0
      );

      datetime st=
         d+
         SessionStartHour*3600;

      datetime en=
         st+
         ORBMinutes*60;

      if(TimeCurrent()>=en)
      {
         double hi=-1e10;
         double l=1e10;

         int bars=iBars(
            Symbol(),
            InpTF
         );

         for(int s=1;s<bars;s++)
         {
            datetime t=iTime(
               Symbol(),
               InpTF,
               s
            );

            if(t<st)
               break;

            if(t<en)
            {
               hi=MathMax(
                  hi,
                  iHigh(Symbol(),InpTF,s)
               );

               l=MathMin(
                  l,
                  iLow(Symbol(),InpTF,s)
               );
            }
         }

         if(hi>l)
         {
            if(
               c>hi &&
               p<=hi
            )
            {
               dir=OP_BUY;

               str="ORB";

               why="OPENING_RANGE_BREAKOUT";

               return true;
            }

            if(
               c<l &&
               p>=l
            )
            {
               dir=OP_SELL;

               str="ORB";

               why="OPENING_RANGE_BREAKOUT";

               return true;
            }
         }
      }
   }


   // =========================================================
   // TREND PULLBACK
   // =========================================================

   if(
      InpStrategy==TREND_PULLBACK ||
      InpStrategy==ENSEMBLE
   )
   {
      if(ad>=MinADX)
      {
         double e20prev=EMA(
            FastEMA,
            2
         );

         double lowPrev=iLow(
            Symbol(),
            InpTF,
            2
         );

         double highPrev=iHigh(
            Symbol(),
            InpTF,
            2
         );

         if(
            e20>e50 &&
            lowPrev<=e20prev &&
            c>e20
         )
         {
            dir=OP_BUY;

            str="TREND_PULLBACK";

            why="EMA_PULLBACK_TREND";

            return true;
         }

         if(
            e20<e50 &&
            highPrev>=e20prev &&
            c<e20
         )
         {
            dir=OP_SELL;

            str="TREND_PULLBACK";

            why="EMA_PULLBACK_TREND";

            return true;
         }
      }
   }


   // =========================================================
   // MEAN REVERSION
   // =========================================================

   if(
      InpStrategy==MEAN_REVERSION ||
      InpStrategy==ENSEMBLE
   )
   {
      if(ad<=MaxADXRange)
      {
         if(
            c<lo &&
            r<=RSILow
         )
         {
            dir=OP_BUY;

            str="MEAN_REVERSION";

            why="BB_RSI_EXTREME";

            return true;
         }

         if(
            c>up &&
            r>=RSIHigh
         )
         {
            dir=OP_SELL;

            str="MEAN_REVERSION";

            why="BB_RSI_EXTREME";

            return true;
         }
      }
   }


   // =========================================================
   // TURTLE INTRADAY
   // =========================================================

   if(
      InpStrategy==TURTLE_INTRADAY ||
      InpStrategy==ENSEMBLE
   )
   {
      double hi=Highest(
         TurtleEntry
      );

      double l=Lowest(
         TurtleEntry
      );

      if(
         hi>0 &&
         c>hi &&
         p<=hi
      )
      {
         dir=OP_BUY;

         str="TURTLE_INTRADAY";

         why="DONCHIAN_BREAKOUT";

         return true;
      }

      if(
         l>0 &&
         c<l &&
         p>=l
      )
      {
         dir=OP_SELL;

         str="TURTLE_INTRADAY";

         why="DONCHIAN_BREAKOUT";

         return true;
      }
   }


   return false;
}


// ============================================================
// LOT CALCULATOR
// ============================================================

double Lots(double stop)
{
   if(stop<=0)
      return 0;

   double tickValue=
      MarketInfo(
         Symbol(),
         MODE_TICKVALUE
      );

   double tickSize=
      MarketInfo(
         Symbol(),
         MODE_TICKSIZE
      );

   if(
      tickValue<=0 ||
      tickSize<=0
   )
      return 0;

   double money=
      AccountEquity()*
      RiskPct/
      100.0;

   double lossPerLot=
      (stop/tickSize)*
      tickValue;

   if(lossPerLot<=0)
      return 0;

   double lot=
      money/
      lossPerLot;

   double step=
      MarketInfo(
         Symbol(),
         MODE_LOTSTEP
      );

   double minLot=
      MarketInfo(
         Symbol(),
         MODE_MINLOT
      );

   double maxLot=
      MarketInfo(
         Symbol(),
         MODE_MAXLOT
      );

   if(step<=0)
      step=minLot;

   if(step<=0)
      step=0.01;

   lot=
      MathFloor(
         lot/step
      )*
      step;

   if(lot<minLot)
      lot=minLot;

   if(lot>maxLot)
      lot=maxLot;

   return NormalizeDouble(
      lot,
      2
   );
}


// ============================================================
// ENTER TRADE
// ============================================================

void Enter(
   int dir,
   double atr,
   string str,
   string why
)
{
   if(atr<=0)
   {
      lastReject="INVALID_ATR";
      return;
   }

   double dist=
      atr*
      StopATR;

   if(dist<=0)
   {
      lastReject="INVALID_STOP_DISTANCE";
      return;
   }

   double px=
      (dir==OP_BUY)
      ? Ask
      : Bid;

   double sl=
      (dir==OP_BUY)
      ? px-dist
      : px+dist;

   double tp=
      (dir==OP_BUY)
      ? px+dist*TargetR
      : px-dist*TargetR;

   double lot=
      Lots(dist);

   if(lot<=0)
   {
      lastReject="INVALID_LOT";
      return;
   }

   sl=NormalizeDouble(
      sl,
      Digits
   );

   tp=NormalizeDouble(
      tp,
      Digits
   );

   px=NormalizeDouble(
      px,
      Digits
   );

   ResetLastError();

   int ticket=OrderSend(
      Symbol(),
      dir,
      lot,
      px,
      SlippagePoints,
      sl,
      tp,
      "Bitey:"+str,
      Magic,
      0,
      clrNONE
   );

   int err=GetLastError();

   if(ticket>0)
   {
      tradesToday++;

      lastStrategy=str;
      lastSignal=why;
      lastReject="NONE";

      Print(
         "OPEN ticket=",
         ticket,
         " strategy=",
         str,
         " reason=",
         why,
         " lots=",
         DoubleToString(lot,2),
         " price=",
         DoubleToString(px,Digits),
         " SL=",
         DoubleToString(sl,Digits),
         " TP=",
         DoubleToString(tp,Digits)
      );
   }
   else
   {
      lastReject=
         "ORDER_ERROR_"+
         IntegerToString(err);

      Print(
         "OrderSend failed. Error=",
         err,
         " strategy=",
         str
      );
   }
}


// ============================================================
// TIME EXIT
// ============================================================

void TimeExit()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(
         i,
         SELECT_BY_POS,
         MODE_TRADES
      ))
         continue;

      if(
         OrderSymbol()!=Symbol() ||
         OrderMagicNumber()!=Magic
      )
         continue;

      int sh=iBarShift(
         Symbol(),
         InpTF,
         OrderOpenTime(),
         false
      );

      if(
         sh>=MaxBarsInTrade &&
         sh>=0
      )
      {
         int ticket=
            OrderTicket();

         double lots=
            OrderLots();

         int type=
            OrderType();

         double px=
            (type==OP_BUY)
            ? Bid
            : Ask;

         ResetLastError();

         // IMPORTANT:
         // OrderClose return value is explicitly checked.
         bool closeResult=
            OrderClose(
               ticket,
               lots,
               px,
               SlippagePoints,
               clrNONE
            );

         int closeError=
            GetLastError();

         if(!closeResult)
         {
            lastReject=
               "TIME_EXIT_ERROR_"+
               IntegerToString(
                  closeError
               );

            Print(
               "TimeExit OrderClose failed. Ticket=",
               ticket,
               " Error=",
               closeError
            );
         }
         else
         {
            lastReject="NONE";

            Print(
               "TimeExit closed ticket=",
               ticket
            );
         }
      }
   }
}


// ============================================================
// JSON ESCAPE
// ============================================================

string JsonEscape(string s)
{
   StringReplace(
      s,
      "\\",
      "\\\\"
   );

   StringReplace(
      s,
      "\"",
      "\\\""
   );

   return s;
}


// ============================================================
// TELEMETRY RESULT / HTTP BACKOFF
// ============================================================

void RegisterTelemetryResult(
   int code,
   int err
)
{
   lastHTTPCode=code;
   lastHTTPError=err;

   // Successful response
   if(
      code>=200 &&
      code<300
   )
   {
      telemetryOK++;

      telemetryBackoffSec=0;

      telemetryBlockedUntil=0;

      return;
   }

   telemetryFail++;

   // ---------------------------------------------------------
   // HTTP 429
   // Exponential backoff:
   // 60 -> 120 -> 240 -> 480 -> 900 seconds
   // ---------------------------------------------------------

   if(code==429)
   {
      if(telemetryBackoffSec<=0)
      {
         telemetryBackoffSec=
            HTTP429BaseBackoffSec;
      }
      else
      {
         telemetryBackoffSec=
            MathMin(
               HTTPMaxBackoffSec,
               telemetryBackoffSec*2
            );
      }

      telemetryBlockedUntil=
         TimeCurrent()+
         telemetryBackoffSec;

      Print(
         "SBT HTTP 429. Telemetry backoff=",
         telemetryBackoffSec,
         " sec"
      );
   }
   else
   {
      // Generic HTTP/network failure
      if(telemetryBackoffSec<=0)
      {
         telemetryBackoffSec=30;
      }
      else
      {
         telemetryBackoffSec=
            MathMin(
               HTTPMaxBackoffSec,
               telemetryBackoffSec*2
            );
      }

      telemetryBlockedUntil=
         TimeCurrent()+
         telemetryBackoffSec;
   }
}


// ============================================================
// TELEMETRY
// ============================================================

void Telemetry()
{
   if(!SBTEnabled)
      return;

   if(
      TimeCurrent()-
      lastTelemetry<
      TelemetryIntervalSec
   )
      return;

   if(
      TimeCurrent()<
      telemetryBlockedUntil
   )
      return;

   lastTelemetry=
      TimeCurrent();

   string mode=
      (IsDemo()
      ? "DEMO"
      : "REAL");

   string allowed=
      (IsTradeAllowed()
      ? "true"
      : "false");

   string p="{";

   p+=
      "\"source\":\"MT4_INTRADAY_EVIDENCE_LAB\",";

   p+=
      "\"version\":\"1.02\",";

   p+=
      "\"account_mode\":\""+
      mode+
      "\",";

   p+=
      "\"account_number\":"+
      IntegerToString(
         AccountNumber()
      )+
      ",";

   p+=
      "\"trade_allowed\":"+
      allowed+
      ",";

   p+=
      "\"enable_trading\":"+
      (
         EnableTrading
         ? "true"
         : "false"
      )+
      ",";

   p+=
      "\"symbol\":\""+
      JsonEscape(Symbol())+
      "\",";

   p+=
      "\"timeframe\":"+
      IntegerToString(InpTF)+
      ",";

   p+=
      "\"strategy_mode\":\""+
      StrategyModeName()+
      "\",";

   p+=
      "\"last_strategy\":\""+
      JsonEscape(lastStrategy)+
      "\",";

   p+=
      "\"last_signal\":\""+
      JsonEscape(lastSignal)+
      "\",";

   p+=
      "\"last_reject\":\""+
      JsonEscape(lastReject)+
      "\",";

   p+=
      "\"trades_today\":"+
      IntegerToString(
         tradesToday
      )+
      ",";

   p+=
      "\"open_trades\":"+
      IntegerToString(
         OpenCount()
      )+
      ",";

   p+=
      "\"daily_drawdown_pct\":"+
      DoubleToString(
         DD(),
         4
      )+
      ",";

   p+=
      "\"spread_points\":"+
      DoubleToString(
         Spread(),
         1
      )+
      ",";

   p+=
      "\"balance\":"+
      DoubleToString(
         AccountBalance(),
         2
      )+
      ",";

   p+=
      "\"equity\":"+
      DoubleToString(
         AccountEquity(),
         2
      )+
      ",";

   p+=
      "\"risk_pct\":"+
      DoubleToString(
         RiskPct,
         3
      )+
      ",";

   p+=
      "\"max_daily_loss_pct\":"+
      DoubleToString(
         MaxDailyLossPct,
         3
      )+
      ",";

   p+=
      "\"telemetry_ok\":"+
      IntegerToString(
         telemetryOK
      )+
      ",";

   p+=
      "\"telemetry_fail\":"+
      IntegerToString(
         telemetryFail
      )+
      ",";

   p+=
      "\"last_http_code\":"+
      IntegerToString(
         lastHTTPCode
      )+
      ",";

   p+=
      "\"last_http_error\":"+
      IntegerToString(
         lastHTTPError
      )+
      ",";

   p+=
      "\"telemetry_backoff_sec\":"+
      IntegerToString(
         telemetryBackoffSec
      );

   p+="}";


   // =========================================================
   // CONVERT JSON TO UTF-8
   // =========================================================

   char data[];
   char res[];

   int n=
      StringToCharArray(
         p,
         data,
         0,
         -1,
         CP_UTF8
      );

   if(
      n>0 &&
      data[n-1]==0
   )
   {
      ArrayResize(
         data,
         n-1
      );
   }


   // =========================================================
   // HTTP HEADERS
   // =========================================================

   string hdr=
      "Content-Type: application/json\r\n";

   if(SBTToken!="")
   {
      hdr+=
         "X-MT4-Token: "+
         SBTToken+
         "\r\n";
   }


   // =========================================================
   // WEB REQUEST
   // =========================================================

   ResetLastError();

   string response_headers="";

   int code=
      WebRequest(
         "POST",
         SBTURL,
         hdr,
         SBTTimeoutMs,
         data,
         res,
         response_headers
      );

   int err=
      GetLastError();

   RegisterTelemetryResult(
      code,
      err
   );

   Print(
      "SBT telemetry HTTP=",
      code,
      " err=",
      err,
      " mode=",
      mode,
      " trade_allowed=",
      allowed,
      " trades_today=",
      tradesToday
   );
}


// ============================================================
// INITIALIZATION
// ============================================================

int OnInit()
{
   ResetDay();

   lastBar=
      iTime(
         Symbol(),
         InpTF,
         0
      );

   Print(
      "================================================"
   );

   Print(
      "Bitey SBT Intraday Evidence Lab v1.02"
   );

   Print(
      "Strategy=",
      StrategyModeName()
   );

   Print(
      "Timeframe=",
      InpTF
   );

   Print(
      "EnableTrading=",
      EnableTrading
   );

   Print(
      "AccountMode=",
      (IsDemo() ? "DEMO" : "REAL")
   );

   Print(
      "AccountNumber=",
      AccountNumber()
   );

   Print(
      "Balance=",
      DoubleToString(
         AccountBalance(),
         2
      )
   );

   Print(
      "Equity=",
      DoubleToString(
         AccountEquity(),
         2
      )
   );

   Print(
      "RiskPct=",
      DoubleToString(
         RiskPct,
         3
      )
   );

   Print(
      "MaxDailyLossPct=",
      DoubleToString(
         MaxDailyLossPct,
         3
      )
   );

   Print(
      "MaxTradesDay=",
      MaxTradesDay
   );

   Print(
      "MaxOpenTrades=",
      MaxOpenTrades
   );

   Print(
      "SBTEnabled=",
      SBTEnabled
   );

   Print(
      "================================================"
   );

   return INIT_SUCCEEDED;
}


// ============================================================
// DEINITIALIZATION
// ============================================================

void OnDeinit(
   const int reason
)
{
   Print(
      "Bitey SBT Intraday Evidence Lab v1.02 stopped.",
      " reason=",
      reason,
      " telemetry_ok=",
      telemetryOK,
      " telemetry_fail=",
      telemetryFail
   );
}


// ============================================================
// MAIN LOOP
// ============================================================

void OnTick()
{
   // ---------------------------------------------------------
   // Daily state
   // ---------------------------------------------------------

   ResetDay();


   // ---------------------------------------------------------
   // Telemetry runs independently from trading decisions.
   // ---------------------------------------------------------

   Telemetry();


   // ---------------------------------------------------------
   // Manage existing position.
   // ---------------------------------------------------------

   TimeExit();


   // ---------------------------------------------------------
   // Trading master switch.
   // ---------------------------------------------------------

   if(!EnableTrading)
   {
      lastReject="TRADING_DISABLED";
      return;
   }


   // ---------------------------------------------------------
   // One decision per new bar.
   // ---------------------------------------------------------

   if(!NewBar())
      return;


   // ---------------------------------------------------------
   // Session filter.
   // ---------------------------------------------------------

   if(!Session())
   {
      lastReject="OUT_OF_SESSION";
      return;
   }


   // ---------------------------------------------------------
   // Daily drawdown protection.
   // ---------------------------------------------------------

   if(
      DD()>=MaxDailyLossPct
   )
   {
      lastReject="DAILY_DRAWDOWN";
      return;
   }


   // ---------------------------------------------------------
   // Spread protection.
   // ---------------------------------------------------------

   if(
      Spread()>MaxSpreadPoints
   )
   {
      lastReject="SPREAD";
      return;
   }


   // ---------------------------------------------------------
   // Daily trade limit.
   // ---------------------------------------------------------

   if(
      tradesToday>=MaxTradesDay
   )
   {
      lastReject="MAX_TRADES_DAY";
      return;
   }


   // ---------------------------------------------------------
   // Maximum simultaneous positions.
   // ---------------------------------------------------------

   if(
      OpenCount()>=MaxOpenTrades
   )
   {
      lastReject="MAX_OPEN_TRADES";
      return;
   }


   // ---------------------------------------------------------
   // Signal engine.
   // ---------------------------------------------------------

   int dir=0;

   double a=0;

   string s="NONE";

   string w="NONE";


   if(
      Signal(
         dir,
         a,
         s,
         w
      )
   )
   {
      Enter(
         dir,
         a,
         s,
         w
      );
   }
   else
   {
      lastReject="NO_SIGNAL";
   }
}