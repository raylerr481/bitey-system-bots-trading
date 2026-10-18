//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.20_WalkForwardRegime.mq4                     |
//| Bitey IA - Walk-forward regime evidence EA                     |
//+------------------------------------------------------------------+
#property strict
#property version "2.20"
#property description "Bitey IA walk-forward 8-strategy regime-aware MT4 EA"
#define STRATEGY_COUNT 8

enum REGIME { UNKNOWN=0,TREND_UP=1,TREND_DOWN=2,RANGE=3,BREAKOUT=4,HIGH_VOL=5 };
input bool InpEnableTrading=false;
input bool InpBacktestExecution=true;
input double InpRiskPercent=0.25;
input int InpMagic=2035020;
input int InpMaxOpenTrades=1;
input int InpATRPeriod=14;
input int InpADXPeriod=14;
input int InpRSIPeriod=14;
input int InpFastEMA=8;
input int InpSlowEMA=21;
input int InpTrendEMA=200;
input int InpLookback=1500;
input int InpOOSBars=300;
input int InpAuditHorizon=15;
input int InpMinTrainTrades=20;
input int InpMinOOSTrades=8;
input double InpMinOOSExpectancy=0.02;
input double InpMinOOSPF=1.05;
input double InpMaxOOSDrawdown=8.0;
input double InpSL_ATR=1.30;
input double InpTP_ATR=2.60;
input double InpMinADXTrend=22.0;
input double InpMaxADXRange=18.0;
input double InpMinATRPoints=5.0;
input int InpMaxSpreadPoints=30;
input double InpMaxSpreadATR=0.20;
input int InpSessionStart=7;
input int InpSessionEnd=20;
input int InpCooldownBars=3;
input bool InpRequireSecondConfirmation=true;
input bool InpPrintAudit=true;
input bool InpWriteCSV=true;
input string InpCSVFile="Bitey_v2.20_Decisions.csv";

struct Stats { int trades,wins,losses,maxLossStreak; double net,gp,gl,pf,expectancy,dd; };
Stats gTrain[STRATEGY_COUNT],gOOS[STRATEGY_COUNT];
int gBest=-1,gLastBars=-1,gLastDir=0,gLastStrategy=-1; datetime gLastBar=0,gLastTrade=0; REGIME gRegime=UNKNOWN;

string StrategyName(int id){
 if(id==0)return "TREND_FOLLOWING"; if(id==1)return "MEAN_REVERSION"; if(id==2)return "MOMENTUM"; if(id==3)return "VOLATILITY_BREAKOUT";
 if(id==4)return "SESSION_BIAS"; if(id==5)return "DIVERGENCE"; if(id==6)return "STRICT_RANGE"; if(id==7)return "FRACTAL_HTF"; return "UNKNOWN";
}
string RegimeName(REGIME r){ if(r==TREND_UP)return "TREND_UP"; if(r==TREND_DOWN)return "TREND_DOWN"; if(r==RANGE)return "RANGE"; if(r==BREAKOUT)return "BREAKOUT"; if(r==HIGH_VOL)return "HIGH_VOL"; return "UNKNOWN"; }
double ATR(int s){return iATR(Symbol(),Period(),InpATRPeriod,s);} double ATRPoints(int s){return Point>0?ATR(s)/Point:0;}
double ADX(int s){return iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,s);} double RSI(int s){return iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,s);}
double EMA(int p,int s){return iMA(Symbol(),Period(),p,0,MODE_EMA,PRICE_CLOSE,s);}
void ResetStats(Stats &x){x.trades=0;x.wins=0;x.losses=0;x.maxLossStreak=0;x.net=0;x.gp=0;x.gl=0;x.pf=0;x.expectancy=0;x.dd=0;}
void AddResult(Stats &x,double r,int &st){x.trades++;x.net+=r;if(r>0){x.wins++;x.gp+=r;st=0;}else{x.losses++;x.gl+=r;st++;if(st>x.maxLossStreak)x.maxLossStreak=st;}}
void FinalizeStats(Stats &x){if(x.trades>0)x.expectancy=x.net/x.trades;if(x.gl<0)x.pf=x.gp/MathAbs(x.gl);}
REGIME RegimeAt(int s){
 if(Bars<s+80)return UNKNOWN; double a=ATRPoints(s),d=ADX(s),f=EMA(InpFastEMA,s),sl=EMA(InpSlowEMA,s),t=EMA(InpTrendEMA,s);
 if(a>=InpMinATRPoints*2.5&&d>=28)return HIGH_VOL;
 if(d>=InpMinADXTrend&&f>sl&&Close[s]>t)return TREND_UP;
 if(d>=InpMinADXTrend&&f<sl&&Close[s]<t)return TREND_DOWN;
 int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+2),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+2);
 if(hi>=0&&lo>=0&&(Close[s]>iHigh(Symbol(),Period(),hi)||Close[s]<iLow(Symbol(),Period(),lo)))return BREAKOUT;
 if(d<=InpMaxADXRange)return RANGE; if(f>sl)return TREND_UP; if(f<sl)return TREND_DOWN; return RANGE;
}
REGIME CurrentRegime(){return RegimeAt(1);}
int SessionSignal(int s){
 int h=TimeHour(Time[s]); if(h<InpSessionStart||h>=InpSessionEnd)return 0;
 int ds=iBarShift(Symbol(),PERIOD_D1,Time[s],false); if(ds<0)return 0; datetime day=iTime(Symbol(),PERIOD_D1,ds); if(day<=0)return 0;
 datetime st=day+InpSessionStart*3600; int sh=iBarShift(Symbol(),Period(),st,false); if(sh<0||sh<s)return 0; double o=iOpen(Symbol(),Period(),sh);
 if(Close[s]>o)return 1;if(Close[s]<o)return -1;return 0;
}
int FractalHTFSignal(int s){
 if(Bars<s+20)return 0; datetime t=iTime(Symbol(),Period(),s); if(t<=0)return 0; int h4=iBarShift(Symbol(),PERIOD_H4,t,false); if(h4<0)return 0;
 int cs=h4+1; double f=iMA(Symbol(),PERIOD_H4,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,cs),sl=iMA(Symbol(),PERIOD_H4,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,cs),local=EMA(InpFastEMA,s);
 if(f>sl&&Close[s]>local)return 1;if(f<sl&&Close[s]<local)return -1;return 0;
}
int StrategySignal(int id,int s){
 if(Bars<s+12)return 0; double f=EMA(InpFastEMA,s),sl=EMA(InpSlowEMA,s),tr=EMA(InpTrendEMA,s),r=RSI(s);
 if(id==0){if(f>sl&&Close[s]>tr)return 1;if(f<sl&&Close[s]<tr)return -1;}
 if(id==1){if(r<=28&&Close[s]<f)return 1;if(r>=72&&Close[s]>f)return -1;}
 if(id==2){if(Close[s]>Close[s+5]&&r>=55&&r<=78)return 1;if(Close[s]<Close[s+5]&&r>=22&&r<=45)return -1;}
 if(id==3){int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+1),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+1);if(hi>=0&&Close[s]>iHigh(Symbol(),Period(),hi))return 1;if(lo>=0&&Close[s]<iLow(Symbol(),Period(),lo))return -1;}
 if(id==4)return SessionSignal(s);
 if(id==5){double r5=RSI(s+5);if(Close[s]<Close[s+5]&&r>r5&&r<45)return 1;if(Close[s]>Close[s+5]&&r<r5&&r>55)return -1;}
 if(id==6){int hi=iHighest(Symbol(),Period(),MODE_HIGH,20,s+1),lo=iLowest(Symbol(),Period(),MODE_LOW,20,s+1);if(hi>=0&&lo>=0){double H=iHigh(Symbol(),Period(),hi),L=iLow(Symbol(),Period(),lo),w=H-L;if(w>0){double p=(Close[s]-L)/w;if(p<.20&&r<45)return 1;if(p>.80&&r>55)return -1;}}}
 if(id==7)return FractalHTFSignal(s); return 0;
}
double StrategyWeight(int id,REGIME r){if(r==TREND_UP||r==TREND_DOWN){if(id==0||id==2||id==7)return 1.20;if(id==1||id==6)return .75;}if(r==RANGE){if(id==1||id==5||id==6||id==4)return 1.20;if(id==0||id==3)return .70;}if(r==BREAKOUT||r==HIGH_VOL){if(id==0||id==2||id==3||id==7)return 1.25;if(id==1||id==6)return .65;}return 1.0;}
bool Compatible(int id,REGIME r){if(r==TREND_UP||r==TREND_DOWN)return id==0||id==2||id==3||id==7;if(r==RANGE)return id==1||id==4||id==5||id==6;if(r==BREAKOUT||r==HIGH_VOL)return id==0||id==2||id==3||id==7;return true;}
bool SimulateTrade(int dir,int entry,int horizon,double sl,double tp,double &r){double e=Close[entry];int end=MathMax(1,entry-horizon);for(int k=entry-1;k>=end;k--){if(dir>0){if(Low[k]<=e-sl){r=-1;return true;}if(High[k]>=e+tp){r=tp/sl;return true;}}else{if(High[k]>=e+sl){r=-1;return true;}if(Low[k]<=e-tp){r=tp/sl;return true;}}}r=sl>0?(dir>0?(Close[end]-e):(e-Close[end]))/sl:0;return true;}
void AuditOne(int id){
 ResetStats(gTrain[id]);ResetStats(gOOS[id]);int avail=Bars-InpAuditHorizon-10,total=MathMin(InpLookback,avail),oos=MathMin(InpOOSBars,MathMax(30,total/5));if(total<150||oos>=total-30)return;
 int stT=0,stO=0;double eqT=0,pkT=0,eqO=0,pkO=0;int trainLast=oos+1;
 for(int s=total;s>=trainLast;s--){int sig=StrategySignal(id,s);if(sig==0)continue;double a=ATR(s);if(a<=0)continue;double r=0;SimulateTrade(sig,s,InpAuditHorizon,a*InpSL_ATR,a*InpTP_ATR,r);AddResult(gTrain[id],r,stT);eqT+=r;if(eqT>pkT)pkT=eqT;if(pkT-eqT>gTrain[id].dd)gTrain[id].dd=pkT-eqT;}
 for(int s=oos;s>=InpAuditHorizon+2;s--){int sig=StrategySignal(id,s);if(sig==0)continue;double a=ATR(s);if(a<=0)continue;double r=0;SimulateTrade(sig,s,InpAuditHorizon,a*InpSL_ATR,a*InpTP_ATR,r);AddResult(gOOS[id],r,stO);eqO+=r;if(eqO>pkO)pkO=eqO;if(pkO-eqO>gOOS[id].dd)gOOS[id].dd=pkO-eqO;}
 FinalizeStats(gTrain[id]);FinalizeStats(gOOS[id]);
}
bool Eligible(int id){return gTrain[id].trades>=InpMinTrainTrades&&gTrain[id].expectancy>0&&gTrain[id].pf>=1.0&&gOOS[id].trades>=InpMinOOSTrades&&gOOS[id].expectancy>=InpMinOOSExpectancy&&gOOS[id].pf>=InpMinOOSPF&&gOOS[id].dd<=InpMaxOOSDrawdown;}
double SelectionScore(int id){double e=MathMax(0.,gOOS[id].expectancy),pf=MathMin(2.5,MathMax(0.,gOOS[id].pf)),stab=1.-MathMin(1.,gOOS[id].dd/MathMax(.1,InpMaxOOSDrawdown)),sample=MathMin(1.,(double)gOOS[id].trades/30.);return(.55*e+.25*(pf-1.)+.20*stab)*sample*StrategyWeight(id,gRegime);}
void AuditAll(){gBest=-1;double best=-1e9;for(int i=0;i<STRATEGY_COUNT;i++){AuditOne(i);if(Eligible(i)&&Compatible(i,gRegime)){double sc=SelectionScore(i);if(sc>best){best=sc;gBest=i;}}}gLastBars=Bars;if(!InpPrintAudit)return;Print("===== BITEY IA v2.20 WALK-FORWARD =====");Print("Regime=",RegimeName(gRegime)," Best=",gBest>=0?StrategyName(gBest):"NONE");for(int i=0;i<STRATEGY_COUNT;i++)Print(StrategyName(i)," TRAIN T=",gTrain[i].trades," PF=",DoubleToString(gTrain[i].pf,2)," E=",DoubleToString(gTrain[i].expectancy,3)," | OOS T=",gOOS[i].trades," PF=",DoubleToString(gOOS[i].pf,2)," E=",DoubleToString(gOOS[i].expectancy,3)," DD=",DoubleToString(gOOS[i].dd,2)," eligible=",Eligible(i)&&Compatible(i,gRegime)?"YES":"NO");}
bool SessionOK(){int h=TimeHour(TimeCurrent());if(InpSessionStart<InpSessionEnd)return h>=InpSessionStart&&h<InpSessionEnd;return h>=InpSessionStart||h<InpSessionEnd;}
bool SpreadOK(){double sp=(Ask-Bid)/Point,a=ATRPoints(1);if(sp<=0||sp>InpMaxSpreadPoints||a<=0||sp/a>InpMaxSpreadATR)return false;return true;}
int OpenTrades(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))if(OrderSymbol()==Symbol()&&OrderMagicNumber()==InpMagic&&(OrderType()==OP_BUY||OrderType()==OP_SELL))n++;return n;}
double LotForRisk(double stopPoints){double tv=MarketInfo(Symbol(),MODE_TICKVALUE),ts=MarketInfo(Symbol(),MODE_TICKSIZE);if(stopPoints<=0||tv<=0||ts<=0)return 0;double money=AccountBalance()*InpRiskPercent/100.,lossLot=(stopPoints*Point/ts)*tv;if(lossLot<=0)return 0;double step=MarketInfo(Symbol(),MODE_LOTSTEP),mn=MarketInfo(Symbol(),MODE_MINLOT),mx=MarketInfo(Symbol(),MODE_MAXLOT);if(step<=0)step=.01;double lot=MathFloor((money/lossLot)/step)*step;lot=MathMax(mn,MathMin(mx,lot));return NormalizeDouble(lot,2);}
int BestSignal(){if(gBest<0)return 0;int sig=StrategySignal(gBest,1);if(sig==0)return 0;if(InpRequireSecondConfirmation){int agree=0;for(int i=0;i<STRATEGY_COUNT;i++){if(i==gBest||!Eligible(i)||!Compatible(i,gRegime))continue;if(StrategySignal(i,1)==sig)agree++;}if(agree==0)return 0;}gLastStrategy=gBest;return sig;}
void ExecuteTrade(int dir){if(!InpEnableTrading&&!(IsTesting()&&InpBacktestExecution))return;if(OpenTrades()>=InpMaxOpenTrades||!SessionOK()||!SpreadOK())return;if(gLastTrade>0){int b=iBarShift(Symbol(),Period(),gLastTrade,false);if(b>=0&&b<InpCooldownBars)return;}double a=ATR(1);if(a<=0)return;double sl=InpSL_ATR*a,tp=InpTP_ATR*a;if(gRegime==HIGH_VOL){sl=MathMax(sl,1.5*a);tp=MathMax(tp,2.2*a);}if(gRegime==RANGE){sl=MathMin(sl,1.1*a);tp=MathMin(tp,1.8*a);}double lot=LotForRisk(sl/Point);if(lot<=0)return;RefreshRates();ResetLastError();string c="B20|"+StrategyName(gLastStrategy);int ticket=-1;if(dir>0)ticket=OrderSend(Symbol(),OP_BUY,lot,Ask,5,NormalizeDouble(Ask-sl,Digits),NormalizeDouble(Ask+tp,Digits),c,InpMagic,0,clrNONE);else ticket=OrderSend(Symbol(),OP_SELL,lot,Bid,5,NormalizeDouble(Bid+sl,Digits),NormalizeDouble(Bid-tp,Digits),c,InpMagic,0,clrNONE);if(ticket>0){gLastTrade=TimeCurrent();Print("B20 EXEC OK ticket=",ticket," strategy=",StrategyName(gLastStrategy)," direction=",dir>0?"BUY":"SELL"," lots=",DoubleToString(lot,2));}else Print("B20 EXEC FAIL error=",GetLastError());}
void WriteDecision(int dir){if(!InpWriteCSV||!IsTesting())return;int h=FileOpen(InpCSVFile,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ,';');if(h==INVALID_HANDLE)return;if(FileSize(h)==0)FileWrite(h,"time","symbol","timeframe","regime","best_strategy","direction","train_trades","train_pf","train_expectancy","oos_trades","oos_pf","oos_expectancy","oos_drawdown");FileSeek(h,0,SEEK_END);int i=gBest;FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),Period(),RegimeName(gRegime),i>=0?StrategyName(i):"NONE",dir,i>=0?gTrain[i].trades:0,i>=0?gTrain[i].pf:0.,i>=0?gTrain[i].expectancy:0.,i>=0?gOOS[i].trades:0,i>=0?gOOS[i].pf:0.,i>=0?gOOS[i].expectancy:0.,i>=0?gOOS[i].dd:0.);FileClose(h);}
bool IsNewBar(){if(Time[0]==gLastBar)return false;gLastBar=Time[0];return true;}
int OnInit(){if(Bars<300){Print("Bitey v2.20 waiting for history. Bars=",Bars);return INIT_SUCCEEDED;}gRegime=CurrentRegime();AuditAll();Print("Bitey IA v2.20 initialized | regime=",RegimeName(gRegime)," | best=",gBest>=0?StrategyName(gBest):"NONE"," | trading=",InpEnableTrading," | tester=",IsTesting());return INIT_SUCCEEDED;}
void OnTick(){if(Bars<300||!IsNewBar())return;gRegime=CurrentRegime();if(gLastBars<0||MathAbs(Bars-gLastBars)>=20)AuditAll();int dir=BestSignal();if(dir!=0)gLastDir=dir;WriteDecision(dir);Comment("BITEY IA v2.20\nRegime: ",RegimeName(gRegime),"\nBest OOS: ",gBest>=0?StrategyName(gBest):"NONE","\nSignal: ",dir>0?"BUY":dir<0?"SELL":"HOLD","\nOOS PF: ",gBest>=0?DoubleToString(gOOS[gBest].pf,2):"-","\nOOS Expectancy: ",gBest>=0?DoubleToString(gOOS[gBest].expectancy,3):"-");if(dir!=0)ExecuteTrade(dir);}
void OnDeinit(const int reason){Comment("");}
//+------------------------------------------------------------------+
