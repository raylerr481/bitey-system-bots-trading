//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.03_EntryProbe8.mq4                              |
//| Bitey IA - Adaptive 8 Strategy MT4 Expert Advisor               |
//| Local AI-style engine: regime + strategy spectrum + risk gate   |
//| Optional read-only Web AI/SBT integration                       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.05"
#property description "Adaptive 8-strategy AI-style MT4 Expert Advisor"
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
input double InpMinATRPoints=20.0;
input bool InpUseMinSpreadFilter=true;
input bool InpUseMaxSpreadFilter=true;
input bool InpUseSpreadATRFilter=true;
input int InpMinSpreadPoints=8;
input int InpMaxSpreadPoints=30;
input bool InpDiagnosticMode=true;
input bool InpDiagnosticPrintBlocks=true;
input bool InpRejectZeroSpread=true;
input double InpMaxSpreadATR=0.20;
input double InpMinConfidence=0.45;
input int InpMinConsensusVotes=1;
input bool InpUseEnsemble=true;
input int InpSessionStart=7;
input int InpSessionEnd=20;
input int InpAuditRefreshBars=20;
input int InpMinAuditTrades=10;
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

StrategyAudit g_audit[STRATEGY_COUNT];
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
int g_orderSendFailed=0;
int g_strategySignals[STRATEGY_COUNT];
int g_strategyCurrentSignals[STRATEGY_COUNT];
int g_pipelineSignals=0;
int g_consensusAccepted=0;
int g_pipelineAfterSpread=0;
int g_pipelineAfterConfidence=0;
int g_barsProcessed=0;
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

void AuditStrategy(int id)
{
   StrategyAudit a;
   a.trades=0;a.wins=0;a.losses=0;a.net=0;a.grossProfit=0;a.grossLoss=0;a.winRate=0;a.profitFactor=0;a.expectancy=0;a.avgWin=0;a.avgLoss=0;a.maxDrawdown=0;a.maxConsecutiveLosses=0;a.payoff=0;a.score=-999;
   int maxBars=MathMin(InpLookback,Bars-InpAuditHorizon-5);
   if(maxBars<100){g_audit[id]=a;return;}
   double eq=0,peak=0;int cons=0;
   for(int s=maxBars;s>=InpAuditHorizon+2;s--)
   {
      int sig=StrategySignal(id,s); if(sig==0)continue;
      double atr=iATR(Symbol(),Period(),InpATRPeriod,s); if(atr<=0)continue;
      double r=0; SimulatedTrade(sig,s,InpAuditHorizon,atr*InpSL_ATR,atr*InpTP_ATR,r);
      a.trades++;a.net+=r;eq+=r;if(eq>peak)peak=eq;if(peak-eq>a.maxDrawdown)a.maxDrawdown=peak-eq;
      if(r>0){a.wins++;a.grossProfit+=r;cons=0;}else{a.losses++;a.grossLoss+=r;cons++;if(cons>a.maxConsecutiveLosses)a.maxConsecutiveLosses=cons;}
   }
   if(a.trades>0){a.winRate=100.0*a.wins/a.trades;a.expectancy=a.net/a.trades;}
   if(a.grossLoss<0)a.profitFactor=a.grossProfit/MathAbs(a.grossLoss);
   if(a.wins>0)a.avgWin=a.grossProfit/a.wins;
   if(a.losses>0)a.avgLoss=a.grossLoss/a.losses;
   if(a.losses>0)a.payoff=a.avgWin/MathAbs(a.avgLoss);
   if(a.trades>=InpMinAuditTrades)
   {
      double pf=MathMin(a.profitFactor,4.0)/4.0;
      double ex=(MathMax(-2.0,MathMin(2.0,a.expectancy))+2.0)/4.0;
      double dd=1.0-MathMin(a.maxDrawdown/10.0,1.0);
      double lc=1.0-MathMin(a.maxConsecutiveLosses/10.0,1.0);
      double sample=MathMin(1.0,a.trades/50.0);
      a.score=(55.0*ex+25.0*pf+10.0*dd+10.0*lc)*sample*StrategyWeight(id,g_regime);
   }
   g_audit[id]=a;
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

void AuditAll()
{
   for(int i=0;i<STRATEGY_COUNT;i++)AuditStrategy(i);
   g_best=-1;double best=-999999;
   for(int j=0;j<STRATEGY_COUNT;j++)
   {
      if(g_audit[j].trades<InpMinAuditTrades)continue;
      if(g_audit[j].expectancy<=0.0||g_audit[j].profitFactor<1.0)continue;
      if(g_audit[j].score>best){best=g_audit[j].score;g_best=j;}
   }
   if(g_best<0){for(int k=0;k<STRATEGY_COUNT;k++){if(g_audit[k].trades>=InpMinAuditTrades&&g_audit[k].score>best){best=g_audit[k].score;g_best=k;}}}
   g_lastAuditBars=Bars;
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

int LocalAISignal(double &confidence,string &reason)
{
   confidence=0; reason="No valid strategy.";
   int votesBuy=0,votesSell=0;
   double weightedBuy=0,weightedSell=0;
   int active=0;
   for(int i=0;i<STRATEGY_COUNT;i++)
   {
      int sig=StrategySignal(i,1);
      if(sig==0) continue;
      active++;
      double w=1.0;
      if(g_audit[i].trades>=InpMinAuditTrades)
      {
         double pf=MathMax(0.0,MathMin(2.0,g_audit[i].profitFactor));
         double ex=MathMax(-1.0,MathMin(1.0,g_audit[i].expectancy));
         double quality=0.5+0.25*MathMin(1.0,pf/2.0)+0.25*((ex+1.0)/2.0);
         w*=quality;
      }
      w*=StrategyWeight(i,g_regime);
      if(sig>0){votesBuy++;weightedBuy+=w;}else{votesSell++;weightedSell+=w;}
   }

   int dir=0;
   if(InpUseEnsemble)
   {
      if(votesBuy>=InpMinConsensusVotes && weightedBuy>weightedSell) dir=1;
      else if(votesSell>=InpMinConsensusVotes && weightedSell>weightedBuy) dir=-1;
   }
   else
   {
      if(g_best>=0) dir=StrategySignal(g_best,1);
   }

   if(dir==0)
   {
      reason="Ensemble has no directional consensus.";
      return 0;
   }

   double winningWeight=(dir>0?weightedBuy:weightedSell);
   double losingWeight=(dir>0?weightedSell:weightedBuy);
   double balance=winningWeight+losingWeight;
   double consensusFit=(balance>0?winningWeight/balance:0.0);
   double adx=ADX(1),h=HurstApprox(1),atrp=ATRPoints(1);
   double regimeFit=(g_regime==REGIME_UNKNOWN?0.5:0.8);
   if((g_regime==REGIME_TREND_UP&&dir>0)||(g_regime==REGIME_TREND_DOWN&&dir<0)) regimeFit=1.0;
   if(g_regime==REGIME_RANGE) regimeFit=0.75;
   if(g_regime==REGIME_BREAKOUT||g_regime==REGIME_HIGH_VOLATILITY) regimeFit=0.85;
   double adxFit=MathMin(1.0,MathMax(0.25,adx/35.0));
   double atrFit=(atrp>=InpMinATRPoints?1.0:0.5);
   confidence=0.50*consensusFit+0.20*regimeFit+0.15*adxFit+0.15*atrFit;
   if(active<2) confidence*=0.85;
   if(InpUseEnsemble && votesBuy==votesSell) confidence*=0.5;

   reason="Ensemble: BUY="+IntegerToString(votesBuy)+" SELL="+IntegerToString(votesSell)+
          " | WBUY="+DoubleToString(weightedBuy,2)+" WSELL="+DoubleToString(weightedSell,2)+
          " | regime="+RegimeName(g_regime)+" | H="+DoubleToString(h,2)+
          " | ADX="+DoubleToString(adx,1)+" | ATR="+DoubleToString(atrp,1);
   if(dir>0 && votesBuy>=InpMinConsensusVotes) g_consensusAccepted++;
   if(dir<0 && votesSell>=InpMinConsensusVotes) g_consensusAccepted++;
   return dir;
}

bool ExecutionAllowed()
{
   // Trading real solo se habilita explícitamente.
   // En Strategy Tester permitimos ejecución simulada independientemente
   // de InpEnableTrading, para que el backtest no quede en 0 operaciones.
   if(InpEnableTrading) return true;
   if(IsTesting() && InpBacktestExecution) return true;
   return false;
}

bool SpreadOK(double &spreadPoints,double &atrPoints)
{
   spreadPoints=(Ask-Bid)/Point;
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
   if(!ExecutionAllowed()||direction==0)return false;
   if(OpenTrades()>=InpMaxOpenTrades){g_riskBlocked++;g_blockedMaxTrades++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | max open trades");return false;}
   if(!SessionOK()){g_riskBlocked++;g_blockedSession++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | outside session");return false;}
   if(!DailyRiskOK()){g_riskBlocked++;g_blockedDailyLoss++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | daily loss limit");return false;}

   double spread=0,atrp=0;
   if(!SpreadOK(spread,atrp))return false;

   if(g_lastTrade>0)
   {
      int bars=iBarShift(Symbol(),Period(),g_lastTrade,false);
      if(bars>=0&&bars<2){g_riskBlocked++;g_blockedCooldown++;if(InpDiagnosticPrintBlocks)Print("DIAG BLOCK | cooldown");return false;}
   }
   g_entriesAccepted++;
   return true;
}

void ExecuteTrade(int direction)
{
   if(!RiskGate(direction))return;
   double atr=ATR(1);if(atr<=0)return;
   double sl=InpSL_ATR*atr,tp=InpTP_ATR*atr,lots=LotForRisk(sl/Point);if(lots<=0)return;
   int ticket=-1;
   if(direction>0)ticket=OrderSend(Symbol(),OP_BUY,lots,Ask,5,NormalizeDouble(Ask-sl,Digits),NormalizeDouble(Ask+tp,Digits),"BiteyAI_v2_BUY",InpMagic,0,clrNONE);
   else ticket=OrderSend(Symbol(),OP_SELL,lots,Bid,5,NormalizeDouble(Bid+sl,Digits),NormalizeDouble(Bid-tp,Digits),"BiteyAI_v2_SELL",InpMagic,0,clrNONE);
   if(ticket>0){g_lastTrade=TimeCurrent();Print("Bitey AI order opened. Ticket=",ticket);}else{g_orderSendFailed++;Print("OrderSend failed. Error=",GetLastError());}
}

void WriteReport(double confidence,int direction,string reason)
{
   if(!InpAutoReport)return;
   int h=FileOpen(InpReportFile,FILE_TXT|FILE_WRITE|FILE_SHARE_READ);if(h==INVALID_HANDLE)return;
   FileWrite(h,"BITEY_AI_TRADING_REPORT_V2.05_ADAPTIVE_ENSEMBLE_SPREAD_GUARD");
   FileWrite(h,"time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   FileWrite(h,"symbol="+Symbol());FileWrite(h,"timeframe="+TFName());FileWrite(h,"regime="+RegimeName(g_regime));
   FileWrite(h,"hurst="+DoubleToString(HurstApprox(1),5));FileWrite(h,"best_strategy="+(g_best>=0?StrategyName(g_best):"NONE"));
   FileWrite(h,"direction="+IntegerToString(direction));FileWrite(h,"confidence="+DoubleToString(confidence,5));FileWrite(h,"reason="+reason);
   for(int i=0;i<STRATEGY_COUNT;i++)FileWrite(h,"strategy="+StrategyName(i)+"|trades="+IntegerToString(g_audit[i].trades)+"|win_rate="+DoubleToString(g_audit[i].winRate,2)+"|profit_factor="+DoubleToString(g_audit[i].profitFactor,4)+"|expectancy="+DoubleToString(g_audit[i].expectancy,5)+"|drawdown="+DoubleToString(g_audit[i].maxDrawdown,4)+"|consecutive_losses="+IntegerToString(g_audit[i].maxConsecutiveLosses)+"|score="+DoubleToString(g_audit[i].score,4));
   double reportSpread=(Ask-Bid)/Point;
   FileWrite(h,"execution_enabled="+(ExecutionAllowed()?"true":"false"));
   FileWrite(h,"live_trading_enabled="+(InpEnableTrading?"true":"false"));
   FileWrite(h,"backtest_execution_enabled="+(InpBacktestExecution?"true":"false"));
   FileWrite(h,"spread_points="+DoubleToString(reportSpread,1));
   FileWrite(h,"min_spread_points="+IntegerToString(InpMinSpreadPoints));
   FileWrite(h,"min_spread_filter="+(InpUseMinSpreadFilter?"true":"false"));
   FileWrite(h,"max_spread_filter="+(InpUseMaxSpreadFilter?"true":"false"));
   FileWrite(h,"spread_atr_filter="+(InpUseSpreadATRFilter?"true":"false"));
   FileWrite(h,"max_spread_points="+IntegerToString(InpMaxSpreadPoints));
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
   string body="{";body+="\"source\":\"AI_Trading_Bot_v2.00_Adaptive8\",";body+="\"symbol\":\""+Symbol()+"\",";body+="\"timeframe\":\""+TFName()+"\",";body+="\"regime\":\""+RegimeName(g_regime)+"\",";body+="\"hurst\":"+DoubleToString(HurstApprox(1),5)+",";body+="\"best_strategy\":\""+(g_best>=0?StrategyName(g_best):"NONE")+"\",";body+="\"best_score\":"+DoubleToString(g_best>=0?g_audit[g_best].score:0,5)+",";body+="\"confidence\":"+DoubleToString(confidence,5)+",";body+="\"direction\":"+IntegerToString(direction)+",";body+="\"execution_enabled\":"+(InpEnableTrading?"true":"false")+",";body+="\"reason\":\""+reason+"\",\"report_type\":\"adaptive_snapshot\"}";
   char data[],result[];string resultHeaders="";StringToCharArray(body,data,0,StringLen(body),CP_UTF8);ResetLastError();
   int code=WebRequest("POST",InpSBTEndpoint,headers,5000,data,result,resultHeaders);
   if(code<200||code>=300)Print("SBT report unavailable HTTP=",code," error=",GetLastError());
}

void UpdatePanel(double confidence,int direction,string reason)
{
   string s="BITEY IA TRADING BOT v2.05 ADAPTIVE ENSEMBLE\n";
   s+="================================\n";
   s+="Symbol: "+Symbol()+"  TF: "+TFName()+"\n";
   s+="Regime: "+RegimeName(g_regime)+"  Hurst="+DoubleToString(HurstApprox(1),3)+"\n";
   s+="Spread: "+DoubleToString((Ask-Bid)/Point,1)+" pts ("+DoubleToString(((Ask-Bid)/Point)/10.0,2)+" pips) | Min="+IntegerToString(InpMinSpreadPoints)+" "+(InpUseMinSpreadFilter?"ON":"OFF")+" | Max="+IntegerToString(InpMaxSpreadPoints)+" "+(InpUseMaxSpreadFilter?"ON":"OFF")+" | S/ATR="+(InpUseSpreadATRFilter?"ON":"OFF")+"\n";
   s+="Best: "+(g_best>=0?StrategyName(g_best):"NONE")+" | Dir="+(direction>0?"BUY":direction<0?"SELL":"HOLD")+" | Conf="+DoubleToString(confidence*100,1)+"%\n";
   s+="Pipeline: signals="+IntegerToString(g_pipelineSignals)+" confidence="+IntegerToString(g_pipelineAfterConfidence)+" spread="+IntegerToString(g_pipelineAfterSpread)+" consensus="+IntegerToString(g_consensusAccepted)+"\n";
   s+="Blocks: lowSpread="+IntegerToString(g_spreadBlockedLow)+" highSpread="+IntegerToString(g_spreadBlockedHigh)+" spreadATR="+IntegerToString(g_spreadBlockedATR)+" ATR="+IntegerToString(g_blockedATR)+" session="+IntegerToString(g_blockedSession)+" maxTrades="+IntegerToString(g_blockedMaxTrades)+"\n";
   s+="Signals: noSignal="+IntegerToString(g_noSignal)+" lowConfidence="+IntegerToString(g_lowConfidence)+"\n";
   s+="--------------------------------\n";
   for(int i=0;i<STRATEGY_COUNT;i++)
      s+=StrategyName(i)+" | HistSig="+IntegerToString(g_strategySignals[i])+" | Now="+(g_strategyCurrentSignals[i]>0?"BUY":g_strategyCurrentSignals[i]<0?"SELL":"-")+" | T="+IntegerToString(g_audit[i].trades)+" | PF="+DoubleToString(g_audit[i].profitFactor,2)+" | E="+DoubleToString(g_audit[i].expectancy,3)+"\n";
   s+="--------------------------------\n";
   s+=reason+"\n";
   Comment(s);
}

int OnInit()
{
   g_dayOfYear=TimeDayOfYear(TimeCurrent());g_dayStartEquity=AccountEquity();g_regime=DetectRegime();AuditAll();ProbeStrategies();
   Print("Bitey IA v2.04 initialized. Best=",g_best>=0?StrategyName(g_best):"NONE"," Regime=",RegimeName(g_regime));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){
   Print("=== BITEY v2.05 ADAPTIVE ENSEMBLE SUMMARY ===");
   Print("Bars processed=",g_barsProcessed," Entries accepted=",g_entriesAccepted," OrderSend failed=",g_orderSendFailed);
   Print("Spread low=",g_spreadBlockedLow," high=",g_spreadBlockedHigh," spread/ATR=",g_spreadBlockedATR," ATR=",g_blockedATR);
   Print("Session=",g_blockedSession," DailyLoss=",g_blockedDailyLoss," MaxTrades=",g_blockedMaxTrades," Cooldown=",g_blockedCooldown);
   Print("NoSignal=",g_noSignal," LowConfidence=",g_lowConfidence);
   Print("Pipeline signals=",g_pipelineSignals," after confidence=",g_pipelineAfterConfidence," after spread=",g_pipelineAfterSpread);
   for(int i=0;i<STRATEGY_COUNT;i++) Print("Strategy ",StrategyName(i)," historicalSignals=",g_strategySignals[i]," currentSignal=",g_strategyCurrentSignals[i]);
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
   double confidence=0;string reason="";int direction=LocalAISignal(confidence,reason);
   if(direction!=0) g_pipelineSignals++; else g_noSignal++;
   if(confidence<InpMinConfidence){if(direction!=0)g_lowConfidence++;direction=0;reason+=" | Confidence below local threshold.";}
   else if(direction!=0) g_pipelineAfterConfidence++;
   double probeSpread=0,probeATR=0;
   if(direction!=0 && SpreadOK(probeSpread,probeATR)) g_pipelineAfterSpread++;
   WriteReport(confidence,direction,reason);WriteCSV(confidence,direction);SendSBT(confidence,direction,reason);UpdatePanel(confidence,direction,reason);
   if(direction!=0)ExecuteTrade(direction);
}
//+------------------------------------------------------------------+
