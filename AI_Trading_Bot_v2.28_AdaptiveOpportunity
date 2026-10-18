//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.28_AdaptiveOpportunity.mq4                    |
//| Adaptive multi-strategy EA for MT4                              |
//| Version 2.28                                                     |
//+------------------------------------------------------------------+
#property strict
#property version   "2.28"
#property description "Adaptive multi-strategy EA with strategy-aware quality gates"

//====================================================
// STRATEGIES
//====================================================
#define STRAT_TREND       0
#define STRAT_MEANREV     1
#define STRAT_MOMENTUM    2
#define STRAT_BREAKOUT    3
#define STRAT_SESSION     4
#define STRAT_DIVERGENCE  5
#define STRAT_RANGE       6
#define STRAT_FRACTAL_HTF 7

#define STRATEGY_COUNT    8

//====================================================
// REGIMES
//====================================================
#define REGIME_UNKNOWN    0
#define REGIME_TREND_UP   1
#define REGIME_TREND_DOWN 2
#define REGIME_RANGE      3
#define REGIME_BREAKOUT   4
#define REGIME_HIGH_VOL   5

//====================================================
// GENERAL
//====================================================
input bool   InpEnableTrading          = false;
input bool   InpBacktestExecution      = true;

input double InpRiskPercent             = 0.25;
input int    InpMagic                   = 2035028;
input int    InpMaxOpenTrades           = 1;

input int    InpLookback                = 1500;
input int    InpOOSBars                 = 300;
input int    InpAuditHorizon            = 15;

//====================================================
// INDICATORS
//====================================================
input int    InpATRPeriod               = 14;
input int    InpADXPeriod               = 14;
input int    InpRSIPeriod               = 14;

input int    InpFastEMA                 = 8;
input int    InpSlowEMA                 = 21;
input int    InpTrendEMA                = 200;

//====================================================
// MARKET CONDITIONS
//====================================================
input double InpMinATRPoints            = 5.0;
input double InpMinADXTrend             = 22.0;
input double InpMaxADXRange             = 18.0;

//====================================================
// STRATEGY-AWARE SIGNAL QUALITY
//====================================================
input bool   InpUseStrategySpecificQuality = true;

input double InpTrendMinATRPoints       = 5.0;
input double InpRangeMinATRPoints       = 4.0;
input double InpBreakoutMinATRPoints    = 5.0;

input double InpTrendEMADistanceATR     = 0.025;
input double InpBreakoutEMADistanceATR  = 0.020;

input bool   InpRequireSecondConfirmation = false;

//====================================================
// EXECUTION
//====================================================
input double InpSL_ATR                  = 1.30;
input double InpTP_ATR                  = 2.60;

input double InpMaxSpreadPoints         = 30.0;
input double InpMinSpreadPoints         = 0.0;
input double InpMaxSpreadATR            = 0.35;

input int    InpSessionStartHour        = 7;
input int    InpSessionEndHour          = 20;

input int    InpCooldownBars            = 3;

//====================================================
// STRICT AUDIT
//====================================================
input int    InpMinTrainTrades          = 20;
input int    InpMinOOSTrades            = 8;
input double InpMinOOSExpectancy        = 0.02;
input double InpMinOOSPF                = 1.05;
input double InpMaxOOSDrawdown          = 8.0;

//====================================================
// RELAXED AUDIT
//====================================================
input bool   InpAllowRelaxedSelection   = true;

input int    InpRelaxedTrainTrades      = 15;
input int    InpRelaxedOOSTrades        = 5;
input double InpRelaxedOOSExpectancy    = 0.00;
input double InpRelaxedOOSPF            = 0.95;
input double InpRelaxedMaxOOSDrawdown   = 12.0;

//====================================================
// OPPORTUNITY RECOVERY
//====================================================
input bool   InpAllowOpportunityStrategy = true;
input bool   InpAllowOpportunityWithoutBest = true;

input int    InpOpportunityMinOOSTrades = 3;
input double InpOpportunityMinPF       = 0.85;
input double InpOpportunityMinExpectancy = -0.03;
input double InpOpportunityMaxDD       = 15.0;
input double InpOpportunityMinScore    = 0.000;

//====================================================
// FRIDAY
//====================================================
input bool   InpFridayClose             = true;
input int    InpFridayCloseHour         = 21;

//====================================================
// CSV
//====================================================
input bool   InpWriteCSV                = true;
input string InpCSVFile                 = "Bitey_v2.28_Decisions.csv";

//====================================================
// GLOBAL STATE
//====================================================
int      gBestStrategy       = -1;
int      gBestRegime         = REGIME_UNKNOWN;
int      gLastStrategy       = -1;
int      gLastDirection      = 0;
datetime gLastTradeTime      = 0;
datetime gLastBarTime        = 0;

bool     gAuditCompleted     = false;

double   gBestScore          = -999999.0;
double   gBestPF             = 0.0;
double   gBestExpectancy     = -999999.0;
double   gBestDD             = 999999.0;

int      gBestOOSTrades      = 0;
int      gBestTrainTrades    = 0;

//====================================================
// DIAGNOSTICS
//====================================================
long gBarsEvaluated          = 0;
long gNoBestStrategy         = 0;
long gNoSignal               = 0;
long gSignalQualityReject    = 0;
long gQualityATRReject       = 0;
long gQualityEMAReject       = 0;
long gQualityPriceReject     = 0;
long gSpreadReject           = 0;
long gSessionReject          = 0;
long gCooldownReject         = 0;
long gPositionReject         = 0;
long gOrderSendErrors        = 0;

long gOpportunitySelected    = 0;
long gPrimarySelected        = 0;
long gSecondarySelected      = 0;

long gRawSignalCount[STRATEGY_COUNT];
long gQualityRejectCount[STRATEGY_COUNT];
long gSelectedCount[STRATEGY_COUNT];

//====================================================
// STRUCTS
//====================================================
struct AuditStats
{
   int trades;
   int wins;
   int losses;

   double grossProfit;
   double grossLoss;
   double netProfit;

   double profitFactor;
   double expectancy;
   double maxDrawdown;

   int trainTrades;
   int oosTrades;
};

//====================================================
// UTILITY
//====================================================
double PipPoint()
{
   if(Digits == 3 || Digits == 5)
      return(Point * 10.0);

   return(Point);
}

//----------------------------------------------------
string StrategyName(int s)
{
   switch(s)
   {
      case STRAT_TREND:       return("TREND");
      case STRAT_MEANREV:     return("MEANREV");
      case STRAT_MOMENTUM:    return("MOMENTUM");
      case STRAT_BREAKOUT:    return("BREAKOUT");
      case STRAT_SESSION:     return("SESSION");
      case STRAT_DIVERGENCE:  return("DIVERGENCE");
      case STRAT_RANGE:       return("RANGE");
      case STRAT_FRACTAL_HTF: return("FRACTAL_HTF");
   }

   return("UNKNOWN");
}

//----------------------------------------------------
string RegimeName(int r)
{
   switch(r)
   {
      case REGIME_TREND_UP:   return("TREND_UP");
      case REGIME_TREND_DOWN: return("TREND_DOWN");
      case REGIME_RANGE:      return("RANGE");
      case REGIME_BREAKOUT:   return("BREAKOUT");
      case REGIME_HIGH_VOL:   return("HIGH_VOL");
   }

   return("UNKNOWN");
}

//----------------------------------------------------
bool IsNewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);

   if(t != gLastBarTime)
   {
      gLastBarTime = t;
      return(true);
   }

   return(false);
}

//----------------------------------------------------
bool EnoughBars()
{
   int required = InpSlowEMA + 20;

   if(InpTrendEMA + 20 > required)
      required = InpTrendEMA + 20;

   if(Bars < required)
      return(false);

   return(true);
}

//====================================================
// MARKET DATA
//====================================================
double ATR(int shift)
{
   return(iATR(Symbol(), Period(), InpATRPeriod, shift));
}

//----------------------------------------------------
double ADX(int shift)
{
   return(iADX(Symbol(), Period(), InpADXPeriod,
               PRICE_CLOSE, MODE_MAIN, shift));
}

//----------------------------------------------------
double RSI(int shift)
{
   return(iRSI(Symbol(), Period(), InpRSIPeriod,
               PRICE_CLOSE, shift));
}

//----------------------------------------------------
double EMA(int period, int shift)
{
   return(iMA(Symbol(), Period(), period, 0,
              MODE_EMA, PRICE_CLOSE, shift));
}

//----------------------------------------------------
double HighPrice(int shift)
{
   return(iHigh(Symbol(), Period(), shift));
}

//----------------------------------------------------
double LowPrice(int shift)
{
   return(iLow(Symbol(), Period(), shift));
}

//----------------------------------------------------
double ClosePrice(int shift)
{
   return(iClose(Symbol(), Period(), shift));
}

//====================================================
// REGIME
//====================================================
int RegimeAt(int s)
{
   double atr = ATR(s);

   if(atr <= 0.0)
      return(REGIME_UNKNOWN);

   double adx = ADX(s);
   double fast = EMA(InpFastEMA, s);
   double slow = EMA(InpSlowEMA, s);
   double trend = EMA(InpTrendEMA, s);
   double close = ClosePrice(s);

   double atrPoints = atr / Point;

   if(atrPoints < InpMinATRPoints)
      return(REGIME_UNKNOWN);

   if(atrPoints >= InpMinATRPoints * 2.5 && adx >= 28.0)
      return(REGIME_HIGH_VOL);

   if(adx >= InpMinADXTrend)
   {
      if(fast > slow && close > trend)
         return(REGIME_TREND_UP);

      if(fast < slow && close < trend)
         return(REGIME_TREND_DOWN);
   }

   // Breakout detection
   double previousHigh = HighPrice(s + 1);
   double previousLow  = LowPrice(s + 1);

   for(int i = s + 2; i <= s + 10; i++)
   {
      if(HighPrice(i) > previousHigh)
         previousHigh = HighPrice(i);

      if(LowPrice(i) < previousLow)
         previousLow = LowPrice(i);
   }

   if(close > previousHigh || close < previousLow)
      return(REGIME_BREAKOUT);

   if(adx <= InpMaxADXRange)
      return(REGIME_RANGE);

   if(fast > slow)
      return(REGIME_TREND_UP);

   if(fast < slow)
      return(REGIME_TREND_DOWN);

   return(REGIME_UNKNOWN);
}

//====================================================
// STRATEGY SIGNALS
// Returns:
//  1 BUY
// -1 SELL
//  0 NONE
//====================================================
int TrendSignal(int s)
{
   double fast  = EMA(InpFastEMA, s);
   double slow  = EMA(InpSlowEMA, s);
   double trend = EMA(InpTrendEMA, s);
   double close = ClosePrice(s);

   if(fast > slow && close > trend)
      return(1);

   if(fast < slow && close < trend)
      return(-1);

   return(0);
}

//----------------------------------------------------
int MeanReversionSignal(int s)
{
   double rsi = RSI(s);
   double close = ClosePrice(s);
   double fast = EMA(InpFastEMA, s);
   double atr = ATR(s);

   if(atr <= 0.0)
      return(0);

   if(rsi <= 28.0 && close < fast)
      return(1);

   if(rsi >= 72.0 && close > fast)
      return(-1);

   return(0);
}

//----------------------------------------------------
int MomentumSignal(int s)
{
   double rsi = RSI(s);
   double fast = EMA(InpFastEMA, s);
   double slow = EMA(InpSlowEMA, s);

   if(fast > slow && rsi >= 55.0 && rsi <= 72.0)
      return(1);

   if(fast < slow && rsi <= 45.0 && rsi >= 28.0)
      return(-1);

   return(0);
}

//----------------------------------------------------
int BreakoutSignal(int s)
{
   double close = ClosePrice(s);

   double highest = HighPrice(s + 1);
   double lowest  = LowPrice(s + 1);

   for(int i = s + 2; i <= s + 12; i++)
   {
      if(HighPrice(i) > highest)
         highest = HighPrice(i);

      if(LowPrice(i) < lowest)
         lowest = LowPrice(i);
   }

   if(close > highest)
      return(1);

   if(close < lowest)
      return(-1);

   return(0);
}

//----------------------------------------------------
int SessionSignal(int s)
{
   datetime t = iTime(Symbol(), Period(), s);

   int hour = TimeHour(t);

   if(hour < InpSessionStartHour ||
      hour > InpSessionEndHour)
      return(0);

   double open  = iOpen(Symbol(), Period(), s);
   double close = ClosePrice(s);

   double atr = ATR(s);

   if(atr <= 0.0)
      return(0);

   double body = close - open;

   if(body > atr * 0.20)
      return(1);

   if(body < -atr * 0.20)
      return(-1);

   return(0);
}

//----------------------------------------------------
int DivergenceSignal(int s)
{
   if(s + 8 >= Bars)
      return(0);

   double rsiNow = RSI(s);
   double rsiOld = RSI(s + 5);

   double lowNow = LowPrice(s);
   double lowOld = LowPrice(s + 5);

   double highNow = HighPrice(s);
   double highOld = HighPrice(s + 5);

   // Bullish divergence
   if(lowNow < lowOld && rsiNow > rsiOld && rsiNow < 45.0)
      return(1);

   // Bearish divergence
   if(highNow > highOld && rsiNow < rsiOld && rsiNow > 55.0)
      return(-1);

   return(0);
}

//----------------------------------------------------
int RangeSignal(int s)
{
   double rsi = RSI(s);

   if(rsi <= 30.0)
      return(1);

   if(rsi >= 70.0)
      return(-1);

   return(0);
}

//----------------------------------------------------
int FractalHTFSignal(int s)
{
   double fast = EMA(InpFastEMA, s);
   double slow = EMA(InpSlowEMA, s);

   double fast2 = EMA(InpFastEMA, s + 3);
   double slow2 = EMA(InpSlowEMA, s + 3);

   if(fast > slow && fast2 > slow2)
      return(1);

   if(fast < slow && fast2 < slow2)
      return(-1);

   return(0);
}

//----------------------------------------------------
int RawSignal(int strategy, int s)
{
   switch(strategy)
   {
      case STRAT_TREND:
         return(TrendSignal(s));

      case STRAT_MEANREV:
         return(MeanReversionSignal(s));

      case STRAT_MOMENTUM:
         return(MomentumSignal(s));

      case STRAT_BREAKOUT:
         return(BreakoutSignal(s));

      case STRAT_SESSION:
         return(SessionSignal(s));

      case STRAT_DIVERGENCE:
         return(DivergenceSignal(s));

      case STRAT_RANGE:
         return(RangeSignal(s));

      case STRAT_FRACTAL_HTF:
         return(FractalHTFSignal(s));
   }

   return(0);
}

//====================================================
// STRATEGY-AWARE QUALITY
//
// Return:
// 0 = OK
// 1 = ATR reject
// 2 = EMA distance reject
// 3 = price confirmation reject
//====================================================
int SignalQualityReason(int strategy, int direction, int s)
{
   double atr = ATR(s);

   if(atr <= 0.0)
      return(1);

   double atrPoints = atr / Point;

   //=================================================
   // RANGE / MEAN REVERSION FAMILY
   // These strategies intentionally trade against
   // short-term EMA direction.
   //=================================================
   if(strategy == STRAT_MEANREV ||
      strategy == STRAT_RANGE ||
      strategy == STRAT_DIVERGENCE ||
      strategy == STRAT_SESSION)
   {
      if(atrPoints < InpRangeMinATRPoints)
         return(1);

      return(0);
   }

   //=================================================
   // TREND FAMILY
   //=================================================
   double fast = EMA(InpFastEMA, s);
   double slow = EMA(InpSlowEMA, s);
   double close = ClosePrice(s);

   double distance = MathAbs(fast - slow) / atr;

   double requiredDistance = InpTrendEMADistanceATR;

   if(strategy == STRAT_BREAKOUT)
      requiredDistance = InpBreakoutEMADistanceATR;

   if(atrPoints < InpTrendMinATRPoints)
      return(1);

   if(distance < requiredDistance)
      return(2);

   // Trend price confirmation
   if(strategy == STRAT_TREND ||
      strategy == STRAT_MOMENTUM ||
      strategy == STRAT_BREAKOUT ||
      strategy == STRAT_FRACTAL_HTF)
   {
      if(direction > 0 && close < fast)
         return(3);

      if(direction < 0 && close > fast)
         return(3);
   }

   return(0);
}

//----------------------------------------------------
bool SignalQualityOK(int strategy, int direction, int s)
{
   int reason = SignalQualityReason(strategy, direction, s);

   if(reason == 0)
      return(true);

   gSignalQualityReject++;
   gQualityRejectCount[strategy]++;

   if(reason == 1)
      gQualityATRReject++;

   if(reason == 2)
      gQualityEMAReject++;

   if(reason == 3)
      gQualityPriceReject++;

   return(false);
}

//====================================================
// AUDIT SIMULATION
//====================================================
double SimTrade(int strategy, int direction, int s)
{
   double atr = ATR(s);

   if(atr <= 0.0)
      return(0.0);

   double entry = ClosePrice(s);

   double slDistance = atr * InpSL_ATR;
   double tpDistance = atr * InpTP_ATR;

   double sl = 0.0;
   double tp = 0.0;

   if(direction > 0)
   {
      sl = entry - slDistance;
      tp = entry + tpDistance;
   }
   else
   {
      sl = entry + slDistance;
      tp = entry - tpDistance;
   }

   int endBar = s - InpAuditHorizon;

   if(endBar < 1)
      endBar = 1;

   for(int i = s - 1; i >= endBar; i--)
   {
      double hi = HighPrice(i);
      double lo = LowPrice(i);

      if(direction > 0)
      {
         // Conservative: SL first
         if(lo <= sl)
            return(-InpRiskPercent);

         if(hi >= tp)
            return(InpRiskPercent * InpTP_ATR / InpSL_ATR);
      }
      else
      {
         if(hi >= sl)
            return(-InpRiskPercent);

         if(lo <= tp)
            return(InpRiskPercent * InpTP_ATR / InpSL_ATR);
      }
   }

   double finalClose = ClosePrice(endBar);

   if(direction > 0)
      return((finalClose - entry) / slDistance * InpRiskPercent);

   return((entry - finalClose) / slDistance * InpRiskPercent);
}

//----------------------------------------------------
void ResetStats(AuditStats &st)
{
   st.trades = 0;
   st.wins = 0;
   st.losses = 0;

   st.grossProfit = 0.0;
   st.grossLoss = 0.0;
   st.netProfit = 0.0;

   st.profitFactor = 0.0;
   st.expectancy = 0.0;
   st.maxDrawdown = 0.0;

   st.trainTrades = 0;
   st.oosTrades = 0;
}

//----------------------------------------------------
void AddResult(AuditStats &st, double result)
{
   st.trades++;
   st.netProfit += result;

   if(result > 0.0)
   {
      st.wins++;
      st.grossProfit += result;
   }
   else if(result < 0.0)
   {
      st.losses++;
      st.grossLoss += MathAbs(result);
   }
}

//----------------------------------------------------
void FinishStats(AuditStats &st)
{
   if(st.grossLoss > 0.0)
      st.profitFactor = st.grossProfit / st.grossLoss;
   else if(st.grossProfit > 0.0)
      st.profitFactor = 999.0;
   else
      st.profitFactor = 0.0;

   if(st.trades > 0)
      st.expectancy = st.netProfit / st.trades;
   else
      st.expectancy = 0.0;
}

//----------------------------------------------------
void AuditStrategy(int strategy, AuditStats &train, AuditStats &oos)
{
   ResetStats(train);
   ResetStats(oos);

   int available = Bars - InpTrendEMA - InpAuditHorizon - 20;

   if(available <= 50)
      return;

   int lookback = InpLookback;

   if(lookback > available)
      lookback = available;

   int oosStart = InpOOSBars;

   if(oosStart >= lookback)
      oosStart = lookback / 3;

   // Historical series:
   // larger shift = older bar
   for(int s = lookback; s >= InpAuditHorizon + 2; s--)
   {
      int signal = RawSignal(strategy, s);

      if(signal == 0)
         continue;

      double result = SimTrade(strategy, signal, s);

      if(s <= oosStart)
      {
         AddResult(oos, result);
      }
      else
      {
         AddResult(train, result);
      }
   }

   train.trainTrades = train.trades;
   oos.oosTrades = oos.trades;

   FinishStats(train);
   FinishStats(oos);
}

//====================================================
// ELIGIBILITY
//====================================================
bool EligibleStrict(AuditStats &train, AuditStats &oos)
{
   if(train.trades < InpMinTrainTrades)
      return(false);

   if(oos.trades < InpMinOOSTrades)
      return(false);

   if(oos.expectancy < InpMinOOSExpectancy)
      return(false);

   if(oos.profitFactor < InpMinOOSPF)
      return(false);

   if(oos.maxDrawdown > InpMaxOOSDrawdown)
      return(false);

   return(true);
}

//----------------------------------------------------
bool EligibleRelaxed(AuditStats &train, AuditStats &oos)
{
   if(!InpAllowRelaxedSelection)
      return(false);

   if(train.trades < InpRelaxedTrainTrades)
      return(false);

   if(oos.trades < InpRelaxedOOSTrades)
      return(false);

   if(oos.expectancy < InpRelaxedOOSExpectancy)
      return(false);

   if(oos.profitFactor < InpRelaxedOOSPF)
      return(false);

   if(oos.maxDrawdown > InpRelaxedMaxOOSDrawdown)
      return(false);

   return(true);
}

//----------------------------------------------------
bool EligibleOpportunity(AuditStats &train, AuditStats &oos)
{
   if(!InpAllowOpportunityStrategy)
      return(false);

   if(oos.trades < InpOpportunityMinOOSTrades)
      return(false);

   if(oos.profitFactor < InpOpportunityMinPF)
      return(false);

   if(oos.expectancy < InpOpportunityMinExpectancy)
      return(false);

   if(oos.maxDrawdown > InpOpportunityMaxDD)
      return(false);

   return(true);
}

//====================================================
// OPPORTUNITY SCORE
//====================================================
double OpportunityScore(AuditStats &train, AuditStats &oos)
{
   double score = 0.0;

   score += MathMin(oos.profitFactor, 3.0) * 0.020;
   score += MathMax(oos.expectancy, -0.10) * 0.50;

   score += MathMin((double)oos.trades, 30.0) * 0.0005;

   score -= MathMin(oos.maxDrawdown, 20.0) * 0.0005;

   return(score);
}

//====================================================
// AUDIT ALL
//====================================================
void AuditAll()
{
   gBestStrategy = -1;
   gBestScore = -999999.0;
   gBestPF = 0.0;
   gBestExpectancy = -999999.0;
   gBestDD = 999999.0;

   gBestOOSTrades = 0;
   gBestTrainTrades = 0;

   double strictScore[STRATEGY_COUNT];
   double relaxedScore[STRATEGY_COUNT];
   double opportunityScore[STRATEGY_COUNT];

   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      strictScore[i] = -999999.0;
      relaxedScore[i] = -999999.0;
      opportunityScore[i] = -999999.0;

      AuditStats train;
      AuditStats oos;

      AuditStrategy(i, train, oos);

      if(EligibleStrict(train, oos))
         strictScore[i] = OpportunityScore(train, oos);

      if(EligibleRelaxed(train, oos))
         relaxedScore[i] = OpportunityScore(train, oos);

      if(EligibleOpportunity(train, oos))
         opportunityScore[i] = OpportunityScore(train, oos);

      Print(
         "B28 AUDIT ",
         StrategyName(i),
         " TRAIN=", train.trades,
         " OOS=", oos.trades,
         " PF=", DoubleToString(oos.profitFactor, 3),
         " EXP=", DoubleToString(oos.expectancy, 4),
         " NET=", DoubleToString(oos.netProfit, 4),
         " SCORE=", DoubleToString(OpportunityScore(train, oos), 5)
      );

      // Strict
      if(strictScore[i] > gBestScore)
      {
         gBestStrategy = i;
         gBestScore = strictScore[i];

         gBestPF = oos.profitFactor;
         gBestExpectancy = oos.expectancy;
         gBestDD = oos.maxDrawdown;

         gBestOOSTrades = oos.trades;
         gBestTrainTrades = train.trades;
      }
   }

   // If strict failed, try relaxed.
   if(gBestStrategy < 0)
   {
      for(int i = 0; i < STRATEGY_COUNT; i++)
      {
         if(relaxedScore[i] > gBestScore)
         {
            AuditStats train;
            AuditStats oos;

            AuditStrategy(i, train, oos);

            gBestStrategy = i;
            gBestScore = relaxedScore[i];

            gBestPF = oos.profitFactor;
            gBestExpectancy = oos.expectancy;
            gBestDD = oos.maxDrawdown;

            gBestOOSTrades = oos.trades;
            gBestTrainTrades = train.trades;
         }
      }
   }

   if(gBestStrategy >= 0)
   {
      gBestRegime = RegimeAt(1);

      Print(
         "B28 BEST STRATEGY=",
         StrategyName(gBestStrategy),
         " PF=",
         DoubleToString(gBestPF, 3),
         " EXP=",
         DoubleToString(gBestExpectancy, 4),
         " OOS=",
         gBestOOSTrades,
         " TRAIN=",
         gBestTrainTrades
      );
   }
   else
   {
      Print("B28 NO STRICT/RELAXED BEST STRATEGY");
   }

   gAuditCompleted = true;
}

//====================================================
// FIND OPPORTUNITY
//====================================================
int FindOpportunity(int &direction, int s)
{
   direction = 0;

   double bestScore = -999999.0;
   int selected = -1;
   int selectedDirection = 0;

   for(int strategy = 0; strategy < STRATEGY_COUNT; strategy++)
   {
      AuditStats train;
      AuditStats oos;

      AuditStrategy(strategy, train, oos);

      if(!EligibleOpportunity(train, oos))
         continue;

      int signal = RawSignal(strategy, s);

      if(signal == 0)
         continue;

      gRawSignalCount[strategy]++;

      if(!SignalQualityOK(strategy, signal, s))
         continue;

      double score = OpportunityScore(train, oos);

      if(score < InpOpportunityMinScore)
         continue;

      if(score > bestScore)
      {
         bestScore = score;
         selected = strategy;
         selectedDirection = signal;
      }
   }

   if(selected >= 0)
   {
      direction = selectedDirection;
      return(selected);
   }

   return(-1);
}

//====================================================
// BEST SIGNAL
//====================================================
int BestSignal(int &direction, int s)
{
   direction = 0;

   gLastStrategy = -1;
   gLastDirection = 0;

   //=================================================
   // Primary strategy
   //=================================================
   if(gBestStrategy >= 0)
   {
      int signal = RawSignal(gBestStrategy, s);

      if(signal != 0)
      {
         gRawSignalCount[gBestStrategy]++;

         if(SignalQualityOK(gBestStrategy, signal, s))
         {
            direction = signal;

            gLastStrategy = gBestStrategy;
            gLastDirection = direction;

            gPrimarySelected++;
            gSelectedCount[gBestStrategy]++;

            return(gBestStrategy);
         }
      }
   }

   //=================================================
   // Secondary strategies
   //=================================================
   double bestScore = -999999.0;
   int selected = -1;
   int selectedDirection = 0;

   for(int strategy = 0; strategy < STRATEGY_COUNT; strategy++)
   {
      if(strategy == gBestStrategy)
         continue;

      AuditStats train;
      AuditStats oos;

      AuditStrategy(strategy, train, oos);

      bool eligible =
         EligibleStrict(train, oos) ||
         EligibleRelaxed(train, oos);

      if(!eligible)
         continue;

      int signal = RawSignal(strategy, s);

      if(signal == 0)
         continue;

      gRawSignalCount[strategy]++;

      if(!SignalQualityOK(strategy, signal, s))
         continue;

      double score = OpportunityScore(train, oos);

      if(score > bestScore)
      {
         bestScore = score;
         selected = strategy;
         selectedDirection = signal;
      }
   }

   if(selected >= 0)
   {
      direction = selectedDirection;

      gLastStrategy = selected;
      gLastDirection = direction;

      gSecondarySelected++;
      gSelectedCount[selected]++;

      return(selected);
   }

   //=================================================
   // Opportunity recovery
   //=================================================
   if(InpAllowOpportunityWithoutBest)
   {
      int oppDirection = 0;

      int oppStrategy = FindOpportunity(oppDirection, s);

      if(oppStrategy >= 0)
      {
         direction = oppDirection;

         gLastStrategy = oppStrategy;
         gLastDirection = direction;

         gOpportunitySelected++;
         gSelectedCount[oppStrategy]++;

         return(oppStrategy);
      }
   }

   return(-1);
}

//====================================================
// SPREAD
//====================================================
bool SpreadOK()
{
   double spreadPoints =
      (Ask - Bid) / Point;

   if(spreadPoints < InpMinSpreadPoints)
      return(false);

   if(spreadPoints > InpMaxSpreadPoints)
      return(false);

   double atr = ATR(1);

   if(atr <= 0.0)
      return(false);

   if((Ask - Bid) / atr > InpMaxSpreadATR)
      return(false);

   return(true);
}

//====================================================
// SESSION
//====================================================
bool SessionOK()
{
   datetime now = TimeCurrent();

   int hour = TimeHour(now);

   if(InpSessionStartHour <= InpSessionEndHour)
   {
      if(hour < InpSessionStartHour ||
         hour > InpSessionEndHour)
         return(false);
   }
   else
   {
      if(hour > InpSessionEndHour &&
         hour < InpSessionStartHour)
         return(false);
   }

   return(true);
}

//====================================================
// OPEN POSITIONS
//====================================================
int CountOpenTrades()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != InpMagic)
         continue;

      if(OrderType() == OP_BUY ||
         OrderType() == OP_SELL)
      {
         count++;
      }
   }

   return(count);
}

//====================================================
// COOLDOWN
//====================================================
bool CooldownOK()
{
   if(gLastTradeTime <= 0)
      return(true);

   int shift = iBarShift(Symbol(), Period(), gLastTradeTime, false);

   if(shift < 0)
      return(true);

   if(shift < InpCooldownBars)
      return(false);

   return(true);
}

//====================================================
// LOT SIZE
//====================================================
double CalculateLots(double stopDistance)
{
   if(stopDistance <= 0.0)
      return(0.0);

   double riskMoney =
      AccountBalance() * InpRiskPercent / 100.0;

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickValue <= 0.0 || tickSize <= 0.0)
      return(0.0);

   double lossPerLot =
      (stopDistance / tickSize) * tickValue;

   if(lossPerLot <= 0.0)
      return(0.0);

   double lots = riskMoney / lossPerLot;

   double minLot =
      MarketInfo(Symbol(), MODE_MINLOT);

   double maxLot =
      MarketInfo(Symbol(), MODE_MAXLOT);

   double lotStep =
      MarketInfo(Symbol(), MODE_LOTSTEP);

   if(lotStep <= 0.0)
      lotStep = 0.01;

   lots =
      MathFloor(lots / lotStep) * lotStep;

   if(lots < minLot)
      lots = minLot;

   if(lots > maxLot)
      lots = maxLot;

   return(NormalizeDouble(lots, 2));
}

//====================================================
// STOP DISTANCE
//====================================================
double MinimumStopDistance()
{
   double stopLevel =
      MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;

   double spread = Ask - Bid;

   double minimum =
      MathMax(stopLevel, spread * 2.0);

   return(minimum);
}

//====================================================
// EXECUTION
//====================================================
bool ExecuteTrade(int strategy, int direction)
{
   if(strategy < 0 || direction == 0)
      return(false);

   if(CountOpenTrades() >= InpMaxOpenTrades)
   {
      gPositionReject++;
      return(false);
   }

   if(!SessionOK())
   {
      gSessionReject++;
      return(false);
   }

   if(!SpreadOK())
   {
      gSpreadReject++;
      return(false);
   }

   if(!CooldownOK())
   {
      gCooldownReject++;
      return(false);
   }

   double atr = ATR(1);

   if(atr <= 0.0)
      return(false);

   double slDistance = atr * InpSL_ATR;
   double tpDistance = atr * InpTP_ATR;

   double minStop = MinimumStopDistance();

   if(slDistance < minStop)
      slDistance = minStop;

   if(tpDistance < minStop)
      tpDistance = minStop;

   double lots = CalculateLots(slDistance);

   if(lots <= 0.0)
      return(false);

   RefreshRates();

   int ticket = -1;

   double price = 0.0;
   double sl = 0.0;
   double tp = 0.0;

   color arrowColor = clrNONE;

   if(direction > 0)
   {
      price = Ask;

      sl = price - slDistance;
      tp = price + tpDistance;

      arrowColor = clrBlue;

      sl = NormalizeDouble(sl, Digits);
      tp = NormalizeDouble(tp, Digits);

      ticket = OrderSend(
         Symbol(),
         OP_BUY,
         lots,
         price,
         3,
         sl,
         tp,
         "B28|" + StrategyName(strategy),
         InpMagic,
         0,
         arrowColor
      );
   }
   else
   {
      price = Bid;

      sl = price + slDistance;
      tp = price - tpDistance;

      arrowColor = clrRed;

      sl = NormalizeDouble(sl, Digits);
      tp = NormalizeDouble(tp, Digits);

      ticket = OrderSend(
         Symbol(),
         OP_SELL,
         lots,
         price,
         3,
         sl,
         tp,
         "B28|" + StrategyName(strategy),
         InpMagic,
         0,
         arrowColor
      );
   }

   if(ticket < 0)
   {
      int err = GetLastError();

      gOrderSendErrors++;

      Print(
         "B28 ORDER ERROR strategy=",
         StrategyName(strategy),
         " direction=",
         direction,
         " error=",
         err
      );

      ResetLastError();

      return(false);
   }

   gLastTradeTime = TimeCurrent();

   Print(
      "B28 TRADE OPENED ticket=",
      ticket,
      " strategy=",
      StrategyName(strategy),
      " direction=",
      direction,
      " lots=",
      DoubleToString(lots, 2),
      " SL=",
      DoubleToString(sl, Digits),
      " TP=",
      DoubleToString(tp, Digits)
   );

   return(true);
}

//====================================================
// FRIDAY CLOSE
//====================================================
void FridayClose()
{
   if(!InpFridayClose)
      return;

   datetime now = TimeCurrent();

   if(TimeDayOfWeek(now) != 5)
      return;

   if(TimeHour(now) < InpFridayCloseHour)
      return;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() != InpMagic)
         continue;

      if(OrderType() == OP_BUY)
      {
         RefreshRates();

         OrderClose(
            OrderTicket(),
            OrderLots(),
            Bid,
            3,
            clrNONE
         );
      }

      if(OrderType() == OP_SELL)
      {
         RefreshRates();

         OrderClose(
            OrderTicket(),
            OrderLots(),
            Ask,
            3,
            clrNONE
         );
      }
   }
}

//====================================================
// CSV
//====================================================
void WriteDecision(
   string status,
   int strategy,
   int direction
)
{
   if(!InpWriteCSV)
      return;

   int handle = FileOpen(
      InpCSVFile,
      FILE_CSV | FILE_READ | FILE_WRITE,
      ';'
   );

   if(handle == INVALID_HANDLE)
      return;

   FileSeek(handle, 0, SEEK_END);

   FileWrite(
      handle,
      TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
      Symbol(),
      Period(),
      status,
      strategy,
      StrategyName(strategy),
      direction,
      RegimeName(gBestRegime),
      DoubleToString(ATR(1) / Point, 2),
      DoubleToString(ADX(1), 2),
      DoubleToString(RSI(1), 2),
      DoubleToString(Ask - Bid, Digits)
   );

   FileClose(handle);
}

//====================================================
// DIAGNOSTICS
//====================================================
void PrintDiagnostics()
{
   Print("==============================================");
   Print("B28 FINAL DIAGNOSTICS");
   Print("==============================================");

   Print("BarsEvaluated=", gBarsEvaluated);
   Print("NoBestStrategy=", gNoBestStrategy);
   Print("NoSignal=", gNoSignal);

   Print("SignalQualityReject=", gSignalQualityReject);
   Print("QualityATRReject=", gQualityATRReject);
   Print("QualityEMAReject=", gQualityEMAReject);
   Print("QualityPriceReject=", gQualityPriceReject);

   Print("SpreadReject=", gSpreadReject);
   Print("SessionReject=", gSessionReject);
   Print("CooldownReject=", gCooldownReject);
   Print("PositionReject=", gPositionReject);
   Print("OrderSendErrors=", gOrderSendErrors);

   Print("PrimarySelected=", gPrimarySelected);
   Print("SecondarySelected=", gSecondarySelected);
   Print("OpportunitySelected=", gOpportunitySelected);

   Print("----------------------------------------------");

   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      Print(
         "STRATEGY ",
         StrategyName(i),
         " RAW=",
         gRawSignalCount[i],
         " QUALITY_REJECT=",
         gQualityRejectCount[i],
         " SELECTED=",
         gSelectedCount[i]
      );
   }

   Print("----------------------------------------------");

   if(gBestStrategy >= 0)
   {
      Print(
         "BEST=",
         StrategyName(gBestStrategy),
         " PF=",
         DoubleToString(gBestPF, 3),
         " EXP=",
         DoubleToString(gBestExpectancy, 4),
         " OOS=",
         gBestOOSTrades,
         " TRAIN=",
         gBestTrainTrades
      );
   }
   else
   {
      Print("BEST=NONE");
   }

   Print("==============================================");
}

//====================================================
// INIT
//====================================================
int OnInit()
{
   ArrayInitialize(gRawSignalCount, 0);
   ArrayInitialize(gQualityRejectCount, 0);
   ArrayInitialize(gSelectedCount, 0);

   gLastBarTime = 0;
   gLastTradeTime = 0;

   gBestStrategy = -1;
   gLastStrategy = -1;

   Print("==============================================");
   Print("Bitey IA v2.28 initialized");
   Print("Symbol=", Symbol());
   Print("Period=", Period());
   Print("Risk=", DoubleToString(InpRiskPercent, 2), "%");
   Print("Magic=", InpMagic);
   Print("Strategy-aware quality=TRUE");
   Print("Opportunity recovery=TRUE");
   Print("==============================================");

   return(INIT_SUCCEEDED);
}

//====================================================
// DEINIT
//====================================================
void OnDeinit(const int reason)
{
   PrintDiagnostics();
}

//====================================================
// MAIN
//====================================================
void OnTick()
{
   if(!EnoughBars())
      return;

   FridayClose();

   if(!IsNewBar())
      return;

   gBarsEvaluated++;

   // Re-audit periodically / at beginning
   if(!gAuditCompleted)
      AuditAll();

   int direction = 0;

   int strategy = BestSignal(direction, 1);

   if(strategy < 0)
   {
      if(gBestStrategy < 0)
         gNoBestStrategy++;

      gNoSignal++;

      WriteDecision("HOLD", -1, 0);

      return;
   }

   if(direction == 0)
   {
      gNoSignal++;

      WriteDecision("HOLD", strategy, 0);

      return;
   }

   WriteDecision("SIGNAL", strategy, direction);

   // In tester, execute automatically.
   bool shouldExecute =
      InpEnableTrading ||
      (IsTesting() && InpBacktestExecution);

   if(!shouldExecute)
      return;

   ExecuteTrade(strategy, direction);
}
//+------------------------------------------------------------------+