//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.32_RegimeIntelligence.mq4                    |
//| Adaptive Regime + 8 Strategy Walk-Forward EA                    |
//| Robust OOS selection + signal scoring + risk protection         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.32"
#property description "Adaptive Regime Intelligence + 8 Strategy Walk-Forward + Robust Execution"

//==================================================================
// INPUTS
//==================================================================

//--- Risk
input double InpRiskPercent       = 0.25;
input int    InpMaxOpenTrades     = 1;
input int    InpMagicNumber       = 2035031;
input int    InpSlippage          = 5;

//--- Indicators
input int    InpATRPeriod         = 14;
input int    InpADXPeriod         = 14;
input int    InpRSIPeriod         = 14;
input int    InpFastEMA           = 8;
input int    InpSlowEMA           = 21;
input int    InpTrendEMA          = 200;

//--- Risk / Reward
input double InpSL_ATR            = 1.30;
input double InpTP_ATR            = 2.60;

//--- Market filters
input int    InpMaxSpreadPoints   = 30;
input double InpMaxSpreadATR      = 0.35;
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

//--- OOS selection
input double InpMinOOSPF          = 0.80;
input double InpMinOOSExpectancy  = -0.05;
input double InpMaxOOSDrawdown    = 15.0;

//--- Signal quality
input double InpMinSignalScore    = 55.0;
input bool   InpRequireBestStrategy = true;
input bool   InpAllowSecondaryStrategy = false;

//--- Regime
input int    InpRegimeLookback    = 20;
input double InpATRExpansion      = 1.25;
input double InpATRContraction    = 0.80;
input double InpTrendADX          = 22.0;
input double InpRangeADX          = 18.0;

//--- Hurst
input int    InpHurstPeriod       = 40;
input double InpHurstTrend        = 0.55;
input double InpHurstRange        = 0.45;

//--- Regime confidence
input double InpMinRegimeADX      = 15.0;
input bool   InpBlockTransition   = true;

//--- Loss protection
input bool   InpUseLossProtection = true;
input int    InpMaxLossStreak     = 3;
input int    InpLossPauseBars     = 6;

//--- Direction flip
input bool   InpUseFlipProtection = true;
input int    InpMaxDirectionFlips = 2;
input int    InpFlipWindowBars    = 24;

//--- Execution
input int    InpMaxRetries        = 2;
input bool   InpUseECNMode        = true;

//--- Reporting
input bool   InpAutoReport        = true;
input bool   InpVerbose           = true;

//==================================================================
// CONSTANTS
//==================================================================

#define STRAT_COUNT 8

#define STRAT_TREND        0
#define STRAT_MEANREV      1
#define STRAT_MOMENTUM     2
#define STRAT_BREAKOUT     3
#define STRAT_SESSION      4
#define STRAT_DIVERGENCE   5
#define STRAT_RANGE        6
#define STRAT_FRACTAL_HTF  7

#define SIGNAL_NONE  0
#define SIGNAL_BUY   1
#define SIGNAL_SELL -1

#define REGIME_UNKNOWN      0
#define REGIME_TREND_UP     1
#define REGIME_TREND_DOWN   2
#define REGIME_RANGE        3
#define REGIME_BREAKOUT     4
#define REGIME_HIGH_VOL     5
#define REGIME_CONTRACTING  6
#define REGIME_TRANSITION   7

//==================================================================
// GLOBALS
//==================================================================

int gBestStrategy = -1;

double gBestScore = -999999.0;
double gBestPF    = 0.0;
double gBestExp   = -999.0;
double gBestDD    = 100.0;

int gBestTrainTrades = 0;
int gBestOOSTrades   = 0;

int gCurrentRegime  = REGIME_UNKNOWN;
int gPreviousRegime = REGIME_UNKNOWN;

double gCurrentHurst    = 0.50;
double gCurrentATRRatio = 1.0;
double gCurrentADX      = 0.0;
double gCurrentStdRatio = 1.0;

datetime gLastBarTime       = 0;
datetime gLastTradeBarTime  = 0;
datetime gRegimeStartTime   = 0;

int gLossStreak         = 0;
int gLossPauseRemaining = 0;

int gLastTradeDirection = 0;
int gFlipCount          = 0;
datetime gFlipWindowStart = 0;

// FIX: real recalibration counter
int gBarsSinceCalibration = 999999;
int gCalibrationCount     = 0;

long gBarsEvaluated   = 0;
long gOpenedTrades    = 0;
long gOrderSendErrors = 0;

long gBlockPosition = 0;
long gBlockSession  = 0;
long gBlockSpread   = 0;
long gBlockCooldown = 0;
long gBlockLoss     = 0;
long gBlockFlip     = 0;
long gBlockContext  = 0;
long gBlockSignalScore = 0;
long gBlockNoSignal = 0;
long gBlockExecution = 0;

long gRegimeChanges = 0;

long gStrategyDetected[STRAT_COUNT];
long gStrategyQualified[STRAT_COUNT];
long gStrategyOpened[STRAT_COUNT];

datetime gLastProcessedHistoryClose = 0;
int      gLastHistoryTicket = -1;

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
// INDICATORS
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

//==================================================================
// NEW BAR
//==================================================================

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

//==================================================================
// DATA VALIDATION
//==================================================================

bool HasEnoughBars()
{
   int minimum=
      InpTrendEMA+
      InpTrainBars+
      InpOOSBars+
      InpHurstPeriod+
      InpRegimeLookback+
      InpAuditHorizon+
      100;

   return Bars>minimum;
}

//==================================================================
// STANDARD DEVIATION
//==================================================================

double StdDev(int shift,int period)
{
   if(period<2)
      return 0.0;

   if(Bars<(shift+period+2))
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
// HURST - RETURN BASED R/S
//==================================================================

double HurstExponent(int shift)
{
   int n=InpHurstPeriod;

   if(n<20)
      return 0.50;

   if(Bars<(shift+n+5))
      return 0.50;

   double mean=0.0;

   for(int i=0;i<n;i++)
   {
      double c1=iClose(Symbol(),Period(),shift+i);
      double c2=iClose(Symbol(),Period(),shift+i+1);

      if(c1<=0 || c2<=0)
         return 0.50;

      mean+=MathLog(c1/c2);
   }

   mean/=n;

   double cumulative=0.0;
   double maxDev=-DBL_MAX;
   double minDev= DBL_MAX;
   double variance=0.0;

   for(int j=0;j<n;j++)
   {
      double c1=iClose(Symbol(),Period(),shift+j);
      double c2=iClose(Symbol(),Period(),shift+j+1);

      if(c1<=0 || c2<=0)
         return 0.50;

      double ret=MathLog(c1/c2);

      cumulative+=(ret-mean);

      maxDev=MathMax(maxDev,cumulative);
      minDev=MathMin(minDev,cumulative);

      variance+=(ret-mean)*(ret-mean);
   }

   double sd=MathSqrt(variance/n);

   if(sd<=0)
      return 0.50;

   double R=maxDev-minDev;

   if(R<=0)
      return 0.50;

   double RS=R/sd;

   if(RS<=0)
      return 0.50;

   double h=MathLog(RS)/MathLog(n);

   if(h<0)
      h=0;

   if(h>1)
      h=1;

   return h;
}

//==================================================================
// ATR RATIO
//==================================================================

double ATRRatio(int shift)
{
   double current=ATR(shift);

   if(current<=0)
      return 1.0;

   int n=InpRegimeLookback;

   double average=0.0;
   int valid=0;

   for(int i=shift+1;i<=shift+n;i++)
   {
      double a=ATR(i);

      if(a>0)
      {
         average+=a;
         valid++;
      }
   }

   if(valid<=0)
      return 1.0;

   average/=valid;

   if(average<=0)
      return 1.0;

   return current/average;
}

//==================================================================
// STD RATIO
//==================================================================

double StdRatio(int shift)
{
   double current=StdDev(shift,InpRegimeLookback);

   if(current<=0)
      return 1.0;

   double average=0.0;
   int valid=0;

   for(int i=shift+1;
       i<=shift+InpRegimeLookback;
       i++)
   {
      double s=StdDev(i,InpRegimeLookback);

      if(s>0)
      {
         average+=s;
         valid++;
      }
   }

   if(valid<=0)
      return 1.0;

   average/=valid;

   if(average<=0)
      return 1.0;

   return current/average;
}

//==================================================================
// REGIME DETECTION
//==================================================================

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

   //===============================================================
   // HIGH VOLATILITY
   //===============================================================

   if(atrRatio>=InpATRExpansion &&
      stdRatio>=InpATRExpansion &&
      adx>=InpTrendADX)
   {
      if((close>trend && fast>slow) ||
         (close<trend && fast<slow))
         return REGIME_HIGH_VOL;
   }

   //===============================================================
   // BREAKOUT
   //===============================================================

   double high12=-DBL_MAX;
   double low12=DBL_MAX;

   for(int i=shift+1;i<=shift+12;i++)
   {
      high12=MathMax(high12,
                     iHigh(Symbol(),Period(),i));

      low12=MathMin(low12,
                    iLow(Symbol(),Period(),i));
   }

   if((close>high12 || close<low12) &&
      atrRatio>=1.05)
   {
      return REGIME_BREAKOUT;
   }

   //===============================================================
   // TREND
   //===============================================================

   if(adx>=InpTrendADX)
   {
      if(close>trend && fast>slow)
         return REGIME_TREND_UP;

      if(close<trend && fast<slow)
         return REGIME_TREND_DOWN;
   }

   //===============================================================
   // CONTRACTING
   //===============================================================

   if(atrRatio<=InpATRContraction &&
      stdRatio<=InpATRContraction)
   {
      return REGIME_CONTRACTING;
   }

   //===============================================================
   // RANGE
   //===============================================================

   if(adx<=InpRangeADX ||
      hurst<=InpHurstRange)
   {
      return REGIME_RANGE;
   }

   //===============================================================
   // HURST TREND
   //===============================================================

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
// REGIME UPDATE
//==================================================================

void UpdateRegime(int shift)
{
   int detected=DetectRegime(shift);

   // Restore current diagnostics only from current candle.
   gCurrentATRRatio=ATRRatio(shift);
   gCurrentStdRatio=StdRatio(shift);
   gCurrentADX=ADX(shift);
   gCurrentHurst=HurstExponent(shift);

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

      // Force recalibration.
      gBarsSinceCalibration=999999;

      if(InpVerbose)
      {
         Print("B32 REGIME CHANGE ",
               RegimeName(gPreviousRegime),
               " -> ",
               RegimeName(gCurrentRegime),
               " ATR=",
               DoubleToString(gCurrentATRRatio,2),
               " STD=",
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

   if(atr<=0)
      return SIGNAL_NONE;

   //===============================================================
   // TREND
   //===============================================================

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

   //===============================================================
   // MEAN REVERSION
   //===============================================================

   if(strategy==STRAT_MEANREV)
   {
      if(adx<=InpRangeADX &&
         rsi<=30.0)
         return SIGNAL_BUY;

      if(adx<=InpRangeADX &&
         rsi>=70.0)
         return SIGNAL_SELL;
   }

   //===============================================================
   // MOMENTUM
   //===============================================================

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

   //===============================================================
   // BREAKOUT
   //===============================================================

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

      if(close0>high12 &&
         adx>=InpTrendADX)
         return SIGNAL_BUY;

      if(close0<low12 &&
         adx>=InpTrendADX)
         return SIGNAL_SELL;
   }

   //===============================================================
   // SESSION
   //===============================================================

   if(strategy==STRAT_SESSION)
   {
      int hour=TimeHour(iTime(Symbol(),
                              Period(),
                              shift));

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

   //===============================================================
   // DIVERGENCE
   //===============================================================

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

   //===============================================================
   // RANGE
   //===============================================================

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

         if(range>0)
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

   //===============================================================
   // FRACTAL HTF
   //===============================================================

   if(strategy==STRAT_FRACTAL_HTF)
   {
      int htfShift=iBarShift(Symbol(),
                             PERIOD_H4,
                             iTime(Symbol(),Period(),shift),
                             false);

      if(htfShift<1)
         return SIGNAL_NONE;

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
// STRATEGY COMPATIBILITY
//==================================================================

bool StrategyCompatibleForRegime(int strategy,
                                  int direction,
                                  int regime)
{
   if(regime==REGIME_UNKNOWN)
      return false;

   if(InpBlockTransition &&
      regime==REGIME_TRANSITION)
      return false;

   // TREND FAMILY
   if(strategy==STRAT_TREND ||
      strategy==STRAT_MOMENTUM ||
      strategy==STRAT_FRACTAL_HTF)
   {
      if(regime==REGIME_HIGH_VOL)
         return true;

      if(regime==REGIME_TREND_UP &&
         direction==SIGNAL_BUY)
         return true;

      if(regime==REGIME_TREND_DOWN &&
         direction==SIGNAL_SELL)
         return true;

      return false;
   }

   // BREAKOUT
   if(strategy==STRAT_BREAKOUT)
   {
      return(regime==REGIME_BREAKOUT ||
             regime==REGIME_HIGH_VOL);
   }

   // RANGE
   if(strategy==STRAT_MEANREV ||
      strategy==STRAT_RANGE ||
      strategy==STRAT_DIVERGENCE)
   {
      return(regime==REGIME_RANGE ||
             regime==REGIME_CONTRACTING);
   }

   // SESSION
   if(strategy==STRAT_SESSION)
   {
      return(regime==REGIME_TREND_UP ||
             regime==REGIME_TREND_DOWN ||
             regime==REGIME_RANGE ||
             regime==REGIME_BREAKOUT ||
             regime==REGIME_HIGH_VOL);
   }

   return false;
}

//==================================================================
// CURRENT REGIME COMPATIBILITY
//==================================================================

bool StrategyCompatible(int strategy,int direction)
{
   return StrategyCompatibleForRegime(
      strategy,
      direction,
      gCurrentRegime);
}

//==================================================================
// QUALITY
//==================================================================

bool QualityOK(int strategy,
               int direction,
               int shift)
{
   double atr=ATR(shift);

   if(atr<=0)
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
// SIGNAL SCORE
//==================================================================

double CalculateSignalScore(int strategy,
                            int direction,
                            int shift)
{
   double score=0.0;

   double atr=ATR(shift);

   if(atr<=0)
      return 0.0;

   double adx=ADX(shift);
   double rsi=RSI(shift);

   double fast=EMA(InpFastEMA,shift);
   double slow=EMA(InpSlowEMA,shift);
   double trend=EMA(InpTrendEMA,shift);

   double close=iClose(Symbol(),Period(),shift);

   //===============================================================
   // REGIME
   //===============================================================

   if(StrategyCompatible(strategy,direction))
      score+=25.0;

   //===============================================================
   // ADX
   //===============================================================

   if(adx>=InpTrendADX)
      score+=15.0;
   else if(adx>=InpMinRegimeADX)
      score+=8.0;

   //===============================================================
   // EMA STRUCTURE
   //===============================================================

   if(direction==SIGNAL_BUY)
   {
      if(fast>slow)
         score+=12.0;

      if(close>fast)
         score+=10.0;

      if(close>trend)
         score+=8.0;
   }
   else if(direction==SIGNAL_SELL)
   {
      if(fast<slow)
         score+=12.0;

      if(close<fast)
         score+=10.0;

      if(close<trend)
         score+=8.0;
   }

   //===============================================================
   // RSI
   //===============================================================

   if(direction==SIGNAL_BUY)
   {
      if(rsi>=50 && rsi<=70)
         score+=7.0;
   }
   else
   {
      if(rsi<=50 && rsi>=30)
         score+=7.0;
   }

   //===============================================================
   // CANDLE
   //===============================================================

   double body=CandleBody(shift);

   if(body>=atr*0.20)
      score+=5.0;

   //===============================================================
   // HURST
   //===============================================================

   double hurst=HurstExponent(shift);

   if(strategy==STRAT_MEANREV ||
      strategy==STRAT_RANGE ||
      strategy==STRAT_DIVERGENCE)
   {
      if(hurst<=0.50)
         score+=10.0;
   }
   else
   {
      if(hurst>=0.50)
         score+=10.0;
   }

   if(score>100.0)
      score=100.0;

   return score;
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

   if(atr<=0)
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

      // Conservative treatment.
      if(hitSL && hitTP)
         return -1.0;

      if(hitSL)
         return -1.0;

      if(hitTP)
         return InpTP_ATR/InpSL_ATR;
   }

   int finalShift=
      MathMax(1,
              entryShift-InpAuditHorizon);

   double finalClose=
      iClose(Symbol(),
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
// HISTORICAL COMPATIBILITY
//==================================================================

bool HistoricalCompatible(int strategy,
                          int direction,
                          int shift)
{
   int historicalRegime=
      DetectRegime(shift);

   return StrategyCompatibleForRegime(
      strategy,
      direction,
      historicalRegime);
}

//==================================================================
// AUDIT STRATEGY
//==================================================================

void ResetAudit(AuditStats &a)
{
   a.trades=0;
   a.wins=0;
   a.losses=0;

   a.grossProfit=0.0;
   a.grossLoss=0.0;
   a.expectancy=0.0;
   a.profitFactor=0.0;

   a.maxDrawdown=0.0;
   a.payoff=0.0;
}

//==================================================================
// PROCESS AUDIT RESULT
//==================================================================

void AddAuditResult(AuditStats &a,
                    double result,
                    double &equity,
                    double &peak)
{
   a.trades++;

   if(result>0)
   {
      a.wins++;
      a.grossProfit+=result;
   }
   else
   {
      a.losses++;
      a.grossLoss+=MathAbs(result);
   }

   equity+=result;

   if(equity>peak)
      peak=equity;

   double dd=peak-equity;

   if(dd>a.maxDrawdown)
      a.maxDrawdown=dd;
}

//==================================================================
// FINISH AUDIT
//==================================================================

void FinalizeAudit(AuditStats &a)
{
   if(a.trades>0)
      a.expectancy=
         (a.grossProfit-a.grossLoss)/
         a.trades;

   if(a.grossLoss>0)
      a.profitFactor=
         a.grossProfit/a.grossLoss;

   if(a.losses>0)
      a.payoff=
         a.grossProfit/
         MathMax(0.0001,a.grossLoss);
}

//==================================================================
// AUDIT STRATEGY
//==================================================================

void AuditStrategy(int strategy,
                   int currentShift,
                   AuditStats &train,
                   AuditStats &oos)
{
   ResetAudit(train);
   ResetAudit(oos);

   //===============================================================
   // TRAIN
   //===============================================================

   int trainStart=
      currentShift+
      InpAuditGap+
      InpOOSBars+
      1;

   int trainEnd=
      trainStart+
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
      int signal=
         RawSignal(strategy,shift);

      if(signal==SIGNAL_NONE)
         continue;

      if(!HistoricalCompatible(strategy,
                               signal,
                               shift))
         continue;

      if(!QualityOK(strategy,
                    signal,
                    shift))
         continue;

      double result=
         SimTrade(signal,shift);

      AddAuditResult(train,
                     result,
                     equity,
                     peak);
   }

   FinalizeAudit(train);

   //===============================================================
   // OOS
   //===============================================================

   int oosStart=
      currentShift+
      InpAuditGap+
      1;

   int oosEnd=
      MathMax(1,
              oosStart-InpOOSBars+1);

   equity=0.0;
   peak=0.0;

   for(int shift2=oosStart;
       shift2>=oosEnd;
       shift2--)
   {
      int signal2=
         RawSignal(strategy,shift2);

      if(signal2==SIGNAL_NONE)
         continue;

      if(!HistoricalCompatible(strategy,
                               signal2,
                               shift2))
         continue;

      if(!QualityOK(strategy,
                    signal2,
                    shift2))
         continue;

      double result2=
         SimTrade(signal2,shift2);

      AddAuditResult(oos,
                     result2,
                     equity,
                     peak);
   }

   FinalizeAudit(oos);
}

//==================================================================
// SCORE STRATEGY
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

   double score=0.0;

   // OOS PF
   score+=MathMin(oos.profitFactor,3.0)*35.0;

   // OOS expectancy
   score+=MathMax(-1.0,
                  MathMin(1.0,
                          oos.expectancy))*100.0;

   // OOS payoff
   score+=MathMin(oos.payoff,3.0)*8.0;

   // Train/OOS degradation
   if(train.profitFactor>0.0)
   {
      double degradation=
         oos.profitFactor/
         train.profitFactor;

      if(degradation>1.0)
         degradation=1.0;

      score+=degradation*20.0;
   }

   // Sample size
   score+=MathMin(oos.trades,20)*1.0;

   // Drawdown
   score-=MathMin(oos.maxDrawdown,20.0)*2.0;

   return score;
}

//==================================================================
// WALK FORWARD
//==================================================================

void WalkForward(int shift)
{
   // Reset selection.
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
   gBarsSinceCalibration=0;

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
      {
         count++;
      }
   }

   return count;
}

//==================================================================
// SESSION
//==================================================================

bool SessionOK()
{
   int hour=
      TimeHour(iTime(Symbol(),
                     Period(),
                     1));

   if(InpSessionStart<=InpSessionEnd)
   {
      return hour>=InpSessionStart &&
             hour<InpSessionEnd;
   }

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

   if(spreadPoints>InpMaxSpreadPoints)
      return false;

   double atr=ATR(1);

   if(atr<=0)
      return false;

   if((spreadPoints*Point)/atr>
      InpMaxSpreadATR)
      return false;

   return true;
}

//==================================================================
// COOLDOWN
//==================================================================

bool CooldownOK()
{
   if(gLastTradeBarTime<=0)
      return true;

   int shift=
      iBarShift(Symbol(),
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
// FLIP WINDOW
//==================================================================

void ResetFlipWindow()
{
   if(gFlipWindowStart<=0)
      return;

   int bars=
      iBarShift(Symbol(),
                Period(),
                gFlipWindowStart,
                false);

   if(bars>=InpFlipWindowBars)
   {
      gFlipCount=0;
      gFlipWindowStart=0;
   }
}

//==================================================================
// DIRECTION PROTECTION
//==================================================================

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
   {
      gFlipWindowStart=
         iTime(Symbol(),Period(),1);
   }

   return gFlipCount<InpMaxDirectionFlips;
}

//==================================================================
// LOT STEP DIGITS
//==================================================================

int LotDigits()
{
   double step=
      MarketInfo(Symbol(),MODE_LOTSTEP);

   if(step>=1.0)
      return 0;

   if(step>=0.1)
      return 1;

   if(step>=0.01)
      return 2;

   return 3;
}

//==================================================================
// LOT CALCULATION
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

   double rawLots=
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

   // IMPORTANT:
   // Do not force min lot when it exceeds requested risk.
   if(rawLots<minLot)
      return 0.0;

   double lots=
      MathFloor(rawLots/lotStep)*
      lotStep;

   if(lots<minLot)
      return 0.0;

   if(lots>maxLot)
      lots=maxLot;

   return NormalizeDouble(lots,
                          LotDigits());
}

//==================================================================
// STOPS VALIDATION
//==================================================================

bool StopsValid(int direction,
                double entry,
                double sl,
                double tp)
{
   double stopLevel=
      MarketInfo(Symbol(),
                 MODE_STOPLEVEL)*Point;

   double freezeLevel=
      MarketInfo(Symbol(),
                 MODE_FREEZELEVEL)*Point;

   double minDistance=
      MathMax(stopLevel,
              freezeLevel);

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
// MARGIN CHECK
//==================================================================

bool MarginOK(int type,double lots)
{
   ResetLastError();

   double marginCheck=
      AccountFreeMarginCheck(Symbol(),
                             type,
                             lots);

   if(marginCheck<=0)
      return false;

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

   double slDistance=
      atr*InpSL_ATR;

   double tpDistance=
      atr*InpTP_ATR;

   int type=
      direction==SIGNAL_BUY ?
      OP_BUY : OP_SELL;

   double lots=
      CalculateLots(slDistance);

   if(lots<=0)
   {
      if(InpVerbose)
         Print("B32 EXECUTION BLOCKED: lot below minimum risk");
      return false;
   }

   if(!MarginOK(type,lots))
   {
      if(InpVerbose)
         Print("B32 EXECUTION BLOCKED: insufficient margin");
      return false;
   }

   string comment=
      "B32_"+StrategyName(strategy);

   //===============================================================
   // STANDARD EXECUTION
   //===============================================================

   for(int attempt=0;
       attempt<=InpMaxRetries;
       attempt++)
   {
      RefreshRates();

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
      {
         gBlockExecution++;
         return false;
      }

      ResetLastError();

      int ticket=-1;

      //============================================================
      // ECN: first open without stops
      //============================================================

      if(InpUseECNMode)
      {
         ticket=
            OrderSend(Symbol(),
                      type,
                      lots,
                      price,
                      InpSlippage,
                      0,
                      0,
                      comment,
                      InpMagicNumber,
                      0,
                      clrNONE);

         if(ticket>=0)
         {
            if(OrderSelect(ticket,
                           SELECT_BY_TICKET,
                           MODE_TRADES))
            {
               bool modified=
                  OrderModify(ticket,
                              OrderOpenPrice(),
                              sl,
                              tp,
                              0,
                              clrNONE);

               if(!modified)
               {
                  if(InpVerbose)
                     Print("B32 WARNING: OrderModify failed ",
                           GetLastError());
               }
            }
         }
      }
      else
      {
         ticket=
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
      }

      if(ticket>=0)
      {
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
            Print("B32 OPENED ticket=",ticket,
                  " STRATEGY=",StrategyName(strategy),
                  " DIR=",
                  direction==SIGNAL_BUY ?
                  "BUY":"SELL",
                  " LOTS=",
                  DoubleToString(lots,LotDigits()),
                  " REGIME=",
                  RegimeName(gCurrentRegime),
                  " SCORE=",
                  DoubleToString(
                     CalculateSignalScore(strategy,
                                          direction,
                                          1),
                     1));
         }

         return true;
      }

      int error=GetLastError();

      gOrderSendErrors++;

      if(InpVerbose)
         Print("B32 ORDER ERROR=",
               error,
               " ATTEMPT=",
               attempt+1,
               " STRATEGY=",
               StrategyName(strategy));

      RefreshRates();
   }

   return false;
}

//==================================================================
// HISTORY CURSOR INITIALIZATION
//==================================================================

void InitializeHistoryCursor()
{
   datetime latest=0;
   int latestTicket=-1;

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

      datetime closeTime=OrderCloseTime();

      if(closeTime<=0)
         continue;

      if(closeTime>latest ||
         (closeTime==latest &&
          OrderTicket()>latestTicket))
      {
         latest=closeTime;
         latestTicket=OrderTicket();
      }
   }

   gLastProcessedHistoryClose=latest;
   gLastHistoryTicket=latestTicket;
}

//==================================================================
// LOSS STATE
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
                  int &direction,
                  double &signalScore)
{
   strategy=-1;
   direction=SIGNAL_NONE;
   signalScore=0.0;

   //===============================================================
   // BEST WF STRATEGY
   //===============================================================

   if(gBestStrategy>=0)
   {
      int signal=
         ValidSignal:
         0;
   }

   return false;
}

//==================================================================
// VALID SIGNAL
//==================================================================

int ValidSignal(int strategy,
                int shift,
                bool countStats)
{
   int signal=
      RawSignal(strategy,shift);

   if(signal==SIGNAL_NONE)
      return SIGNAL_NONE;

   if(countStats)
      gStrategyDetected[strategy]++;

   if(!QualityOK(strategy,
                 signal,
                 shift))
      return SIGNAL_NONE;

   if(!StrategyCompatible(strategy,
                          signal))
      return SIGNAL_NONE;

   if(countStats)
      gStrategyQualified[strategy]++;

   return signal;
}

//==================================================================
// SELECT SIGNAL IMPLEMENTATION
//==================================================================

bool SelectSignal2(int shift,
                   int &strategy,
                   int &direction,
                   double &signalScore)
{
   strategy=-1;
   direction=SIGNAL_NONE;
   signalScore=0.0;

   // First: WF winner.
   if(gBestStrategy>=0)
   {
      int signal=
         ValidSignal(gBestStrategy,
                     shift,
                     true);

      if(signal!=SIGNAL_NONE)
      {
         double score=
            CalculateSignalScore(
               gBestStrategy,
               signal,
               shift);

         if(score>=InpMinSignalScore)
         {
            strategy=gBestStrategy;
            direction=signal;
            signalScore=score;
            return true;
         }
      }
   }

   // Optional secondary strategy.
   if(!InpAllowSecondaryStrategy)
      return false;

   double bestSecondaryScore=-1.0;
   int bestSecondary=-1;
   int bestSecondaryDirection=SIGNAL_NONE;

   for(int s=0;s<STRAT_COUNT;s++)
   {
      if(s==gBestStrategy)
         continue;

      int signal=
         ValidSignal(s,
                     shift,
                     true);

      if(signal==SIGNAL_NONE)
         continue;

      double score=
         CalculateSignalScore(s,
                              signal,
                              shift);

      if(score>bestSecondaryScore)
      {
         bestSecondaryScore=score;
         bestSecondary=s;
         bestSecondaryDirection=signal;
      }
   }

   if(bestSecondary>=0 &&
      bestSecondaryScore>=InpMinSignalScore)
   {
      strategy=bestSecondary;
      direction=bestSecondaryDirection;
      signalScore=bestSecondaryScore;

      return true;
   }

   return false;
}

//==================================================================
// REPORT
//==================================================================

void WriteReport()
{
   if(!InpAutoReport)
      return;

   int handle=
      FileOpen("B32_RegimeReport.csv",
               FILE_CSV|
               FILE_READ|
               FILE_WRITE|
               FILE_SHARE_READ,
               ',');

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
                "RegimeChanges",
                "Calibrations");
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
             gBestStrategy>=0 ?
             StrategyName(gBestStrategy):
             "NONE",
             DoubleToString(gBestScore,3),
             DoubleToString(gBestPF,4),
             DoubleToString(gBestExp,5),
             DoubleToString(gBestDD,4),
             gBestTrainTrades,
             gBestOOSTrades,
             gRegimeChanges,
             gCalibrationCount);

   FileClose(handle);
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

   Print("PREVIOUS=",
         RegimeName(gPreviousRegime));

   Print("ATR_RATIO=",
         DoubleToString(gCurrentATRRatio,3));

   Print("STD_RATIO=",
         DoubleToString(gCurrentStdRatio,3));

   Print("ADX=",
         DoubleToString(gCurrentADX,2));

   Print("HURST=",
         DoubleToString(gCurrentHurst,3));

   Print("BEST=",
         gBestStrategy>=0 ?
         StrategyName(gBestStrategy):
         "NONE");

   Print("SCORE=",
         DoubleToString(gBestScore,2));

   Print("OOS_PF=",
         DoubleToString(gBestPF,3));

   Print("OOS_EXP=",
         DoubleToString(gBestExp,4));

   Print("OOS_DD=",
         DoubleToString(gBestDD,3));

   Print("TRAIN=",
         gBestTrainTrades);

   Print("OOS=",
         gBestOOSTrades);

   Print("CALIBRATIONS=",
         gCalibrationCount);

   Print("REGIME_CHANGES=",
         gRegimeChanges);

   Print("OPENED=",
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

   Print("BLOCK_SIGNAL_SCORE=",
         gBlockSignalScore);

   Print("BLOCK_NO_SIGNAL=",
         gBlockNoSignal);

   Print("BLOCK_EXECUTION=",
         gBlockExecution);

   for(int s=0;s<STRAT_COUNT;s++)
   {
      Print("STRATEGY ",
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

   gCurrentRegime=REGIME_UNKNOWN;
   gPreviousRegime=REGIME_UNKNOWN;

   gBestStrategy=-1;
   gBestScore=-999999.0;

   gBarsSinceCalibration=999999;
   gCalibrationCount=0;

   gLossStreak=0;
   gLossPauseRemaining=0;

   gLastTradeDirection=0;
   gFlipCount=0;
   gFlipWindowStart=0;

   InitializeHistoryCursor();

   if(InpVerbose)
   {
      Print("==============================================");
      Print("AI Trading Bot v2.32 initialized");
      Print("Symbol=",Symbol());
      Print("Period=",Period());
      Print("Risk=",DoubleToString(InpRiskPercent,2),"%");
      Print("SL ATR=",DoubleToString(InpSL_ATR,2));
      Print("TP ATR=",DoubleToString(InpTP_ATR,2));
      Print("Train=",InpTrainBars);
      Print("OOS=",InpOOSBars);
      Print("Recalibration=",InpRecalibrationBars);
      Print("Min Signal Score=",
            DoubleToString(InpMinSignalScore,1));
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
   //===============================================================
   // HISTORY
   //===============================================================

   UpdateLossState();

   //===============================================================
   // NEW BAR ONLY
   //===============================================================

   if(!IsNewBar())
      return;

   gBarsEvaluated++;

   // FIX: real calibration counter.
   gBarsSinceCalibration++;

   if(gLossPauseRemaining>0)
      gLossPauseRemaining--;

   int shift=1;

   if(!HasEnoughBars())
      return;

   //===============================================================
   // CURRENT MARKET INTELLIGENCE
   //===============================================================

   UpdateRegime(shift);

   //===============================================================
   // WALK FORWARD
   //===============================================================

   if(gBestStrategy<0 ||
      gBarsSinceCalibration>=InpRecalibrationBars)
   {
      WalkForward(shift);

      // Restore current regime after historical WF calculations.
      UpdateRegime(shift);
   }

   //===============================================================
   // REPORT
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
   // LOSS PROTECTION
   //===============================================================

   if(!LossProtectionOK())
   {
      gBlockLoss++;
      return;
   }

   //===============================================================
   // TRANSITION FILTER
   //===============================================================

   if(InpBlockTransition &&
      gCurrentRegime==REGIME_TRANSITION)
   {
      gBlockContext++;
      return;
   }

   //===============================================================
   // SIGNAL
   //===============================================================

   int strategy=-1;
   int direction=SIGNAL_NONE;
   double signalScore=0.0;

   if(!SelectSignal2(shift,
                     strategy,
                     direction,
                     signalScore))
   {
      gBlockNoSignal++;
      return;
   }

   //===============================================================
   // SIGNAL SCORE
   //===============================================================

   if(signalScore<InpMinSignalScore)
   {
      gBlockSignalScore++;
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

   if(!ExecuteTrade(strategy,
                    direction))
   {
      gBlockExecution++;
      return;
   }
}
//+------------------------------------------------------------------+