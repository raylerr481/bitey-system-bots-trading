//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.54_TradeAttribution.mq4                       |
//| Bitey IA - Adaptive 8-Strategy Ensemble EA                      |
//| v2.54 - Directional evidence, recovery gate and exact trade attribution  |
//+------------------------------------------------------------------+
#property strict
#property version   "2.54"
#property description "Adaptive 8-strategy AI-style Expert Advisor with directional evidence, recovery control and exact trade attribution"

//==================================================================
// ENUMS
//==================================================================
enum AI_MODE
{
   AI_LOCAL_ONLY = 0,
   AI_LOCAL_PLUS_WEB = 1,
   AI_WEB_PRIMARY = 2
};

enum TEST_MODE
{
   MODE_CALIBRATION = 0,
   MODE_VALIDATION  = 1
};

enum REGIME
{
   REGIME_TREND = 0,
   REGIME_RANGE,
   REGIME_BREAKOUT,
   REGIME_UNKNOWN
};

enum STRATEGY_ID
{
   ST_TREND = 0,
   ST_MEAN_REVERSION,
   ST_MOMENTUM,
   ST_VOLATILITY_BREAKOUT,
   ST_SESSION_BIAS,
   ST_DIVERGENCE,
   ST_STRICT_RANGE,
   ST_FRACTAL_HTF,
   ST_COUNT
};

//==================================================================
// INPUTS
//==================================================================
//--- Trading / execution
input AI_MODE InpAIMode                    = AI_LOCAL_ONLY;
input TEST_MODE InpTestMode                = MODE_CALIBRATION;
input bool InpEnableTrading                = false;
input bool InpBacktestExecution            = true;
input bool InpTesterBypassSpreadMinimum    = true;
input bool InpTesterBypassSessionGate      = false;
input bool InpAutoStrategy                 = true;
input double InpRiskPercent                = 0.25;
input double InpMaxDailyLossPercent        = 3.0;
input int InpMaxOpenTrades                 = 1;
input int InpMagic                         = 2036002;

//--- Indicators
input int InpATRPeriod                     = 14;
input int InpADXPeriod                     = 14;
input int InpRSIPeriod                     = 14;
input int InpFastEMA                       = 8;
input int InpSlowEMA                       = 21;
input int InpTrendEMA                      = 200;
input int InpLookback                      = 1500;

//--- Execution geometry
input double InpSL_ATR                     = 1.30;
input double InpTP_ATR                     = 2.60;
input int InpSlippage                      = 5;

//--- Regime
input double InpMinADXTrend                = 22.0;
input double InpMaxADXRange                = 18.0;
input double InpMinATRPoints               = 5.0;

//--- Spread
input double InpMinSpreadPoints            = 8.0;
input double InpMaxSpreadPoints            = 50.0;
input bool InpUseSpreadATRFilter           = false;
input bool InpUseSyntheticSpreadGate       = true;
input double InpSyntheticSpreadPoints      = 10.0;
input double InpMaxSpreadATR               = 0.20;

//--- Evidence / audit
input double InpMinConfidence              = 0.47;
input double InpMinEvidenceScore           = 0.45;
input int InpMinEvidenceTrades             = 12;
input double InpRegimeEvidenceWeight       = 0.70;
input int InpMinRegimeEvidenceTrades       = 8;
input double InpMaxAuditDrawdownPct        = 5.0;
input int InpMaxAuditConsecutiveLosses     = 8;

//--- Directional evidence
input bool InpUseDirectionalEvidence       = true;
input double InpDirectionalEvidenceWeight  = 0.25;
input int InpMinDirectionalTrades          = 8;
input double InpMinDirectionalEvidence     = 0.35;

//--- Selection
input bool InpUseEnsemble                  = true;
input int InpMinConsensusVotes             = 1;
input double InpShortConfidenceExtra       = 0.02;
input bool InpEvidenceCalibrationFallback  = true;
input double InpEvidenceFallbackMinScore   = 0.00;

//--- Adaptive entry
input bool InpAdaptiveEntry                = true;
input bool InpAdaptiveDirectionalScore     = true;
input double InpSellScoreThreshold         = 0.54;
input double InpBuyScoreThreshold           = 0.47;
input double InpAdaptiveMinConfidence      = 0.47;
input double InpAdaptiveStrongConfidence   = 0.70;
input double InpAdaptivePullbackATR        = 0.35;
input double InpAdaptiveBreakoutATR        = 0.20;
input bool InpAdaptiveRequireCandleConfirmation = false;
input bool InpRequireCandleBodyFilter      = false;
input double InpMinCandleBodyRatio         = 0.15;
input bool InpRequireRegimeCompatibility   = false;
input bool InpRequireRegimeDirection       = false;

//--- Live protection
input int InpCooldownBarsAfterLoss         = 3;
input int InpMaxConsecutiveLossesLive      = 3;
input bool InpEnableRecoveryOverride      = true;
input double InpRecoveryMinConfidence       = 0.54;
input int InpRecoveryMinVotes               = 3;
input double InpRecoveryScoreMargin         = 0.00;
input double InpRecoveryMinStrategyEvidence = 0.50;

//--- Session
input int InpSessionStartHour              = 7;
input int InpSessionEndHour                = 20;

//--- Audit refresh
input int InpAuditRefreshBars              = 20;
input int InpMinAuditTrades               = 10;
input int InpAuditHorizon                  = 15;

//--- Diagnostics / reports
input bool InpPrintAuditTable              = true;
input bool InpDecisionAuditEnabled         = true;
input int InpDecisionAuditMaxRows          = 5000;
input bool InpAutoReport                   = true;
input string InpReportPrefix               = "Bitey_v2.54";
input bool InpExportCSV                    = true;
input bool InpUseLiveTradeLearning          = true;
input int InpLiveLearningMinTrades          = 3;
input double InpLiveLearningPenalty         = 0.85;
input double InpLiveLearningBoost           = 1.05;

//--- Optional integrations: intentionally not required for tester
input bool InpUseSBTReport                 = false;
input string InpSBTEndpoint                = "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";
input bool InpUseWebAI                     = false;
input string InpWebAIEndpoint              = "https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze";

//==================================================================
// STRUCTS
//==================================================================
struct StrategyAudit
{
   int trades;
   int wins;
   int losses;
   int buys;
   int sells;
   double grossProfit;
   double grossLoss;
   double equity;
   double peak;
   double maxDD;
   int currentLossStreak;
   int maxLossStreak;
   double score;
   double buyScore;
   double sellScore;
};

struct DecisionSnapshot
{
   datetime time;
   int shift;
   int direction;
   int regime;
   int selectedStrategy;
   int buyVotes;
   int sellVotes;
   double confidence;
   double evidence;
   double buyEvidence;
   double sellEvidence;
   double directional;
   double adx;
   double atrPoints;
   double rsi;
   double emaGapATR;
   double momentumATR;
   double bodyRatio;
   double spreadPoints;
   double buyScore;
   double sellScore;
   bool adaptiveOK;
   bool riskOK;
};

//==================================================================
// GLOBALS
//==================================================================
StrategyAudit g_audit[ST_COUNT];
StrategyAudit g_dirAudit[2];
StrategyAudit g_strategyDirAudit[ST_COUNT][2];

datetime g_lastBarTime = 0;
datetime g_lastAuditBar = 0;
datetime g_lastLossTradeTime = 0;
int g_barsSinceAudit = 0;
bool g_initialized = false;
bool g_lastTradeWasLoss = false;
int g_liveLossStreak = 0;

int g_entriesAccepted = 0;
int g_entriesRejected = 0;
int g_blockedCooldown = 0;
int g_blockedLossStreak = 0;
int g_blockedSpread = 0;
int g_blockedSession = 0;
int g_blockedDailyLoss = 0;
int g_blockedOpenTrades = 0;
int g_blockedConfidence = 0;
int g_blockedStrategy = 0;
int g_blockedAdaptive = 0;
int g_orderSendFailed = 0;
int g_recoveryOverrides = 0;
bool g_recoveryUsedSinceLoss = false;

DecisionSnapshot g_lastDecision;

struct DecisionRecord
{
   datetime time;
   int direction;
   int regime;
   int strategy;
   int buyVotes;
   int sellVotes;
   double confidence;
   double buyScore;
   double sellScore;
   double adx;
   double atrPoints;
   double rsi;
   double emaGapATR;
   double momentumATR;
   double bodyRatio;
   double spreadPoints;
   bool adaptiveOK;
   bool riskOK;
   string decision;
};
DecisionRecord g_decisions[];
int g_decisionCount=0;
int g_rawBuySignals=0;
int g_rawSellSignals=0;
int g_noSignal=0;

// Exact attribution of real tester/live trades to the decision that opened them.
struct TradeAttribution
{
   int ticket;
   datetime openTime;
   int direction;
   int strategy;
   int regime;
   int buyVotes;
   int sellVotes;
   double confidence;
   double buyScore;
   double sellScore;
   double evidence;
   double adx;
   double atrPoints;
   double rsi;
   double emaGapATR;
   double momentumATR;
   double bodyRatio;
   double spreadPoints;
   double lot;
   double openPrice;
   double sl;
   double tp;
};
TradeAttribution g_tradeMap[];
int g_tradeMapCount=0;

string StrategyName(int id)
{
   switch(id)
   {
      case ST_TREND: return "TREND_FOLLOWING";
      case ST_MEAN_REVERSION: return "MEAN_REVERSION";
      case ST_MOMENTUM: return "MOMENTUM";
      case ST_VOLATILITY_BREAKOUT: return "VOLATILITY_BREAKOUT";
      case ST_SESSION_BIAS: return "SESSION_BIAS";
      case ST_DIVERGENCE: return "DIVERGENCE";
      case ST_STRICT_RANGE: return "STRICT_RANGE";
      case ST_FRACTAL_HTF: return "FRACTAL_HTF";
   }
   return "UNKNOWN";
}

string RegimeName(int r)
{
   if(r == REGIME_TREND) return "TREND";
   if(r == REGIME_RANGE) return "RANGE";
   if(r == REGIME_BREAKOUT) return "BREAKOUT";
   return "UNKNOWN";
}

//==================================================================
// BASIC UTILITIES
//==================================================================
bool NewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);
   if(t == 0) return false;
   if(t != g_lastBarTime)
   {
      g_lastBarTime = t;
      return true;
   }
   return false;
}

double ATR(int shift)
{
   return iATR(Symbol(), Period(), InpATRPeriod, shift);
}

double ADX(int shift)
{
   return iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MAIN, shift);
}

double RSI(int shift)
{
   return iRSI(Symbol(), Period(), InpRSIPeriod, PRICE_CLOSE, shift);
}

double EMA(int period, int shift)
{
   return iMA(Symbol(), Period(), period, 0, MODE_EMA, PRICE_CLOSE, shift);
}

double SafeDiv(double a, double b, double fallback = 0.0)
{
   if(MathAbs(b) < 1e-10) return fallback;
   return a / b;
}

double CandleBodyRatio(int shift)
{
   double range = High[shift] - Low[shift];
   if(range <= Point) return 0.0;
   return MathAbs(Close[shift] - Open[shift]) / range;
}

double MomentumATR(int shift)
{
   double a = ATR(shift);
   if(a <= 0.0) return 0.0;
   return SafeDiv(Close[shift] - Close[shift+3], a, 0.0);
}

double EmaGapATR(int shift)
{
   double a = ATR(shift);
   if(a <= 0.0) return 0.0;
   return SafeDiv(EMA(InpFastEMA, shift) - EMA(InpSlowEMA, shift), a, 0.0);
}

bool InSession()
{
   int h = TimeHour(TimeCurrent());
   if(InpSessionStartHour <= InpSessionEndHour)
      return (h >= InpSessionStartHour && h < InpSessionEndHour);
   return (h >= InpSessionStartHour || h < InpSessionEndHour);
}

double CurrentSpreadPoints()
{
   RefreshRates();
   return SafeDiv(Ask - Bid, Point, 0.0);
}

bool SpreadOK()
{
   double sp = CurrentSpreadPoints();
   bool bypassMin = (IsTesting() && InpBacktestExecution && InpTesterBypassSpreadMinimum);
   if((!bypassMin && sp < InpMinSpreadPoints) || sp > InpMaxSpreadPoints)
      return false;

   if(InpUseSpreadATRFilter)
   {
      double a = ATR(1);
      if(a > 0.0 && SafeDiv(sp * Point, a, 999.0) > InpMaxSpreadATR)
         return false;
   }
   return true;
}

int OpenTradeCount()
{
   int n = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      n++;
   }
   return n;
}

double TodayClosedProfit()
{
   datetime dayStart = StrToTime(TimeToString(TimeCurrent(), TIME_DATE));
   double p = 0.0;

   for(int i=OrdersHistoryTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol()) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderCloseTime() < dayStart) continue;
      p += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return p;
}

bool DailyLossOK()
{
   double bal = AccountBalance();
   if(bal <= 0.0) return false;
   double lossPct = -100.0 * TodayClosedProfit() / bal;
   if(lossPct <= 0.0) return true;
   return lossPct < InpMaxDailyLossPercent;
}

//==================================================================
// REGIME
//==================================================================
int DetectRegime(int shift)
{
   double adx = ADX(shift);
   double a = ATR(shift);
   if(a <= 0.0) return REGIME_UNKNOWN;

   double atrPoints = a / Point;
   double body = CandleBodyRatio(shift);
   double range = High[shift] - Low[shift];

   if(adx >= InpMinADXTrend)
      return REGIME_TREND;

   if(adx <= InpMaxADXRange)
      return REGIME_RANGE;

   if(atrPoints >= InpMinATRPoints && range > a * 1.25 && body >= 0.55)
      return REGIME_BREAKOUT;

   return REGIME_UNKNOWN;
}

//==================================================================
// 8 STRATEGY SIGNALS
// Returns +1 BUY, -1 SELL, 0 neutral
//==================================================================
int SignalTrend(int s)
{
   double f = EMA(InpFastEMA,s);
   double sl = EMA(InpSlowEMA,s);
   double tr = EMA(InpTrendEMA,s);

   if(f > sl && sl > tr && Close[s] > f) return 1;
   if(f < sl && sl < tr && Close[s] < f) return -1;
   return 0;
}

int SignalMeanReversion(int s)
{
   double r = RSI(s);
   double f = EMA(InpFastEMA,s);

   if(r <= 30.0 && Close[s] < f) return 1;
   if(r >= 70.0 && Close[s] > f) return -1;
   return 0;
}

int SignalMomentum(int s)
{
   double m = MomentumATR(s);
   double r = RSI(s);

   if(m > 0.35 && r > 52.0) return 1;
   if(m < -0.35 && r < 48.0) return -1;
   return 0;
}

int SignalVolatilityBreakout(int s)
{
   double a = ATR(s);
   if(a <= 0.0) return 0;

   double priorHigh = High[s+1];
   double priorLow  = Low[s+1];

   if(Close[s] > priorHigh && (High[s]-Low[s]) > a*0.90) return 1;
   if(Close[s] < priorLow  && (High[s]-Low[s]) > a*0.90) return -1;
   return 0;
}

int SignalSessionBias(int s)
{
   int h = TimeHour(Time[s]);
   if(h >= 7 && h < 13)
   {
      if(Close[s] > Open[s]) return 1;
      if(Close[s] < Open[s]) return -1;
   }
   if(h >= 13 && h < 20)
   {
      double f = EMA(InpFastEMA,s);
      if(Close[s] > f) return 1;
      if(Close[s] < f) return -1;
   }
   return 0;
}

int SignalDivergence(int s)
{
   double r0 = RSI(s);
   double r4 = RSI(s+4);

   if(Low[s] < Low[s+4] && r0 > r4 + 3.0) return 1;
   if(High[s] > High[s+4] && r0 < r4 - 3.0) return -1;
   return 0;
}

int SignalStrictRange(int s)
{
   double adx = ADX(s);
   if(adx > InpMaxADXRange) return 0;

   double r = RSI(s);
   if(r < 35.0) return 1;
   if(r > 65.0) return -1;
   return 0;
}

int SignalFractalHTF(int s)
{
   // Critical historical fix: map the tested bar to H4 and use
   // a fully closed H4 candle, avoiding future information leakage.
   int h4 = iBarShift(Symbol(), PERIOD_H4, Time[s], false);
   if(h4 < 0) return 0;
   h4++;

   double h = iHigh(Symbol(), PERIOD_H4, h4);
   double l = iLow(Symbol(), PERIOD_H4, h4);
   double c = iClose(Symbol(), PERIOD_H4, h4);
   if(h <= 0.0 || l <= 0.0 || c <= 0.0) return 0;

   double mid = (h+l)/2.0;
   if(c > mid && Close[s] > EMA(InpSlowEMA,s)) return 1;
   if(c < mid && Close[s] < EMA(InpSlowEMA,s)) return -1;
   return 0;
}

int GetSignal(int id, int s)
{
   switch(id)
   {
      case ST_TREND: return SignalTrend(s);
      case ST_MEAN_REVERSION: return SignalMeanReversion(s);
      case ST_MOMENTUM: return SignalMomentum(s);
      case ST_VOLATILITY_BREAKOUT: return SignalVolatilityBreakout(s);
      case ST_SESSION_BIAS: return SignalSessionBias(s);
      case ST_DIVERGENCE: return SignalDivergence(s);
      case ST_STRICT_RANGE: return SignalStrictRange(s);
      case ST_FRACTAL_HTF: return SignalFractalHTF(s);
   }
   return 0;
}

//==================================================================
// STRATEGY WEIGHT / COMPATIBILITY
//==================================================================
double StrategyWeight(int id, int regime)
{
   if(id == ST_TREND)
      return (regime == REGIME_TREND ? 1.20 : 0.80);

   if(id == ST_MEAN_REVERSION)
      return (regime == REGIME_RANGE ? 1.20 : 0.75);

   if(id == ST_MOMENTUM)
      return (regime == REGIME_TREND || regime == REGIME_BREAKOUT ? 1.15 : 0.80);

   if(id == ST_VOLATILITY_BREAKOUT)
      return (regime == REGIME_BREAKOUT ? 1.25 : 0.75);

   if(id == ST_SESSION_BIAS)
      return 1.00;

   if(id == ST_DIVERGENCE)
      return (regime == REGIME_RANGE ? 1.05 : 0.85);

   if(id == ST_STRICT_RANGE)
      return (regime == REGIME_RANGE ? 1.25 : 0.65);

   if(id == ST_FRACTAL_HTF)
      return (regime == REGIME_TREND ? 1.10 : 0.90);

   return 1.0;
}

//==================================================================
// AUDIT / HISTORICAL SIMULATION
//==================================================================
void ResetAudits()
{
   for(int i=0;i<ST_COUNT;i++)
   {
      g_audit[i].trades=0;
      g_audit[i].wins=0;
      g_audit[i].losses=0;
      g_audit[i].buys=0;
      g_audit[i].sells=0;
      g_audit[i].grossProfit=0;
      g_audit[i].grossLoss=0;
      g_audit[i].equity=0;
      g_audit[i].peak=0;
      g_audit[i].maxDD=0;
      g_audit[i].currentLossStreak=0;
      g_audit[i].maxLossStreak=0;
      g_audit[i].score=0;
      g_audit[i].buyScore=0;
      g_audit[i].sellScore=0;
   }

   for(int d=0;d<2;d++)
   {
      g_dirAudit[d].trades=0;
      g_dirAudit[d].wins=0;
      g_dirAudit[d].losses=0;
      g_dirAudit[d].buys=0;
      g_dirAudit[d].sells=0;
      g_dirAudit[d].grossProfit=0;
      g_dirAudit[d].grossLoss=0;
      g_dirAudit[d].equity=0;
      g_dirAudit[d].peak=0;
      g_dirAudit[d].maxDD=0;
      g_dirAudit[d].currentLossStreak=0;
      g_dirAudit[d].maxLossStreak=0;
      g_dirAudit[d].score=0;
      g_dirAudit[d].buyScore=0;
      g_dirAudit[d].sellScore=0;
   }

   for(int i=0;i<ST_COUNT;i++)
      for(int d=0;d<2;d++)
      {
         g_strategyDirAudit[i][d].trades=0;
         g_strategyDirAudit[i][d].wins=0;
         g_strategyDirAudit[i][d].losses=0;
         g_strategyDirAudit[i][d].buys=0;
         g_strategyDirAudit[i][d].sells=0;
         g_strategyDirAudit[i][d].grossProfit=0;
         g_strategyDirAudit[i][d].grossLoss=0;
         g_strategyDirAudit[i][d].equity=0;
         g_strategyDirAudit[i][d].peak=0;
         g_strategyDirAudit[i][d].maxDD=0;
         g_strategyDirAudit[i][d].currentLossStreak=0;
         g_strategyDirAudit[i][d].maxLossStreak=0;
         g_strategyDirAudit[i][d].score=0;
         g_strategyDirAudit[i][d].buyScore=0;
         g_strategyDirAudit[i][d].sellScore=0;
      }
}

void AuditTrade(StrategyAudit &a, int direction, double pnl)
{
   a.trades++;
   a.equity += pnl;

   if(direction > 0) a.buys++;
   if(direction < 0) a.sells++;

   if(pnl > 0.0)
   {
      a.wins++;
      a.grossProfit += pnl;
      a.currentLossStreak = 0;
   }
   else if(pnl < 0.0)
   {
      a.losses++;
      a.grossLoss += -pnl;
      a.currentLossStreak++;
      if(a.currentLossStreak > a.maxLossStreak)
         a.maxLossStreak = a.currentLossStreak;
   }

   if(a.equity > a.peak) a.peak = a.equity;
   double dd = a.peak - a.equity;
   if(dd > a.maxDD) a.maxDD = dd;

   double pf = (a.grossLoss > 0.0 ? a.grossProfit/a.grossLoss : 0.0);
   double wr = SafeDiv(a.wins, a.trades, 0.0);
   a.score = 0.55*wr + 0.45*MathMin(pf/2.0,1.0);
}

double SimulatedTradePnl(int direction, int entryShift, int horizon)
{
   double a = ATR(entryShift);
   if(a <= 0.0 || entryShift <= 1) return 0.0;

   double entry;
   double synthetic = (InpUseSyntheticSpreadGate ? InpSyntheticSpreadPoints*Point : 0.0);

   if(direction > 0)
      entry = Close[entryShift] + synthetic/2.0;
   else
      entry = Close[entryShift] - synthetic/2.0;

   double slDist = a*InpSL_ATR;
   double tpDist = a*InpTP_ATR;

   double sl = (direction > 0 ? entry-slDist : entry+slDist);
   double tp = (direction > 0 ? entry+tpDist : entry-tpDist);

   // MT4 series arrays: lower shift values are later bars.
   // Therefore the future of entryShift is entryShift-1 ... entryShift-horizon.
   int last = MathMax(1, entryShift-horizon);

   for(int k=entryShift-1; k>=last; k--)
   {
      if(direction > 0)
      {
         if(Low[k] <= sl) return sl-entry;
         if(High[k] >= tp) return tp-entry;
      }
      else
      {
         if(High[k] >= sl) return entry-sl;
         if(Low[k] <= tp) return entry-tp;
      }
   }

   if(last < 0 || last >= Bars) return 0.0;
   if(direction > 0) return Close[last]-entry;
   return entry-Close[last];
}

void AuditStrategy(int id)
{
   int safeLookback = MathMin(InpLookback, 600);
   int maxS = MathMin(Bars-1, safeLookback);
   for(int s=maxS; s>InpAuditHorizon+10; s--)
   {
      int sig = GetSignal(id,s);
      if(sig == 0) continue;

      int regime = DetectRegime(s);
      double pnl = SimulatedTradePnl(sig,s,InpAuditHorizon);
      AuditTrade(g_audit[id],sig,pnl);

      if(sig > 0)
      {
         AuditTrade(g_dirAudit[0],sig,pnl);
         AuditTrade(g_strategyDirAudit[id][0],sig,pnl);
      }
      else
      {
         AuditTrade(g_dirAudit[1],sig,pnl);
         AuditTrade(g_strategyDirAudit[id][1],sig,pnl);
      }
   }
}

void AuditAll()
{
   ResetAudits();

   for(int id=0;id<ST_COUNT;id++)
      AuditStrategy(id);

   if(InpPrintAuditTable)
   {
      Print("========== BITEY v2.54 AUDIT ==========");
      for(int j=0;j<ST_COUNT;j++)
      {
         Print(StrategyName(j),
               " trades=",g_audit[j].trades,
               " wins=",g_audit[j].wins,
               " losses=",g_audit[j].losses,
               " score=",DoubleToString(g_audit[j].score,3),
               " DD=",DoubleToString(g_audit[j].maxDD/Point,1)," pts");
      }
      Print("BUY trades=",g_dirAudit[0].trades,
            " score=",DoubleToString(g_dirAudit[0].score,3),
            " | SELL trades=",g_dirAudit[1].trades,
            " score=",DoubleToString(g_dirAudit[1].score,3));
      Print("=======================================");
   }
}

//==================================================================
// EVIDENCE
//==================================================================
double StrategyEvidence(int id, int direction)
{
   if(id < 0 || id >= ST_COUNT) return 0.0;
   int idx=(direction>0 ? 0 : 1);
   StrategyAudit a=g_strategyDirAudit[id][idx];

   if(a.trades < InpMinEvidenceTrades)
      return (InpTestMode == MODE_CALIBRATION && InpEvidenceCalibrationFallback
              ? InpEvidenceFallbackMinScore : 0.0);

   double wr=SafeDiv(a.wins,a.trades,0.0);
   double pf=(a.grossLoss>0.0 ? a.grossProfit/a.grossLoss : 0.0);
   double evidence=0.55*wr + 0.45*MathMin(pf/2.0,1.0);

   if(a.maxDD>0.0)
      evidence*=MathMax(0.0,1.0-SafeDiv(a.maxDD,InpMaxAuditDrawdownPct,0.0));

   return MathMax(0.0,MathMin(1.0,evidence));
}

double DirectionEvidence(int direction)
{
   int idx = (direction > 0 ? 0 : 1);
   StrategyAudit a = g_dirAudit[idx];

   if(a.trades < InpMinDirectionalTrades)
      return (InpTestMode == MODE_CALIBRATION ? 0.50 : 0.0);

   double wr = SafeDiv(a.wins,a.trades,0.0);
   double pf = (a.grossLoss > 0.0 ? a.grossProfit/a.grossLoss : 0.0);
   double e = 0.55*wr + 0.45*MathMin(pf/2.0,1.0);
   return MathMax(0.0,MathMin(1.0,e));
}

double BestStrategyEvidence(int direction, int regime, int &bestId, int &votes)
{
   double best = -1.0;
   bestId = -1;
   votes = 0;

   for(int id=0;id<ST_COUNT;id++)
   {
      int sig = GetSignal(id,1);
      if(sig != direction) continue;

      votes++;
      double e = StrategyEvidence(id,direction);
      double w = StrategyWeight(id,regime);
      double value = e*w;

      if(value > best)
      {
         best = value;
         bestId = id;
      }
   }

   if(best < 0.0) return 0.0;
   return MathMin(best,1.0);
}

//==================================================================
// LIVE TRADE LEARNING
//==================================================================
int StrategyIdFromComment(string comment)
{
   for(int id=0;id<ST_COUNT;id++)
   {
      string key=StrategyName(id);
      if(StringFind(comment,key,0)>=0) return id;
   }
   return -1;
}

double LiveStrategyWinRate(int strategy, int direction, int &count)
{
   count=0;
   int wins=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()<=0) continue;
      int od=(OrderType()==OP_BUY ? 1 : (OrderType()==OP_SELL ? -1 : 0));
      if(od!=direction) continue;
      if(StrategyIdFromComment(OrderComment())!=strategy) continue;
      double pnl=OrderProfit()+OrderSwap()+OrderCommission();
      count++;
      if(pnl>0.0) wins++;
   }
   return (count>0 ? (double)wins/count : 0.5);
}

double ApplyLiveLearning(int direction, int strategy, double score)
{
   if(!InpUseLiveTradeLearning || strategy<0) return score;
   int n=0;
   double wr=LiveStrategyWinRate(strategy,direction,n);
   if(n<InpLiveLearningMinTrades) return score;
   if(wr<0.34) score*=InpLiveLearningPenalty;
   else if(wr>=0.60) score*=InpLiveLearningBoost;
   return MathMax(0.0,MathMin(1.0,score));
}

//==================================================================
// LOCAL AI DECISION
//==================================================================
int LocalAISignal(double &confidence,
                  double &evidence,
                  double &buyEvidence,
                  double &sellEvidence,
                  int &selectedStrategy,
                  int &buyVotes,
                  int &sellVotes,
                  double &buyScore,
                  double &sellScore)
{
   confidence=0.0;
   evidence=0.0;
   buyEvidence=0.0;
   sellEvidence=0.0;
   selectedStrategy=-1;
   buyVotes=0;
   sellVotes=0;
   buyScore=0.0;
   sellScore=0.0;

   int regime = DetectRegime(1);

   for(int id=0;id<ST_COUNT;id++)
   {
      int sig = GetSignal(id,1);
      if(sig > 0) buyVotes++;
      if(sig < 0) sellVotes++;
   }

   int buyBest=-1, sellBest=-1;
   int tmpVotes=0;
   buyEvidence = BestStrategyEvidence(1,regime,buyBest,tmpVotes);
   sellEvidence = BestStrategyEvidence(-1,regime,sellBest,tmpVotes);

   double dirBuy = DirectionEvidence(1);
   double dirSell = DirectionEvidence(-1);

   buyScore = buyEvidence;
   sellScore = sellEvidence;

   if(InpUseDirectionalEvidence)
   {
      buyScore = (1.0-InpDirectionalEvidenceWeight)*buyScore
                 + InpDirectionalEvidenceWeight*dirBuy;
      sellScore = (1.0-InpDirectionalEvidenceWeight)*sellScore
                 + InpDirectionalEvidenceWeight*dirSell;
   }

   if(buyVotes < InpMinConsensusVotes) buyScore *= 0.90;
   if(sellVotes < InpMinConsensusVotes) sellScore *= 0.90;

   if(InpAutoStrategy)
   {
      if(buyBest>=0) buyScore=ApplyLiveLearning(1,buyBest,buyScore);
      if(sellBest>=0) sellScore=ApplyLiveLearning(-1,sellBest,sellScore);
   }

   int dir=0;
   if(buyScore >= InpBuyScoreThreshold && buyScore > sellScore)
      dir=1;
   else if(sellScore >= InpSellScoreThreshold && sellScore > buyScore)
      dir=-1;

   if(dir == 0)
      return 0;

   selectedStrategy = (dir > 0 ? buyBest : sellBest);
   evidence = (dir > 0 ? buyEvidence : sellEvidence);

   confidence = MathMax(buyScore,sellScore);

   if(dir < 0)
      confidence = MathMax(0.0,confidence-InpShortConfidenceExtra);

   return dir;
}

//==================================================================
// ADAPTIVE ENTRY
//==================================================================
bool AdaptiveEntryAllowed(int direction, double confidence, string &reason)
{
   reason = "";

   if(!InpAdaptiveEntry)
   {
      reason = "adaptive entry disabled";
      return true;
   }

   if(confidence < InpAdaptiveMinConfidence)
   {
      reason = "confidence below adaptive minimum";
      return false;
   }

   int regime = DetectRegime(1);
   double a = ATR(1);
   if(a <= 0.0)
   {
      reason = "ATR unavailable";
      return false;
   }

   double emaGap = EmaGapATR(1);
   double mom = MomentumATR(1);
   double body = CandleBodyRatio(1);

   bool regimeOK = true;
   if(InpRequireRegimeCompatibility)
   {
      if(regime == REGIME_TREND)
         regimeOK = (direction > 0 ? emaGap > 0.0 : emaGap < 0.0);
      else if(regime == REGIME_RANGE)
         regimeOK = true;
      else if(regime == REGIME_BREAKOUT)
         regimeOK = (direction > 0 ? mom > 0.0 : mom < 0.0);
   }

   if(InpRequireRegimeCompatibility && !regimeOK)
   {
      reason = "regime compatibility failed";
      return false;
   }

   if(InpRequireRegimeDirection)
   {
      bool directionOK = (direction > 0 ? emaGap >= 0.0 : emaGap <= 0.0);
      if(!directionOK)
      {
         reason = "regime direction failed";
         return false;
      }
   }

   if(InpAdaptiveRequireCandleConfirmation || InpRequireCandleBodyFilter)
   {
      if(body < InpMinCandleBodyRatio)
      {
         reason = "candle body confirmation failed";
         return false;
      }
   }

   // Pullback / breakout geometry is diagnostic by default.
   // It becomes a hard gate only through explicit regime options.
   if(regime == REGIME_BREAKOUT)
   {
      if(MathAbs(mom) < InpAdaptiveBreakoutATR)
      {
         reason = "breakout momentum weak";
         if(InpRequireRegimeCompatibility) return false;
      }
   }

   if(regime == REGIME_TREND)
   {
      if(MathAbs(emaGap) < InpAdaptivePullbackATR && confidence < InpAdaptiveStrongConfidence)
      {
         reason = "trend geometry soft warning";
      }
   }

   if(reason == "") reason = "adaptive entry accepted";
   return true;
}

//==================================================================
// LIVE LOSS STATE
//==================================================================
void UpdateLiveLossState()
{
   datetime newest = 0;
   bool found = false;
   bool loss = false;

   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()<=0) continue;

      if(!found || OrderCloseTime()>newest)
      {
         newest=OrderCloseTime();
         double pnl=OrderProfit()+OrderSwap()+OrderCommission();
         loss=(pnl<0.0);
         found=true;
      }
   }

   if(found)
   {
      g_lastTradeWasLoss=loss;
      g_lastLossTradeTime=(loss ? newest : g_lastLossTradeTime);
      if(!loss) g_recoveryUsedSinceLoss=false;
   }

   int streak=0;
   for(int k=OrdersHistoryTotal()-1;k>=0;k--)
   {
      if(!OrderSelect(k,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol()) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderCloseTime()<=0) continue;

      double p=OrderProfit()+OrderSwap()+OrderCommission();
      if(p<0.0) streak++;
      else if(p>0.0) break;
   }
   g_liveLossStreak=streak;
}

bool CooldownOK()
{
   if(!g_lastTradeWasLoss || g_lastLossTradeTime<=0) return true;

   int shift=iBarShift(Symbol(),Period(),g_lastLossTradeTime,false);
   if(shift<0) return true;

   return (shift >= InpCooldownBarsAfterLoss);
}

//==================================================================
// RECOVERY OVERRIDE
//==================================================================
bool RecoveryAllowed(int direction, int strategy, int buyVotes, int sellVotes,
                     double confidence, double buyScore, double sellScore,
                     bool adaptiveOK, string &reason)
{
   reason="";
   if(!InpEnableRecoveryOverride) { reason="recovery disabled"; return false; }
   if(g_recoveryUsedSinceLoss) { reason="recovery already used"; return false; }
   if(g_liveLossStreak < InpMaxConsecutiveLossesLive) { reason="loss streak below recovery threshold"; return false; }
   if(direction==0 || strategy<0) { reason="invalid recovery signal"; return false; }
   if(!adaptiveOK) { reason="adaptive filter"; return false; }
   if(confidence < InpRecoveryMinConfidence) { reason="recovery confidence"; return false; }

   int votes=(direction>0 ? buyVotes : sellVotes);
   double score=(direction>0 ? buyScore : sellScore);
   double threshold=(direction>0 ? InpBuyScoreThreshold : InpSellScoreThreshold);
   if(votes < InpRecoveryMinVotes) { reason="recovery votes"; return false; }
   if(score < threshold + InpRecoveryScoreMargin) { reason="recovery score"; return false; }

   double se=StrategyEvidence(strategy,direction);
   if(se < InpRecoveryMinStrategyEvidence) { reason="recovery strategy evidence"; return false; }

   // Recovery may bypass only the consecutive-loss block. All other risk gates remain active.
   reason="recovery eligible";
   return true;
}

//==================================================================
// RISK GATE
//==================================================================
bool ExecutionAllowed(string &reason)
{
   reason="";

   if(!InpTesterBypassSessionGate || !IsTesting())
   {
      if(!InSession())
      {
         reason="outside session";
         g_blockedSession++;
         return false;
      }
   }

   if(OpenTradeCount() >= InpMaxOpenTrades)
   {
      reason="max open trades";
      g_blockedOpenTrades++;
      return false;
   }

   if(!DailyLossOK())
   {
      reason="daily loss limit";
      g_blockedDailyLoss++;
      return false;
   }

   if(!CooldownOK())
   {
      reason="loss cooldown";
      g_blockedCooldown++;
      return false;
   }

   if(g_liveLossStreak >= InpMaxConsecutiveLossesLive)
   {
      reason="live consecutive loss limit";
      g_blockedLossStreak++;
      return false;
   }

   if(!SpreadOK())
   {
      reason="spread";
      g_blockedSpread++;
      return false;
   }

   return true;
}

bool RiskGate(string &reason)
{
   return ExecutionAllowed(reason);
}

//==================================================================
// LOT SIZE
//==================================================================
double LotForRisk(double stopDistance)
{
   double minLot=MarketInfo(Symbol(),MODE_MINLOT);
   double maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   double step=MarketInfo(Symbol(),MODE_LOTSTEP);
   double tickValue=MarketInfo(Symbol(),MODE_TICKVALUE);
   double tickSize=MarketInfo(Symbol(),MODE_TICKSIZE);

   if(stopDistance<=0.0 || tickValue<=0.0 || tickSize<=0.0)
      return minLot;

   double riskMoney=AccountBalance()*InpRiskPercent/100.0;
   double moneyPerLot=(stopDistance/tickSize)*tickValue;

   if(moneyPerLot<=0.0) return minLot;

   double lot=riskMoney/moneyPerLot;

   // Broker minimum is a floor. It is reported in diagnostics rather
   // than silently claiming the exact configured percentage was used.
   if(lot<minLot) lot=minLot;
   if(lot>maxLot) lot=maxLot;

   if(step>0.0)
      lot=MathFloor(lot/step)*step;

   if(lot<minLot) lot=minLot;
   return NormalizeDouble(lot,2);
}

//==================================================================
// DECISION SNAPSHOT
//==================================================================
void BuildDecisionSnapshot(int direction,
                           int selectedStrategy,
                           int buyVotes,
                           int sellVotes,
                           double confidence,
                           double evidence,
                           double buyEvidence,
                           double sellEvidence,
                           double buyScore,
                           double sellScore,
                           bool adaptiveOK,
                           bool riskOK)
{
   g_lastDecision.time=TimeCurrent();
   g_lastDecision.shift=1;
   g_lastDecision.direction=direction;
   g_lastDecision.regime=DetectRegime(1);
   g_lastDecision.selectedStrategy=selectedStrategy;
   g_lastDecision.buyVotes=buyVotes;
   g_lastDecision.sellVotes=sellVotes;
   g_lastDecision.confidence=confidence;
   g_lastDecision.evidence=evidence;
   g_lastDecision.buyEvidence=buyEvidence;
   g_lastDecision.sellEvidence=sellEvidence;
   g_lastDecision.directional=(direction>0 ? DirectionEvidence(1) : DirectionEvidence(-1));
   g_lastDecision.adx=ADX(1);
   g_lastDecision.atrPoints=SafeDiv(ATR(1),Point,0.0);
   g_lastDecision.rsi=RSI(1);
   g_lastDecision.emaGapATR=EmaGapATR(1);
   g_lastDecision.momentumATR=MomentumATR(1);
   g_lastDecision.bodyRatio=CandleBodyRatio(1);
   g_lastDecision.spreadPoints=CurrentSpreadPoints();
   g_lastDecision.buyScore=buyScore;
   g_lastDecision.sellScore=sellScore;
   g_lastDecision.adaptiveOK=adaptiveOK;
   g_lastDecision.riskOK=riskOK;
}

void RecordDecision(string decisionText)
{
   if(!InpDecisionAuditEnabled) return;
   if(InpDecisionAuditMaxRows<=0) return;
   if(g_decisionCount>=InpDecisionAuditMaxRows) return;
   ArrayResize(g_decisions,g_decisionCount+1);
   g_decisions[g_decisionCount].time=g_lastDecision.time;
   g_decisions[g_decisionCount].direction=g_lastDecision.direction;
   g_decisions[g_decisionCount].regime=g_lastDecision.regime;
   g_decisions[g_decisionCount].strategy=g_lastDecision.selectedStrategy;
   g_decisions[g_decisionCount].buyVotes=g_lastDecision.buyVotes;
   g_decisions[g_decisionCount].sellVotes=g_lastDecision.sellVotes;
   g_decisions[g_decisionCount].confidence=g_lastDecision.confidence;
   g_decisions[g_decisionCount].buyScore=g_lastDecision.buyScore;
   g_decisions[g_decisionCount].sellScore=g_lastDecision.sellScore;
   g_decisions[g_decisionCount].adx=g_lastDecision.adx;
   g_decisions[g_decisionCount].atrPoints=g_lastDecision.atrPoints;
   g_decisions[g_decisionCount].rsi=g_lastDecision.rsi;
   g_decisions[g_decisionCount].emaGapATR=g_lastDecision.emaGapATR;
   g_decisions[g_decisionCount].momentumATR=g_lastDecision.momentumATR;
   g_decisions[g_decisionCount].bodyRatio=g_lastDecision.bodyRatio;
   g_decisions[g_decisionCount].spreadPoints=g_lastDecision.spreadPoints;
   g_decisions[g_decisionCount].adaptiveOK=g_lastDecision.adaptiveOK;
   g_decisions[g_decisionCount].riskOK=g_lastDecision.riskOK;
   g_decisions[g_decisionCount].decision=decisionText;
   g_decisionCount++;
}

void ExportDecisionJournal()
{
   if(!InpExportCSV || g_decisionCount<=0) return;
   string fn=InpReportPrefix+"_DecisionJournal_"+Symbol()+"_"+IntegerToString(Period())+".csv";
   int h=FileOpen(fn,FILE_CSV|FILE_WRITE,';');
   if(h==INVALID_HANDLE) { Print("Decision journal export failed. Error=",GetLastError()); return; }
   FileWrite(h,"time","direction","regime","strategy","buyVotes","sellVotes","confidence","buyScore","sellScore","ADX","ATR_points","RSI","EMA_gap_ATR","Momentum_ATR","BodyRatio","SpreadPoints","adaptiveOK","riskOK","decision");
   for(int i=0;i<g_decisionCount;i++)
   {
      DecisionRecord r=g_decisions[i];
      FileWrite(h,TimeToString(r.time,TIME_DATE|TIME_MINUTES),DirectionText(r.direction),RegimeName(r.regime),StrategyName(r.strategy),r.buyVotes,r.sellVotes,DoubleToString(r.confidence,4),DoubleToString(r.buyScore,4),DoubleToString(r.sellScore,4),DoubleToString(r.adx,2),DoubleToString(r.atrPoints,1),DoubleToString(r.rsi,2),DoubleToString(r.emaGapATR,4),DoubleToString(r.momentumATR,4),DoubleToString(r.bodyRatio,4),DoubleToString(r.spreadPoints,1),r.adaptiveOK,r.riskOK,r.decision);
   }
   FileClose(h);
   Print("Decision journal exported: ",fn," rows=",g_decisionCount);
}

void PrintDecision()
{
   Print("BITEY DECISION | dir=",g_lastDecision.direction,
         " regime=",RegimeName(g_lastDecision.regime),
         " strategy=",StrategyName(g_lastDecision.selectedStrategy),
         " votes(B/S)=",g_lastDecision.buyVotes,"/",g_lastDecision.sellVotes,
         " conf=",DoubleToString(g_lastDecision.confidence,3),
         " evidence=",DoubleToString(g_lastDecision.evidence,3),
         " dirEv=",DoubleToString(g_lastDecision.directional,3),
         " buyScore=",DoubleToString(g_lastDecision.buyScore,3),
         " sellScore=",DoubleToString(g_lastDecision.sellScore,3),
         " ADX=",DoubleToString(g_lastDecision.adx,2),
         " ATRpts=",DoubleToString(g_lastDecision.atrPoints,1),
         " RSI=",DoubleToString(g_lastDecision.rsi,2),
         " EMAgapATR=",DoubleToString(g_lastDecision.emaGapATR,3),
         " MomATR=",DoubleToString(g_lastDecision.momentumATR,3),
         " Body=",DoubleToString(g_lastDecision.bodyRatio,3),
         " Spread=",DoubleToString(g_lastDecision.spreadPoints,1),
         " adaptive=",g_lastDecision.adaptiveOK,
         " risk=",g_lastDecision.riskOK);
}

//==================================================================
// ORDER EXECUTION
//==================================================================
bool ExecuteTrade(int direction, int selectedStrategy, double confidence, bool recoveryOverride=false)
{
   string reason="";
   bool riskOK=RiskGate(reason);
   if(recoveryOverride && !riskOK && reason=="live consecutive loss limit")
      riskOK=true;

   double evidence=0.0,buyEvidence=0.0,sellEvidence=0.0;
   int bv=0,sv=0,sel=-1;
   double bs=0.0,ss=0.0;
   double c2=0.0;

   // Recompute for diagnostics without changing counters.
   int diag=LocalAISignal(c2,evidence,buyEvidence,sellEvidence,sel,bv,sv,bs,ss);
   bool adaptiveOK=true;
   string adaptiveReason="";
   adaptiveOK=AdaptiveEntryAllowed(direction,confidence,adaptiveReason);

   BuildDecisionSnapshot(direction,selectedStrategy,bv,sv,confidence,
                         evidence,buyEvidence,sellEvidence,bs,ss,
                         adaptiveOK,riskOK);

   if(InpDecisionAuditEnabled) PrintDecision();

   if(!riskOK)
   {
      g_entriesRejected++;
      RecordDecision("BLOCK_RISK");
      return false;
   }

   if(!adaptiveOK)
   {
      g_blockedAdaptive++;
      g_entriesRejected++;
      RecordDecision("BLOCK_ADAPTIVE");
      return false;
   }

   RefreshRates();

   double a=ATR(1);
   if(a<=0.0)
   {
      g_entriesRejected++;
      return false;
   }

   double slDist=a*InpSL_ATR;
   double tpDist=a*InpTP_ATR;
   double lot=LotForRisk(slDist);

   double price=(direction>0 ? Ask : Bid);
   double sl=(direction>0 ? price-slDist : price+slDist);
   double tp=(direction>0 ? price+tpDist : price-tpDist);

   int digits=(int)MarketInfo(Symbol(),MODE_DIGITS);
   price=NormalizeDouble(price,digits);
   sl=NormalizeDouble(sl,digits);
   tp=NormalizeDouble(tp,digits);

   string comment="Bitey54|";
   comment += StrategyName(selectedStrategy);
   comment += "|";
   comment += (direction>0 ? "BUY" : "SELL");

   int ticket=OrderSend(Symbol(),
                        (direction>0 ? OP_BUY : OP_SELL),
                        lot,
                        price,
                        InpSlippage,
                        sl,
                        tp,
                        comment,
                        InpMagic,
                        0,
                        clrNONE);

   if(ticket<0)
   {
      int err=GetLastError();
      Print("OrderSend failed. Error=",err,
            " dir=",direction,
            " strategy=",StrategyName(selectedStrategy));
      g_orderSendFailed++;
      g_entriesRejected++;
      RecordDecision("ORDER_SEND_FAILED");
      return false;
   }

   g_entriesAccepted++;
   if(recoveryOverride)
   {
      g_recoveryOverrides++;
      g_recoveryUsedSinceLoss=true;
   }

   ArrayResize(g_tradeMap,g_tradeMapCount+1);
   g_tradeMap[g_tradeMapCount].ticket=ticket;
   g_tradeMap[g_tradeMapCount].openTime=TimeCurrent();
   g_tradeMap[g_tradeMapCount].direction=direction;
   g_tradeMap[g_tradeMapCount].strategy=selectedStrategy;
   g_tradeMap[g_tradeMapCount].regime=g_lastDecision.regime;
   g_tradeMap[g_tradeMapCount].buyVotes=g_lastDecision.buyVotes;
   g_tradeMap[g_tradeMapCount].sellVotes=g_lastDecision.sellVotes;
   g_tradeMap[g_tradeMapCount].confidence=g_lastDecision.confidence;
   g_tradeMap[g_tradeMapCount].buyScore=g_lastDecision.buyScore;
   g_tradeMap[g_tradeMapCount].sellScore=g_lastDecision.sellScore;
   g_tradeMap[g_tradeMapCount].evidence=g_lastDecision.evidence;
   g_tradeMap[g_tradeMapCount].adx=g_lastDecision.adx;
   g_tradeMap[g_tradeMapCount].atrPoints=g_lastDecision.atrPoints;
   g_tradeMap[g_tradeMapCount].rsi=g_lastDecision.rsi;
   g_tradeMap[g_tradeMapCount].emaGapATR=g_lastDecision.emaGapATR;
   g_tradeMap[g_tradeMapCount].momentumATR=g_lastDecision.momentumATR;
   g_tradeMap[g_tradeMapCount].bodyRatio=g_lastDecision.bodyRatio;
   g_tradeMap[g_tradeMapCount].spreadPoints=g_lastDecision.spreadPoints;
   g_tradeMap[g_tradeMapCount].lot=lot;
   g_tradeMap[g_tradeMapCount].openPrice=price;
   g_tradeMap[g_tradeMapCount].sl=sl;
   g_tradeMap[g_tradeMapCount].tp=tp;
   g_tradeMapCount++;

   RecordDecision(recoveryOverride ? "RECOVERY_ORDER_ACCEPTED" : "ORDER_ACCEPTED");
   Print("ORDER ACCEPTED | ticket=",ticket,
         " dir=",direction,
         " strategy=",StrategyName(selectedStrategy),
         " lot=",DoubleToString(lot,2),
         " conf=",DoubleToString(confidence,3));
   return true;
}

//==================================================================
// EXACT TRADE ATTRIBUTION EXPORT
//==================================================================
string CloseReasonText(int ticket)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_HISTORY)) return "UNKNOWN";
   double cp=OrderClosePrice();
   double tol=Point*3.0;
   if(OrderTakeProfit()>0 && MathAbs(cp-OrderTakeProfit())<=tol) return "TP";
   if(OrderStopLoss()>0 && MathAbs(cp-OrderStopLoss())<=tol) return "SL";
   return "OTHER";
}

void ExportTradeDecisionMap()
{
   if(!InpExportCSV) return;
   string fn=InpReportPrefix+"_TradeDecisionMap_"+Symbol()+"_"+IntegerToString(Period())+".csv";
   int h=FileOpen(fn,FILE_CSV|FILE_WRITE|FILE_COMMON,';');
   if(h==INVALID_HANDLE) { Print("Trade decision map export failed. Error=",GetLastError()); return; }
   FileWrite(h,"ticket","open_time","close_time","direction","regime","strategy",
             "buy_votes","sell_votes","confidence","buy_score","sell_score","evidence",
             "ADX","ATR_points","RSI","EMA_gap_ATR","Momentum_ATR","BodyRatio","SpreadPoints",
             "lot","open_price","close_price","SL","TP","profit","R","holding_hours","close_reason","recovery");

   for(int i=0;i<g_tradeMapCount;i++)
   {
      TradeAttribution t=g_tradeMap[i];
      if(!OrderSelect(t.ticket,SELECT_BY_TICKET,MODE_HISTORY)) continue;
      double pnl=OrderProfit()+OrderSwap()+OrderCommission();
      double riskMoney=MathAbs(t.openPrice-t.sl);
      double r=(riskMoney>0 ? (t.direction>0 ? OrderClosePrice()-t.openPrice : t.openPrice-OrderClosePrice())/riskMoney : 0.0);
      double hours=(OrderCloseTime()>0 ? (OrderCloseTime()-t.openTime)/3600.0 : 0.0);
      FileWrite(h,t.ticket,TimeToString(t.openTime,TIME_DATE|TIME_SECONDS),
                TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),DirectionText(t.direction),
                RegimeName(t.regime),StrategyName(t.strategy),t.buyVotes,t.sellVotes,
                DoubleToString(t.confidence,4),DoubleToString(t.buyScore,4),DoubleToString(t.sellScore,4),
                DoubleToString(t.evidence,4),DoubleToString(t.adx,2),DoubleToString(t.atrPoints,1),
                DoubleToString(t.rsi,2),DoubleToString(t.emaGapATR,3),DoubleToString(t.momentumATR,3),
                DoubleToString(t.bodyRatio,3),DoubleToString(t.spreadPoints,1),DoubleToString(t.lot,2),
                DoubleToString(t.openPrice,Digits),DoubleToString(OrderClosePrice(),Digits),
                DoubleToString(t.sl,Digits),DoubleToString(t.tp,Digits),DoubleToString(pnl,2),
                DoubleToString(r,3),DoubleToString(hours,2),CloseReasonText(t.ticket),
                (StringFind(OrderComment(),"Bitey54|",0)>=0 ? "true" : "false"));
   }
   FileClose(h);
   Print("Trade decision map exported: ",fn," rows=",g_tradeMapCount);
}

//==================================================================
// REPORTING
//==================================================================
string DirectionText(int d)
{
   if(d>0) return "BUY";
   if(d<0) return "SELL";
   return "NONE";
}

void ExportAuditCSV()
{
   if(!InpExportCSV) return;

   string fn=InpReportPrefix+"_"+Symbol()+"_"+IntegerToString(Period())+".csv";
   int h=FileOpen(fn,FILE_CSV|FILE_WRITE|FILE_COMMON,';');
   if(h==INVALID_HANDLE)
   {
      Print("CSV open failed: ",GetLastError());
      return;
   }

   FileWrite(h,
             "strategy","trades","wins","losses","winrate",
             "gross_profit","gross_loss","profit_factor","score",
             "max_loss_streak","max_dd_points");

   for(int i=0;i<ST_COUNT;i++)
   {
      double wr=SafeDiv(g_audit[i].wins,g_audit[i].trades,0.0);
      double pf=(g_audit[i].grossLoss>0.0 ? g_audit[i].grossProfit/g_audit[i].grossLoss : 0.0);

      FileWrite(h,
                StrategyName(i),
                g_audit[i].trades,
                g_audit[i].wins,
                g_audit[i].losses,
                DoubleToString(wr,4),
                DoubleToString(g_audit[i].grossProfit,6),
                DoubleToString(g_audit[i].grossLoss,6),
                DoubleToString(pf,4),
                DoubleToString(g_audit[i].score,4),
                g_audit[i].maxLossStreak,
                DoubleToString(g_audit[i].maxDD/Point,2));
   }

   FileWrite(h,"DIRECTION","trades","wins","losses","winrate",
             "gross_profit","gross_loss","profit_factor","score",
             "max_loss_streak","max_dd_points");

   for(int d=0;d<2;d++)
   {
      double wr2=SafeDiv(g_dirAudit[d].wins,g_dirAudit[d].trades,0.0);
      double pf2=(g_dirAudit[d].grossLoss>0.0 ? g_dirAudit[d].grossProfit/g_dirAudit[d].grossLoss : 0.0);

      FileWrite(h,
                DirectionText(d==0?1:-1),
                g_dirAudit[d].trades,
                g_dirAudit[d].wins,
                g_dirAudit[d].losses,
                DoubleToString(wr2,4),
                DoubleToString(g_dirAudit[d].grossProfit,6),
                DoubleToString(g_dirAudit[d].grossLoss,6),
                DoubleToString(pf2,4),
                DoubleToString(g_dirAudit[d].score,4),
                g_dirAudit[d].maxLossStreak,
                DoubleToString(g_dirAudit[d].maxDD/Point,2));
   }

   FileClose(h);
   Print("Audit CSV exported: ",fn);
}

void PrintSummary()
{
   Print("========== BITEY v2.54 SUMMARY ==========");
   Print("Mode=", (InpTestMode==MODE_CALIBRATION ? "CALIBRATION" : "VALIDATION"),
         " | Trading=",InpEnableTrading,
         " | BacktestExecution=",InpBacktestExecution);

   Print("Raw signals BUY=",g_rawBuySignals," SELL=",g_rawSellSignals," noSignal=",g_noSignal);
   Print("Decision journal rows=",g_decisionCount);
   Print("Entries accepted=",g_entriesAccepted,
         " rejected=",g_entriesRejected,
         " openTrades=",g_blockedOpenTrades,
         " cooldown=",g_blockedCooldown,
         " lossStreak=",g_blockedLossStreak,
         " spread=",g_blockedSpread,
         " session=",g_blockedSession,
         " dailyLoss=",g_blockedDailyLoss,
         " orderSendFailed=",g_orderSendFailed,
         " recoveryOverrides=",g_recoveryOverrides);

   Print("Signal blocks: confidence=",g_blockedConfidence,
         " strategy=",g_blockedStrategy,
         " adaptive=",g_blockedAdaptive);

   Print("Live loss streak=",g_liveLossStreak,
         " last trade loss=",g_lastTradeWasLoss);

   for(int i=0;i<ST_COUNT;i++)
      Print(StrategyName(i),
            " trades=",g_audit[i].trades,
            " score=",DoubleToString(g_audit[i].score,3));

   Print("=========================================");
}

//==================================================================
// INITIALIZATION
//==================================================================
int OnInit()
{
   ResetAudits();
   g_barsSinceAudit = 0;
   g_initialized = true;
   UpdateLiveLossState();

   Print("Bitey IA AI Trading Bot v2.54 initialized.");
   Print("Calibration fallback=",
         InpEvidenceCalibrationFallback,
         " | TestMode=",
         (InpTestMode==MODE_CALIBRATION ? "CALIBRATION" : "VALIDATION"));

   AuditAll();
   if(InpAutoReport) ExportAuditCSV();

   return INIT_SUCCEEDED;
}

//==================================================================
// TICK
//==================================================================
void OnTick()
{
   // IMPORTANT: heavy diagnostics are bar-based, never tick-based.
   // This prevents MT4 Strategy Tester freezes caused by repeated
   // full-history scans on every modeled tick.

   if(!NewBar())
      return;

   g_barsSinceAudit++;

   // Update trade state only once per bar.
   UpdateLiveLossState();

   // Refresh historical audit only at the configured interval.
   if(InpAuditRefreshBars > 0 &&
      (g_lastAuditBar == 0 || g_barsSinceAudit >= InpAuditRefreshBars))
   {
      AuditAll();
      g_lastAuditBar = Time[0];
      g_barsSinceAudit = 0;

      if(InpAutoReport)
         ExportAuditCSV();
   }

   double confidence=0.0;
   double evidence=0.0;
   double buyEvidence=0.0;
   double sellEvidence=0.0;
   int selectedStrategy=-1;
   int buyVotes=0;
   int sellVotes=0;
   double buyScore=0.0;
   double sellScore=0.0;

   int direction=LocalAISignal(confidence,
                               evidence,
                               buyEvidence,
                               sellEvidence,
                               selectedStrategy,
                               buyVotes,
                               sellVotes,
                               buyScore,
                               sellScore);

   bool adaptiveOK=true;
   string adaptiveReason="";
   bool riskOK=true;
   string riskReason="";
   bool recoveryOverride=false;

   if(direction != 0)
      adaptiveOK=AdaptiveEntryAllowed(direction,confidence,adaptiveReason);

   if(direction != 0)
      riskOK=RiskGate(riskReason);

   if(direction != 0 && !riskOK)
      recoveryOverride=RecoveryAllowed(direction,selectedStrategy,buyVotes,sellVotes,
                                       confidence,buyScore,sellScore,adaptiveOK,riskReason);
   if(recoveryOverride)
      riskOK=true;

   BuildDecisionSnapshot(direction,
                         selectedStrategy,
                         buyVotes,
                         sellVotes,
                         confidence,
                         evidence,
                         buyEvidence,
                         sellEvidence,
                         buyScore,
                         sellScore,
                         adaptiveOK,
                         riskOK);

   if(buyVotes>0) g_rawBuySignals++;
   if(sellVotes>0) g_rawSellSignals++;
   if(direction==0) g_noSignal++;

   if(direction==0) RecordDecision("NO_SIGNAL");

   // Only print decision details when there is an actual directional signal.
   // This prevents Journal/Tester log flooding.
   if(InpDecisionAuditEnabled && direction != 0)
      PrintDecision();

   if(direction == 0)
      return;

   if(confidence < InpMinConfidence)
   {
      g_blockedConfidence++;
      g_entriesRejected++;
      Print("ENTRY REJECTED | confidence=",
            DoubleToString(confidence,3),
            " < ",
            DoubleToString(InpMinConfidence,3));
      RecordDecision("BLOCK_CONFIDENCE");
      return;
   }

   if(selectedStrategy < 0)
   {
      g_blockedStrategy++;
      g_entriesRejected++;
      Print("ENTRY REJECTED | no selected strategy");
      RecordDecision("BLOCK_STRATEGY");
      return;
   }

   if(!riskOK)
   {
      g_entriesRejected++;
      Print("ENTRY REJECTED | ",riskReason);
      RecordDecision("BLOCK_"+riskReason);
      return;
   }

   if(!adaptiveOK)
   {
      g_blockedAdaptive++;
      g_entriesRejected++;
      Print("ENTRY REJECTED | ",adaptiveReason);
      RecordDecision("BLOCK_ADAPTIVE");
      return;
   }

   // Live trading requires explicit enablement. In Strategy Tester,
   // InpBacktestExecution permits real OrderSend() execution so the
   // tester can produce actual transactions without enabling live trading.
   bool executionEnabled = (InpEnableTrading || (IsTesting() && InpBacktestExecution));
   if(!executionEnabled)
   {
      Print("SIGNAL ONLY | direction=",
            DirectionText(direction),
            " strategy=",
            StrategyName(selectedStrategy),
            " confidence=",
            DoubleToString(confidence,3));
      RecordDecision("SIGNAL_ONLY");
      return;
   }

   ExecuteTrade(direction,selectedStrategy,confidence,recoveryOverride);
}

//==================================================================
// DEINITIALIZATION
//==================================================================
void OnDeinit(const int reason)
{
   PrintSummary();
   if(InpAutoReport) ExportAuditCSV();
   ExportDecisionJournal();
   ExportTradeDecisionMap();
}
