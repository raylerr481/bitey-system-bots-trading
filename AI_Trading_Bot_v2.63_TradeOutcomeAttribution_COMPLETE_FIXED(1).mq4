//+------------------------------------------------------------------+
//| AI_Trading_Bot_v2.63_TradeOutcomeAttribution_COMPLETE_FIXED.mq4  |
//| Bitey IA - Adaptive 8-Strategy Ensemble EA                       |
//| v2.63 - Trade outcome attribution + robust CSV export            |
//+------------------------------------------------------------------+
#property strict
#property version "2.63"
#property description "Bitey IA MT4 EA - adaptive 8-strategy ensemble, regime intelligence and trade outcome attribution."

#define STRATEGY_COUNT 8
#define REGIME_COUNT 4
#define AUDIT_DIR_COUNT 2
#define MAX_SNAPSHOTS 5000

enum Direction { DIR_NONE=0, DIR_BUY=1, DIR_SELL=-1 };
enum Regime { REG_UNKNOWN=0, REG_TREND_UP=1, REG_TREND_DOWN=2, REG_RANGE=3 };

input int MagicNumber=263063;
input double Lots=0.10;
input bool UseRiskPercent=false;
input double RiskPercent=1.0;
input int StopLossPoints=350;
input int TakeProfitPoints=700;
input int Slippage=20;
input int MaxSpreadPoints=35;
input bool OneTradePerSymbol=true;
input bool AllowBuy=true;
input bool AllowSell=true;
input bool UseAdaptiveEntry=true;
input double MinEntryScore=0.55;
input double MinDirectionalEdge=0.10;
input int MinConsensus=3;
input bool UseRegimeFilter=true;
input bool EnableOutcomeAttribution=true;
input bool ExportCSV=true;
input bool ExportToCommonFolder=true;
input string CSVFileName="Bitey_v2.63_TradeOutcomeAttribution.csv";
input int FastMAPeriod=20;
input int SlowMAPeriod=50;
input int RSIPeriod=14;
input int ATRPeriod=14;
input int ADXPeriod=14;
input int BBPeriod=20;
input double BBDeviation=2.0;
input bool EnableTrailing=false;
input int TrailStartPoints=500;
input int TrailDistancePoints=250;

string StrategyName[STRATEGY_COUNT]={"EMA_Cross","RSI","MACD","ADX","Bollinger","Breakout","Momentum","Structure"};

struct DirectionAudit { int samples,wins,losses; double netProfit,grossProfit,grossLoss,winRate,profitFactor,avgProfit,lastScore; };
struct CellAudit { int samples,wins,losses; double netProfit,grossProfit,grossLoss,winRate,profitFactor,avgProfit; };
struct TradeSnapshot {
   int ticket,type,strategy,regime,consensus;
   datetime openTime;
   double entryScore,directional,atr,adx,rsi,stopPoints,targetPoints;
   string reason;
};

DirectionAudit g_dir[AUDIT_DIR_COUNT];
CellAudit g_cell[STRATEGY_COUNT][AUDIT_DIR_COUNT][REGIME_COUNT];
TradeSnapshot g_snap[MAX_SNAPSHOTS];
int g_snapCount=0;
datetime g_lastBar=0;
int g_lastSignal=DIR_NONE,g_lastStrategy=-1,g_lastRegime=REG_UNKNOWN,g_lastConsensus=0;
double g_lastScore=0,g_lastDirectional=0;

//-------------------- Utilities ------------------------------------
double SafeDiv(double a,double b){ return (MathAbs(b)<1e-12)?0.0:a/b; }
double Clamp(double v,double lo,double hi){ return MathMax(lo,MathMin(hi,v)); }
string DirName(int d){ if(d==DIR_BUY)return "BUY"; if(d==DIR_SELL)return "SELL"; return "NONE"; }
string RegimeName(int r){ if(r==REG_TREND_UP)return "TREND_UP"; if(r==REG_TREND_DOWN)return "TREND_DOWN"; if(r==REG_RANGE)return "RANGE"; return "UNKNOWN"; }
string SafeText(string s){ StringReplace(s,"\"","'"); StringReplace(s,",",";"); StringReplace(s,"\r"," "); StringReplace(s,"\n"," "); return s; }

//-------------------- Indicators -----------------------------------
double EMA(int p,int sh){ return iMA(NULL,0,p,0,MODE_EMA,PRICE_CLOSE,sh); }
double RSIv(int sh){ return iRSI(NULL,0,RSIPeriod,PRICE_CLOSE,sh); }
double ATRv(int sh){ return iATR(NULL,0,ATRPeriod,sh); }
double ADXv(int sh){ return iADX(NULL,0,ADXPeriod,PRICE_CLOSE,MODE_MAIN,sh); }
double MACDm(int sh){ return iMACD(NULL,0,12,26,9,PRICE_CLOSE,MODE_MAIN,sh); }
double MACDs(int sh){ return iMACD(NULL,0,12,26,9,PRICE_CLOSE,MODE_SIGNAL,sh); }
double BBup(int sh){ return iBands(NULL,0,BBPeriod,BBDeviation,0,PRICE_CLOSE,MODE_UPPER,sh); }
double BBlow(int sh){ return iBands(NULL,0,BBPeriod,BBDeviation,0,PRICE_CLOSE,MODE_LOWER,sh); }
double BBmid(int sh){ return iBands(NULL,0,BBPeriod,BBDeviation,0,PRICE_CLOSE,MODE_MAIN,sh); }
double HH(int n,int sh){ int i=iHighest(NULL,0,MODE_HIGH,n,sh); return i<0?0:iHigh(NULL,0,i); }
double LL(int n,int sh){ int i=iLowest(NULL,0,MODE_LOW,n,sh); return i<0?0:iLow(NULL,0,i); }

//-------------------- Regime ---------------------------------------
int DetectRegime(){
   double a=ATRv(1),f=EMA(FastMAPeriod,1),s=EMA(SlowMAPeriod,1),adx=ADXv(1);
   if(a<=0)return REG_UNKNOWN;
   double sep=MathAbs(f-s)/a;
   if(adx>=23.0 && sep>=0.45){ if(f>s)return REG_TREND_UP; if(f<s)return REG_TREND_DOWN; }
   return REG_RANGE;
}

//-------------------- Eight strategies ------------------------------
int StrategyVote(int st,int sh){
   double c=iClose(NULL,0,sh),o=iOpen(NULL,0,sh);
   if(st==0){ double f=EMA(FastMAPeriod,sh),s=EMA(SlowMAPeriod,sh); if(f>s)return DIR_BUY; if(f<s)return DIR_SELL; }
   if(st==1){ double r=RSIv(sh); if(r<35)return DIR_BUY; if(r>65)return DIR_SELL; if(r>52)return DIR_BUY; if(r<48)return DIR_SELL; }
   if(st==2){ double m=MACDm(sh),s=MACDs(sh); if(m>s)return DIR_BUY; if(m<s)return DIR_SELL; }
   if(st==3){ double ad=ADXv(sh),p=iADX(NULL,0,ADXPeriod,PRICE_CLOSE,MODE_PLUSDI,sh),m=iADX(NULL,0,ADXPeriod,PRICE_CLOSE,MODE_MINUSDI,sh); if(ad>=18){if(p>m)return DIR_BUY;if(m>p)return DIR_SELL;} }
   if(st==4){ double u=BBup(sh),l=BBlow(sh),mid=BBmid(sh); if(c<=l)return DIR_BUY; if(c>=u)return DIR_SELL; if(c>mid)return DIR_BUY; if(c<mid)return DIR_SELL; }
   if(st==5){ double h=HH(20,sh+1),l=LL(20,sh+1); if(c>h)return DIR_BUY; if(c<l)return DIR_SELL; if(iHigh(NULL,0,sh)>h&&c>o)return DIR_BUY; if(iLow(NULL,0,sh)<l&&c<o)return DIR_SELL; }
   if(st==6){ double old=iClose(NULL,0,sh+5); if(c>old)return DIR_BUY; if(c<old)return DIR_SELL; }
   if(st==7){ double h1=HH(5,sh+1),l1=LL(5,sh+1),h2=HH(5,sh+6),l2=LL(5,sh+6); if(h1>h2&&l1>l2)return DIR_BUY; if(h1<h2&&l1<l2)return DIR_SELL; }
   return DIR_NONE;
}

void BuildVotes(int &buys,int &sells){ buys=0;sells=0; for(int s=0;s<STRATEGY_COUNT;s++){int v=StrategyVote(s,1);if(v==DIR_BUY)buys++;else if(v==DIR_SELL)sells++;} }
double DirectionalEdge(int buys,int sells){ int n=buys+sells; return n==0?0.0:(double)(buys-sells)/n; }
int SelectStrategy(int signal,int regime){
   double best=-1; int pick=-1;
   for(int s=0;s<STRATEGY_COUNT;s++){
      if(StrategyVote(s,1)!=signal)continue;
      double x=1.0;
      if(s==0&&(regime==REG_TREND_UP||regime==REG_TREND_DOWN))x+=0.20;
      if(s==3&&ADXv(1)>=25)x+=0.15;
      if(s==4&&regime==REG_RANGE)x+=0.20;
      if(s==7)x+=0.10;
      if(x>best){best=x;pick=s;}
   }
   return pick;
}
double EntryScore(int signal,int regime,int buys,int sells){
   int side=signal==DIR_BUY?buys:sells,total=buys+sells; if(total<=0)return 0;
   double score=0.50*SafeDiv(side,total),adx=ADXv(1),a=ATRv(1),pt=MarketInfo(Symbol(),MODE_POINT);
   if(adx>=25)score+=0.20;else if(adx>=18)score+=0.10;
   if(pt>0&&a/pt>80)score+=0.10;
   if(UseRegimeFilter){if(signal==DIR_BUY&&regime==REG_TREND_UP)score+=0.20;if(signal==DIR_SELL&&regime==REG_TREND_DOWN)score+=0.20;if(regime==REG_RANGE)score+=0.05;}
   else score+=0.10;
   return Clamp(score,0,1);
}

//-------------------- Trading --------------------------------------
int OpenCount(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()==Symbol()&&OrderMagicNumber()==MagicNumber&&(OrderType()==OP_BUY||OrderType()==OP_SELL))n++;}return n;}
bool SpreadOK(){double p=MarketInfo(Symbol(),MODE_POINT);return p>0&&((Ask-Bid)/p)<=MaxSpreadPoints;}
double NormalizeLots(double x){double mn=MarketInfo(Symbol(),MODE_MINLOT),mx=MarketInfo(Symbol(),MODE_MAXLOT),st=MarketInfo(Symbol(),MODE_LOTSTEP);if(st<=0)st=mn;x=MathMax(mn,MathMin(mx,x));return NormalizeDouble(MathFloor(x/st+1e-8)*st,2);}
double CalcLots(){
   if(!UseRiskPercent||StopLossPoints<=0)return NormalizeLots(Lots);
   double tv=MarketInfo(Symbol(),MODE_TICKVALUE),ts=MarketInfo(Symbol(),MODE_TICKSIZE),pt=MarketInfo(Symbol(),MODE_POINT);
   if(tv<=0||ts<=0||pt<=0)return NormalizeLots(Lots);
   double risk=AccountBalance()*RiskPercent/100.0,val=tv*(pt/ts),x=SafeDiv(risk,StopLossPoints*val);return NormalizeLots(x);
}
void AdjustStops(int type,double &sl,double &tp){
   double p=MarketInfo(Symbol(),MODE_POINT),minD=MarketInfo(Symbol(),MODE_STOPLEVEL)*p;RefreshRates();
   if(type==OP_BUY){if(sl>0&&Bid-sl<minD)sl=Bid-minD;if(tp>0&&tp-Bid<minD)tp=Bid+minD;}
   else{if(sl>0&&sl-Ask<minD)sl=Ask+minD;if(tp>0&&Ask-tp<minD)tp=Ask-minD;}
   if(sl>0)sl=NormalizeDouble(sl,Digits);if(tp>0)tp=NormalizeDouble(tp,Digits);
}

//-------------------- Snapshot attribution -------------------------
int FindSnapshot(int ticket){for(int i=0;i<g_snapCount;i++)if(g_snap[i].ticket==ticket)return i;return -1;}
void RemoveSnapshot(int idx){if(idx<0||idx>=g_snapCount)return;for(int i=idx+1;i<g_snapCount;i++)g_snap[i-1]=g_snap[i];g_snapCount--;}
void SaveSnapshot(int ticket,int dir,int strategy,int regime,double score,double edge,int consensus,string reason){
   if(!EnableOutcomeAttribution)return;int idx=FindSnapshot(ticket);if(idx<0){if(g_snapCount>=MAX_SNAPSHOTS){for(int i=1;i<MAX_SNAPSHOTS;i++)g_snap[i-1]=g_snap[i];g_snapCount=MAX_SNAPSHOTS-1;}idx=g_snapCount++;}
   g_snap[idx].ticket=ticket;g_snap[idx].type=(dir==DIR_BUY?OP_BUY:OP_SELL);g_snap[idx].strategy=strategy;g_snap[idx].regime=regime;g_snap[idx].consensus=consensus;g_snap[idx].openTime=TimeCurrent();g_snap[idx].entryScore=score;g_snap[idx].directional=edge;g_snap[idx].atr=ATRv(1);g_snap[idx].adx=ADXv(1);g_snap[idx].rsi=RSIv(1);g_snap[idx].stopPoints=StopLossPoints;g_snap[idx].targetPoints=TakeProfitPoints;g_snap[idx].reason=reason;
}
void UpdateAudit(int dir,int strategy,int regime,double profit){
   int d=(dir==DIR_BUY?0:1);DirectionAudit &a=g_dir[d];a.samples++;if(profit>0){a.wins++;a.grossProfit+=profit;}else if(profit<0){a.losses++;a.grossLoss+=MathAbs(profit);}a.netProfit+=profit;a.winRate=SafeDiv(a.wins,a.samples);a.profitFactor=SafeDiv(a.grossProfit,a.grossLoss);a.avgProfit=SafeDiv(a.netProfit,a.samples);a.lastScore=g_lastScore;
   if(strategy>=0&&strategy<STRATEGY_COUNT&&regime>=0&&regime<REGIME_COUNT){CellAudit &c=g_cell[strategy][d][regime];c.samples++;if(profit>0){c.wins++;c.grossProfit+=profit;}else if(profit<0){c.losses++;c.grossLoss+=MathAbs(profit);}c.netProfit+=profit;c.winRate=SafeDiv(c.wins,c.samples);c.profitFactor=SafeDiv(c.grossProfit,c.grossLoss);c.avgProfit=SafeDiv(c.netProfit,c.samples);}
}

//-------------------- CSV ------------------------------------------
void ExportClosed(int ticket,int dir,int strategy,int regime,double profit,TradeSnapshot &s){
   if(!ExportCSV)return;int flags=FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE;if(ExportToCommonFolder)flags|=FILE_COMMON;int h=FileOpen(CSVFileName,flags,',');if(h==INVALID_HANDLE){Print("CSV FileOpen error=",GetLastError());return;}FileSeek(h,0,SEEK_END);if(FileSize(h)==0)FileWrite(h,"timestamp","symbol","ticket","direction","strategy","regime","profit","entry_score","directional","consensus","atr","adx","rsi","stop_points","target_points","reason");FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),Symbol(),ticket,DirName(dir),strategy>=0&&strategy<STRATEGY_COUNT?StrategyName[strategy]:"UNKNOWN",RegimeName(regime),DoubleToString(profit,2),DoubleToString(s.entryScore,6),DoubleToString(s.directional,6),s.consensus,DoubleToString(s.atr,Digits),DoubleToString(s.adx,4),DoubleToString(s.rsi,4),DoubleToString(s.stopPoints,2),DoubleToString(s.targetPoints,2),SafeText(s.reason));FileFlush(h);FileClose(h);
}
void AttributeClosedOrders(){
   if(!EnableOutcomeAttribution)return;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))continue;if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber)continue;if(OrderType()!=OP_BUY&&OrderType()!=OP_SELL)continue;
      int ticket=OrderTicket(),idx=FindSnapshot(ticket);if(idx<0)continue;double profit=OrderProfit()+OrderSwap()+OrderCommission();int dir=(OrderType()==OP_BUY?DIR_BUY:DIR_SELL);UpdateAudit(dir,g_snap[idx].strategy,g_snap[idx].regime,profit);ExportClosed(ticket,dir,g_snap[idx].strategy,g_snap[idx].regime,profit,g_snap[idx]);Print("CLOSED ticket=",ticket," profit=",DoubleToString(profit,2)," ",DirName(dir)," ",StrategyName[g_snap[idx].strategy]," ",RegimeName(g_snap[idx].regime));RemoveSnapshot(idx);
   }
}

//-------------------- Entry ----------------------------------------
bool GenerateSignal(int &signal,int &strategy,int &regime,double &score,double &edge,int &consensus,string &reason){
   signal=DIR_NONE;strategy=-1;regime=DetectRegime();score=0;edge=0;consensus=0;reason="";int buys,sells;BuildVotes(buys,sells);edge=DirectionalEdge(buys,sells);
   if(buys>sells){signal=DIR_BUY;consensus=buys;}else if(sells>buys){signal=DIR_SELL;consensus=sells;}else{reason="NO_DIRECTIONAL_EDGE";return false;}
   if(MathAbs(edge)<MinDirectionalEdge){reason="DIRECTIONAL_EDGE_TOO_SMALL";return false;}
   if(consensus<MinConsensus){reason="CONSENSUS_TOO_SMALL";return false;}
   if(UseRegimeFilter&&((signal==DIR_BUY&&regime==REG_TREND_DOWN)||(signal==DIR_SELL&&regime==REG_TREND_UP))){reason="REGIME_CONFLICT";return false;}
   score=EntryScore(signal,regime,buys,sells);if(UseAdaptiveEntry&&score<MinEntryScore){reason="ENTRY_SCORE_TOO_LOW";return false;}
   strategy=SelectStrategy(signal,regime);if(strategy<0){reason="NO_SUPPORTING_STRATEGY";return false;}reason="ENSEMBLE_OK";return true;
}

bool OpenTrade(int signal,int strategy,int regime,double score,double edge,int consensus,string reason){
   if(!SpreadOK()||signal==DIR_NONE)return false;if(OneTradePerSymbol&&OpenCount()>0)return false;if(signal==DIR_BUY&&!AllowBuy)return false;if(signal==DIR_SELL&&!AllowSell)return false;
   double p=MarketInfo(Symbol(),MODE_POINT);if(p<=0)return false;int type=(signal==DIR_BUY?OP_BUY:OP_SELL);double lots=CalcLots();RefreshRates();double price=(type==OP_BUY?Ask:Bid),sl=0,tp=0;if(StopLossPoints>0)sl=(type==OP_BUY?price-StopLossPoints*p:price+StopLossPoints*p);if(TakeProfitPoints>0)tp=(type==OP_BUY?price+TakeProfitPoints*p:price-TakeProfitPoints*p);AdjustStops(type,sl,tp);
   string comment="Bitey263|S"+IntegerToString(strategy+1)+"|"+DirName(signal)+"|"+RegimeName(regime);ResetLastError();int ticket=OrderSend(Symbol(),type,lots,price,Slippage,sl,tp,comment,MagicNumber,0,clrNONE);if(ticket<0){Print("OrderSend failed error=",GetLastError());return false;}SaveSnapshot(ticket,signal,strategy,regime,score,edge,consensus,reason);Print("OPEN ticket=",ticket," ",DirName(signal)," ",StrategyName[strategy]," ",RegimeName(regime)," score=",DoubleToString(score,4)," edge=",DoubleToString(edge,4));return true;
}

//-------------------- Trailing -------------------------------------
void ManageTrailing(){
   if(!EnableTrailing)return;double p=MarketInfo(Symbol(),MODE_POINT);if(p<=0)return;
   for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()!=Symbol()||OrderMagicNumber()!=MagicNumber)continue;int t=OrderType();if(t!=OP_BUY&&t!=OP_SELL)continue;RefreshRates();double pts=(t==OP_BUY?(Bid-OrderOpenPrice())/p:(OrderOpenPrice()-Ask)/p);if(pts<TrailStartPoints)continue;double sl=(t==OP_BUY?Bid-TrailDistancePoints*p:Ask+TrailDistancePoints*p);if(t==OP_BUY){if(OrderStopLoss()>0&&sl<=OrderStopLoss())continue;}else{if(OrderStopLoss()>0&&sl>=OrderStopLoss())continue;}sl=NormalizeDouble(sl,Digits);if(!OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE))Print("Trailing error=",GetLastError());}
}

//-------------------- Logging / chart ------------------------------
void PrintAudit(){for(int d=0;d<2;d++)Print("AUDIT ",d==0?"BUY":"SELL"," n=",g_dir[d].samples," wins=",g_dir[d].wins," losses=",g_dir[d].losses," net=",DoubleToString(g_dir[d].netProfit,2)," WR=",DoubleToString(g_dir[d].winRate*100,2),"% PF=",DoubleToString(g_dir[d].profitFactor,3)," avg=",DoubleToString(g_dir[d].avgProfit,2));}
void PrintCells(){for(int s=0;s<STRATEGY_COUNT;s++)for(int d=0;d<2;d++)for(int r=0;r<REGIME_COUNT;r++)if(g_cell[s][d][r].samples>0)Print("CELL ",StrategyName[s]," ",d==0?"BUY":"SELL"," ",RegimeName(r)," n=",g_cell[s][d][r].samples," net=",DoubleToString(g_cell[s][d][r].netProfit,2)," PF=",DoubleToString(g_cell[s][d][r].profitFactor,3));}
void UpdateComment(){Comment("Bitey IA MT4 v2.63\nSignal: ",DirName(g_lastSignal),"\nScore: ",DoubleToString(g_lastScore,3),"\nDirectional: ",DoubleToString(g_lastDirectional,3),"\nConsensus: ",g_lastConsensus,"\nStrategy: ",g_lastStrategy>=0?StrategyName[g_lastStrategy]:"NONE","\nRegime: ",RegimeName(g_lastRegime),"\nOpen: ",OpenCount());}

void ProcessNewBar(){int sig,st,reg,cons;double score,edge;string reason;bool ok=GenerateSignal(sig,st,reg,score,edge,cons,reason);g_lastSignal=sig;g_lastStrategy=st;g_lastRegime=reg;g_lastConsensus=cons;g_lastScore=score;g_lastDirectional=edge;Print("DECISION valid=",ok," signal=",DirName(sig)," score=",DoubleToString(score,4)," edge=",DoubleToString(edge,4)," consensus=",cons," strategy=",st>=0?StrategyName[st]:"NONE"," regime=",RegimeName(reg)," reason=",reason);if(ok)OpenTrade(sig,st,reg,score,edge,cons,reason);}

int OnInit(){g_lastBar=iTime(NULL,0,0);g_snapCount=0;Print("Bitey IA MT4 v2.63 COMPLETE FIXED initialized. Symbol=",Symbol()," Period=",Period()," Magic=",MagicNumber);return INIT_SUCCEEDED;}
void OnDeinit(const int reason){AttributeClosedOrders();PrintAudit();PrintCells();Comment("");}
void OnTick(){AttributeClosedOrders();ManageTrailing();UpdateComment();datetime b=iTime(NULL,0,0);if(b<=0)return;if(b!=g_lastBar){g_lastBar=b;ProcessNewBar();}}
//+------------------------------------------------------------------+
