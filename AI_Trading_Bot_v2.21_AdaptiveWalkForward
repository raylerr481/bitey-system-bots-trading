//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.21_AdaptiveWalkForward.mq4                    |
//| Bitey IA - Adaptive Walk-Forward Regime Evidence EA             |
//| Deterministic/local; Strategy Tester ready                      |
//+------------------------------------------------------------------+
#property strict
#property version "2.21"
#property description "Walk-forward 8-strategy regime-aware MT4 Expert Advisor - adaptive selection"

#define STRATEGY_COUNT 8
#define REGIME_COUNT 5

enum REGIME
{
   UNKNOWN=0,
   TREND_UP=1,
   TREND_DOWN=2,
   RANGE=3,
   BREAKOUT=4,
   HIGH_VOL=5
};

//==================================================================
// INPUTS
//==================================================================

input bool   InpEnableTrading=false;
input bool   InpBacktestExecution=true;

input double InpRiskPercent=0.25;
input int    InpMagic=2035021;
input int    InpMaxOpenTrades=1;

input int    InpATRPeriod=14;
input int    InpADXPeriod=14;
input int    InpRSIPeriod=14;

input int    InpFastEMA=8;
input int    InpSlowEMA=21;
input int    InpTrendEMA=200;

input int    InpLookback=1500;
input int    InpOOSBars=300;
input int    InpAuditHorizon=15;

input int    InpMinTrainTrades=20;
input int    InpMinOOSTrades=8;

input double InpMinOOSExpectancy=0.02;
input double InpMinOOSPF=1.05;
input double InpMaxOOSDrawdown=8.0;

input double InpSL_ATR=1.30;
input double InpTP_ATR=2.60;

input double InpMinADXTrend=22.0;
input double InpMaxADXRange=18.0;
input double InpMinATRPoints=5.0;

input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATR=0.20;

input int    InpSessionStart=7;
input int    InpSessionEnd=20;

input int    InpCooldownBars=3;

// Primary confirmation is disabled initially so that the selected
// strategy can be measured without an additional blocking filter.
input bool   InpRequireSecondConfirmation=false;

// Adaptive diagnostic relaxation.
// It is only used when no strict candidate exists.
input bool   InpAllowAdaptiveRelaxation=true;
input int    InpRelaxedMinTrainTrades=15;
input int    InpRelaxedMinOOSTrades=5;
input double InpRelaxedMinOOSExpectancy=0.00;
input double InpRelaxedMinOOSPF=0.95;
input double InpRelaxedMaxOOSDrawdown=12.0;

// Estimated round-trip spread cost used by historical audit.
input double InpAuditSpreadPoints=1.0;

input bool   InpPrintAudit=true;
input bool   InpWriteCSV=true;

input string InpCSVFile=
   "Bitey_v2.21_Decisions.csv";

//==================================================================
// STATISTICS
//==================================================================

struct Stats
{
   int trades;
   int wins;
   int losses;
   int maxLossStreak;

   double net;
   double gp;
   double gl;
   double pf;
   double expectancy;
   double dd;
};

Stats gTrain[STRATEGY_COUNT];
Stats gOOS[STRATEGY_COUNT];

//==================================================================
// GLOBAL STATE
//==================================================================

int gBest=-1;
int gLastBars=-1;
int gLastDir=0;
int gLastStrategy=-1;
int gLossStreak=0;

bool gBestRelaxed=false;

datetime gLastBar=0;
datetime gLastTrade=0;

REGIME gRegime=UNKNOWN;

//==================================================================
// NAMES
//==================================================================

string SName(int id)
{
   if(id==0) return "TREND_FOLLOWING";
   if(id==1) return "MEAN_REVERSION";
   if(id==2) return "MOMENTUM";
   if(id==3) return "VOLATILITY_BREAKOUT";
   if(id==4) return "SESSION_BIAS";
   if(id==5) return "DIVERGENCE";
   if(id==6) return "STRICT_RANGE";
   if(id==7) return "FRACTAL_HTF";

   return "UNKNOWN";
}

//------------------------------------------------------------------

string RName(REGIME r)
{
   if(r==TREND_UP)   return "TREND_UP";
   if(r==TREND_DOWN) return "TREND_DOWN";
   if(r==RANGE)      return "RANGE";
   if(r==BREAKOUT)   return "BREAKOUT";
   if(r==HIGH_VOL)   return "HIGH_VOL";

   return "UNKNOWN";
}

//==================================================================
// INDICATORS
//==================================================================

double ATR(int s)
{
   return iATR(
      Symbol(),
      Period(),
      InpATRPeriod,
      s
   );
}

//------------------------------------------------------------------

double ATRPts(int s)
{
   if(Point<=0)
      return 0;

   return ATR(s)/Point;
}

//------------------------------------------------------------------

double ADX(int s)
{
   return iADX(
      Symbol(),
      Period(),
      InpADXPeriod,
      PRICE_CLOSE,
      MODE_MAIN,
      s
   );
}

//------------------------------------------------------------------

double RSI(int s)
{
   return iRSI(
      Symbol(),
      Period(),
      InpRSIPeriod,
      PRICE_CLOSE,
      s
   );
}

//------------------------------------------------------------------

double EMA(int p,int s)
{
   return iMA(
      Symbol(),
      Period(),
      p,
      0,
      MODE_EMA,
      PRICE_CLOSE,
      s
   );
}

//==================================================================
// STATISTICS
//==================================================================

void Reset(Stats &x)
{
   x.trades=0;
   x.wins=0;
   x.losses=0;
   x.maxLossStreak=0;

   x.net=0;
   x.gp=0;
   x.gl=0;
   x.pf=0;
   x.expectancy=0;
   x.dd=0;
}

//------------------------------------------------------------------

void Add(
   Stats &x,
   double r,
   int &streak
)
{
   x.trades++;
   x.net+=r;

   if(r>0)
   {
      x.wins++;
      x.gp+=r;
      streak=0;
   }
   else
   {
      x.losses++;
      x.gl+=r;

      streak++;

      if(streak>x.maxLossStreak)
         x.maxLossStreak=streak;
   }
}

//------------------------------------------------------------------

void Finalize(Stats &x)
{
   if(x.trades>0)
      x.expectancy=x.net/x.trades;

   if(x.gl<0)
      x.pf=x.gp/MathAbs(x.gl);
}

//==================================================================
// REGIME DETECTION
//==================================================================

REGIME RegimeAt(int s)
{
   if(Bars<s+80)
      return UNKNOWN;

   double a=ATRPts(s);
   double d=ADX(s);

   double f=EMA(InpFastEMA,s);
   double sl=EMA(InpSlowEMA,s);
   double t=EMA(InpTrendEMA,s);

   // High volatility first.
   if(
      a>=InpMinATRPoints*2.5 &&
      d>=28
   )
      return HIGH_VOL;

   // Confirmed uptrend.
   if(
      d>=InpMinADXTrend &&
      f>sl &&
      Close[s]>t
   )
      return TREND_UP;

   // Confirmed downtrend.
   if(
      d>=InpMinADXTrend &&
      f<sl &&
      Close[s]<t
   )
      return TREND_DOWN;

   // Breakout.
   int hi=iHighest(
      Symbol(),
      Period(),
      MODE_HIGH,
      20,
      s+2
   );

   int lo=iLowest(
      Symbol(),
      Period(),
      MODE_LOW,
      20,
      s+2
   );

   if(
      hi>=0 &&
      lo>=0 &&
      (
         Close[s]>iHigh(Symbol(),Period(),hi) ||
         Close[s]<iLow(Symbol(),Period(),lo)
      )
   )
      return BREAKOUT;

   // Range.
   if(d<=InpMaxADXRange)
      return RANGE;

   // Secondary trend classification.
   if(f>sl)
      return TREND_UP;

   if(f<sl)
      return TREND_DOWN;

   return RANGE;
}

//------------------------------------------------------------------

REGIME CurrentRegime()
{
   return RegimeAt(1);
}

//==================================================================
// SESSION STRATEGY
//==================================================================

int SessionSignal(int s)
{
   int h=TimeHour(Time[s]);

   if(
      h<InpSessionStart ||
      h>=InpSessionEnd
   )
      return 0;

   int d=iBarShift(
      Symbol(),
      PERIOD_D1,
      Time[s],
      false
   );

   if(d<0)
      return 0;

   datetime day=iTime(
      Symbol(),
      PERIOD_D1,
      d
   );

   datetime st=
      day+
      InpSessionStart*3600;

   int sh=iBarShift(
      Symbol(),
      Period(),
      st,
      false
   );

   if(sh<0)
      return 0;

   // Never use a future bar.
   if(sh<s)
      return 0;

   double o=iOpen(
      Symbol(),
      Period(),
      sh
   );

   if(Close[s]>o)
      return 1;

   if(Close[s]<o)
      return -1;

   return 0;
}

//==================================================================
// HTF STRATEGY
//==================================================================

int FractalHTFSignal(int s)
{
   datetime t=iTime(
      Symbol(),
      Period(),
      s
   );

   int h4=iBarShift(
      Symbol(),
      PERIOD_H4,
      t,
      false
   );

   if(h4<0)
      return 0;

   // +1 = completed H4 candle.
   double f=iMA(
      Symbol(),
      PERIOD_H4,
      InpFastEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE,
      h4+1
   );

   double sl=iMA(
      Symbol(),
      PERIOD_H4,
      InpSlowEMA,
      0,
      MODE_EMA,
      PRICE_CLOSE,
      h4+1
   );

   double local=EMA(
      InpFastEMA,
      s
   );

   if(
      f>sl &&
      Close[s]>local
   )
      return 1;

   if(
      f<sl &&
      Close[s]<local
   )
      return -1;

   return 0;
}

//==================================================================
// STRATEGY SIGNALS
//==================================================================

int Signal(
   int id,
   int s
)
{
   if(Bars<s+10)
      return 0;

   double f=EMA(InpFastEMA,s);
   double sl=EMA(InpSlowEMA,s);
   double tr=EMA(InpTrendEMA,s);
   double r=RSI(s);

   //===============================================================
   // 0 - TREND FOLLOWING
   //===============================================================

   if(id==0)
   {
      if(
         f>sl &&
         Close[s]>tr
      )
         return 1;

      if(
         f<sl &&
         Close[s]<tr
      )
         return -1;
   }

   //===============================================================
   // 1 - MEAN REVERSION
   //===============================================================

   if(id==1)
   {
      if(
         r<=28 &&
         Close[s]<f
      )
         return 1;

      if(
         r>=72 &&
         Close[s]>f
      )
         return -1;
   }

   //===============================================================
   // 2 - MOMENTUM
   //===============================================================

   if(id==2)
   {
      if(
         Close[s]>Close[s+5] &&
         r>=55 &&
         r<=78
      )
         return 1;

      if(
         Close[s]<Close[s+5] &&
         r>=22 &&
         r<=45
      )
         return -1;
   }

   //===============================================================
   // 3 - VOLATILITY BREAKOUT
   //===============================================================

   if(id==3)
   {
      int hi=iHighest(
         Symbol(),
         Period(),
         MODE_HIGH,
         20,
         s+1
      );

      int lo=iLowest(
         Symbol(),
         Period(),
         MODE_LOW,
         20,
         s+1
      );

      if(
         hi>=0 &&
         Close[s]>iHigh(Symbol(),Period(),hi)
      )
         return 1;

      if(
         lo>=0 &&
         Close[s]<iLow(Symbol(),Period(),lo)
      )
         return -1;
   }

   //===============================================================
   // 4 - SESSION BIAS
   //===============================================================

   if(id==4)
      return SessionSignal(s);

   //===============================================================
   // 5 - DIVERGENCE
   //===============================================================

   if(id==5)
   {
      double r5=RSI(s+5);

      if(
         Close[s]<Close[s+5] &&
         r>r5 &&
         r<45
      )
         return 1;

      if(
         Close[s]>Close[s+5] &&
         r<r5 &&
         r>55
      )
         return -1;
   }

   //===============================================================
   // 6 - STRICT RANGE
   //===============================================================

   if(id==6)
   {
      int hi=iHighest(
         Symbol(),
         Period(),
         MODE_HIGH,
         20,
         s+1
      );

      int lo=iLowest(
         Symbol(),
         Period(),
         MODE_LOW,
         20,
         s+1
      );

      if(
         hi>=0 &&
         lo>=0
      )
      {
         double H=iHigh(
            Symbol(),
            Period(),
            hi
         );

         double L=iLow(
            Symbol(),
            Period(),
            lo
         );

         double w=H-L;

         if(w>0)
         {
            double p=
               (Close[s]-L)/w;

            if(
               p<0.20 &&
               r<45
            )
               return 1;

            if(
               p>0.80 &&
               r>55
            )
               return -1;
         }
      }
   }

   //===============================================================
   // 7 - FRACTAL HTF
   //===============================================================

   if(id==7)
      return FractalHTFSignal(s);

   return 0;
}

//==================================================================
// STRATEGY WEIGHTS
//==================================================================

double StrategyWeight(
   int id,
   REGIME r
)
{
   if(
      r==TREND_UP ||
      r==TREND_DOWN
   )
   {
      if(
         id==0 ||
         id==2 ||
         id==7
      )
         return 1.20;

      if(
         id==1 ||
         id==6
      )
         return 0.75;
   }

   if(r==RANGE)
   {
      if(
         id==1 ||
         id==5 ||
         id==6 ||
         id==4
      )
         return 1.20;

      if(
         id==0 ||
         id==3
      )
         return 0.70;
   }

   if(
      r==BREAKOUT ||
      r==HIGH_VOL
   )
   {
      if(
         id==2 ||
         id==3 ||
         id==7 ||
         id==0
      )
         return 1.25;

      if(
         id==1 ||
         id==6
      )
         return 0.65;
   }

   return 1.0;
}

//==================================================================
// COMPATIBILITY
//==================================================================

bool Compatible(
   int id,
   REGIME r
)
{
   if(
      r==TREND_UP ||
      r==TREND_DOWN
   )
      return
         id==0 ||
         id==2 ||
         id==3 ||
         id==7;

   if(r==RANGE)
      return
         id==1 ||
         id==4 ||
         id==5 ||
         id==6;

   if(
      r==BREAKOUT ||
      r==HIGH_VOL
   )
      return
         id==0 ||
         id==2 ||
         id==3 ||
         id==7;

   return true;
}

//==================================================================
// HISTORICAL TRADE SIMULATION
//==================================================================

bool SimTrade(
   int dir,
   int entry,
   int horizon,
   double sl,
   double tp,
   double &r
)
{
   double e=Close[entry];

   int end=
      MathMax(
         1,
         entry-horizon
      );

   for(
      int k=entry-1;
      k>=end;
      k--
   )
   {
      // BUY
      if(dir>0)
      {
         // Conservative: SL checked first.
         if(Low[k]<=e-sl)
         {
            r=-1;
            return true;
         }

         if(High[k]>=e+tp)
         {
            r=tp/sl;
            return true;
         }
      }

      // SELL
      else
      {
         // Conservative: SL checked first.
         if(High[k]>=e+sl)
         {
            r=-1;
            return true;
         }

         if(Low[k]<=e-tp)
         {
            r=tp/sl;
            return true;
         }
      }
   }

   r=
      (
         dir>0
         ?
         (Close[end]-e)
         :
         (e-Close[end])
      )/sl;

   // Historical spread approximation.
   if(
      InpAuditSpreadPoints>0 &&
      sl>0
   )
   {
      r-=
         (
            InpAuditSpreadPoints*
            Point/
            sl
         );
   }

   return true;
}

//==================================================================
// AUDIT
//==================================================================

void AuditOne(int id)
{
   Reset(gTrain[id]);
   Reset(gOOS[id]);

   int available=
      Bars-
      InpAuditHorizon-
      10;

   int total=
      MathMin(
         InpLookback,
         available
      );

   int oos=
      MathMin(
         InpOOSBars,
         MathMax(
            30,
            total/5
         )
      );

   if(
      total<150 ||
      oos>=total-30
   )
      return;

   int streakT=0;
   int streakO=0;

   double eqT=0;
   double peakT=0;

   double eqO=0;
   double peakO=0;

   //===============================================================
   // TRAINING
   //===============================================================

   int trainLast=oos+1;

   for(
      int s=total;
      s>=trainLast;
      s--
   )
   {
      int sig=Signal(id,s);

      if(sig==0)
         continue;

      double a=ATR(s);

      if(a<=0)
         continue;

      double r=0;

      SimTrade(
         sig,
         s,
         InpAuditHorizon,
         a*InpSL_ATR,
         a*InpTP_ATR,
         r
      );

      Add(
         gTrain[id],
         r,
         streakT
      );

      eqT+=r;

      if(eqT>peakT)
         peakT=eqT;

      if(
         peakT-eqT>
         gTrain[id].dd
      )
         gTrain[id].dd=
            peakT-eqT;
   }

   //===============================================================
   // OOS
   //===============================================================

   for(
      int s=oos;
      s>=InpAuditHorizon+2;
      s--
   )
   {
      int sig=Signal(id,s);

      if(sig==0)
         continue;

      double a=ATR(s);

      if(a<=0)
         continue;

      double r=0;

      SimTrade(
         sig,
         s,
         InpAuditHorizon,
         a*InpSL_ATR,
         a*InpTP_ATR,
         r
      );

      Add(
         gOOS[id],
         r,
         streakO
      );

      eqO+=r;

      if(eqO>peakO)
         peakO=eqO;

      if(
         peakO-eqO>
         gOOS[id].dd
      )
         gOOS[id].dd=
            peakO-eqO;
   }

   Finalize(gTrain[id]);
   Finalize(gOOS[id]);
}

//==================================================================
// STRICT ELIGIBILITY
//==================================================================

bool EligibleStrict(int id)
{
   return
      gTrain[id].trades>=InpMinTrainTrades &&
      gTrain[id].expectancy>0 &&
      gTrain[id].pf>=1.0 &&

      gOOS[id].trades>=InpMinOOSTrades &&
      gOOS[id].expectancy>=InpMinOOSExpectancy &&
      gOOS[id].pf>=InpMinOOSPF &&
      gOOS[id].dd<=InpMaxOOSDrawdown;
}

//==================================================================
// RELAXED ELIGIBILITY
//==================================================================

bool EligibleRelaxed(int id)
{
   return
      gTrain[id].trades>=InpRelaxedMinTrainTrades &&

      gTrain[id].expectancy>-0.05 &&

      gOOS[id].trades>=InpRelaxedMinOOSTrades &&
      gOOS[id].expectancy>=InpRelaxedMinOOSExpectancy &&
      gOOS[id].pf>=InpRelaxedMinOOSPF &&
      gOOS[id].dd<=InpRelaxedMaxOOSDrawdown;
}

//==================================================================
// ACTIVE ELIGIBILITY
//==================================================================

bool Eligible(int id)
{
   if(
      EligibleStrict(id)
   )
      return true;

   if(
      gBestRelaxed &&
      EligibleRelaxed(id)
   )
      return true;

   return false;
}

//==================================================================
// SELECTION SCORE
//==================================================================

double SelectionScore(int id)
{
   double o=
      MathMax(
         0.0,
         gOOS[id].expectancy
      );

   double pf=
      MathMin(
         2.5,
         MathMax(
            0.0,
            gOOS[id].pf
         )
      );

   double stability=
      1.0-
      MathMin(
         1.0,
         gOOS[id].dd/
         MathMax(
            0.1,
            InpMaxOOSDrawdown
         )
      );

   double sample=
      MathMin(
         1.0,
         (double)gOOS[id].trades/
         30.0
      );

   return
      (
         0.55*o+
         0.25*(pf-1.0)+
         0.20*stability
      )
      *
      sample
      *
      StrategyWeight(
         id,
         gRegime
      );
}

//==================================================================
// COMPLETE AUDIT
//==================================================================

void AuditAll()
{
   gBest=-1;
   gBestRelaxed=false;

   double best=-1e9;

   //===============================================================
   // PASS 1 - STRICT
   //===============================================================

   for(
      int i=0;
      i<STRATEGY_COUNT;
      i++
   )
   {
      AuditOne(i);

      if(
         EligibleStrict(i) &&
         Compatible(i,gRegime)
      )
      {
         double sc=
            SelectionScore(i);

         if(sc>best)
         {
            best=sc;
            gBest=i;
         }
      }
   }

   //===============================================================
   // PASS 2 - ADAPTIVE RELAXATION
   //===============================================================

   if(
      gBest<0 &&
      InpAllowAdaptiveRelaxation
   )
   {
      gBestRelaxed=true;
      best=-1e9;

      for(
         int i=0;
         i<STRATEGY_COUNT;
         i++
      )
      {
         if(
            EligibleRelaxed(i) &&
            Compatible(i,gRegime)
         )
         {
            double sc=
               SelectionScore(i);

            if(sc>best)
            {
               best=sc;
               gBest=i;
            }
         }
      }

      if(gBest>=0)
      {
         Print(
            "B21 ADAPTIVE RELAXATION: selected ",
            SName(gBest)
         );
      }
   }

   gLastBars=Bars;

   //===============================================================
   // REPORT
   //===============================================================

   if(InpPrintAudit)
   {
      Print(
         "=== BITEY v2.21 WALK-FORWARD AUDIT ==="
      );

      Print(
         "Regime=",
         RName(gRegime),
         " Best=",
         (
            gBest>=0
            ?
            SName(gBest)
            :
            "NONE"
         ),
         " mode=",
         (
            gBestRelaxed
            ?
            "RELAXED"
            :
            "STRICT"
         )
      );

      for(
         int i=0;
         i<STRATEGY_COUNT;
         i++
      )
      {
         Print(
            SName(i),

            " TRAIN T=",
            gTrain[i].trades,

            " PF=",
            DoubleToString(
               gTrain[i].pf,
               2
            ),

            " E=",
            DoubleToString(
               gTrain[i].expectancy,
               3
            ),

            " | OOS T=",
            gOOS[i].trades,

            " PF=",
            DoubleToString(
               gOOS[i].pf,
               2
            ),

            " E=",
            DoubleToString(
               gOOS[i].expectancy,
               3
            ),

            " DD=",
            DoubleToString(
               gOOS[i].dd,
               2
            ),

            " strict=",
            (
               EligibleStrict(i) &&
               Compatible(i,gRegime)
               ?
               "YES"
               :
               "NO"
            ),

            " relaxed=",
            (
               EligibleRelaxed(i) &&
               Compatible(i,gRegime)
               ?
               "YES"
               :
               "NO"
            )
         );
      }
   }
}

//==================================================================
// SESSION FILTER
//==================================================================

bool SessionOK()
{
   int h=TimeHour(TimeCurrent());

   if(
      InpSessionStart<
      InpSessionEnd
   )
   {
      return
         h>=InpSessionStart &&
         h<InpSessionEnd;
   }

   return
      h>=InpSessionStart ||
      h<InpSessionEnd;
}

//==================================================================
// SPREAD FILTER
//==================================================================

bool SpreadOK()
{
   double sp=
      (Ask-Bid)/Point;

   double a=
      ATRPts(1);

   if(
      sp<=0 ||
      sp>InpMaxSpreadPoints
   )
      return false;

   if(
      a<=0 ||
      sp/a>InpMaxSpreadATR
   )
      return false;

   return true;
}

//==================================================================
// OPEN TRADES
//==================================================================

int OpenTrades()
{
   int n=0;

   for(
      int i=OrdersTotal()-1;
      i>=0;
      i--
   )
   {
      if(
         !OrderSelect(
            i,
            SELECT_BY_POS,
            MODE_TRADES
         )
      )
         continue;

      if(
         OrderSymbol()==Symbol() &&
         OrderMagicNumber()==InpMagic &&
         (
            OrderType()==OP_BUY ||
            OrderType()==OP_SELL
         )
      )
         n++;
   }

   return n;
}

//==================================================================
// LOT CALCULATION
//==================================================================

double LotForRisk(
   double slPoints
)
{
   double tv=
      MarketInfo(
         Symbol(),
         MODE_TICKVALUE
      );

   double ts=
      MarketInfo(
         Symbol(),
         MODE_TICKSIZE
      );

   if(
      slPoints<=0 ||
      tv<=0 ||
      ts<=0
   )
      return 0;

   double money=
      AccountBalance()*
      InpRiskPercent/
      100.0;

   double lossLot=
      (
         slPoints*
         Point/
         ts
      )*
      tv;

   if(lossLot<=0)
      return 0;

   double step=
      MarketInfo(
         Symbol(),
         MODE_LOTSTEP
      );

   double mn=
      MarketInfo(
         Symbol(),
         MODE_MINLOT
      );

   double mx=
      MarketInfo(
         Symbol(),
         MODE_MAXLOT
      );

   if(step<=0)
      step=0.01;

   double lot=
      MathFloor(
         (money/lossLot)/
         step
      )*
      step;

   lot=
      MathMax(
         mn,
         MathMin(
            mx,
            lot
         )
      );

   return NormalizeDouble(
      lot,
      2
   );
}

//==================================================================
// BEST SIGNAL
//==================================================================

int BestSignal()
{
   if(gBest<0)
      return 0;

   int s=
      Signal(
         gBest,
         1
      );

   if(s==0)
      return 0;

   // Optional second confirmation.
   if(InpRequireSecondConfirmation)
   {
      int agree=0;

      for(
         int i=0;
         i<STRATEGY_COUNT;
         i++
      )
      {
         if(i==gBest)
            continue;

         if(
            !Eligible(i) ||
            !Compatible(i,gRegime)
         )
            continue;

         if(
            Signal(i,1)==s
         )
            agree++;
      }

      if(agree==0)
         return 0;
   }

   gLastStrategy=gBest;

   return s;
}

//==================================================================
// EXECUTION
//==================================================================

void Execute(int dir)
{
   if(
      !InpEnableTrading &&
      !(
         IsTesting() &&
         InpBacktestExecution
      )
   )
      return;

   if(
      OpenTrades()>=
      InpMaxOpenTrades
   )
      return;

   if(!SessionOK())
      return;

   if(!SpreadOK())
      return;

   if(gLastTrade>0)
   {
      int b=
         iBarShift(
            Symbol(),
            Period(),
            gLastTrade,
            false
         );

      if(
         b>=0 &&
         b<InpCooldownBars
      )
         return;
   }

   double a=ATR(1);

   if(a<=0)
      return;

   double sl=
      InpSL_ATR*a;

   double tp=
      InpTP_ATR*a;

   // High volatility protection.
   if(gRegime==HIGH_VOL)
   {
      sl=
         MathMax(
            sl,
            1.5*a
         );

      tp=
         MathMax(
            tp,
            2.2*a
         );
   }

   // Range adaptation.
   if(gRegime==RANGE)
   {
      sl=
         MathMin(
            sl,
            1.1*a
         );

      tp=
         MathMin(
            tp,
            1.8*a
         );
   }

   double lot=
      LotForRisk(
         sl/Point
      );

   if(lot<=0)
      return;

   RefreshRates();

   ResetLastError();

   int ticket=-1;

   string c=
      "B21|"+
      SName(
         gLastStrategy
      );

   // BUY
   if(dir>0)
   {
      ticket=
         OrderSend(
            Symbol(),
            OP_BUY,
            lot,
            Ask,
            5,
            NormalizeDouble(
               Ask-sl,
               Digits
            ),
            NormalizeDouble(
               Ask+tp,
               Digits
            ),
            c,
            InpMagic,
            0,
            clrNONE
         );
   }

   // SELL
   else
   {
      ticket=
         OrderSend(
            Symbol(),
            OP_SELL,
            lot,
            Bid,
            5,
            NormalizeDouble(
               Bid+sl,
               Digits
            ),
            NormalizeDouble(
               Bid-tp,
               Digits
            ),
            c,
            InpMagic,
            0,
            clrNONE
         );
   }

   if(ticket>0)
   {
      gLastTrade=
         TimeCurrent();

      Print(
         "B21 EXEC OK ticket=",
         ticket,
         " strategy=",
         SName(gLastStrategy),
         " dir=",
         (
            dir>0
            ?
            "BUY"
            :
            "SELL"
         ),
         " lot=",
         DoubleToString(
            lot,
            2
         )
      );
   }
   else
   {
      Print(
         "B21 EXEC FAIL error=",
         GetLastError()
      );
   }
}

//==================================================================
// CSV
//==================================================================

void WriteDecision(
   int dir
)
{
   if(
      !InpWriteCSV ||
      !IsTesting()
   )
      return;

   int h=
      FileOpen(
         InpCSVFile,
         FILE_CSV|
         FILE_READ|
         FILE_WRITE|
         FILE_SHARE_READ,
         ';'
      );

   if(h==INVALID_HANDLE)
      return;

   if(FileSize(h)==0)
   {
      FileWrite(
         h,
         "time",
         "symbol",
         "tf",
         "regime",
         "best",
         "direction",
         "mode",
         "train_trades",
         "train_pf",
         "train_exp",
         "oos_trades",
         "oos_pf",
         "oos_exp",
         "oos_dd"
      );
   }

   FileSeek(
      h,
      0,
      SEEK_END
   );

   int i=gBest;

   FileWrite(
      h,

      TimeToString(
         TimeCurrent(),
         TIME_DATE|
         TIME_SECONDS
      ),

      Symbol(),

      Period(),

      RName(gRegime),

      i>=0
      ?
      SName(i)
      :
      "NONE",

      dir,

      gBestRelaxed
      ?
      "RELAXED"
      :
      "STRICT",

      i>=0
      ?
      gTrain[i].trades
      :
      0,

      i>=0
      ?
      gTrain[i].pf
      :
      0,

      i>=0
      ?
      gTrain[i].expectancy
      :
      0,

      i>=0
      ?
      gOOS[i].trades
      :
      0,

      i>=0
      ?
      gOOS[i].pf
      :
      0,

      i>=0
      ?
      gOOS[i].expectancy
      :
      0,

      i>=0
      ?
      gOOS[i].dd
      :
      0
   );

   FileClose(h);
}

//==================================================================
// NEW BAR
//==================================================================

bool NewBar()
{
   if(Time[0]==gLastBar)
      return false;

   gLastBar=
      Time[0];

   return true;
}

//==================================================================
// INIT
//==================================================================

int OnInit()
{
   if(Bars<300)
      return INIT_SUCCEEDED;

   gRegime=
      CurrentRegime();

   AuditAll();

   Print(
      "Bitey IA v2.21 initialized | regime=",
      RName(gRegime),
      " | best=",
      (
         gBest>=0
         ?
         SName(gBest)
         :
         "NONE"
      ),
      " | mode=",
      (
         gBestRelaxed
         ?
         "RELAXED"
         :
         "STRICT"
      ),
      " | trading=",
      InpEnableTrading,
      " | tester=",
      IsTesting()
   );

   return INIT_SUCCEEDED;
}

//==================================================================
// TICK
//==================================================================

void OnTick()
{
   if(
      Bars<300 ||
      !NewBar()
   )
      return;

   gRegime=
      CurrentRegime();

   if(
      gLastBars<0 ||
      MathAbs(
         Bars-gLastBars
      )>=20
   )
   {
      AuditAll();
   }

   int dir=
      BestSignal();

   if(dir!=0)
      gLastDir=dir;

   WriteDecision(dir);

   Comment(
      "BITEY IA v2.21\n",
      "Regime: ",
      RName(gRegime),

      "\nBest OOS strategy: ",
      (
         gBest>=0
         ?
         SName(gBest)
         :
         "NONE"
      ),

      "\nSelection mode: ",
      (
         gBestRelaxed
         ?
         "RELAXED"
         :
         "STRICT"
      ),

      "\nSignal: ",
      (
         dir>0
         ?
         "BUY"
         :
         dir<0
         ?
         "SELL"
         :
         "HOLD"
      ),

      "\nOOS PF: ",
      (
         gBest>=0
         ?
         DoubleToString(
            gOOS[gBest].pf,
            2
         )
         :
         "-"
      ),

      "  OOS E: ",
      (
         gBest>=0
         ?
         DoubleToString(
            gOOS[gBest].expectancy,
            3
         )
         :
         "-"
      )
   );

   if(dir!=0)
      Execute(dir);
}

//==================================================================
// DEINIT
//==================================================================

void OnDeinit(
   const int reason
)
{
   Comment("");
}

//+------------------------------------------------------------------+