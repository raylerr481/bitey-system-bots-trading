//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.00_Adaptive8.mq4                              |
//| Bitey IA - Adaptive 8 Strategy MT4 Expert Advisor               |
//| Local AI-style engine: regime + strategy spectrum + risk gate   |
//| Optional read-only Web AI/SBT integration                       |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Adaptive 8-strategy AI-style MT4 Expert Advisor"
#property description "Local deterministic decision engine with optional Bitey AI"

#define STRATEGY_COUNT 8

enum AI_MODE { AI_LOCAL_ONLY=0, AI_LOCAL_PLUS_WEB=1 };
enum MARKET_REGIME { REGIME_UNKNOWN=0, REGIME_TREND_UP, REGIME_TREND_DOWN, REGIME_RANGE, REGIME_BREAKOUT, REGIME_HIGH_VOLATILITY };

input AI_MODE InpAIMode=AI_LOCAL_ONLY;
input bool InpEnableTrading=false;
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
input int InpMaxSpreadPoints=30;
input double InpMaxSpreadATR=0.20;
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
   confidence=0;reason="No valid strategy.";
   if(g_best<0)return 0;
   int dir=StrategySignal(g_best,1);if(dir==0){reason="Best strategy has no current signal.";return 0;}
   double adx=ADX(1),h=HurstApprox(1),atrp=ATRPoints(1);
   double scoreFit=MathMax(0.0,MathMin(1.0,g_audit[g_best].score/100.0));
   double sampleFit=MathMin(1.0,g_audit[g_best].trades/50.0);
   double pfFit=MathMin(1.0,MathMax(0.0,(g_audit[g_best].profitFactor-1.0)/2.0));
   confidence=0.30*scoreFit+0.25*sampleFit+0.20*pfFit+0.15*MathMin(1.0,StrategyWeight(g_best,g_regime)/1.25)+0.10*(adx>=InpMinADXTrend?1.0:0.5);
   if(g_regime==REGIME_RANGE&&(g_best==0||g_best==3))confidence*=0.65;
   if(g_regime==REGIME_HIGH_VOLATILITY&&g_best==1)confidence*=0.60;
   if(atrp<InpMinATRPoints)confidence*=0.70;
   reason="Local AI: "+StrategyName(g_best)+" | regime="+RegimeName(g_regime)+" | H="+DoubleToString(h,2)+" | ADX="+DoubleToString(adx,1)+" | PF="+DoubleToString(g_audit[g_best].profitFactor,2)+" | Exp="+DoubleToString(g_audit[g_best].expectancy,3);
   return dir;
}

bool RiskGate(int direction)
{
   if(!InpEnableTrading||direction==0)return false;
   if(OpenTrades()>=InpMaxOpenTrades||!SessionOK()||!DailyRiskOK())return false;
   double spread=(Ask-Bid)/Point,atrp=ATRPoints(1);
   if(spread>InpMaxSpreadPoints||atrp<InpMinATRPoints)return false;
   if(atrp>0&&spread/atrp>InpMaxSpreadATR)return false;
   if(g_lastTrade>0){int bars=iBarShift(Symbol(),Period(),g_lastTrade,false);if(bars>=0&&bars<2)return false;}
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
   if(ticket>0){g_lastTrade=TimeCurrent();Print("Bitey AI order opened. Ticket=",ticket);}else Print("OrderSend failed. Error=",GetLastError());
}

void WriteReport(double confidence,int direction,string reason)
{
   if(!InpAutoReport)return;
   int h=FileOpen(InpReportFile,FILE_TXT|FILE_WRITE|FILE_SHARE_READ);if(h==INVALID_HANDLE)return;
   FileWrite(h,"BITEY_AI_TRADING_REPORT_V2");
   FileWrite(h,"time="+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   FileWrite(h,"symbol="+Symbol());FileWrite(h,"timeframe="+TFName());FileWrite(h,"regime="+RegimeName(g_regime));
   FileWrite(h,"hurst="+DoubleToString(HurstApprox(1),5));FileWrite(h,"best_strategy="+(g_best>=0?StrategyName(g_best):"NONE"));
   FileWrite(h,"direction="+IntegerToString(direction));FileWrite(h,"confidence="+DoubleToString(confidence,5));FileWrite(h,"reason="+reason);
   for(int i=0;i<STRATEGY_COUNT;i++)FileWrite(h,"strategy="+StrategyName(i)+"|trades="+IntegerToString(g_audit[i].trades)+"|win_rate="+DoubleToString(g_audit[i].winRate,2)+"|profit_factor="+DoubleToString(g_audit[i].profitFactor,4)+"|expectancy="+DoubleToString(g_audit[i].expectancy,5)+"|drawdown="+DoubleToString(g_audit[i].maxDrawdown,4)+"|consecutive_losses="+IntegerToString(g_audit[i].maxConsecutiveLosses)+"|score="+DoubleToString(g_audit[i].score,4));
   FileWrite(h,"execution_enabled="+(InpEnableTrading?"true":"false"));FileClose(h);
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
   string s="BITEY IA TRADING BOT v2.00\n";s+="================================\n";s+="Symbol: "+Symbol()+"  TF: "+TFName()+"\n";s+="Regime: "+RegimeName(g_regime)+"\n";s+="Hurst: "+DoubleToString(HurstApprox(1),3)+"\n";s+="Best: "+(g_best>=0?StrategyName(g_best):"NONE")+"\n";s+="AI direction: "+(direction>0?"BUY":direction<0?"SELL":"HOLD")+"\n";s+="AI confidence: "+DoubleToString(confidence*100,1)+"%\n";s+="Execution: "+(InpEnableTrading?"ON":"OFF")+"\n";s+="--------------------------------\n";
   for(int i=0;i<STRATEGY_COUNT;i++){s+=StrategyName(i)+" | T="+IntegerToString(g_audit[i].trades)+" | WR="+DoubleToString(g_audit[i].winRate,1)+"% | PF="+DoubleToString(g_audit[i].profitFactor,2)+" | E="+DoubleToString(g_audit[i].expectancy,3)+" | S="+DoubleToString(g_audit[i].score,1)+"\n";}
   s+="--------------------------------\n";s+=reason+"\n";s+="Risk Gate: "+(DailyRiskOK()?"ALLOW":"BLOCK DAILY LOSS")+"\n";Comment(s);
}

int OnInit()
{
   g_dayOfYear=TimeDayOfYear(TimeCurrent());g_dayStartEquity=AccountEquity();g_regime=DetectRegime();AuditAll();
   Print("Bitey IA v2.00 initialized. Best=",g_best>=0?StrategyName(g_best):"NONE"," Regime=",RegimeName(g_regime));
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){Comment("");}

void OnTick()
{
   if(Bars<300)return;
   if(!NewBar())return;
   g_regime=DetectRegime();
   if(g_lastAuditBars<0||MathAbs(Bars-g_lastAuditBars)>=InpAuditRefreshBars)AuditAll();
   double confidence=0;string reason="";int direction=LocalAISignal(confidence,reason);
   if(confidence<0.55){direction=0;reason+=" | Confidence below local threshold.";}
   WriteReport(confidence,direction,reason);WriteCSV(confidence,direction);SendSBT(confidence,direction,reason);UpdatePanel(confidence,direction,reason);
   if(direction!=0)ExecuteTrade(direction);
}
//+------------------------------------------------------------------+
