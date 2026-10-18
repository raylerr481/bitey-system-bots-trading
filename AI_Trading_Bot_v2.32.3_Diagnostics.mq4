//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.32.3_Diagnostics.mq4                     |
//| Adaptive Regime + 8 Strategy Walk-Forward EA                    |
//+------------------------------------------------------------------+
#property strict
#property version   "2.32.3"
#property description "Entry diagnostic build: 8-strategy walk-forward with granular signal/filter counters"

//==================================================================
// INPUTS
//==================================================================

//--- Risk
input double InpRiskPercent       = 0.25;
input int    InpMaxOpenTrades     = 1;
input int    InpMagicNumber       = 2035032;
input int    InpSlippage          = 5;

//--- Indicators
input int    InpATRPeriod         = 14;
input int    InpADXPeriod         = 14;
input int    InpRSIPeriod         = 14;
input int    InpFastEMA           = 8;
input int    InpSlowEMA           = 21;
input int    InpTrendEMA          = 200;

//--- Risk/Reward
input double InpSL_ATR            = 1.30;
input double InpTP_ATR            = 2.60;

//--- Market filters
input int    InpMaxSpreadPoints   = 50;
input double InpMaxSpreadATR      = 0.60;
input int    InpSessionStart      = 7;
input int    InpSessionEnd        = 20;

//--- Cooldown
input int    InpCooldownBars      = 3;

//--- Walk Forward
input int    InpTrainBars         = 120;
input int    InpOOSBars           = 50;
input int    InpAuditGap          = 3;
input int    InpAuditHorizon      = 12;
input int    InpRecalibrationBars = 12;
input int    InpMinTrainTrades    = 8;
input int    InpMinOOSTrades      = 3;

//--- Selection thresholds
input double InpMinOOSPF          = 0.80;
input double InpMinOOSExpectancy  = -0.05;
input double InpMaxOOSDrawdown    = 15.0;

//--- Regime engine
input int    InpRegimeLookback    = 20;
input double InpATRExpansion      = 1.25;
input double InpATRContraction    = 0.80;
input double InpTrendADX          = 22.0;
input double InpRangeADX          = 18.0;

//--- Hurst
input int    InpHurstPeriod       = 40;
input double InpHurstTrend        = 0.55;
input double InpHurstRange        = 0.45;

//--- Regime change
input double InpRegimeChangeScore = 2.0;

//--- Loss protection
input bool   InpUseLossProtection = true;
input int    InpMaxLossStreak     = 3;
input int    InpLossPauseBars     = 6;

//--- Direction flip
input bool   InpUseFlipProtection = true;
input int    InpMaxDirectionFlips = 2;
input int    InpFlipWindowBars    = 24;

//--- Reporting
input bool   InpAutoReport        = true;
input bool   InpVerbose           = true;

//==================================================================
// CONSTANTS
//==================================================================

#define STRAT_COUNT 8

#define STRAT_TREND       0
#define STRAT_MEANREV     1
#define STRAT_MOMENTUM    2
#define STRAT_BREAKOUT    3
#define STRAT_SESSION     4
#define STRAT_DIVERGENCE  5
#define STRAT_RANGE       6
#define STRAT_FRACTAL_HTF 7

#define SIGNAL_NONE  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL -1

#define REGIME_UNKNOWN     0
#define REGIME_TREND_UP    1
#define REGIME_TREND_DOWN  2
#define REGIME_RANGE       3
#define REGIME_BREAKOUT    4
#define REGIME_HIGH_VOL    5
#define REGIME_CONTRACTING 6
#define REGIME_TRANSITION  7

//==================================================================
// GLOBALS
//==================================================================

int gBestStrategy = -1;

double gBestScore = -999999.0;
double gBestPF = 0.0;
double gBestExp = -999.0;
double gBestDD = 100.0;

int gBestTrainTrades = 0;
int gBestOOSTrades = 0;

int gCurrentRegime = REGIME_UNKNOWN;
int gPreviousRegime = REGIME_UNKNOWN;

double gCurrentHurst = 0.50;
double gCurrentATRRatio = 1.0;
double gCurrentADX = 0.0;
double gCurrentStdRatio = 1.0;

datetime gLastBarTime = 0;
datetime gLastTradeBarTime = 0;
datetime gRegimeStartTime = 0;

int gLossStreak = 0;
int gLossPauseRemaining = 0;

int gLastTradeDirection = 0;
int gFlipCount = 0;
datetime gFlipWindowStart = 0;

int gLastCalibrationBar = -1;
long gBarSequence = 0;
int gCalibrationCount = 0;

long gBarsEvaluated = 0;
long gOpenedTrades = 0;
long gOrderSendErrors = 0;

long gBlockPosition = 0;
long gBlockSession = 0;
long gBlockSpread = 0;
long gBlockCooldown = 0;
long gBlockLoss = 0;
long gBlockFlip = 0;
long gBlockContext = 0;
long gBlockNoSignal = 0;

//--- granular signal diagnostics
long gRawSignals[STRAT_COUNT];
long gQualityPass[STRAT_COUNT];
long gContextPass[STRAT_COUNT];
long gSelectedSignals = 0;
long gRejectedQuality = 0;
long gRejectedContext = 0;
long gSpreadAtrBlocks = 0;
double gLastSpreadPoints = 0.0;
double gLastSpreadATRRatio = 0.0;

long gRegimeChanges = 0;

long gStrategyDetected[STRAT_COUNT];
long gStrategyQualified[STRAT_COUNT];
long gStrategyOpened[STRAT_COUNT];

datetime gLastProcessedHistoryClose = 0;
int gLastHistoryTicket = -1;

//==================================================================
// NAMES
//==================================================================

string StrategyName(int s)
{
   switch(s)
   {
      case STRAT_TREND:       return "TREND";
      case STRAT_MEANREV:     return "MEANREV";
      case STRAT_MOMENTUM:    return "MOMENTUM";
      case STRAT_BREAKOUT:    return "BREAKOUT";
      case STRAT_SESSION:     return "SESSION";
      case STRAT_DIVERGENCE:  return "DIVERGENCE";
      case STRAT_RANGE:       return "RANGE";
      case STRAT_FRACTAL_HTF: return "FRACTAL_HTF";
   }

   return "UNKNOWN";
}

string RegimeName(int r)
{
   switch(r)
   {
      case REGIME_TREND_UP:    return "TREND_UP";
      case REGIME_TREND_DOWN:  return "TREND_DOWN";
      case REGIME_RANGE:       return "RANGE";
      case REGIME_BREAKOUT:    return "BREAKOUT";
      case REGIME_HIGH_VOL:    return "HIGH_VOL";
      case REGIME_CONTRACTING: return "CONTRACTING";
      case REGIME_TRANSITION:  return "TRANSITION";
   }

   return "UNKNOWN";
}

//==================================================================
// BASIC INDICATORS
//==================================================================

double ATR(int shift)
{
   return iATR(Symbol(),Period(),InpATRPeriod,shift);
}

double ADX(int shift)
{
   return iADX(Symbol(),Period(),InpADXPeriod,
               PRICE_CLOSE,MODE_MAIN,shift);
}

double RSI(int shift)
{
   return iRSI(Symbol(),Period(),InpRSIPeriod,
               PRICE_CLOSE,shift);
}

double EMA(int period,int shift)
{
   return iMA(Symbol(),Period(),period,0,
              MODE_EMA,PRICE_CLOSE,shift);
}

double CandleBody(int shift)
{
   return MathAbs(iClose(Symbol(),Period(),shift) -
                  iOpen(Symbol(),Period(),shift));
}

double CandleRange(int shift)
{
   return iHigh(Symbol(),Period(),shift) -
          iLow(Symbol(),Period(),shift);
}

bool IsNewBar()
{
   datetime t=iTime(Symbol(),Period(),0);

   if(t<=0)
      return false;

   if(t!=gLastBarTime)
   {
      gLastBarTime=t;
      return true;
   }

   return false;
}

bool HasEnoughBars()
{
   int minimum=InpTrendEMA+
               InpTrainBars+
               InpOOSBars+
               InpHurstPeriod+
               50;

   return Bars>minimum;
}

//==================================================================
// STANDARD DEVIATION
//==================================================================

double StdDev(int shift,int period)
{
   if(period<2)
      return 0.0;

   double mean=0.0;

   for(int i=shift;i<shift+period;i++)
      mean+=iClose(Symbol(),Period(),i);

   mean/=period;

   double variance=0.0;

   for(int j=shift;j<shift+period;j++)
   {
      double d=iClose(Symbol(),Period(),j)-mean;
      variance+=d*d;
   }

   variance/=(period-1);

   return MathSqrt(variance);
}

//==================================================================
// HURST ESTIMATOR
//==================================================================

double HurstExponent(int shift)
{
   int n=InpHurstPeriod;

   if(n<20 || Bars<(shift+n+5))
      return 0.50;

   double mean=0.0;

   for(int i=0;i<n;i++)
      mean+=iClose(Symbol(),Period(),shift+i);

   mean/=n;

   double cumulative=0.0;
   double maxDev=-DBL_MAX;
   double minDev=DBL_MAX;
   double variance=0.0;

   for(int j=0;j<n;j++)
   {
      double deviation=iClose(Symbol(),Period(),shift+j)-mean;

      cumulative+=deviation;

      if(cumulative>maxDev)
         maxDev=cumulative;

      if(cumulative<minDev)
         minDev=cumulative;

      variance+=deviation*deviation;
   }

   double sd=MathSqrt(variance/n);

   if(sd<=0.0)
      return 0.50;

   double R=maxDev-minDev;

   if(R<=0.0)
      return 0.50;

   double rs=R/sd;

   if(rs<=0.0)
      return 0.50;

   double h=MathLog(rs)/MathLog(n);

   if(h<0.0)
      h=0.0;

   if(h>1.0)
      h=1.0;

   return h;
}

//==================================================================
// REGIME ENGINE
//==================================================================

double ATRRatio(int shift)
{
   double current=ATR(shift);

   if(current<=0.0)
      return 1.0;

   double average=0.0;

   int n=InpRegimeLookback;

   for(int i=shift+1;i<=shift+n;i++)
      average+=ATR(i);

   average/=n;

   if(average<=0.0)
      return 1.0;

   return current/average;
}

double StdRatio(int shift)
{
   double current=StdDev(shift,InpRegimeLookback);

   if(current<=0.0)
      return 1.0;

   double average=0.0;

   for(int i=shift+1;i<=shift+InpRegimeLookback;i++)
      average+=StdDev(i,InpRegimeLookback);

   average/=InpRegimeLookback;

   if(average<=0.0)
      return 1.0;

   return current/average;
}

int DetectRegime(int shift)
{
   double atrRatio=ATRRatio(shift);
   double stdRatio=StdRatio(shift);
   double adx=ADX(shift);
   double hurst=HurstExponent(shift);

   double fast=EMA(InpFastEMA,shift);
   double slow=EMA(InpSlowEMA,shift);
   double trend=EMA(InpTrendEMA,shift);

   double close=iClose(Symbol(),Period(),shift);

   gCurrentATRRatio=atrRatio;
   gCurrentStdRatio=stdRatio;
   gCurrentADX=adx;
   gCurrentHurst=hurst;

   // Strong expansion + directional structure
   if(atrRatio>=InpATRExpansion &&
      stdRatio>=InpATRExpansion &&
      adx>=InpTrendADX)
   {
      if(close>trend && fast>slow)
         return REGIME_HIGH_VOL;

      if(close<trend && fast<slow)
         return REGIME_HIGH_VOL;
   }

   // Breakout
   double high12=-DBL_MAX;
   double low12=DBL_MAX;

   for(int i=shift+1;i<=shift+12;i++)
   {
      high12=MathMax(high12,iHigh(Symbol(),Period(),i));
      low12=MathMin(low12,iLow(Symbol(),Period(),i));
   }

   if((close>high12 || close<low12) &&
      atrRatio>=1.05)
   {
      return REGIME_BREAKOUT;
   }

   // Directional trend
   if(adx>=InpTrendADX)
   {
      if(close>trend && fast>slow)
         return REGIME_TREND_UP;

      if(close<trend && fast<slow)
         return REGIME_TREND_DOWN;
   }

   // Strong contraction
   if(atrRatio<=InpATRContraction &&
      stdRatio<=InpATRContraction)
   {
      return REGIME_CONTRACTING;
   }

   // Range
   if(adx<=InpRangeADX ||
      hurst<=InpHurstRange)
   {
      return REGIME_RANGE;
   }

   // Hurst persistence
   if(hurst>=InpHurstTrend)
   {
      if(close>trend && fast>slow)
         return REGIME_TREND_UP;

      if(close<trend && fast<slow)
         return REGIME_TREND_DOWN;
   }

   return REGIME_TRANSITION;
}

//==================================================================
// REGIME CHANGE
//==================================================================

void UpdateRegime(int shift)
{
   int detected=DetectRegime(shift);

   if(gCurrentRegime==REGIME_UNKNOWN)
   {
      gCurrentRegime=detected;
      gPreviousRegime=detected;
      gRegimeStartTime=iTime(Symbol(),Period(),shift);
      return;
   }

   if(detected!=gCurrentRegime)
   {
      gPreviousRegime=gCurrentRegime;
      gCurrentRegime=detected;

      gRegimeChanges++;
      gRegimeStartTime=iTime(Symbol(),Period(),shift);

      // Force recalibration
      gLastCalibrationBar=-1;

      if(InpVerbose)
      {
         Print("B32 REGIME CHANGE ",
               RegimeName(gPreviousRegime),
               " -> ",
               RegimeName(gCurrentRegime),
               " ATR_RATIO=",
               DoubleToString(gCurrentATRRatio,2),
               " STD_RATIO=",
               DoubleToString(gCurrentStdRatio,2),
               " ADX=",
               DoubleToString(gCurrentADX,2),
               " HURST=",
               DoubleToString(gCurrentHurst,3));
      }
   }
}

//==================================================================
// RAW STRATEGIES
//==================================================================

int RawSignal(int strategy,int shift)
{
   if(shift<2)
      return SIGNAL_NONE;

   double close0=iClose(Symbol(),Period(),shift);
   double close1=iClose(Symbol(),Period(),shift+1);

   double high0=iHigh(Symbol(),Period(),shift);
   double low0=iLow(Symbol(),Period(),shift);

   double emaFast=EMA(InpFastEMA,shift);
   double emaSlow=EMA(InpSlowEMA,shift);
   double emaTrend=EMA(InpTrendEMA,shift);

   double rsi=RSI(shift);
   double adx=ADX(shift);
   double atr=ATR(shift);

   if(atr<=0.0)
      return SIGNAL_NONE;

   // TREND
   if(strategy==STRAT_TREND)
   {
      if(adx>=InpTrendADX &&
         close0>emaTrend &&
         emaFast>emaSlow &&
         close0>emaFast)
         return SIGNAL_BUY;

      if(adx>=InpTrendADX &&
         close0<emaTrend &&
         emaFast<emaSlow &&
         close0<emaFast)
         return SIGNAL_SELL;
   }

   // MEAN REVERSION
   if(strategy==STRAT_MEANREV)
   {
      if(adx<=InpRangeADX &&
         rsi<=30.0)
         return SIGNAL_BUY;

      if(adx<=InpRangeADX &&
         rsi>=70.0)
         return SIGNAL_SELL;
   }

   // MOMENTUM
   if(strategy==STRAT_MOMENTUM)
   {
      double body=CandleBody(shift);

      if(body>=atr*0.35 &&
         close0>close1 &&
         close0>emaFast &&
         emaFast>emaSlow &&
         rsi>=55.0 &&
         rsi<=75.0)
         return SIGNAL_BUY;

      if(body>=atr*0.35 &&
         close0<close1 &&
         close0<emaFast &&
         emaFast<emaSlow &&
         rsi<=45.0 &&
         rsi>=25.0)
         return SIGNAL_SELL;
   }

   // BREAKOUT
   if(strategy==STRAT_BREAKOUT)
   {
      double high12=-DBL_MAX;
      double low12=DBL_MAX;

      for(int i=shift+1;i<=shift+12;i++)
      {
         high12=MathMax(high12,
                        iHigh(Symbol(),Period(),i));

         low12=MathMin(low12,
                        iLow(Symbol(),Period(),i));
      }

      if(close0>high12 && adx>=InpTrendADX)
         return SIGNAL_BUY;

      if(close0<low12 && adx>=InpTrendADX)
         return SIGNAL_SELL;
   }

   // SESSION
   if(strategy==STRAT_SESSION)
   {
      int hour=TimeHour(iTime(Symbol(),Period(),shift));

      if(hour>=InpSessionStart &&
         hour<InpSessionEnd)
      {
         if(emaFast>emaSlow &&
            close0>emaFast &&
            rsi>=50.0)
            return SIGNAL_BUY;

         if(emaFast<emaSlow &&
            close0<emaFast &&
            rsi<=50.0)
            return SIGNAL_SELL;
      }
   }

   // DIVERGENCE
   if(strategy==STRAT_DIVERGENCE)
   {
      double rsiOld=RSI(shift+3);

      double lowOld=iLow(Symbol(),Period(),shift+3);
      double highOld=iHigh(Symbol(),Period(),shift+3);

      if(adx<=InpRangeADX)
      {
         if(low0<lowOld &&
            rsi>rsiOld &&
            rsi<=45.0)
            return SIGNAL_BUY;

         if(high0>highOld &&
            rsi<rsiOld &&
            rsi>=55.0)
            return SIGNAL_SELL;
      }
   }

   // RANGE
   if(strategy==STRAT_RANGE)
   {
      if(adx<=InpRangeADX)
      {
         double rh=-DBL_MAX;
         double rl=DBL_MAX;

         for(int r=shift+1;r<=shift+10;r++)
         {
            rh=MathMax(rh,
                       iHigh(Symbol(),Period(),r));

            rl=MathMin(rl,
                       iLow(Symbol(),Period(),r));
         }

         double range=rh-rl;

         if(range>0.0)
         {
            if(close0<=rl+range*0.20 &&
               rsi<45.0)
               return SIGNAL_BUY;

            if(close0>=rh-range*0.20 &&
               rsi>55.0)
               return SIGNAL_SELL;
         }
      }
   }

   // FRACTAL HTF
   if(strategy==STRAT_FRACTAL_HTF)
   {
      int htfShift=shift/4+1;

      double htfFast=iMA(Symbol(),
                         PERIOD_H4,
                         InpFastEMA,
                         0,
                         MODE_EMA,
                         PRICE_CLOSE,
                         htfShift);

      double htfSlow=iMA(Symbol(),
                         PERIOD_H4,
                         InpSlowEMA,
                         0,
                         MODE_EMA,
                         PRICE_CLOSE,
                         htfShift);

      double htfClose=iClose(Symbol(),
                             PERIOD_H4,
                             htfShift);

      if(htfClose>htfFast &&
         htfFast>htfSlow &&
         close0>emaFast)
         return SIGNAL_BUY;

      if(htfClose<htfFast &&
         htfFast<htfSlow &&
         close0<emaFast)
         return SIGNAL_SELL;
   }

   return SIGNAL_NONE;
}

//==================================================================
// STRATEGY / REGIME COMPATIBILITY
//==================================================================

bool StrategyCompatible(int strategy,int direction)
{
   int r=gCurrentRegime;

   // TREND
   if(strategy==STRAT_TREND ||
      strategy==STRAT_MOMENTUM ||
      strategy==STRAT_FRACTAL_HTF)
   {
      if(r==REGIME_TREND_UP &&
         direction==SIGNAL_BUY)
         return true;

      if(r==REGIME_TREND_DOWN &&
         direction==SIGNAL_SELL)
         return true;

      if(r==REGIME_HIGH_VOL)
         return true;

      return false;
   }

   // BREAKOUT
   if(strategy==STRAT_BREAKOUT)
   {
      return (r==REGIME_BREAKOUT ||
              r==REGIME_HIGH_VOL);
   }

   // RANGE / REVERSION
   if(strategy==STRAT_MEANREV ||
      strategy==STRAT_RANGE ||
      strategy==STRAT_DIVERGENCE)
   {
      return (r==REGIME_RANGE ||
              r==REGIME_CONTRACTING);
   }

   // SESSION
   if(strategy==STRAT_SESSION)
   {
      return (r==REGIME_TREND_UP ||
              r==REGIME_TREND_DOWN ||
              r==REGIME_RANGE ||
              r==REGIME_BREAKOUT ||
              r==REGIME_HIGH_VOL);
   }

   return false;
}

//==================================================================
// QUALITY
//==================================================================

bool QualityOK(int strategy,int direction,int shift)
{
   double atr=ATR(shift);

   if(atr<=0.0)
      return false;

   if(atr/Point<5.0)
      return false;

   double close0=iClose(Symbol(),Period(),shift);
   double fast=EMA(InpFastEMA,shift);
   double slow=EMA(InpSlowEMA,shift);

   double body=CandleBody(shift);

   if(strategy==STRAT_TREND ||
      strategy==STRAT_MOMENTUM ||
      strategy==STRAT_BREAKOUT ||
      strategy==STRAT_FRACTAL_HTF)
   {
      if(body<atr*0.10)
         return false;

      if(MathAbs(fast-slow)<atr*0.05)
         return false;

      if(direction==SIGNAL_BUY &&
         close0<fast)
         return false;

      if(direction==SIGNAL_SELL &&
         close0>fast)
         return false;
   }

   return true;
}

//==================================================================
// VALID SIGNAL
//==================================================================

int ValidSignal(int strategy,int shift,bool countStats)
{
   int signal=RawSignal(strategy,shift);

   if(signal==SIGNAL_NONE)
      return SIGNAL_NONE;

   if(countStats)
   {
      gRawSignals[strategy]++;
      gStrategyDetected[strategy]++;
   }

   if(!QualityOK(strategy,signal,shift))
   {
      if(countStats)
      {
         gRejectedQuality++;
      }
      return SIGNAL_NONE;
   }

   if(countStats)
      gQualityPass[strategy]++;

   if(!StrategyCompatible(strategy,signal))
   {
      if(countStats)
         gRejectedContext++;
      return SIGNAL_NONE;
   }

   if(countStats)
   {
      gContextPass[strategy]++;
      gStrategyQualified[strategy]++;
   }

   return signal;
}

//==================================================================
// AUDIT STRUCTURE
//==================================================================

struct AuditStats
{
   int trades;
   int wins;
   int losses;

   double grossProfit;
   double grossLoss;
   double expectancy;
   double profitFactor;

   double maxDrawdown;
   double payoff;
};

//==================================================================
// SIMULATED TRADE
//==================================================================

double SimTrade(int direction,int entryShift)
{
   double atr=ATR(entryShift);

   if(atr<=0.0)
      return 0.0;

   double entry=iClose(Symbol(),
                       Period(),
                       entryShift);

   double slDistance=atr*InpSL_ATR;
   double tpDistance=atr*InpTP_ATR;

   double sl;
   double tp;

   if(direction==SIGNAL_BUY)
   {
      sl=entry-slDistance;
      tp=entry+tpDistance;
   }
   else
   {
      sl=entry+slDistance;
      tp=entry-tpDistance;
   }

   for(int f=entryShift-1;
       f>=1 &&
       f>=entryShift-InpAuditHorizon;
       f--)
   {
      double high=iHigh(Symbol(),Period(),f);
      double low=iLow(Symbol(),Period(),f);

      bool hitSL=false;
      bool hitTP=false;

      if(direction==SIGNAL_BUY)
      {
         hitSL=(low<=sl);
         hitTP=(high>=tp);
      }
      else
      {
         hitSL=(high>=sl);
         hitTP=(low<=tp);
      }

      // Conservative same-candle treatment
      if(hitSL && hitTP)
         return -1.0;

      if(hitSL)
         return -1.0;

      if(hitTP)
         return InpTP_ATR/InpSL_ATR;
   }

   // Time-out is penalized rather than treated as a winner.
   int finalShift=MathMax(1,
                          entryShift-InpAuditHorizon);

   double finalClose=iClose(Symbol(),
                            Period(),
                            finalShift);

   if(direction==SIGNAL_BUY)
   {
      if(finalClose>entry)
         return 0.25;

      return -0.50;
   }

   if(finalClose<entry)
      return 0.25;

   return -0.50;
}

//==================================================================
// AUDIT STRATEGY
//==================================================================

void AuditStrategy(int strategy,
                   int currentShift,
                   AuditStats &train,
                   AuditStats &oos)
{
   train.trades=0;
   train.wins=0;
   train.losses=0;
   train.grossProfit=0;
   train.grossLoss=0;
   train.expectancy=0;
   train.profitFactor=0;
   train.maxDrawdown=0;
   train.payoff=0;

   oos.trades=0;
   oos.wins=0;
   oos.losses=0;
   oos.grossProfit=0;
   oos.grossLoss=0;
   oos.expectancy=0;
   oos.profitFactor=0;
   oos.maxDrawdown=0;
   oos.payoff=0;

   //===============================================================
   // TRAIN
   //===============================================================

   int trainStart=currentShift+
                   InpAuditGap+
                   InpOOSBars+
                   1;

   int trainEnd=trainStart+
                 InpTrainBars-
                 1;

   if(trainEnd>=Bars-2)
      return;

   double equity=0.0;
   double peak=0.0;

   for(int shift=trainStart;
       shift<=trainEnd;
       shift++)
   {
      int signal=RawSignal(strategy,shift);

      if(signal==SIGNAL_NONE)
         continue;

      // For historical audit use the regime belonging
      // to the historical candle rather than today's regime.
      int historicalRegime=DetectRegime(shift);

      bool compatible=false;

      if(strategy==STRAT_TREND ||
         strategy==STRAT_MOMENTUM ||
         strategy==STRAT_FRACTAL_HTF)
      {
         if(signal==SIGNAL_BUY &&
            (historicalRegime==REGIME_TREND_UP ||
             historicalRegime==REGIME_HIGH_VOL))
            compatible=true;

         if(signal==SIGNAL_SELL &&
            (historicalRegime==REGIME_TREND_DOWN ||
             historicalRegime==REGIME_HIGH_VOL))
            compatible=true;
      }
      else if(strategy==STRAT_BREAKOUT)
      {
         compatible=(historicalRegime==REGIME_BREAKOUT ||
                     historicalRegime==REGIME_HIGH_VOL);
      }
      else if(strategy==STRAT_MEANREV ||
              strategy==STRAT_RANGE ||
              strategy==STRAT_DIVERGENCE)
      {
         compatible=(historicalRegime==REGIME_RANGE ||
                     historicalRegime==REGIME_CONTRACTING);
      }
      else if(strategy==STRAT_SESSION)
      {
         compatible=(historicalRegime!=REGIME_UNKNOWN &&
                     historicalRegime!=REGIME_TRANSITION);
      }

      if(!compatible)
         continue;

      if(!QualityOK(strategy,signal,shift))
         continue;

      double result=SimTrade(signal,shift);

      train.trades++;

      if(result>0)
      {
         train.wins++;
         train.grossProfit+=result;
      }
      else
      {
         train.losses++;
         train.grossLoss+=MathAbs(result);
      }

      equity+=result;

      if(equity>peak)
         peak=equity;

      double dd=peak-equity;

      if(dd>train.maxDrawdown)
         train.maxDrawdown=dd;
   }

   if(train.trades>0)
   {
      train.expectancy=
         (train.grossProfit-train.grossLoss)/
         train.trades;
   }

   if(train.grossLoss>0)
      train.profitFactor=
         train.grossProfit/train.grossLoss;

   if(train.losses>0)
      train.payoff=
         train.grossProfit/
         MathMax(0.0001,train.grossLoss);

   //===============================================================
   // OOS
   //===============================================================

   // OOS must be the most recent complete block immediately after the
   // audit gap.  With currentShift=1 and OOSBars=50 this evaluates
   // shifts 54..5, not only five bars (the v2.31 windowing bug).
   int oosNewest=currentShift+InpAuditGap+InpOOSBars;
   int oosOldest=currentShift+InpAuditGap+1;

   if(oosNewest>=Bars-2)
      return;

   equity=0.0;
   peak=0.0;

   for(int shift2=oosNewest;
       shift2>=oosOldest;
       shift2--)
   {
      int signal2=RawSignal(strategy,shift2);

      if(signal2==SIGNAL_NONE)
         continue;

      int historicalRegime2=DetectRegime(shift2);

      bool compatible2=false;

      if(strategy==STRAT_TREND ||
         strategy==STRAT_MOMENTUM ||
         strategy==STRAT_FRACTAL_HTF)
      {
         if(signal2==SIGNAL_BUY &&
            (historicalRegime2==REGIME_TREND_UP ||
             historicalRegime2==REGIME_HIGH_VOL))
            compatible2=true;

         if(signal2==SIGNAL_SELL &&
            (historicalRegime2==REGIME_TREND_DOWN ||
             historicalRegime2==REGIME_HIGH_VOL))
            compatible2=true;
      }
      else if(strategy==STRAT_BREAKOUT)
      {
         compatible2=(historicalRegime2==REGIME_BREAKOUT ||
                      historicalRegime2==REGIME_HIGH_VOL);
      }
      else if(strategy==STRAT_MEANREV ||
              strategy==STRAT_RANGE ||
              strategy==STRAT_DIVERGENCE)
      {
         compatible2=(historicalRegime2==REGIME_RANGE ||
                      historicalRegime2==REGIME_CONTRACTING);
      }
      else if(strategy==STRAT_SESSION)
      {
         compatible2=(historicalRegime2!=REGIME_UNKNOWN &&
                      historicalRegime2!=REGIME_TRANSITION);
      }

      if(!compatible2)
         continue;

      if(!QualityOK(strategy,signal2,shift2))
         continue;

      double result2=SimTrade(signal2,shift2);

      oos.trades++;

      if(result2>0)
      {
         oos.wins++;
         oos.grossProfit+=result2;
      }
      else
      {
         oos.losses++;
         oos.grossLoss+=MathAbs(result2);
      }

      equity+=result2;

      if(equity>peak)
         peak=equity;

      double dd2=peak-equity;

      if(dd2>oos.maxDrawdown)
         oos.maxDrawdown=dd2;
   }

   if(oos.trades>0)
   {
      oos.expectancy=
         (oos.grossProfit-oos.grossLoss)/
         oos.trades;
   }

   if(oos.grossLoss>0)
      oos.profitFactor=
         oos.grossProfit/oos.grossLoss;

   if(oos.losses>0)
      oos.payoff=
         oos.grossProfit/
         MathMax(0.0001,oos.grossLoss);
}

//==================================================================
// SCORE
//==================================================================

double ScoreStrategy(AuditStats &train,
                     AuditStats &oos)
{
   if(train.trades<InpMinTrainTrades)
      return -999999.0;

   if(oos.trades<InpMinOOSTrades)
      return -999999.0;

   if(oos.profitFactor<InpMinOOSPF)
      return -999999.0;

   if(oos.expectancy<InpMinOOSExpectancy)
      return -999999.0;

   if(oos.maxDrawdown>InpMaxOOSDrawdown)
      return -999999.0;

   // Core statistical score.
   double score=0.0;

   score+=oos.profitFactor*40.0;
   score+=oos.expectancy*150.0;
   score+=oos.payoff*10.0;

   // Stability bonus.
   if(train.profitFactor>0)
   {
      double degradation=
         oos.profitFactor/train.profitFactor;

      if(degradation>1.0)
         degradation=1.0;

      score+=degradation*20.0;
   }

   // OOS sample bonus, capped.
   score+=MathMin(oos.trades,20)*0.75;

   // Drawdown penalty.
   score-=oos.maxDrawdown*3.0;

   return score;
}

//==================================================================
// WALK FORWARD
//==================================================================

void WalkForward(int shift)
{
   gBestStrategy=-1;
   gBestScore=-999999.0;
   gBestPF=0.0;
   gBestExp=-999.0;
   gBestDD=100.0;
   gBestTrainTrades=0;
   gBestOOSTrades=0;

   for(int s=0;s<STRAT_COUNT;s++)
   {
      AuditStats train;
      AuditStats oos;

      AuditStrategy(s,
                    shift,
                    train,
                    oos);

      double score=
         ScoreStrategy(train,oos);

      if(InpVerbose)
      {
         Print("B32 WF ",
               StrategyName(s),
               " TRAIN=",train.trades,
               " OOS=",oos.trades,
               " PF=",DoubleToString(oos.profitFactor,3),
               " EXP=",DoubleToString(oos.expectancy,4),
               " DD=",DoubleToString(oos.maxDrawdown,3),
               " PAYOFF=",DoubleToString(oos.payoff,3),
               " SCORE=",DoubleToString(score,2));
      }

      if(score>gBestScore)
      {
         gBestScore=score;
         gBestStrategy=s;
         gBestPF=oos.profitFactor;
         gBestExp=oos.expectancy;
         gBestDD=oos.maxDrawdown;
         gBestTrainTrades=train.trades;
         gBestOOSTrades=oos.trades;
      }
   }

   gCalibrationCount++;
   gLastCalibrationBar=(int)gBarSequence;

   if(InpVerbose)
   {
      if(gBestStrategy>=0)
      {
         Print("B32 WF BEST=",
               StrategyName(gBestStrategy),
               " SCORE=",DoubleToString(gBestScore,2),
               " PF=",DoubleToString(gBestPF,3),
               " EXP=",DoubleToString(gBestExp,4),
               " DD=",DoubleToString(gBestDD,3),
               " TRAIN=",gBestTrainTrades,
               " OOS=",gBestOOSTrades);
      }
      else
      {
         Print("B32 WF BEST=NONE");
      }
   }
}

//==================================================================
// SAFE DISPLAY HELPERS
//==================================================================

string BestStrategyText()
{
   if(gBestStrategy>=0)
      return StrategyName(gBestStrategy);

   return "NONE";
}

//==================================================================
// REPORT
//==================================================================

void WriteReport()
{
   if(!InpAutoReport)
      return;

   int handle=FileOpen("B32_RegimeReport.csv",
                       FILE_CSV|
                       FILE_READ|
                       FILE_WRITE|
                       FILE_SHARE_READ|
                       ',',
                       CP_UTF8);

   if(handle==INVALID_HANDLE)
   {
      if(InpVerbose)
         Print("B32 REPORT ERROR=",GetLastError());

      return;
   }

   FileSeek(handle,0,SEEK_END);

   if(FileTell(handle)==0)
   {
      FileWrite(handle,
                "Time",
                "Symbol",
                "Period",
                "Regime",
                "PreviousRegime",
                "ATRRatio",
                "StdRatio",
                "ADX",
                "Hurst",
                "BestStrategy",
                "BestScore",
                "OOSPF",
                "OOSExpectancy",
                "OOSDD",
                "TrainTrades",
                "OOSTrades",
                "RegimeChanges");
   }

   FileWrite(handle,
             TimeToString(TimeCurrent(),
                          TIME_DATE|TIME_SECONDS),
             Symbol(),
             Period(),
             RegimeName(gCurrentRegime),
             RegimeName(gPreviousRegime),
             DoubleToString(gCurrentATRRatio,4),
             DoubleToString(gCurrentStdRatio,4),
             DoubleToString(gCurrentADX,3),
             DoubleToString(gCurrentHurst,4),
             BestStrategyText(),
             DoubleToString(gBestScore,3),
             DoubleToString(gBestPF,4),
             DoubleToString(gBestExp,5),
             DoubleToString(gBestDD,4),
             gBestTrainTrades,
             gBestOOSTrades,
             gRegimeChanges);

   FileClose(handle);
}

//==================================================================
// POSITION COUNT
//==================================================================

int CountOpenPositions()
{
   int count=0;

   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,
                      SELECT_BY_POS,
                      MODE_TRADES))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=InpMagicNumber)
         continue;

      if(OrderType()==OP_BUY ||
         OrderType()==OP_SELL)
         count++;
   }

   return count;
}

//==================================================================
// SESSION
//==================================================================

bool SessionOK()
{
   int hour=TimeHour(iTime(Symbol(),
                           Period(),
                           1));

   if(InpSessionStart<=InpSessionEnd)
      return hour>=InpSessionStart &&
             hour<InpSessionEnd;

   return hour>=InpSessionStart ||
          hour<InpSessionEnd;
}

//==================================================================
// SPREAD
//==================================================================

bool SpreadOK()
{
   RefreshRates();

   double spreadPoints=
      (Ask-Bid)/Point;
   gLastSpreadPoints=spreadPoints;

   if(spreadPoints>InpMaxSpreadPoints)
      return false;

   double atr=ATR(1);

   if(atr<=0)
      return false;

   double spreadATRRatio=(spreadPoints*Point)/atr;
   gLastSpreadATRRatio=spreadATRRatio;

   if(spreadATRRatio>InpMaxSpreadATR)
   {
      gSpreadAtrBlocks++;
      return false;
   }

   return true;
}

//==================================================================
// COOLDOWN
//==================================================================

bool CooldownOK()
{
   if(gLastTradeBarTime<=0)
      return true;

   int shift=iBarShift(Symbol(),
                       Period(),
                       gLastTradeBarTime,
                       false);

   if(shift<0)
      return true;

   return shift>=InpCooldownBars;
}

//==================================================================
// LOSS PROTECTION
//==================================================================

bool LossProtectionOK()
{
   if(!InpUseLossProtection)
      return true;

   return gLossPauseRemaining<=0;
}

//==================================================================
// FLIP PROTECTION
//==================================================================

void ResetFlipWindow()
{
   if(gFlipWindowStart<=0)
      return;

   int bars=iBarShift(Symbol(),
                      Period(),
                      gFlipWindowStart,
                      false);

   if(bars>=InpFlipWindowBars)
   {
      gFlipCount=0;
      gFlipWindowStart=0;
   }
}

bool DirectionOK(int direction)
{
   if(!InpUseFlipProtection)
      return true;

   ResetFlipWindow();

   if(gLastTradeDirection==0)
      return true;

   if(direction==gLastTradeDirection)
      return true;

   if(gFlipWindowStart<=0)
      gFlipWindowStart=
         iTime(Symbol(),Period(),1);

   return gFlipCount<InpMaxDirectionFlips;
}

//==================================================================
// LOTS
//==================================================================

double CalculateLots(double stopDistance)
{
   if(stopDistance<=0)
      return 0.0;

   double riskMoney=
      AccountBalance()*
      InpRiskPercent/
      100.0;

   double tickValue=
      MarketInfo(Symbol(),MODE_TICKVALUE);

   double tickSize=
      MarketInfo(Symbol(),MODE_TICKSIZE);

   if(tickValue<=0 ||
      tickSize<=0)
      return 0.0;

   double moneyPerLot=
      stopDistance/
      tickSize*
      tickValue;

   if(moneyPerLot<=0)
      return 0.0;

   double lots=
      riskMoney/
      moneyPerLot;

   double minLot=
      MarketInfo(Symbol(),MODE_MINLOT);

   double maxLot=
      MarketInfo(Symbol(),MODE_MAXLOT);

   double lotStep=
      MarketInfo(Symbol(),MODE_LOTSTEP);

   if(lotStep<=0)
      lotStep=0.01;

   lots=MathFloor(lots/lotStep)*
         lotStep;

   lots=MathMax(lots,minLot);
   lots=MathMin(lots,maxLot);

   int digits=2;

   if(lotStep>=1.0)
      digits=0;
   else if(lotStep>=0.1)
      digits=1;

   return NormalizeDouble(lots,digits);
}

//==================================================================
// STOPS
//==================================================================

bool StopsValid(int direction,
                double entry,
                double sl,
                double tp)
{
   double minDistance=
      MarketInfo(Symbol(),
                 MODE_STOPLEVEL)*Point;

   if(minDistance<Point)
      minDistance=Point;

   if(direction==SIGNAL_BUY)
   {
      if(entry-sl<minDistance)
         return false;

      if(tp-entry<minDistance)
         return false;
   }

   if(direction==SIGNAL_SELL)
   {
      if(sl-entry<minDistance)
         return false;

      if(entry-tp<minDistance)
         return false;
   }

   return true;
}

//==================================================================
// EXECUTION
//==================================================================

bool ExecuteTrade(int strategy,
                  int direction)
{
   RefreshRates();

   double atr=ATR(1);

   if(atr<=0)
      return false;

   double slDistance=atr*InpSL_ATR;
   double tpDistance=atr*InpTP_ATR;

   double price;
   double sl;
   double tp;

   if(direction==SIGNAL_BUY)
   {
      price=Ask;
      sl=price-slDistance;
      tp=price+tpDistance;
   }
   else
   {
      price=Bid;
      sl=price+slDistance;
      tp=price-tpDistance;
   }

   price=NormalizeDouble(price,Digits);
   sl=NormalizeDouble(sl,Digits);
   tp=NormalizeDouble(tp,Digits);

   if(!StopsValid(direction,
                  price,
                  sl,
                  tp))
      return false;

   double lots=
      CalculateLots(slDistance);

   if(lots<=0)
      return false;

   int type=
      direction==SIGNAL_BUY ? OP_BUY : OP_SELL;

   string comment=
      "B32_"+StrategyName(strategy);

   ResetLastError();

   int ticket=
      OrderSend(Symbol(),
                type,
                lots,
                price,
                InpSlippage,
                sl,
                tp,
                comment,
                InpMagicNumber,
                0,
                clrNONE);

   if(ticket<0)
   {
      int error=GetLastError();

      gOrderSendErrors++;

      if(InpVerbose)
         Print("B32 ORDER ERROR=",
               error,
               " STRATEGY=",
               StrategyName(strategy));

      return false;
   }

   gOpenedTrades++;
   gStrategyOpened[strategy]++;

   gLastTradeBarTime=
      iTime(Symbol(),Period(),1);

   if(gLastTradeDirection!=0 &&
      direction!=gLastTradeDirection)
   {
      if(gFlipWindowStart<=0)
         gFlipWindowStart=
            iTime(Symbol(),Period(),1);

      gFlipCount++;
   }

   gLastTradeDirection=direction;

   if(InpVerbose)
   {
      Print("B32 OPENED ticket=",
            ticket,
            " STRATEGY=",
            StrategyName(strategy),
            " DIR=",
            (direction==SIGNAL_BUY ? "BUY" : "SELL"),
            " LOTS=",
            DoubleToString(lots,2),
            " REGIME=",
            RegimeName(gCurrentRegime));
   }

   return true;
}

//==================================================================
// HISTORY STATE
//==================================================================

void UpdateLossState()
{
   datetime newestClose=
      gLastProcessedHistoryClose;

   int newestTicket=
      gLastHistoryTicket;

   for(int i=OrdersHistoryTotal()-1;
       i>=0;
       i--)
   {
      if(!OrderSelect(i,
                      SELECT_BY_POS,
                      MODE_HISTORY))
         continue;

      if(OrderSymbol()!=Symbol())
         continue;

      if(OrderMagicNumber()!=InpMagicNumber)
         continue;

      if(OrderType()!=OP_BUY &&
         OrderType()!=OP_SELL)
         continue;

      datetime closeTime=
         OrderCloseTime();

      if(closeTime<=0)
         continue;

      bool newer=
         closeTime>newestClose ||
         (closeTime==newestClose &&
          OrderTicket()>newestTicket);

      if(!newer)
         continue;

      newestClose=closeTime;
      newestTicket=OrderTicket();

      double net=
         OrderProfit()+
         OrderSwap()+
         OrderCommission();

      if(net<0)
      {
         gLossStreak++;

         if(InpUseLossProtection &&
            gLossStreak>=InpMaxLossStreak)
         {
            gLossPauseRemaining=
               InpLossPauseBars;
         }

         if(InpVerbose)
            Print("B32 LOSS ticket=",
                  OrderTicket(),
                  " NET=",
                  DoubleToString(net,2),
                  " STREAK=",
                  gLossStreak);
      }
      else if(net>0)
      {
         gLossStreak=0;
         gLossPauseRemaining=0;

         if(InpVerbose)
            Print("B32 WIN ticket=",
                  OrderTicket(),
                  " NET=",
                  DoubleToString(net,2));
      }
   }

   gLastProcessedHistoryClose=newestClose;
   gLastHistoryTicket=newestTicket;
}

//==================================================================
// SIGNAL SELECTION
//==================================================================

bool SelectSignal(int shift,
                  int &strategy,
                  int &direction)
{
   strategy=-1;
   direction=SIGNAL_NONE;

   // First use the statistically selected strategy.
   if(gBestStrategy>=0)
   {
      int signal=
         ValidSignal(gBestStrategy,
                     shift,
                     true);

      if(signal!=SIGNAL_NONE)
      {
         strategy=gBestStrategy;
         direction=signal;
         gSelectedSignals++;
         return true;
      }
   }

   // Secondary strategies.
   int order[STRAT_COUNT];

   order[0]=STRAT_TREND;
   order[1]=STRAT_MOMENTUM;
   order[2]=STRAT_BREAKOUT;
   order[3]=STRAT_SESSION;
   order[4]=STRAT_DIVERGENCE;
   order[5]=STRAT_RANGE;
   order[6]=STRAT_MEANREV;
   order[7]=STRAT_FRACTAL_HTF;

   for(int i=0;i<STRAT_COUNT;i++)
   {
      int s=order[i];

      if(s==gBestStrategy)
         continue;

      int signal=
         ValidSignal(s,
                     shift,
                     true);

      if(signal==SIGNAL_NONE)
         continue;

      strategy=s;
      direction=signal;
      gSelectedSignals++;

      return true;
   }

   return false;
}

//==================================================================
// DIAGNOSTICS
//==================================================================

void Diagnostics()
{
   Print("==================================================");
   Print("B32 DIAGNOSTICS");

   Print("REGIME=",
         RegimeName(gCurrentRegime));

   Print("PREVIOUS_REGIME=",
         RegimeName(gPreviousRegime));

   Print("ATR_RATIO=",
         DoubleToString(gCurrentATRRatio,3));

   Print("STD_RATIO=",
         DoubleToString(gCurrentStdRatio,3));

   Print("ADX=",
         DoubleToString(gCurrentADX,2));

   Print("HURST=",
         DoubleToString(gCurrentHurst,3));

   Print("BEST_STRATEGY=",BestStrategyText());

   Print("BEST_SCORE=",
         DoubleToString(gBestScore,2));

   Print("OOS_PF=",
         DoubleToString(gBestPF,3));

   Print("OOS_EXP=",
         DoubleToString(gBestExp,4));

   Print("OOS_DD=",
         DoubleToString(gBestDD,3));

   Print("TRAIN_TRADES=",
         gBestTrainTrades);

   Print("OOS_TRADES=",
         gBestOOSTrades);

   Print("REGIME_CHANGES=",
         gRegimeChanges);

   Print("CALIBRATIONS=",
         gCalibrationCount);

   Print("OPENED_TRADES=",
         gOpenedTrades);

   Print("ORDER_ERRORS=",
         gOrderSendErrors);

   Print("BLOCK_POSITION=",
         gBlockPosition);

   Print("BLOCK_SESSION=",
         gBlockSession);

   Print("BLOCK_SPREAD=",
         gBlockSpread);

   Print("BLOCK_COOLDOWN=",
         gBlockCooldown);

   Print("BLOCK_LOSS=",
         gBlockLoss);

   Print("BLOCK_FLIP=",
         gBlockFlip);

   Print("BLOCK_CONTEXT=",
         gBlockContext);

   Print("NO_SIGNAL=",
         gBlockNoSignal);

   Print("SELECTED_SIGNALS=",gSelectedSignals);
   Print("REJECTED_QUALITY=",gRejectedQuality);
   Print("REJECTED_CONTEXT=",gRejectedContext);
   Print("SPREAD_ATR_BLOCKS=",gSpreadAtrBlocks);
   Print("SPREAD_POINTS=",DoubleToString(gLastSpreadPoints,1),
         " SPREAD_ATR_RATIO=",DoubleToString(gLastSpreadATRRatio,3),
         " MAX_SPREAD_POINTS=",InpMaxSpreadPoints,
         " MAX_SPREAD_ATR=",DoubleToString(InpMaxSpreadATR,3));

   for(int d=0;d<STRAT_COUNT;d++)
   {
      Print("B32.1 FLOW ",StrategyName(d),
            " RAW=",gRawSignals[d],
            " QUALITY=",gQualityPass[d],
            " CONTEXT=",gContextPass[d]);
   }

   for(int s=0;s<STRAT_COUNT;s++)
   {
      Print("B32 STRATEGY ",
            StrategyName(s),
            " DETECTED=",
            gStrategyDetected[s],
            " QUALIFIED=",
            gStrategyQualified[s],
            " OPENED=",
            gStrategyOpened[s]);
   }

   Print("==================================================");
}

//==================================================================
// INIT
//==================================================================

int OnInit()
{
   ArrayInitialize(gStrategyDetected,0);
   ArrayInitialize(gStrategyQualified,0);
   ArrayInitialize(gStrategyOpened,0);
   ArrayInitialize(gRawSignals,0);
   ArrayInitialize(gQualityPass,0);
   ArrayInitialize(gContextPass,0);

   gCurrentRegime=REGIME_UNKNOWN;
   gPreviousRegime=REGIME_UNKNOWN;

   gBestStrategy=-1;
   gLastCalibrationBar=-1;

   gLossStreak=0;
   gLossPauseRemaining=0;

   gLastTradeDirection=0;
   gFlipCount=0;
   gFlipWindowStart=0;

   gLastProcessedHistoryClose=0;
   gLastHistoryTicket=-1;

   if(InpVerbose)
   {
      Print("==============================================");
      Print("AI Trading Bot v2.32 initialized");
      Print("Symbol=",Symbol());
      Print("Period=",Period());
      Print("Risk=",DoubleToString(InpRiskPercent,2),"%");
      Print("SL ATR=",DoubleToString(InpSL_ATR,2));
      Print("TP ATR=",DoubleToString(InpTP_ATR,2));
      Print("HurstPeriod=",InpHurstPeriod);
      Print("==============================================");
   }

   return INIT_SUCCEEDED;
}

//==================================================================
// DEINIT
//==================================================================

void OnDeinit(const int reason)
{
   Diagnostics();
}

//==================================================================
// MAIN
//==================================================================

void OnTick()
{
   UpdateLossState();

   if(!IsNewBar())
      return;

   gBarsEvaluated++;
   gBarSequence++;

   if(gLossPauseRemaining>0)
      gLossPauseRemaining--;

   int shift=1;

   if(!HasEnoughBars())
      return;

   //===============================================================
   // MARKET INTELLIGENCE
   //===============================================================

   UpdateRegime(shift);

   //===============================================================
   // RECALIBRATION
   //===============================================================

   if(gBestStrategy<0 ||
      gLastCalibrationBar<0 ||
      (gBarSequence-gLastCalibrationBar)>=InpRecalibrationBars)
   {
      WalkForward(shift);
   }

   //===============================================================
   // AUTO REPORT
   //===============================================================

   WriteReport();

   //===============================================================
   // POSITION LIMIT
   //===============================================================

   if(CountOpenPositions()>=InpMaxOpenTrades)
   {
      gBlockPosition++;
      return;
   }

   //===============================================================
   // SESSION
   //===============================================================

   if(!SessionOK())
   {
      gBlockSession++;
      return;
   }

   //===============================================================
   // SPREAD
   //===============================================================

   if(!SpreadOK())
   {
      gBlockSpread++;
      return;
   }

   //===============================================================
   // COOLDOWN
   //===============================================================

   if(!CooldownOK())
   {
      gBlockCooldown++;
      return;
   }

   //===============================================================
   // LOSS PAUSE
   //===============================================================

   if(!LossProtectionOK())
   {
      gBlockLoss++;
      return;
   }

   //===============================================================
   // SIGNAL
   //===============================================================

   int strategy=-1;
   int direction=SIGNAL_NONE;

   if(!SelectSignal(shift,
                    strategy,
                    direction))
   {
      gBlockNoSignal++;
      return;
   }

   //===============================================================
   // DIRECTION PROTECTION
   //===============================================================

   if(!DirectionOK(direction))
   {
      gBlockFlip++;
      return;
   }

   //===============================================================
   // FINAL REGIME CHECK
   //===============================================================

   if(!StrategyCompatible(strategy,
                          direction))
   {
      gBlockContext++;
      return;
   }

   //===============================================================
   // EXECUTION
   //===============================================================

   ExecuteTrade(strategy,
                direction);
}
//+------------------------------------------------------------------+