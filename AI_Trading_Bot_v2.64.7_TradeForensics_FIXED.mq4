//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.64.7_TradeForensics.mq4                              |
//| Bitey IA - Adaptive 8 Strategy MT4 Expert Advisor               |
//| Local AI-style engine: regime + strategy spectrum + risk gate   |
//| Optional read-only Web AI/SBT integration                       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.647"
#property description "Adaptive 8-strategy MT4 EA trade-forensics rebuild with isolated decision gates"
#property description "Local deterministic decision engine with optional Bitey AI"

#define STRATEGY_COUNT 8

enum AI_MODE { AI_LOCAL_ONLY=0, AI_LOCAL_PLUS_WEB=1 };
enum MARKET_REGIME { REGIME_UNKNOWN=0, REGIME_TREND_UP, REGIME_TREND_DOWN, REGIME_RANGE, REGIME_BREAKOUT, REGIME_HIGH_VOLATILITY };

input AI_MODE InpAIMode=AI_LOCAL_ONLY;
input bool InpEnableTrading=false;
input bool InpBacktestExecution=true; // permite OrderSend solo dentro del Strategy Tester
input bool InpAutoStrategy=true;
input double InpRiskPercent=0.25;
input double InpMaxDailyLossPercent=3.0;
input int InpMaxOpenTrades=1;
input int InpMagic=2035001;
input int InpATRPeriod=14;
input int InpADXPeriod=14;
input int InpRSIPeriod=14;
input int InpFastEMA=8;
input int InpSlowEMA=21;
input int InpTrendEMA=200;
input int InpLookback=1500;
input double InpSL_ATR=1.30;
input double InpTP_ATR=2.60;
input int InpAuditHorizon=15;
input double InpMinADXTrend=22.0;
input double InpMaxADXRange=18.0;
input double InpMinATRPoints=5.0; // calibration only; restore after diagnostic
input bool InpUseMinSpreadFilter=true;
input bool InpUseMaxSpreadFilter=true;
input bool InpUseSpreadATRFilter=false; // calibration only; isolate entry pipeline
input int InpMinSpreadPoints=8;
input int InpMaxSpreadPoints=50;
input bool InpDiagnosticMode=true;
input bool InpDiagnosticPrintBlocks=true;
input bool InpRejectZeroSpread=true;
// Backtest control: uses a synthetic spread ONLY for the decision filters.
// MT4 still executes OrderSend at the tester's actual Bid/Ask, so PnL remains
// dependent on the tester spread. For a clean performance test, set the
// Strategy Tester Spread may remain Actual/high; diagnostic gate uses synthetic spread while real spread is logged.
input bool InpUseSyntheticSpreadForGate=true;
input double InpSyntheticSpreadPoints=10.0;
input double InpMaxSpreadATR=0.20;
input double InpMinConfidence=0.40;
input double InpMinEvidenceScore=0.45;
input double InpMinExpectancy=0.0;
input double InpMinProfitFactor=1.0;
input int InpEvidenceMinTrades=8;
// Regime evidence is blended with global evidence to avoid overreacting to
// small regime samples. 0.70 means regime-specific evidence dominates.
input double InpRegimeEvidenceWeight=0.70;
input int InpMinRegimeEvidenceTrades=8;
input double InpMaxAuditDrawdown=5.0;
input int InpMaxAuditConsecutiveLosses=8;
input bool InpRequireRegimeCompatibility=true;
input bool InpRequireSignalConsensus=false; // DIAGNOSTIC: do not discard valid directional signals
input int InpCooldownBarsAfterLoss=3;
input int InpMaxConsecutiveLossesLive=3;
input int InpMinConsensusVotes=1;
input bool InpUseEnsemble=true;
// Calibration mode: if strict evidence produces no eligible strategy, allow the best
// audited strategy to pass only for diagnostic/backtest calibration. It is marked in the report.
input bool InpEvidenceCalibrationFallback=true;
input double InpFallbackMinScore=0.00;
input bool InpRawPipelineProbe=false;
input double InpRawProbeConfidence=0.50;
input bool InpAdaptiveEntry=false; // DIAGNOSTIC: isolate adaptive geometry from signal/risk gates
input double InpAdaptiveMinConfidence=0.48;
input double InpAdaptiveStrongConfidence=0.68;
input double InpAdaptivePullbackATR=0.35;
input double InpAdaptiveBreakoutATR=0.20;
input bool InpAdaptiveRequireCandleConfirmation=true;
input bool InpPrintAuditTable=true;
input bool InpDecisionAudit=true;
input int InpDecisionAuditMaxRows=5000;
input int InpSessionStart=7;
input int InpSessionEnd=20;
input int InpAuditRefreshBars=20;
input int InpMinAuditTrades=8;
input bool InpAutoReport=true;
input string InpReportFile="Bitey_AI_Trading_Report.tch";
input string InpCSVFile="Bitey_AI_Trading_Report.csv";
input bool InpSBTReport=false;
input string InpSBTEndpoint="https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";
input string InpSBTToken="";
input bool InpWebAI=false;
input string InpAIEndpoint="https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze";
input string InpAIAuthToken="";
input int InpWebTimeout=5000;
// v2.64.7 diagnostic controls. These do not change strategy thresholds.
input bool InpDiagnosticFunnel=true;
input bool InpValidateStopLevel=true;
input string InpFunnelCSVFile="Bitey_v2.64.7_DecisionFunnel.csv";
// v2.64.7 selector diagnostics: regime-aware expected-value correction only.
input bool InpUseEvidenceAwareSelector=true;
input bool InpSelectOnlyMatchingDirection=true;
input double InpNegativeExpectancyPenalty=2.0;
input double InpPositiveExpectancyBonus=0.80;
input double InpNegativeProfitFactorPenalty=0.30;
input double InpPositiveProfitFactorBonus=0.15;

struct StrategyAudit
{
   int trades;
   int wins;
   int losses;
   double net;
   double grossProfit;
   double grossLoss;
   double winRate;
   double profitFactor;
   double expectancy;
   double avgWin;
   double avgLoss;
   double maxDrawdown;
   int maxConsecutiveLosses;
   double payoff;
   double score;
};

// One immutable decision snapshot per processed bar. Execution stages update only
// the gate/order fields, preventing duplicate LocalAISignal() evaluation.
struct DecisionSnapshot
{
   datetime time;
   int direction;
   int selectedStrategy;
   int buyVotes;
   int sellVotes;
   double buyWeight;
   double sellWeight;
   double consensus;
   double confidence;
   double evidence;
   double directionalScore;
   double atrPoints;
   double adx;
   double rsi;
   double realSpreadPoints;
   double gateSpreadPoints;
   double bodyRatio;
   double stopLevelPoints;
   double slPoints;
   double tpPoints;
   bool signalGate;
   bool adaptiveGate;
   bool spreadGate;
   bool riskGate;
   bool stopGate;
   bool orderAttempt;
   int orderTicket;
   int orderError;
   string decision;
   string rejectReason;
};

DecisionSnapshot g_decision;
int g_cachedDirection=0;
double g_cachedConfidence=0.0;
string g_cachedReason="";
double g_lastSelectionScore=0.0;
double g_lastSelectionExpectancy=0.0;
double g_lastSelectionPFFactor=1.0;
double g_lastSelectionExpectancyFactor=1.0;
int g_riskGatePassed=0;
int g_orderSuccess=0;
int g_blockedAdaptive=0;
int g_blockedCandle=0;
int g_blockedGeometry=0;
int g_blockedStopLevel=0;
int g_blockedConfidence=0;
int g_blockedDirection=0;
double g_realSpreadSum=0.0;
double g_realSpreadMax=0.0;
double g_realSpreadMin=1.0e9;
int g_realSpreadSamples=0;

StrategyAudit g_audit[STRATEGY_COUNT];
// Regime-specific historical evidence: TREND_UP, TREND_DOWN, RANGE, BREAKOUT, HIGH_VOLATILITY.
#define REGIME_BUCKETS 5
StrategyAudit g_regimeAudit[STRATEGY_COUNT][REGIME_BUCKETS];
int g_best=-1;
MARKET_REGIME g_regime=REGIME_UNKNOWN;
datetime g_lastBar=0;
datetime g_lastTrade=0;
int g_lastAuditBars=-1;
int g_spreadBlockedLow=0;
int g_spreadBlockedHigh=0;
int g_spreadBlockedATR=0;
int g_riskBlocked=0;
int g_blockedATR=0;
int g_blockedSession=0;
int g_blockedDailyLoss=0;
int g_blockedMaxTrades=0;
int g_blockedCooldown=0;
int g_noSignal=0;
int g_lowConfidence=0;
int g_entriesAccepted=0;
int g_evidenceRejected=0;
int g_regimeRejected=0;
int g_consensusRejected=0;
int g_cooldownRejected=0;
int g_liveLossStreak=0;
int g_orderSendFailed=0;
int g_orderAttempts=0;
int g_blockedExecution=0;
int g_blockedLot=0;
int g_blockedATRExec=0;
int g_rawProbeAccepted=0;
int g_riskGateRejected=0;
int g_strategySignals[STRATEGY_COUNT];
int g_strategyCurrentSignals[STRATEGY_COUNT];
int g_pipelineSignals=0;
int g_consensusAccepted=0;
int g_pipelineAfterSpread=0;
int g_pipelineAfterConfidence=0;
int g_barsProcessed=0;
int g_decisionAuditRows=0;
int g_attrTrades[STRATEGY_COUNT];
int g_attrWins[STRATEGY_COUNT];
int g_attrLosses[STRATEGY_COUNT];
double g_attrNet[STRATEGY_COUNT];
double g_attrGrossProfit[STRATEGY_COUNT];
double g_attrGrossLoss[STRATEGY_COUNT];
int g_attrBuyTrades[STRATEGY_COUNT];
int g_attrSellTrades[STRATEGY_COUNT];
int g_attrBuyWins[STRATEGY_COUNT];
int g_attrSellWins[STRATEGY_COUNT];
double g_attrBuyNet[STRATEGY_COUNT];
double g_attrSellNet[STRATEGY_COUNT];
int g_attrUnknown=0;
double g_dayStartEquity=0.0;
int g_dayOfYear=-1;

string StrategyName(int id)
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

string RegimeName(MARKET_REGIME r)
{
   if(r==REGIME_TREND_UP) return "TREND_UP";
   if(r==REGIME_TREND_DOWN) return "TREND_DOWN";
   if(r==REGIME_RANGE) return "RANGE";
   if(r==REGIME_BREAKOUT) return "BREAKOUT";
   if(r==REGIME_HIGH_VOLATILITY) return "HIGH_VOLATILITY";
   return "UNKNOWN";
}

string TFName()
{
   if(Period()==PERIOD_M1) return "M1";
   if(Period()==PERIOD_M5) return "M5";
   if(Period()==PERIOD_M15) return "M15";
   if(Period()==PERIOD_M30) return "M30";
   if(Period()==PERIOD_H1) return "H1";
   if(Period()==PERIOD_H4) return "H4";
   if(Period()==PERIOD_D1) return "D1";
   return IntegerToString(Period());
}

bool NewBar()
{
   if(Time[0]==g_lastBar) return false;
   g_lastBar=Time[0];
   return true;
}

double ATR(int shift=1){ return iATR(Symbol(),Period(),InpATRPeriod,shift); }
double ATRPoints(int shift=1){ if(Point<=0) return 0; return ATR(shift)/Point; }
double ADX(int shift=1){ return iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift); }
double RSI(int shift=1){ return iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,shift); }
double EMA(int period,int shift=1){ return iMA(Symbol(),Period(),period,0,MODE_EMA,PRICE_CLOSE,shift); }

double HurstApprox(int shift=1)
{
   int n=64;
   if(Bars<n+shift+5) return 0.5;
   double mean=0.0;
   for(int i=shift;i<shift+n;i++) mean+=Close[i];
   mean/=n;
   double cum=0.0,maxR=-1e100,minR=1e100,sq=0.0;
   for(int j=0;j<n;j++)
   {
      double d=Close[shift+j]-mean;
      cum+=d;
      if(cum>maxR) maxR=cum;
      if(cum<minR) minR=cum;
      sq+=d*d;
   }
   double sd=MathSqrt(sq/n);
   if(sd<=0.0) return 0.5;
   double rs=(maxR-minR)/sd;
   if(rs<=0.0) return 0.5;
   double h=MathLog(rs)/MathLog(n);
   return MathMax(0.0,MathMin(1.0,h));
}

MARKET_REGIME DetectRegime()
{
   double atrp=ATRPoints(1),adx=ADX(1),fast=EMA(InpFastEMA,1),slow=EMA(InpSlowEMA,1),trend=EMA(InpTrendEMA,1),h=HurstApprox(1);
   if(atrp>=InpMinATRPoints*2.5 && adx>=28.0) return REGIME_HIGH_VOLATILITY;
   if(adx>=InpMinADXTrend && fast>slow && Close[1]>trend) return REGIME_TREND_UP;
   if(adx>=InpMinADXTrend && fast<slow && Close[1]<trend) return REGIME_TREND_DOWN;
   if(adx<=InpMaxADXRange && h<0.55) return REGIME_RANGE;
   int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,2),lo=iLowest(Symbol(),Period(),MODE_LOW,20,2);
   if(hi>=0 && lo>=0 && (Close[1]>iHigh(Symbol(),Period(),hi) || Close[1]<iLow(Symbol(),Period(),lo))) return REGIME_BREAKOUT;
   if(h>0.57 && fast>slow) return REGIME_TREND_UP;
   if(h>0.57 && fast<slow) return REGIME_TREND_DOWN;
   return REGIME_RANGE;
}

int SignalTrend(int s){ double f=EMA(InpFastEMA,s),sl=EMA(InpSlowEMA,s),t=EMA(InpTrendEMA,s); if(f>sl&&Close[s]>t)return 1; if(f<sl&&Close[s]<t)return -1; return 0; }
int SignalMeanReversion(int s){ double r=RSI(s),f=EMA(InpFastEMA,s); if(r<=28&&Close[s]<f)return 1; if(r>=72&&Close[s]>f)return -1; return 0; }
int SignalMomentum(int s){ double r=RSI(s); if(Close[s]>Close[s+5]&&r>=55&&r<=78)return 1; if(Close[s]<Close[s+5]&&r<=45&&r>=22)return -1; return 0; }
int SignalBreakout(int s){ int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+1),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+1); if(hi<0||lo<0)return 0; if(Close[s]>iHigh(Symbol(),Period(),hi))return 1; if(Close[s]<iLow(Symbol(),Period(),lo))return -1; return 0; }
int SignalSession(int s){ int h=TimeHour(Time[s]); if(h<InpSessionStart||h>=InpSessionEnd)return 0; int d=iBarShift(Symbol(),PERIOD_D1,Time[s]); if(d<0)return 0; double o=iOpen(Symbol(),PERIOD_D1,d); if(Close[s]>o)return 1; if(Close[s]<o)return -1; return 0; }
int SignalDivergence(int s){ if(Bars<s+12)return 0; double r0=RSI(s),r5=RSI(s+5); if(Close[s]<Close[s+5]&&r0>r5&&r0<45)return 1; if(Close[s]>Close[s+5]&&r0<r5&&r0>55)return -1; return 0; }
int SignalRange(int s){ int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+1),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+1); if(hi<0||lo<0)return 0; double high=iHigh(Symbol(),Period(),hi),low=iLow(Symbol(),Period(),lo),w=high-low; if(w<=0)return 0; double p=(Close[s]-low)/w; if(p<0.20&&RSI(s)<45)return 1; if(p>0.80&&RSI(s)>55)return -1; return 0; }
int SignalFractalHTF(int s){ double f=iMA(Symbol(),PERIOD_H4,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1),sl=iMA(Symbol(),PERIOD_H4,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1); if(f>sl&&Close[s]>EMA(InpFastEMA,s))return 1; if(f<sl&&Close[s]<EMA(InpFastEMA,s))return -1; return 0; }

int StrategySignal(int id,int shift)
{
   if(id==0)return SignalTrend(shift);
   if(id==1)return SignalMeanReversion(shift);
   if(id==2)return SignalMomentum(shift);
   if(id==3)return SignalBreakout(shift);
   if(id==4)return SignalSession(shift);
   if(id==5)return SignalDivergence(shift);
   if(id==6)return SignalRange(shift);
   if(id==7)return SignalFractalHTF(shift);
   return 0;
}

double StrategyWeight(int id,MARKET_REGIME r)
{
   if(!InpAutoStrategy)return 1.0;
   if(r==REGIME_TREND_UP||r==REGIME_TREND_DOWN){ if(id==0||id==2||id==7)return 1.20; if(id==1||id==6)return 0.75; }
   if(r==REGIME_RANGE){ if(id==1||id==5||id==6)return 1.20; if(id==0||id==3)return 0.70; }
   if(r==REGIME_BREAKOUT||r==REGIME_HIGH_VOLATILITY){ if(id==2||id==3)return 1.25; if(id==1||id==6)return 0.65; }
   return 1.0;
}

bool SimulatedTrade(int dir,int entryShift,int horizon,double sl,double tp,double &r)
{
   double entry=Close[entryShift];
   int end=MathMax(1,entryShift-horizon);
   for(int k=entryShift-1;k>=end;k--)
   {
      if(dir>0){ if(Low[k]<=entry-sl){r=-1.0;return true;} if(High[k]>=entry+tp){r=tp/sl;return true;} }
      else { if(High[k]>=entry+sl){r=-1.0;return true;} if(Low[k]<=entry-tp){r=tp/sl;return true;} }
   }
   double last=Close[end];
   r=dir>0?(last-entry)/sl:(entry-last)/sl;
   return true;
}

int RegimeBucket(MARKET_REGIME r)
{
   if(r==REGIME_TREND_UP) return 0;
   if(r==REGIME_TREND_DOWN) return 1;
   if(r==REGIME_RANGE) return 2;
   if(r==REGIME_BREAKOUT) return 3;
   if(r==REGIME_HIGH_VOLATILITY) return 4;
   return -1;
}

MARKET_REGIME DetectRegimeAtShift(int s)
{
   if(Bars<s+80) return REGIME_UNKNOWN;
   double atrp=ATRPoints(s),adx=ADX(s),fast=EMA(InpFastEMA,s),slow=EMA(InpSlowEMA,s),trend=EMA(InpTrendEMA,s),h=HurstApprox(s);
   if(atrp>=InpMinATRPoints*2.5 && adx>=28.0) return REGIME_HIGH_VOLATILITY;
   if(adx>=InpMinADXTrend && fast>slow && Close[s]>trend) return REGIME_TREND_UP;
   if(adx>=InpMinADXTrend && fast<slow && Close[s]<trend) return REGIME_TREND_DOWN;
   if(adx<=InpMaxADXRange && h<0.55) return REGIME_RANGE;
   int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+2),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+2);
   if(hi>=0 && lo>=0 && (Close[s]>iHigh(Symbol(),Period(),hi) || Close[s]<iLow(Symbol(),Period(),lo))) return REGIME_BREAKOUT;
   if(h>0.57 && fast>slow) return REGIME_TREND_UP;
   if(h>0.57 && fast<slow) return REGIME_TREND_DOWN;
   return REGIME_RANGE;
}

void ResetAudit(StrategyAudit &a)
{
   a.trades=0;a.wins=0;a.losses=0;a.net=0;a.grossProfit=0;a.grossLoss=0;a.winRate=0;a.profitFactor=0;a.expectancy=0;a.avgWin=0;a.avgLoss=0;a.maxDrawdown=0;a.maxConsecutiveLosses=0;a.payoff=0;a.score=-999;
}

void FinalizeAudit(StrategyAudit &a,int minTrades)
{
   if(a.trades>0){a.winRate=100.0*a.wins/a.trades;a.expectancy=a.net/a.trades;}
   if(a.grossLoss<0)a.profitFactor=a.grossProfit/MathAbs(a.grossLoss);
   if(a.wins>0)a.avgWin=a.grossProfit/a.wins;
   if(a.losses>0)a.avgLoss=a.grossLoss/a.losses;
   if(a.losses>0)a.payoff=a.avgWin/MathAbs(a.avgLoss);
   if(a.trades>=minTrades)
   {
      double pf=MathMin(a.profitFactor,4.0)/4.0;
      double ex=(MathMax(-2.0,MathMin(2.0,a.expectancy))+2.0)/4.0;
      double dd=1.0-MathMin(a.maxDrawdown/10.0,1.0);
      double lc=1.0-MathMin(a.maxConsecutiveLosses/10.0,1.0);
      double sample=MathMin(1.0,a.trades/50.0);
      a.score=(55.0*ex+25.0*pf+10.0*dd+10.0*lc)*sample;
   }
}

void AddAuditResult(StrategyAudit &a,double r)
{
   a.trades++;a.net+=r;
   if(r>0){a.wins++;a.grossProfit+=r;}
   else {a.losses++;a.grossLoss+=r;}
}

void FinalizeDrawdown(StrategyAudit &a,double eq,double peak,int cons)
{
   if(peak-eq>a.maxDrawdown)a.maxDrawdown=peak-eq;
   if(cons>a.maxConsecutiveLosses)a.maxConsecutiveLosses=cons;
}

void AuditStrategy(int id)
{
   StrategyAudit a; ResetAudit(a);
   for(int rb=0;rb<REGIME_BUCKETS;rb++) ResetAudit(g_regimeAudit[id][rb]);
   int maxBars=MathMin(InpLookback,Bars-InpAuditHorizon-5);
   if(maxBars<100){g_audit[id]=a;return;}
   double eq=0,peak=0;int cons=0;
   double rbEq[REGIME_BUCKETS],rbPeak[REGIME_BUCKETS];
   int rbCons[REGIME_BUCKETS];
   for(int z=0;z<REGIME_BUCKETS;z++){rbEq[z]=0;rbPeak[z]=0;rbCons[z]=0;}

   for(int s=maxBars;s>=InpAuditHorizon+2;s--)
   {
      int sig=StrategySignal(id,s); if(sig==0)continue;
      double atr=iATR(Symbol(),Period(),InpATRPeriod,s); if(atr<=0)continue;
      double r=0; SimulatedTrade(sig,s,InpAuditHorizon,atr*InpSL_ATR,atr*InpTP_ATR,r);
      AddAuditResult(a,r);
      eq+=r;if(eq>peak)peak=eq;if(peak-eq>a.maxDrawdown)a.maxDrawdown=peak-eq;
      if(r>0)cons=0;else{cons++;if(cons>a.maxConsecutiveLosses)a.maxConsecutiveLosses=cons;}

      MARKET_REGIME hr=DetectRegimeAtShift(s);
      int rb=RegimeBucket(hr);
      if(rb>=0 && rb<REGIME_BUCKETS)
      {
         StrategyAudit x=g_regimeAudit[id][rb];
         AddAuditResult(x,r);
         rbEq[rb]+=r;if(rbEq[rb]>rbPeak[rb])rbPeak[rb]=rbEq[rb];
         if(rbPeak[rb]-rbEq[rb]>x.maxDrawdown)x.maxDrawdown=rbPeak[rb]-rbEq[rb];
         if(r>0)rbCons[rb]=0;else{rbCons[rb]++;if(rbCons[rb]>x.maxConsecutiveLosses)x.maxConsecutiveLosses=rbCons[rb];}
         g_regimeAudit[id][rb]=x;
      }
   }
   FinalizeAudit(a,InpMinAuditTrades);
   g_audit[id]=a;
   for(int rb=0;rb<REGIME_BUCKETS;rb++) FinalizeAudit(g_regimeAudit[id][rb],MathMax(5,InpMinAuditTrades/2));
}

string RegimeBucketName(int rb)
{
   if(rb==0)return "TREND_UP";
   if(rb==1)return "TREND_DOWN";
   if(rb==2)return "RANGE";
   if(rb==3)return "BREAKOUT";
   if(rb==4)return "HIGH_VOLATILITY";
   return "UNKNOWN";
}

void PrintRegimeEvidenceMatrix()
{
   if(!InpPrintAuditTable)return;
   Print("=== BITEY v2.33 STRATEGY x REGIME EVIDENCE MATRIX ===");
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      string row="MATRIX | "+StrategyName(i);
      for(int rb=0;rb<REGIME_BUCKETS;rb++)
      {
         StrategyAudit x=g_regimeAudit[i][rb];
         row+=" | "+RegimeBucketName(rb)+":T="+IntegerToString(x.trades)+",PF="+DoubleToString(x.profitFactor,2)+",E="+DoubleToString(x.expectancy,3)+",S="+DoubleToString(x.score,2);
      }
      Print(row);
   }
}

void PrintCurrentRegimeDecisionTable()
{
   if(!InpPrintAuditTable) return;
   int rb=RegimeBucket(g_regime);
   Print("=== BITEY v2.33 CURRENT REGIME DECISION TABLE ===");
   Print("Current regime=",RegimeName(g_regime)," bucket=",rb);
   if(rb<0) return;
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      StrategyAudit x=g_regimeAudit[i][rb];
      bool enough=(x.trades>=InpMinRegimeEvidenceTrades);
      bool positive=(x.expectancy>0.0 && x.profitFactor>=1.0);
      bool compatible=StrategyRegimeCompatible(i);
      double globalEv=StrategyEvidenceForAudit(g_audit[i]);
      double regimeEv=StrategyEvidenceForAudit(x);
      double ev=StrategyEvidence(i);
      double w=(0.35+0.65*ev)*StrategyWeight(i,g_regime)*(compatible?1.0:0.55);
      Print("REGIME | ",StrategyName(i),
            " eligible=",(enough&&positive?"true":"false"),
            " compatible=",(compatible?"true":"false"),
            " trades=",x.trades,
            " winRate=",DoubleToString(x.winRate,2),
            " PF=",DoubleToString(x.profitFactor,3),
            " E=",DoubleToString(x.expectancy,4),
            " globalEvidence=",DoubleToString(globalEv,3),
            " regimeEvidence=",DoubleToString(regimeEv,3),
            " blendedEvidence=",DoubleToString(ev,3),
            " weight=",DoubleToString(w,3));
   }
}

void ResetSignalDiagnostics()
{
   for(int i=0;i<STRATEGY_COUNT;i++){g_strategySignals[i]=0;g_strategyCurrentSignals[i]=0;}
   g_pipelineSignals=0;g_pipelineAfterSpread=0;g_pipelineAfterConfidence=0;
}

void ProbeStrategies()
{
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      g_strategyCurrentSignals[i]=sig;
      int limit=MathMin(300,Bars-10);
      for(int s=1;s<=limit;s++) if(StrategySignal(i,s)!=0) g_strategySignals[i]++;
   }
}

void PrintAuditTable()
{
   if(!InpPrintAuditTable)return;
   Print("=== BITEY v2.64.7 STRATEGY ATTRIBUTION AUDIT ===");
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      StrategyAudit a=g_audit[i];
      Print(StrategyName(i),
            " trades=",a.trades,
            " winRate=",DoubleToString(a.winRate,2),
            " PF=",DoubleToString(a.profitFactor,3),
            " expectancy=",DoubleToString(a.expectancy,4),
            " DD=",DoubleToString(a.maxDrawdown,3),
            " maxLossStreak=",a.maxConsecutiveLosses,
            " score=",DoubleToString(a.score,3));
   }
}

void AuditAll()
{
   for(int i=0;i<STRATEGY_COUNT;i++)AuditStrategy(i);
   g_best=-1;
   double best=-999999;

   // Primary selection: current-regime evidence blended with global evidence.
   // The blend reduces the chance that a small regime sample dominates the
   // decision while still allowing regime specialization.
   for(int j=0;j<STRATEGY_COUNT;j++)
   {
      if(g_audit[j].trades<InpMinAuditTrades) continue;
      double ev=StrategyEvidence(j);
      if(ev<InpMinEvidenceScore) continue;

      int rb=RegimeBucket(g_regime);
      if(rb>=0)
      {
         StrategyAudit rx=g_regimeAudit[j][rb];
         if(rx.trades>=InpMinRegimeEvidenceTrades)
         {
            if(rx.expectancy<InpMinExpectancy || rx.profitFactor<InpMinProfitFactor)
            {
               // Do not hard reject a strategy solely from a thin regime sample;
               // the global evidence remains part of the blended score.
            }
         }
      }

      bool compatible=StrategyRegimeCompatible(j);
      double compatibilityFactor=(InpRequireRegimeCompatibility && !compatible)?0.55:1.0;
      double score=ev*100.0*StrategyWeight(j,g_regime)*compatibilityFactor;
      if(score>best)
      {
         best=score;
         g_best=j;
      }
   }

   // Calibration fallback: preserve v2.16 behavior when strict evidence has
   // no candidate, but mark the report through the existing fallback flag.
   if(g_best<0 && InpEvidenceCalibrationFallback)
   {
      for(int k=0;k<STRATEGY_COUNT;k++)
      {
         if(g_audit[k].trades<InpMinAuditTrades) continue;
         if(g_audit[k].score<InpFallbackMinScore) continue;
         double ev=StrategyEvidence(k);
         double score=(0.35+0.65*ev)*StrategyWeight(k,g_regime);
         if(score>best){best=score;g_best=k;}
      }
   }

   g_lastAuditBars=Bars;
   PrintAuditTable();
   PrintRegimeEvidenceMatrix();
   PrintCurrentRegimeDecisionTable();
}

int OpenTrades()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=InpMagic)continue;if(OrderType()==OP_BUY||OrderType()==OP_SELL)n++;}
   return n;
}

bool SessionOK()
{
   int h=TimeHour(TimeCurrent());
   if(InpSessionStart==InpSessionEnd)return true;
   if(InpSessionStart<InpSessionEnd)return h>=InpSessionStart&&h<InpSessionEnd;
   return h>=InpSessionStart||h<InpSessionEnd;
}

bool DailyRiskOK()
{
   int d=TimeDayOfYear(TimeCurrent());
   if(d!=g_dayOfYear){g_dayOfYear=d;g_dayStartEquity=AccountEquity();}
   if(g_dayStartEquity<=0)g_dayStartEquity=AccountEquity();
   double dd=100.0*(g_dayStartEquity-AccountEquity())/g_dayStartEquity;
   return dd<InpMaxDailyLossPercent;
}

double LotForRisk(double slPoints)
{
   if(slPoints<=0)return 0;
   double money=AccountBalance()*InpRiskPercent/100.0;
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),ts=MarketInfo(Symbol(),MODE_TICKSIZE);
   if(tv<=0||ts<=0)return 0;
   double lossPerLot=(slPoints*Point/ts)*tv;if(lossPerLot<=0)return 0;
   double lot=money/lossPerLot,step=MarketInfo(Symbol(),MODE_LOTSTEP),minLot=MarketInfo(Symbol(),MODE_MINLOT),maxLot=MarketInfo(Symbol(),MODE_MAXLOT);
   if(step<=0)step=0.01;lot=MathFloor(lot/step)*step;lot=MathMax(minLot,MathMin(maxLot,lot));return NormalizeDouble(lot,2);
}

int g_selectedStrategy=-1;

double StrategyEvidenceForAudit(StrategyAudit &a)
{
   if(a.trades<=0) return 0.05;
   double pf=(a.profitFactor>0.0?MathMin(2.5,a.profitFactor)/2.5:0.0);
   double ex=(MathMax(-1.0,MathMin(1.0,a.expectancy))+1.0)/2.0;
   double dd=(a.maxDrawdown<=0.0?1.0:1.0-MathMin(1.0,a.maxDrawdown/MathMax(1.0,InpMaxAuditDrawdown)));
   double streak=1.0-MathMin(1.0,(double)a.maxConsecutiveLosses/MathMax(1,InpMaxAuditConsecutiveLosses));
   double sample=MathMin(1.0,(double)a.trades/50.0);
   double e=0.30*pf+0.30*ex+0.15*dd+0.10*streak+0.15*sample;
   if(a.expectancy<0.0)e*=0.55;
   if(a.profitFactor>0.0 && a.profitFactor<1.0)e*=0.70;
   if(a.maxDrawdown>InpMaxAuditDrawdown)e*=0.70;
   return MathMax(0.02,MathMin(1.0,e));
}

double StrategyEvidence(int id)
{
   // Blend regime-specific evidence with global evidence. This keeps the
   // adaptive engine from overfitting a small regime sample.
   double globalEv=StrategyEvidenceForAudit(g_audit[id]);
   int rb=RegimeBucket(g_regime);
   if(rb<0) return globalEv;

   StrategyAudit x=g_regimeAudit[id][rb];
   if(x.trades<InpMinRegimeEvidenceTrades) return globalEv;

   double regimeEv=StrategyEvidenceForAudit(x);
   double w=MathMax(0.0,MathMin(1.0,InpRegimeEvidenceWeight));
   return MathMax(0.02,MathMin(1.0,w*regimeEv+(1.0-w)*globalEv));
}

bool StrategyRegimeCompatible(int id)
{
   if(g_regime==REGIME_TREND_UP||g_regime==REGIME_TREND_DOWN)
      return (id==0||id==2||id==7||id==3);
   if(g_regime==REGIME_RANGE)
      return (id==1||id==5||id==6||id==4);
   if(g_regime==REGIME_BREAKOUT||g_regime==REGIME_HIGH_VOLATILITY)
      return (id==2||id==3||id==7||id==0);
   return true;
}

double StrategySelectionScore(int id,int signal,double &evidence,double &sampleExpectancy,double &pfFactor,double &expectancyFactor)
{
   evidence=StrategyEvidence(id);
   sampleExpectancy=g_audit[id].expectancy;
   double samplePF=g_audit[id].profitFactor;
   int rb=RegimeBucket(g_regime);
   if(rb>=0)
   {
      StrategyAudit ra=g_regimeAudit[id][rb];
      if(ra.trades>=InpMinRegimeEvidenceTrades)
      {
         sampleExpectancy=ra.expectancy;
         samplePF=ra.profitFactor;
      }
   }

   expectancyFactor=1.0;
   if(InpUseEvidenceAwareSelector)
   {
      if(sampleExpectancy<0.0)
         expectancyFactor=1.0/(1.0+MathAbs(sampleExpectancy)*MathMax(0.0,InpNegativeExpectancyPenalty));
      else
         expectancyFactor=1.0+MathMin(sampleExpectancy,0.50)*MathMax(0.0,InpPositiveExpectancyBonus);
   }

   pfFactor=1.0;
   if(InpUseEvidenceAwareSelector)
   {
      if(samplePF>0.0 && samplePF<1.0)
         pfFactor=1.0-MathMin(0.45,MathMax(0.0,1.0-samplePF)*MathMax(0.0,InpNegativeProfitFactorPenalty));
      else if(samplePF>=1.0)
         pfFactor=1.0+MathMin(0.20,(samplePF-1.0)*MathMax(0.0,InpPositiveProfitFactorBonus));
   }

   double compatibilityFactor=(InpRequireRegimeCompatibility && !StrategyRegimeCompatible(id))?0.55:1.0;
   double signalFactor=(signal!=0?1.0:0.0);
   return (0.35+0.65*evidence)*StrategyWeight(id,g_regime)*compatibilityFactor*expectancyFactor*pfFactor*signalFactor;
}

int LocalAISignal(double &confidence,string &reason)
{
   confidence=0.0; reason="No active strategy signal."; g_selectedStrategy=-1;
   g_lastSelectionScore=0.0; g_lastSelectionExpectancy=0.0; g_lastSelectionPFFactor=1.0; g_lastSelectionExpectancyFactor=1.0;
   int active=0,buyVotes=0,sellVotes=0;
   double buyWeight=0.0,sellWeight=0.0;
   int fallbackBestId=-1,fallbackBestDir=0;
   double fallbackBestWeight=-1.0;

   // Pass 1: aggregate directional votes using the existing evidence/compatibility
   // weights. This preserves the directional engine while separating it from
   // strategy selection.
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      if(sig==0) continue;
      active++;

      double evidence=StrategyEvidence(i);
      double regimeFactor=1.0;
      if(InpRequireRegimeCompatibility && !StrategyRegimeCompatible(i)) regimeFactor=0.55;
      double weight=(0.35+0.65*evidence)*StrategyWeight(i,g_regime)*regimeFactor;

      if(sig>0){buyVotes++;buyWeight+=weight;}
      else {sellVotes++;sellWeight+=weight;}

      if(weight>fallbackBestWeight){fallbackBestWeight=weight;fallbackBestId=i;fallbackBestDir=sig;}
   }

   if(active==0){g_noSignal++;return 0;}

   double total=buyWeight+sellWeight;
   int dir=0;
   if(buyWeight>sellWeight) dir=1;
   else if(sellWeight>buyWeight) dir=-1;
   else dir=fallbackBestDir;

   int winningVotes=(dir>0?buyVotes:sellVotes);
   double winningWeight=(dir>0?buyWeight:sellWeight);
   double consensus=(total>0.0?winningWeight/total:0.0);
   double strength=MathMin(1.0,winningWeight/2.0);

   // Pass 2: select the strategy AFTER the final direction is known. This fixes
   // the previous behavior where the highest-weight strategy could be selected
   // even when its signal was opposite to the aggregate direction.
   int bestId=-1;
   double bestSelection=-1.0;
   double bestEvidence=0.0;
   double bestExp=0.0;
   double bestPF=0.0;
   double bestExpFactor=1.0;
   double bestPFFactor=1.0;
   int rb=RegimeBucket(g_regime);

   for(int j=0;j<STRATEGY_COUNT;j++)
   {
      int sig=StrategySignal(j,1);
      if(sig==0) continue;
      if(InpSelectOnlyMatchingDirection && sig!=dir) continue;

      double ev=0.0,ex=0.0,pff=1.0,exf=1.0;
      double score=StrategySelectionScore(j,sig,ev,ex,pff,exf);
      if(score>bestSelection)
      {
         bestSelection=score;
         bestId=j;
         bestEvidence=ev;
         bestExp=ex;
         bestPF=(rb>=0 && g_regimeAudit[j][rb].trades>=InpMinRegimeEvidenceTrades ? g_regimeAudit[j][rb].profitFactor : g_audit[j].profitFactor);
         bestExpFactor=exf;
         bestPFFactor=pff;
      }
   }

   // If no strategy matches the aggregate direction, retain the strongest
   // active strategy as a diagnostic fallback rather than silently inventing one.
   if(bestId<0)
   {
      bestId=fallbackBestId;
      bestEvidence=(bestId>=0?StrategyEvidence(bestId):0.0);
      bestSelection=fallbackBestWeight;
      if(bestId>=0)
      {
         StrategyAudit ba=g_audit[bestId];
         bestExp=ba.expectancy;
         bestPF=ba.profitFactor;
      }
   }

   double regimeFit=(bestId>=0 && StrategyRegimeCompatible(bestId)?1.0:0.55);
   double adxFit=MathMin(1.0,MathMax(0.25,ADX(1)/35.0));
   double atrFit=(ATRPoints(1)>=InpMinATRPoints?1.0:0.50);
   confidence=0.35*consensus+0.25*bestEvidence+0.15*strength+0.15*regimeFit+0.05*adxFit+0.05*atrFit;

   if(InpRequireSignalConsensus && active>=2 && winningVotes<InpMinConsensusVotes)
   {
      g_consensusRejected++;
      reason="Directional consensus failed.";
      return 0;
   }

   if(confidence<InpMinConfidence)
   {
      g_lowConfidence++;
      reason="Dynamic evidence confidence="+DoubleToString(confidence,3)+
             " < "+DoubleToString(InpMinConfidence,3)+
             " best="+(bestId>=0?StrategyName(bestId):"NONE");
      return 0;
   }

   g_selectedStrategy=bestId;
   g_lastSelectionScore=bestSelection;
   g_lastSelectionExpectancy=bestExp;
   g_lastSelectionPFFactor=bestPFFactor;
   g_lastSelectionExpectancyFactor=bestExpFactor;
   g_pipelineAfterConfidence++;
   g_consensusAccepted++;
   reason="EVIDENCE_SELECTOR strategy="+(bestId>=0?StrategyName(bestId):"NONE")+
          " dir="+(dir>0?"BUY":"SELL")+
          " BUYvotes="+IntegerToString(buyVotes)+
          " SELLvotes="+IntegerToString(sellVotes)+
          " evidence="+DoubleToString(bestEvidence,3)+
          " selScore="+DoubleToString(bestSelection,3)+
          " sampleE="+DoubleToString(bestExp,4)+
          " samplePF="+DoubleToString(bestPF,3)+
          " exFactor="+DoubleToString(bestExpFactor,3)+
          " pfFactor="+DoubleToString(bestPFFactor,3)+
          " confidence="+DoubleToString(confidence,3)+
          " regime="+RegimeName(g_regime);
   return dir;
}


bool AdaptiveEntryAllowed(int direction,string &entryReason)
{
   entryReason="adaptive entry disabled";
   g_decision.adaptiveGate=true;
   if(!InpAdaptiveEntry) return true;
   if(direction==0) { entryReason="no direction"; g_blockedDirection++; g_decision.adaptiveGate=false; return false; }
   if(g_cachedDirection!=direction) { entryReason="cached direction mismatch"; g_blockedDirection++; g_decision.adaptiveGate=false; return false; }
   double atr=ATR(1);
   if(atr<=0.0) { entryReason="invalid ATR"; g_decision.adaptiveGate=false; g_blockedAdaptive++; return false; }
   double c1=Close[1],o1=Open[1],h1=High[1],l1=Low[1];
   double range=h1-l1;
   if(range<=0.0) { entryReason="invalid candle range"; g_decision.adaptiveGate=false; g_blockedAdaptive++; return false; }
   double body=MathAbs(c1-o1);
   double bodyRatio=body/range;
   g_decision.bodyRatio=bodyRatio;
   double confidence=g_cachedConfidence;
   if(confidence<InpAdaptiveMinConfidence) { entryReason="confidence below adaptive minimum"; g_decision.adaptiveGate=false; g_blockedConfidence++; return false; }
   bool candleOK=true;
   if(InpAdaptiveRequireCandleConfirmation)
   {
      if(direction>0) candleOK=(c1>o1 && bodyRatio>=0.25);
      else candleOK=(c1<o1 && bodyRatio>=0.25);
   }
   if(!candleOK) { entryReason="candle confirmation failed"; g_decision.adaptiveGate=false; g_blockedCandle++; return false; }
   double fast=EMA(InpFastEMA,1);
   double dist=MathAbs(c1-fast);
   bool regimeOK=true;
   if(g_regime==REGIME_TREND_UP && direction>0) regimeOK=(c1>=fast-InpAdaptivePullbackATR*atr);
   if(g_regime==REGIME_TREND_DOWN && direction<0) regimeOK=(c1<=fast+InpAdaptivePullbackATR*atr);
   if(g_regime==REGIME_BREAKOUT || g_regime==REGIME_HIGH_VOLATILITY)
   {
      int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,2);
      int lo=iLowest(Symbol(),Period(),MODE_LOW,20,2);
      if(hi<0 || lo<0) regimeOK=false;
      else
      {
         double prevHigh=High[hi],prevLow=Low[lo];
         if(direction>0) regimeOK=(c1>=prevHigh-InpAdaptiveBreakoutATR*atr);
         else regimeOK=(c1<=prevLow+InpAdaptiveBreakoutATR*atr);
      }
   }
   if(g_regime==REGIME_RANGE) regimeOK=(dist>=0.10*atr);
   if(!regimeOK) { entryReason="regime entry geometry failed"; g_decision.adaptiveGate=false; g_blockedGeometry++; return false; }
   if(confidence<InpAdaptiveStrongConfidence && bodyRatio<0.35) { entryReason="weak adaptive candle"; g_decision.adaptiveGate=false; g_blockedCandle++; return false; }
   entryReason="adaptive entry accepted";
   return true;
}

bool ExecutionAllowed()
{
   // Trading real solo se habilita explícitamente.
   // En Strategy Tester permitimos ejecución simulada independientemente
   // de InpEnableTrading, para que el backtest no quede en 0 operaciones.
   if(InpEnableTrading) return true;
   if(IsTesting() && InpBacktestExecution) return true;
   g_blockedExecution++;
   if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | execution disabled (not tester/backtest)");
   return false;
}

bool SpreadOK(double &spreadPoints,double &atrPoints)
{
   double testerSpread=(Ask-Bid)/Point;
   // Telemetry: always record the tester's effective Bid/Ask spread separately
   // from the optional synthetic filter spread. This makes cost distortion visible.
   if(testerSpread>=0.0 && testerSpread<1000000.0)
   {
      g_realSpreadSum+=testerSpread;
      g_realSpreadSamples++;
      if(testerSpread>g_realSpreadMax) g_realSpreadMax=testerSpread;
      if(testerSpread<g_realSpreadMin) g_realSpreadMin=testerSpread;
   }
   g_decision.realSpreadPoints=testerSpread;
   spreadPoints=InpUseSyntheticSpreadForGate ? InpSyntheticSpreadPoints : testerSpread;
   g_decision.gateSpreadPoints=spreadPoints;
   atrPoints=ATRPoints(1);

   if(InpRejectZeroSpread && spreadPoints<=0.0)
   {
      g_spreadBlockedLow++;
      if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | spread zero/invalid: ",DoubleToString(spreadPoints,1)," pts");
      return false;
   }

   if(InpUseMinSpreadFilter && spreadPoints < InpMinSpreadPoints)
   {
      g_spreadBlockedLow++;
      if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | spread below minimum: ",DoubleToString(spreadPoints,1)," < ",InpMinSpreadPoints," pts");
      return false;
   }

   if(InpUseMaxSpreadFilter && spreadPoints > InpMaxSpreadPoints)
   {
      g_spreadBlockedHigh++;
      if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | spread above maximum: ",DoubleToString(spreadPoints,1)," > ",InpMaxSpreadPoints," pts");
      return false;
   }

   if(atrPoints < InpMinATRPoints)
   {
      g_blockedATR++;
      if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | ATR below minimum: ",DoubleToString(atrPoints,1)," < ",DoubleToString(InpMinATRPoints,1)," pts");
      return false;
   }

   if(InpUseSpreadATRFilter && atrPoints>0 && spreadPoints/atrPoints > InpMaxSpreadATR)
   {
      g_spreadBlockedATR++;
      if(InpDiagnosticPrintBlocks) Print("DIAG BLOCK | spread/ATR too high: ",DoubleToString(spreadPoints/atrPoints,3)," > ",DoubleToString(InpMaxSpreadATR,3));
      return false;
   }

   return true;
}

bool RiskGate(int direction)
{
   g_decision.riskGate=false;
   if(!ExecutionAllowed()||direction==0) return false;
   if(OpenTrades()>=InpMaxOpenTrades){g_riskBlocked++;g_blockedMaxTrades++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | max open trades");return false;}
   if(g_lastTrade>0 && InpCooldownBarsAfterLoss>0)
   {
      int barsSince=iBarShift(Symbol(),Period(),g_lastTrade,true);
      if(barsSince>=0 && barsSince<InpCooldownBarsAfterLoss)
      {
         g_riskBlocked++;g_cooldownRejected++;g_blockedCooldown++;
         if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | cooldown bars=",barsSince," < ",InpCooldownBarsAfterLoss);
         return false;
      }
   }
   if(!SessionOK()){g_riskBlocked++;g_blockedSession++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | outside session");return false;}
   if(!DailyRiskOK()){g_riskBlocked++;g_blockedDailyLoss++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | daily loss limit");return false;}
   double spread=0,atrp=0;
   if(!SpreadOK(spread,atrp))return false;
   g_pipelineAfterSpread++;
   g_decision.spreadGate=true;
   g_riskGatePassed++;
   g_decision.riskGate=true;
   return true;
}

void ExecuteTrade(int direction)
{
   g_decision.orderAttempt=false;
   g_decision.orderTicket=-1;
   g_decision.orderError=0;
   if(direction==0){g_decision.decision="NO_SIGNAL";return;}

   string adaptiveReason="";
   if(!AdaptiveEntryAllowed(direction,adaptiveReason))
   {
      g_riskGateRejected++;
      g_decision.decision="ADAPTIVE_BLOCK";
      g_decision.rejectReason=adaptiveReason;
      if(InpDiagnosticPrintBlocks) Print("DIAG ADAPTIVE ENTRY BLOCK | ",adaptiveReason);
      return;
   }

   if(!RiskGate(direction))
   {
      g_riskGateRejected++;
      g_decision.decision="RISK_BLOCK";
      if(g_decision.rejectReason=="") g_decision.rejectReason="risk gate rejected";
      return;
   }

   double atr=ATR(1);
   if(atr<=0){g_blockedATRExec++;g_decision.decision="ATR_BLOCK";g_decision.rejectReason="invalid ATR";if(InpDiagnosticPrintBlocks)Print("DIAG EXEC BLOCK | invalid ATR");return;}
   double sl=InpSL_ATR*atr,tp=InpTP_ATR*atr;
   double slPoints=sl/Point,tpPoints=tp/Point;
   g_decision.slPoints=slPoints;g_decision.tpPoints=tpPoints;

   double stopLevel=MarketInfo(Symbol(),MODE_STOPLEVEL);
   g_decision.stopLevelPoints=stopLevel;
   if(InpValidateStopLevel && stopLevel>0.0)
   {
      if(slPoints<stopLevel || tpPoints<stopLevel)
      {
         g_blockedStopLevel++;
         g_decision.stopGate=false;
         g_decision.decision="STOP_LEVEL_BLOCK";
         g_decision.rejectReason="SL/TP below MODE_STOPLEVEL";
         if(InpDiagnosticPrintBlocks) Print("DIAG EXEC BLOCK | stop level=",DoubleToString(stopLevel,1)," SL=",DoubleToString(slPoints,1)," TP=",DoubleToString(tpPoints,1));
         return;
      }
   }
   g_decision.stopGate=true;

   double lots=LotForRisk(slPoints);
   if(lots<=0){g_blockedLot++;g_decision.decision="LOT_BLOCK";g_decision.rejectReason="invalid lot size";if(InpDiagnosticPrintBlocks)Print("DIAG EXEC BLOCK | invalid lot size");return;}

   RefreshRates();
   double price,stopLoss,takeProfit;
   if(direction>0)
   {
      price=Ask;
      stopLoss=NormalizeDouble(Bid-sl,Digits);
      takeProfit=NormalizeDouble(Ask+tp,Digits);
   }
   else
   {
      price=Bid;
      stopLoss=NormalizeDouble(Ask+sl,Digits);
      takeProfit=NormalizeDouble(Bid-tp,Digits);
   }

   g_orderAttempts++;g_decision.orderAttempt=true;
   ResetLastError();
   int ticket=OrderSend(Symbol(),direction>0?OP_BUY:OP_SELL,lots,price,5,stopLoss,takeProfit,
      "S="+(g_selectedStrategy>=0?StrategyName(g_selectedStrategy):"UNKNOWN")+"|B64|"+(direction>0?"BUY":"SELL"),InpMagic,0,clrNONE);
   if(ticket>0)
   {
      g_orderSuccess++;g_entriesAccepted++;g_lastTrade=TimeCurrent();
      g_decision.orderTicket=ticket;g_decision.decision="ORDER_SUCCESS";g_decision.rejectReason="";
      Print("EXEC OK | Ticket=",ticket," direction=",direction>0?"BUY":"SELL"," strategy=",(g_selectedStrategy>=0?StrategyName(g_selectedStrategy):"UNKNOWN")," lots=",DoubleToString(lots,2)," SLpts=",DoubleToString(slPoints,1)," TPpts=",DoubleToString(tpPoints,1));
   }
   else
   {
      int err=GetLastError();g_orderSendFailed++;g_decision.orderError=err;g_decision.decision="ORDER_ERROR";g_decision.rejectReason="OrderSend error="+IntegerToString(err);
      Print("EXEC FAIL | OrderSend error=",err," direction=",direction>0?"BUY":"SELL"," strategy=",(g_selectedStrategy>=0?StrategyName(g_selectedStrategy):"UNKNOWN")," lots=",DoubleToString(lots,2));
   }
}

void ResetAttribution()
{
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      g_attrTrades[i]=0; g_attrWins[i]=0; g_attrLosses[i]=0;
      g_attrNet[i]=0.0; g_attrGrossProfit[i]=0.0; g_attrGrossLoss[i]=0.0;
      g_attrBuyTrades[i]=0; g_attrSellTrades[i]=0;
      g_attrBuyWins[i]=0; g_attrSellWins[i]=0;
      g_attrBuyNet[i]=0.0; g_attrSellNet[i]=0.0;
   }
   g_attrUnknown=0;
}

int StrategyIdFromComment(string c)
{
   // MT4/broker comments can be truncated. Keep strategy identifier first.
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      string token="S="+StrategyName(i);
      if(StringFind(c,token,0)==0 || StringFind(c,token,0)>=0) return i;
   }
   return -1;
}

void AttributeClosedTrades()
{
   ResetAttribution();
   int total=OrdersHistoryTotal();
   for(int p=total-1;p>=0;p--)
   {
      if(!OrderSelect(p,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderSymbol()!=Symbol() || OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      int id=StrategyIdFromComment(OrderComment());
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      if(id<0){g_attrUnknown++;continue;}
      g_attrTrades[id]++;
      g_attrNet[id]+=net;
      if(type==OP_BUY){g_attrBuyTrades[id]++;g_attrBuyNet[id]+=net;}
      else if(type==OP_SELL){g_attrSellTrades[id]++;g_attrSellNet[id]+=net;}
      if(net>0)
      {
         g_attrWins[id]++; g_attrGrossProfit[id]+=net;
         if(type==OP_BUY) g_attrBuyWins[id]++; else if(type==OP_SELL) g_attrSellWins[id]++;
      }
      else
      {
         g_attrLosses[id]++; g_attrGrossLoss[id]+=net;
      }
   }
}

void PrintAttribution()
{
   AttributeClosedTrades();
   Print("=== V2.64.7 STRATEGY ATTRIBUTION ===");
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      double wr=(g_attrTrades[i]>0?100.0*g_attrWins[i]/g_attrTrades[i]:0.0);
      double pf=(g_attrGrossLoss[i]<0?g_attrGrossProfit[i]/MathAbs(g_attrGrossLoss[i]):0.0);
      double ex=(g_attrTrades[i]>0?g_attrNet[i]/g_attrTrades[i]:0.0);
      Print("ATTR | ",StrategyName(i),
            " trades=",g_attrTrades[i],
            " wins=",g_attrWins[i],
            " losses=",g_attrLosses[i],
            " winRate=",DoubleToString(wr,2),
            " PF=",DoubleToString(pf,3),
            " net=",DoubleToString(g_attrNet[i],2),
            " expectancy=",DoubleToString(ex,4));
      double buyWR=(g_attrBuyTrades[i]>0?100.0*g_attrBuyWins[i]/g_attrBuyTrades[i]:0.0);
      double sellWR=(g_attrSellTrades[i]>0?100.0*g_attrSellWins[i]/g_attrSellTrades[i]:0.0);
      Print("ATTR-DIR | ",StrategyName(i),
            " BUY trades=",g_attrBuyTrades[i]," wins=",g_attrBuyWins[i],
            " winRate=",DoubleToString(buyWR,2)," net=",DoubleToString(g_attrBuyNet[i],2),
            " | SELL trades=",g_attrSellTrades[i]," wins=",g_attrSellWins[i],
            " winRate=",DoubleToString(sellWR,2)," net=",DoubleToString(g_attrSellNet[i],2));
   }
   Print("ATTR | UNKNOWN=",g_attrUnknown);
}

void WriteAttributionCSV()
{
   if(!InpAutoReport)return;
   string f="Bitey_AI_Strategy_Attribution_v2.64.7.csv";
   int h=FileOpen(f,FILE_CSV|FILE_WRITE|FILE_SHARE_READ,';');
   if(h==INVALID_HANDLE)return;
   FileWrite(h,"strategy","trades","wins","losses","win_rate","profit_factor","net","expectancy","buy_trades","buy_wins","buy_win_rate","buy_net","sell_trades","sell_wins","sell_win_rate","sell_net");
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      double wr=(g_attrTrades[i]>0?100.0*g_attrWins[i]/g_attrTrades[i]:0.0);
      double pf=(g_attrGrossLoss[i]<0?g_attrGrossProfit[i]/MathAbs(g_attrGrossLoss[i]):0.0);
      double ex=(g_attrTrades[i]>0?g_attrNet[i]/g_attrTrades[i]:0.0);
      FileWrite(h,StrategyName(i),g_attrTrades[i],g_attrWins[i],g_attrLosses[i],
         DoubleToString(wr,2),DoubleToString(pf,3),DoubleToString(g_attrNet[i],2),DoubleToString(ex,4),
         g_attrBuyTrades[i],g_attrBuyWins[i],DoubleToString(g_attrBuyTrades[i]>0?100.0*g_attrBuyWins[i]/g_attrBuyTrades[i]:0.0,2),DoubleToString(g_attrBuyNet[i],2),
         g_attrSellTrades[i],g_attrSellWins[i],DoubleToString(g_attrSellTrades[i]>0?100.0*g_attrSellWins[i]/g_attrSellTrades[i]:0.0,2),DoubleToString(g_attrSellNet[i],2));
   }
   FileWrite(h,"UNKNOWN",g_attrUnknown,0,0,"0","0","0","0");
   FileClose(h);
}

void WriteAttributionFile()
{
   if(!InpAutoReport)return;
   string f="Bitey_AI_Strategy_Attribution_v2.64.7.tch";
   int h=FileOpen(f,FILE_TXT|FILE_WRITE|FILE_SHARE_READ);
   if(h==INVALID_HANDLE)return;
   FileWrite(h,"BITEY_STRATEGY_ATTRIBUTION_V2.64.7");
   FileWrite(h,"symbol="+Symbol());
   FileWrite(h,"timeframe="+TFName());
   FileWrite(h,"note=closed trades attributed by MT4 order comment; diagnostic attribution, not proof of future performance");
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      double wr=(g_attrTrades[i]>0?100.0*g_attrWins[i]/g_attrTrades[i]:0.0);
      double pf=(g_attrGrossLoss[i]<0?g_attrGrossProfit[i]/MathAbs(g_attrGrossLoss[i]):0.0);
      double ex=(g_attrTrades[i]>0?g_attrNet[i]/g_attrTrades[i]:0.0);
      FileWrite(h,"strategy="+StrategyName(i)+"|trades="+IntegerToString(g_attrTrades[i])+"|wins="+IntegerToString(g_attrWins[i])+"|losses="+IntegerToString(g_attrLosses[i])+"|win_rate="+DoubleToString(wr,2)+"|profit_factor="+DoubleToString(pf,3)+"|net="+DoubleToString(g_attrNet[i],2)+"|expectancy="+DoubleToString(ex,4)+"|buy_trades="+IntegerToString(g_attrBuyTrades[i])+"|buy_wins="+IntegerToString(g_attrBuyWins[i])+"|buy_net="+DoubleToString(g_attrBuyNet[i],2)+"|sell_trades="+IntegerToString(g_attrSellTrades[i])+"|sell_wins="+IntegerToString(g_attrSellWins[i])+"|sell_net="+DoubleToString(g_attrSellNet[i],2));
   }
   FileWrite(h,"unknown_strategy_trades="+IntegerToString(g_attrUnknown));
   FileClose(h);
}

void WriteReport(double confidence,int direction,string reason)
{
   if(!InpAutoReport)return;
   int h=FileOpen(InpReportFile,FILE_TXT|FILE_WRITE|FILE_SHARE_READ);if(h==INVALID_HANDLE)return;
   FileWrite(h,"BITEY_AI_TRADING_REPORT_V2.64.7_TRADE_FORENSICS");
   FileWrite(h,"time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   FileWrite(h,"symbol="+Symbol());FileWrite(h,"timeframe="+TFName());FileWrite(h,"regime="+RegimeName(g_regime));
   FileWrite(h,"hurst="+DoubleToString(HurstApprox(1),5));FileWrite(h,"best_strategy="+(g_best>=0?StrategyName(g_best):"NONE"));
   FileWrite(h,"direction="+IntegerToString(direction));FileWrite(h,"selected_strategy="+(g_selectedStrategy>=0?StrategyName(g_selectedStrategy):"NONE"));FileWrite(h,"confidence="+DoubleToString(confidence,5));FileWrite(h,"reason="+reason);
   for(int i=0;i<STRATEGY_COUNT;i++)FileWrite(h,"strategy="+StrategyName(i)+"|evidence="+DoubleToString(StrategyEvidence(i),4)+"|regime_compatible="+(StrategyRegimeCompatible(i)?"true":"false")+"|trades="+IntegerToString(g_audit[i].trades)+"|win_rate="+DoubleToString(g_audit[i].winRate,2)+"|profit_factor="+DoubleToString(g_audit[i].profitFactor,4)+"|expectancy="+DoubleToString(g_audit[i].expectancy,5)+"|drawdown="+DoubleToString(g_audit[i].maxDrawdown,4)+"|consecutive_losses="+IntegerToString(g_audit[i].maxConsecutiveLosses)+"|score="+DoubleToString(g_audit[i].score,4));
   double reportSpread=(Ask-Bid)/Point;
   int reportRb=RegimeBucket(g_regime);
   FileWrite(h,"regime_bucket="+IntegerToString(reportRb));
   if(reportRb>=0)
   {
      for(int ri=0;ri<STRATEGY_COUNT;ri++)
      {
         StrategyAudit rx=g_regimeAudit[ri][reportRb];
         FileWrite(h,"regime_strategy="+StrategyName(ri)+"|regime="+RegimeBucketName(reportRb)+"|trades="+IntegerToString(rx.trades)+"|win_rate="+DoubleToString(rx.winRate,2)+"|profit_factor="+DoubleToString(rx.profitFactor,4)+"|expectancy="+DoubleToString(rx.expectancy,5)+"|drawdown="+DoubleToString(rx.maxDrawdown,4)+"|consecutive_losses="+IntegerToString(rx.maxConsecutiveLosses)+"|score="+DoubleToString(rx.score,4));
      }
   }
   FileWrite(h,"execution_enabled="+(ExecutionAllowed()?"true":"false"));
   FileWrite(h,"live_trading_enabled="+(InpEnableTrading?"true":"false"));
   FileWrite(h,"backtest_execution_enabled="+(InpBacktestExecution?"true":"false"));
   FileWrite(h,"tester_spread_points="+DoubleToString(reportSpread,1));
   FileWrite(h,"synthetic_spread_gate="+(InpUseSyntheticSpreadForGate?"true":"false"));
   FileWrite(h,"effective_spread_points="+DoubleToString(InpUseSyntheticSpreadForGate?InpSyntheticSpreadPoints:reportSpread,1));
   FileWrite(h,"effective_spread_pips="+DoubleToString((InpUseSyntheticSpreadForGate?InpSyntheticSpreadPoints:reportSpread)/10.0,2));
   FileWrite(h,"spread_points="+DoubleToString(reportSpread,1));
   FileWrite(h,"min_spread_points="+IntegerToString(InpMinSpreadPoints));
   FileWrite(h,"min_spread_filter="+(InpUseMinSpreadFilter?"true":"false"));
   FileWrite(h,"max_spread_filter="+(InpUseMaxSpreadFilter?"true":"false"));
   FileWrite(h,"spread_atr_filter="+(InpUseSpreadATRFilter?"true":"false"));
   FileWrite(h,"max_spread_points="+IntegerToString(InpMaxSpreadPoints));
   FileWrite(h,"evidence_calibration_fallback="+(InpEvidenceCalibrationFallback?"true":"false"));
   FileWrite(h,"evidence_calibration_min_score="+DoubleToString(InpFallbackMinScore,3));
   FileWrite(h,"spread_blocked_low="+IntegerToString(g_spreadBlockedLow));
   FileWrite(h,"spread_blocked_high="+IntegerToString(g_spreadBlockedHigh));
   FileWrite(h,"spread_blocked_atr="+IntegerToString(g_spreadBlockedATR));
   FileWrite(h,"risk_gate_blocked="+IntegerToString(g_riskBlocked));
   FileWrite(h,"---diagnostics---");
   FileWrite(h,"bars_processed="+IntegerToString(g_barsProcessed));
   FileWrite(h,"entries_accepted="+IntegerToString(g_entriesAccepted));
   FileWrite(h,"blocked_spread_low="+IntegerToString(g_spreadBlockedLow));
   FileWrite(h,"blocked_spread_high="+IntegerToString(g_spreadBlockedHigh));
   FileWrite(h,"blocked_spread_atr="+IntegerToString(g_spreadBlockedATR));
   FileWrite(h,"blocked_atr="+IntegerToString(g_blockedATR));
   FileWrite(h,"blocked_session="+IntegerToString(g_blockedSession));
   FileWrite(h,"blocked_daily_loss="+IntegerToString(g_blockedDailyLoss));
   FileWrite(h,"blocked_max_trades="+IntegerToString(g_blockedMaxTrades));
   FileWrite(h,"blocked_cooldown="+IntegerToString(g_blockedCooldown));
   FileWrite(h,"no_signal="+IntegerToString(g_noSignal));
   FileWrite(h,"low_confidence="+IntegerToString(g_lowConfidence));
   FileWrite(h,"ordersend_failed="+IntegerToString(g_orderSendFailed));
   FileWrite(h,"order_attempts="+IntegerToString(g_orderAttempts));
   FileWrite(h,"blocked_execution="+IntegerToString(g_blockedExecution));
   FileWrite(h,"blocked_lot="+IntegerToString(g_blockedLot));
   FileWrite(h,"blocked_atr_execution="+IntegerToString(g_blockedATRExec));
   FileWrite(h,"evidence_rejected="+IntegerToString(g_evidenceRejected));
   FileWrite(h,"regime_rejected="+IntegerToString(g_regimeRejected));
   FileWrite(h,"consensus_rejected="+IntegerToString(g_consensusRejected));
   FileWrite(h,"cooldown_rejected="+IntegerToString(g_cooldownRejected));
   FileWrite(h,"pipeline_signals="+IntegerToString(g_pipelineSignals));
   FileWrite(h,"pipeline_after_confidence="+IntegerToString(g_pipelineAfterConfidence));
   FileWrite(h,"pipeline_after_spread="+IntegerToString(g_pipelineAfterSpread));
   FileWrite(h,"consensus_accepted="+IntegerToString(g_consensusAccepted));
   for(int j=0;j<STRATEGY_COUNT;j++)FileWrite(h,"strategy_probe="+StrategyName(j)+"|historical_signals="+IntegerToString(g_strategySignals[j])+"|current_signal="+IntegerToString(g_strategyCurrentSignals[j]));
   FileClose(h);
}

void WriteCSV(double confidence,int direction)
{
   int h=FileOpen(InpCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');if(h==INVALID_HANDLE)return;
   if(FileSize(h)==0)FileWrite(h,"time","symbol","tf","regime","hurst","best","direction","confidence","trades","win_rate","profit_factor","expectancy","drawdown","score");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),TFName(),RegimeName(g_regime),DoubleToString(HurstApprox(1),4),g_best>=0?StrategyName(g_best):"NONE",direction,DoubleToString(confidence,4),g_best>=0?g_audit[g_best].trades:0,g_best>=0?DoubleToString(g_audit[g_best].winRate,2):"0",g_best>=0?DoubleToString(g_audit[g_best].profitFactor,3):"0",g_best>=0?DoubleToString(g_audit[g_best].expectancy,4):"0",g_best>=0?DoubleToString(g_audit[g_best].maxDrawdown,3):"0",g_best>=0?DoubleToString(g_audit[g_best].score,3):"0");
   FileClose(h);
}

void SendSBT(double confidence,int direction,string reason)
{
   if(!InpSBTReport)return;
   string headers="Content-Type: application/json\r\n";if(InpSBTToken!="")headers+="X-MT4-Token: "+InpSBTToken+"\r\n";
   string body="{";body+="\"source\":\"AI_Trading_Bot_v2.33_RegimeEvidence\",";body+="\"symbol\":\""+Symbol()+"\",";body+="\"timeframe\":\""+TFName()+"\",";body+="\"regime\":\""+RegimeName(g_regime)+"\",";body+="\"hurst\":"+DoubleToString(HurstApprox(1),5)+",";body+="\"best_strategy\":\""+(g_best>=0?StrategyName(g_best):"NONE")+"\",";body+="\"best_score\":"+DoubleToString(g_best>=0?g_audit[g_best].score:0,5)+",";body+="\"confidence\":"+DoubleToString(confidence,5)+",";body+="\"direction\":"+IntegerToString(direction)+",";body+="\"execution_enabled\":"+(InpEnableTrading?"true":"false")+",";body+="\"reason\":\""+reason+"\",\"report_type\":\"adaptive_snapshot\"}";
   char data[],result[];string resultHeaders="";StringToCharArray(body,data,0,StringLen(body),CP_UTF8);ResetLastError();
   int code=WebRequest("POST",InpSBTEndpoint,headers,5000,data,result,resultHeaders);
   if(code<200||code>=300)Print("SBT report unavailable HTTP=",code," error=",GetLastError());
}

void UpdatePanel(double confidence,int direction,string reason)
{
   string s="BITEY IA TRADING BOT v2.64.7 TRADE FORENSICS\n";
   s+="================================\n";
   s+="Symbol: "+Symbol()+"  TF: "+TFName()+"\n";
   s+="Regime: "+RegimeName(g_regime)+"  Hurst="+DoubleToString(HurstApprox(1),3)+"\n";
   s+="Tester spread: "+DoubleToString((Ask-Bid)/Point,1)+" pts ("+DoubleToString(((Ask-Bid)/Point)/10.0,2)+" pips) | Effective gate: "+DoubleToString(InpUseSyntheticSpreadForGate?InpSyntheticSpreadPoints:(Ask-Bid)/Point,1)+" pts | Min="+IntegerToString(InpMinSpreadPoints)+" "+(InpUseMinSpreadFilter?"ON":"OFF")+" | Max="+IntegerToString(InpMaxSpreadPoints)+" "+(InpUseMaxSpreadFilter?"ON":"OFF")+" | S/ATR="+(InpUseSpreadATRFilter?"ON":"OFF")+"\n";
   s+="Best: "+(g_best>=0?StrategyName(g_best):"NONE")+" | Dir="+(direction>0?"BUY":direction<0?"SELL":"HOLD")+" | Conf="+DoubleToString(confidence*100,1)+"%\n";
   s+="Pipeline: signals="+IntegerToString(g_pipelineSignals)+" confidence="+IntegerToString(g_pipelineAfterConfidence)+" spread="+IntegerToString(g_pipelineAfterSpread)+" consensus="+IntegerToString(g_consensusAccepted)+"\n";
   s+="Blocks: lowSpread="+IntegerToString(g_spreadBlockedLow)+" highSpread="+IntegerToString(g_spreadBlockedHigh)+" spreadATR="+IntegerToString(g_spreadBlockedATR)+" ATR="+IntegerToString(g_blockedATR)+" session="+IntegerToString(g_blockedSession)+" maxTrades="+IntegerToString(g_blockedMaxTrades)+"\n";
   s+="Evidence: rejected="+IntegerToString(g_evidenceRejected)+" consensus="+IntegerToString(g_consensusRejected)+" cooldown="+IntegerToString(g_cooldownRejected)+" min="+DoubleToString(InpMinEvidenceScore,2)+" fallback="+(InpEvidenceCalibrationFallback?"ON":"OFF")+"\n";
   s+="Signals: noSignal="+IntegerToString(g_noSignal)+" lowConfidence="+IntegerToString(g_lowConfidence)+"\n";
   s+="Current regime evidence:\n";
   int prb=RegimeBucket(g_regime);
   if(prb>=0)
   {
      for(int pi=0;pi<STRATEGY_COUNT;pi++)
      {
         StrategyAudit px=g_regimeAudit[pi][prb];
         s+=StrategyName(pi)+" | RegT="+IntegerToString(px.trades)+" | RegPF="+DoubleToString(px.profitFactor,2)+" | RegE="+DoubleToString(px.expectancy,3)+" | RegS="+DoubleToString(px.score,2)+"\n";
      }
   }
   s+="--------------------------------\n";
   for(int i=0;i<STRATEGY_COUNT;i++)
      s+=StrategyName(i)+" | HistSig="+IntegerToString(g_strategySignals[i])+" | Now="+(g_strategyCurrentSignals[i]>0?"BUY":g_strategyCurrentSignals[i]<0?"SELL":"-")+" | T="+IntegerToString(g_audit[i].trades)+" | PF="+DoubleToString(g_audit[i].profitFactor,2)+" | E="+DoubleToString(g_audit[i].expectancy,3)+"\n";
   s+="--------------------------------\n";
   s+=reason+"\n";
   Comment(s);
}


void ResetDecisionSnapshot()
{
   g_decision.time=TimeCurrent();g_decision.direction=0;g_decision.selectedStrategy=-1;
   g_decision.buyVotes=0;g_decision.sellVotes=0;g_decision.buyWeight=0;g_decision.sellWeight=0;
   g_decision.consensus=0;g_decision.confidence=0;g_decision.evidence=0;g_decision.directionalScore=0;
   g_decision.atrPoints=ATRPoints(1);g_decision.adx=ADX(1);g_decision.rsi=RSI(1);
   g_decision.realSpreadPoints=(Point>0?(Ask-Bid)/Point:0);
   g_decision.gateSpreadPoints=InpUseSyntheticSpreadForGate?InpSyntheticSpreadPoints:g_decision.realSpreadPoints;
   g_decision.bodyRatio=0;g_decision.stopLevelPoints=MarketInfo(Symbol(),MODE_STOPLEVEL);g_decision.slPoints=0;g_decision.tpPoints=0;
   g_decision.signalGate=false;g_decision.adaptiveGate=false;g_decision.spreadGate=false;g_decision.riskGate=false;g_decision.stopGate=false;
   g_decision.orderAttempt=false;g_decision.orderTicket=-1;g_decision.orderError=0;
   g_decision.decision="INIT";g_decision.rejectReason="";
}

void CaptureDecisionMetrics(int direction,double confidence,string reason)
{
   ResetDecisionSnapshot();
   g_decision.direction=direction;g_decision.selectedStrategy=g_selectedStrategy;g_decision.confidence=confidence;
   g_decision.signalGate=(direction!=0);
   g_cachedDirection=direction;g_cachedConfidence=confidence;g_cachedReason=reason;
   int active=0;
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      if(sig==0) continue;
      active++;
      double ev=StrategyEvidence(i);
      double factor=(InpRequireRegimeCompatibility && !StrategyRegimeCompatible(i))?0.55:1.0;
      double w=(0.35+0.65*ev)*StrategyWeight(i,g_regime)*factor;
      if(sig>0){g_decision.buyVotes++;g_decision.buyWeight+=w;}
      else {g_decision.sellVotes++;g_decision.sellWeight+=w;}
   }
   double total=g_decision.buyWeight+g_decision.sellWeight;
   double win=(direction>0?g_decision.buyWeight:g_decision.sellWeight);
   g_decision.consensus=(total>0?win/total:0);
   if(g_selectedStrategy>=0) g_decision.evidence=StrategyEvidence(g_selectedStrategy);
   double atr=ATR(1);
   double emaDelta=EMA(InpFastEMA,1)-EMA(InpSlowEMA,1);
   double momentum=(Bars>4?Close[1]-Close[4]:0);
   double dirTrend=(atr>0?direction*emaDelta/atr:0);
   double dirMomentum=(atr>0?direction*momentum/atr:0);
   double r=RSI(1);
   double rsiFit=(direction>0?(r-50.0)/25.0:(50.0-r)/25.0);
   double adxFit=ADX(1)/35.0;
   g_decision.directionalScore=MathMax(-1.0,MathMin(1.0,0.40*dirTrend+0.30*dirMomentum+0.20*rsiFit+0.10*adxFit));
   if(direction!=0 && g_decision.decision=="INIT") g_decision.decision="SIGNAL";
   if(direction==0 && reason!="") g_decision.decision=(active==0?"NO_SIGNAL":"SIGNAL_BLOCK");
   g_decision.rejectReason=reason;
}

void WriteFunnelCSV()
{
   if(!InpDiagnosticFunnel) return;
   int h=FileOpen(InpFunnelCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE)return;
   if(FileSize(h)==0)
      FileWrite(h,"time","symbol","tf","regime","direction","selected_strategy","buy_votes","sell_votes","buy_weight","sell_weight","consensus","confidence","evidence","selection_score","selection_expectancy","selection_pf_factor","selection_expectancy_factor","directional_score","adx","rsi","atr_points","real_spread_points","gate_spread_points","body_ratio","stop_level_points","sl_points","tp_points","signal_gate","adaptive_gate","spread_gate","risk_gate","stop_gate","order_attempt","order_ticket","order_error","decision","reject_reason");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(g_decision.time,TIME_DATE|TIME_SECONDS),Symbol(),TFName(),RegimeName(g_regime),g_decision.direction,
      g_decision.selectedStrategy>=0?StrategyName(g_decision.selectedStrategy):"NONE",g_decision.buyVotes,g_decision.sellVotes,
      DoubleToString(g_decision.buyWeight,5),DoubleToString(g_decision.sellWeight,5),DoubleToString(g_decision.consensus,5),
      DoubleToString(g_decision.confidence,5),DoubleToString(g_decision.evidence,5),DoubleToString(g_lastSelectionScore,5),DoubleToString(g_lastSelectionExpectancy,5),DoubleToString(g_lastSelectionPFFactor,5),DoubleToString(g_lastSelectionExpectancyFactor,5),DoubleToString(g_decision.directionalScore,5),
      DoubleToString(g_decision.adx,3),DoubleToString(g_decision.rsi,3),DoubleToString(g_decision.atrPoints,2),
      DoubleToString(g_decision.realSpreadPoints,2),DoubleToString(g_decision.gateSpreadPoints,2),DoubleToString(g_decision.bodyRatio,4),
      DoubleToString(g_decision.stopLevelPoints,2),DoubleToString(g_decision.slPoints,2),DoubleToString(g_decision.tpPoints,2),
      g_decision.signalGate,g_decision.adaptiveGate,g_decision.spreadGate,g_decision.riskGate,g_decision.stopGate,
      g_decision.orderAttempt,g_decision.orderTicket,g_decision.orderError,g_decision.decision,g_decision.rejectReason);
   FileClose(h);
}

void WriteDecisionAudit(int direction,double confidence,string reason)
{
   if(!InpDecisionAudit) return;
   if(g_decisionAuditRows>=InpDecisionAuditMaxRows) return;

   string file="Bitey_v2.64.7_DecisionAudit.csv";
   int h=FileOpen(file,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) return;
   if(FileSize(h)==0)
   {
      FileWrite(h,"time","symbol","tf","regime","hurst","direction","selected",
                "confidence","reason","global_trades","global_pf","global_expectancy",
                "regime_trades","regime_pf","regime_expectancy","combined_evidence",
                "strategy_0","strategy_1","strategy_2","strategy_3","strategy_4","strategy_5","strategy_6","strategy_7");
   }
   FileSeek(h,0,SEEK_END);

   int rb=RegimeBucket(g_regime);
   int sid=g_selectedStrategy;
   double combined=(sid>=0?StrategyEvidence(sid):0.0);
   int rgTrades=0; double rgPF=0.0,rgExp=0.0;
   if(sid>=0 && rb>=0)
   {
      StrategyAudit rx=g_regimeAudit[sid][rb];
      rgTrades=rx.trades; rgPF=rx.profitFactor; rgExp=rx.expectancy;
   }

   string cells[8];
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      double ev=StrategyEvidence(i);
      double factor=1.0;
      if(InpRequireRegimeCompatibility && !StrategyRegimeCompatible(i)) factor=0.55;
      double weight=(0.35+0.65*ev)*StrategyWeight(i,g_regime)*factor;
      int rt=0; double rpf=0.0,re=0.0;
      if(rb>=0)
      {
         StrategyAudit ra=g_regimeAudit[i][rb];
         rt=ra.trades; rpf=ra.profitFactor; re=ra.expectancy;
      }
      cells[i]=StrategyName(i)+"|sig="+IntegerToString(sig)+"|ev="+DoubleToString(ev,3)+
               "|w="+DoubleToString(weight,3)+"|rt="+IntegerToString(rt)+
               "|rpf="+DoubleToString(rpf,2)+"|re="+DoubleToString(re,3)+
               (i==sid?"|SELECTED":"|ALT");
   }

   FileWrite(h,
      TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),TFName(),RegimeName(g_regime),
      DoubleToString(HurstApprox(1),4),direction,
      sid>=0?StrategyName(sid):"NONE",DoubleToString(confidence,4),reason,
      sid>=0?g_audit[sid].trades:0,sid>=0?DoubleToString(g_audit[sid].profitFactor,4):"0",
      sid>=0?DoubleToString(g_audit[sid].expectancy,4):"0",
      rgTrades,DoubleToString(rgPF,4),DoubleToString(rgExp,4),DoubleToString(combined,4),
      cells[0],cells[1],cells[2],cells[3],cells[4],cells[5],cells[6],cells[7]);
   FileClose(h);
   g_decisionAuditRows++;
}

void PrintDecisionAuditSnapshot(int direction,double confidence,string reason)
{
   if(!InpDecisionAudit || !InpPrintAuditTable) return;
   Print("=== V2.64.7 DECISION AUDIT | REGIME=",RegimeName(g_regime),
         " | selected=",(g_selectedStrategy>=0?StrategyName(g_selectedStrategy):"NONE"),
         " | direction=",direction,
         " | confidence=",DoubleToString(confidence,3)," ===");
   int rb=RegimeBucket(g_regime);
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      double ev=StrategyEvidence(i);
      double factor=(InpRequireRegimeCompatibility && !StrategyRegimeCompatible(i))?0.55:1.0;
      double weight=(0.35+0.65*ev)*StrategyWeight(i,g_regime)*factor;
      StrategyAudit ga=g_audit[i];
      StrategyAudit ra;
      ResetAudit(ra);
      if(rb>=0) ra=g_regimeAudit[i][rb];
      Print("DECISION ALT | ",StrategyName(i),
            " sig=",sig,
            " selected=",(i==g_selectedStrategy?"true":"false"),
            " globalT=",ga.trades," globalPF=",DoubleToString(ga.profitFactor,3),
            " globalE=",DoubleToString(ga.expectancy,4),
            " regimeT=",ra.trades," regimePF=",DoubleToString(ra.profitFactor,3),
            " regimeE=",DoubleToString(ra.expectancy,4),
            " evidence=",DoubleToString(ev,3)," weight=",DoubleToString(weight,3));
   }
   Print("DECISION REASON | ",reason);
}

int OnInit()
{
   Print("=== BITEY v2.64.7 TRADE FORENSICS ===");
   Print("DIAG CONFIG | AdaptiveEntry=",InpAdaptiveEntry," Consensus=",InpRequireSignalConsensus," MinConfidence=",DoubleToString(InpMinConfidence,3)," MinEvidence=",DoubleToString(InpMinEvidenceScore,3)," SyntheticSpread=",DoubleToString(InpSyntheticSpreadPoints,1));
   g_dayOfYear=TimeDayOfYear(TimeCurrent());g_dayStartEquity=AccountEquity();g_regime=DetectRegime();AuditAll();ProbeStrategies();
   if(IsTesting() && InpUseSyntheticSpreadForGate)
      Print("WARNING: synthetic spread affects FILTERS only. OrderSend/PnL still use tester Bid/Ask. Set Tester Spread to a fixed value for clean performance comparison.");
   Print("Bitey IA v2.64.7 initialized. RawPipelineProbe=",InpRawPipelineProbe," Best=",g_best>=0?StrategyName(g_best):"NONE"," Regime=",RegimeName(g_regime));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   PrintAttribution();
   WriteAttributionFile();
   WriteAttributionCSV();
   Print("=== BITEY v2.64.7 STRATEGY ATTRIBUTION SUMMARY ===");
   Print("Bars processed=",g_barsProcessed," RawProbeAccepted=",g_rawProbeAccepted," Entries accepted=",g_entriesAccepted," RiskGateRejected=",g_riskGateRejected," OrderAttempts=",g_orderAttempts," OrderSend failed=",g_orderSendFailed);
   Print("RAW SIGNAL COUNTS: ",StrategyName(0),"=",g_strategySignals[0]," ",StrategyName(1),"=",g_strategySignals[1]," ",StrategyName(2),"=",g_strategySignals[2]," ",StrategyName(3),"=",g_strategySignals[3]," ",StrategyName(4),"=",g_strategySignals[4]," ",StrategyName(5),"=",g_strategySignals[5]," ",StrategyName(6),"=",g_strategySignals[6]," ",StrategyName(7),"=",g_strategySignals[7]);
   Print("Spread low=",g_spreadBlockedLow," high=",g_spreadBlockedHigh," spread/ATR=",g_spreadBlockedATR," ATR=",g_blockedATR);
   Print("Session=",g_blockedSession," DailyLoss=",g_blockedDailyLoss," MaxTrades=",g_blockedMaxTrades," Cooldown=",g_blockedCooldown);
   Print("EvidenceRejected=",g_evidenceRejected," ConsensusRejected=",g_consensusRejected," CooldownRejected=",g_cooldownRejected);
   Print("NoSignal=",g_noSignal," LowConfidence=",g_lowConfidence);
   Print("Pipeline signals=",g_pipelineSignals," after confidence=",g_pipelineAfterConfidence," after spread=",g_pipelineAfterSpread," rawProbeAccepted=",g_rawProbeAccepted);
   for(int i=0;i<STRATEGY_COUNT;i++) Print("Strategy ",StrategyName(i)," historicalSignals=",g_strategySignals[i]," currentSignal=",g_strategyCurrentSignals[i]);
   Print("FUNNEL | riskGatePassed=",g_riskGatePassed," orderSuccess=",g_orderSuccess," adaptiveBlocks=",g_blockedAdaptive," candleBlocks=",g_blockedCandle," geometryBlocks=",g_blockedGeometry," stopLevelBlocks=",g_blockedStopLevel," confidenceBlocks=",g_blockedConfidence," directionBlocks=",g_blockedDirection);
   double avgSpread=(g_realSpreadSamples>0?g_realSpreadSum/g_realSpreadSamples:0.0);
   double minSpread=(g_realSpreadSamples>0?g_realSpreadMin:0.0);
   Print("SPREAD TELEMETRY | samples=",g_realSpreadSamples," avg=",DoubleToString(avgSpread,2)," min=",DoubleToString(minSpread,2)," max=",DoubleToString(g_realSpreadMax,2)," gate=",(InpUseSyntheticSpreadForGate?"SYNTHETIC":"REAL")," gate_value=",DoubleToString(InpUseSyntheticSpreadForGate?InpSyntheticSpreadPoints:avgSpread,2));
   Print("ATTRIBUTION FILE | Bitey_AI_Strategy_Attribution_v2.64.7.csv");
   Comment("");
}

void OnTick()
{
   if(Bars<300)return;
   if(!NewBar())return;
   g_barsProcessed++;
   g_regime=DetectRegime();
   if(g_lastAuditBars<0||MathAbs(Bars-g_lastAuditBars)>=InpAuditRefreshBars)AuditAll();
   ProbeStrategies();

   // Single-pass signal evaluation for this bar. AdaptiveEntryAllowed() consumes
   // the cached result instead of calling LocalAISignal() a second time.
   double confidence=0;string reason="";
   int direction=LocalAISignal(confidence,reason);
   CaptureDecisionMetrics(direction,confidence,reason);
   if(direction!=0) g_pipelineSignals++;

   if(direction!=0) ExecuteTrade(direction);
   if(direction==0) g_decision.decision=(g_decision.decision=="INIT"?"NO_SIGNAL":g_decision.decision);

   WriteDecisionAudit(direction,confidence,reason);
   WriteFunnelCSV();
   WriteReport(confidence,direction,reason);
   WriteCSV(confidence,direction);
   SendSBT(confidence,direction,reason);
   UpdatePanel(confidence,direction,reason);
   if(InpDecisionAudit && InpPrintAuditTable) PrintDecisionAuditSnapshot(direction,confidence,reason);
}

//+------------------------------------------------------------------+
