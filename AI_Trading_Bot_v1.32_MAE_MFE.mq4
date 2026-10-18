#property strict
#property version "1.32"
#property description "AI Trading Bot v1.32 - MAE/MFE and Exit Reason Lab"

input bool InpAllowBuy=true;
input bool InpAllowSell=true;
input double InpRiskPct=0.25;
input int InpMaxTrades=1;
input int InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int InpATRPeriod=14;
input double InpMinATRPoints=20.0;
input int InpADXPeriod=14;
input double InpADXMin=20.0;
input int InpRSIPeriod=14;
input double InpRSIBuyMin=50.0;
input double InpRSIBuyMax=68.0;
input double InpRSISellMin=32.0;
input double InpRSISellMax=50.0;
input int InpFastEMA=8;
input int InpSlowEMA=21;
input int InpMacroEMA=200;
input bool InpUseMacroSlope=true;
input int InpBuyMinScore=5;
input int InpSellMinScore=5;
input double InpSLMult=1.30;
input double InpTPMult=2.60;
input int InpManagementMode=3; // 0=BE+Trailing, 1=BE only, 2=Trailing only, 3=SL/TP only
input double InpBEStartMult=1.35;
input double InpBELockMult=0.05;
input double InpTrailStartMult=1.95;
input double InpTrailDistMult=1.10;
input int InpStartHour=7;
input int InpEndHour=20;
input int InpFridayCloseHour=21;
input int InpCooldownBars=3;
input int InpMagicNumber=8883190;
input bool InpWriteCSV=true;
input bool InpVerboseLog=true;

string CSV="AI_Trading_Bot_v1.32_MAE_MFE.csv";
datetime g_lastBar=0,g_lastTradeBar=0;
int g_buySig=0,g_sellSig=0,g_buyOrd=0,g_sellOrd=0,g_err=0;
int g_spreadBlock=0,g_atrBlock=0,g_sessionBlock=0,g_cooldownBlock=0;
int g_bars=0,g_wins=0,g_losses=0,g_streak=0,g_maxWinStreak=0,g_maxLossStreak=0;

int g_trackTicket=-1;
double g_trackEntry=0,g_trackInitialRisk=0,g_trackMAE=0,g_trackMFE=0;
datetime g_trackOpen=0;

void LogCSV(string type,string detail,double v1=0,double v2=0,double v3=0,double v4=0,double v5=0,double v6=0){
   if(!InpWriteCSV)return;
   int h=FileOpen(CSV,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE)return;
   if(FileSize(h)==0)FileWrite(h,"time","type","detail","v1","v2","v3","v4","v5","v6");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),type,detail,
      DoubleToString(v1,6),DoubleToString(v2,6),DoubleToString(v3,6),
      DoubleToString(v4,6),DoubleToString(v5,6),DoubleToString(v6,6));
   FileClose(h);
}

bool NewBar(){datetime t=iTime(_Symbol,_Period,0);if(t!=g_lastBar){g_lastBar=t;return true;}return false;}
int OpenTrades(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))if(OrderSymbol()==_Symbol&&OrderMagicNumber()==InpMagicNumber)n++;return n;}
bool SessionOK(){int h=TimeHour(TimeCurrent()),d=TimeDayOfWeek(TimeCurrent());if(d==0||d==6)return false;if(d==5&&h>=InpFridayCloseHour)return false;return h>=InpStartHour&&h<InpEndHour;}
bool CooldownOK(){if(g_lastTradeBar==0)return true;int sh=iBarShift(_Symbol,_Period,g_lastTradeBar,true);return sh<0||sh>=InpCooldownBars;}

double LotRisk(double dist){double tv=MarketInfo(_Symbol,MODE_TICKVALUE),ts=MarketInfo(_Symbol,MODE_TICKSIZE),step=MarketInfo(_Symbol,MODE_LOTSTEP),mn=MarketInfo(_Symbol,MODE_MINLOT),mx=MarketInfo(_Symbol,MODE_MAXLOT);if(dist<=0||tv<=0||ts<=0||step<=0)return mn;double lots=(AccountBalance()*InpRiskPct/100.0)/(dist/ts*tv);lots=MathMin(mx,lots);lots=MathFloor(lots/step)*step;return NormalizeDouble(MathMax(mn,lots),2);}

int ScoreBuy(double c,double f,double s,double m1,double m2,double adx,double rsi,double atr){int x=0;if(c>m1)x++;if(f>s)x++;if(adx>=InpADXMin)x++;if(rsi>=InpRSIBuyMin&&rsi<=InpRSIBuyMax)x++;if(atr/Point>=InpMinATRPoints)x++;if(!InpUseMacroSlope||m1>m2)x++;if(c>f&&f>s)x++;return x;}
int ScoreSell(double c,double f,double s,double m1,double m2,double adx,double rsi,double atr){int x=0;if(c<m1)x++;if(f<s)x++;if(adx>=InpADXMin)x++;if(rsi>=InpRSISellMin&&rsi<=InpRSISellMax)x++;if(atr/Point>=InpMinATRPoints)x++;if(!InpUseMacroSlope||m1<m2)x++;if(c<f&&f<s)x++;return x;}

bool MarketOK(double atr){double spr=(Ask-Bid)/Point;if(spr>InpMaxSpreadPoints){g_spreadBlock++;return false;}if(atr/Point<InpMinATRPoints){g_atrBlock++;return false;}if(atr>0&&(Ask-Bid)/atr>InpMaxSpreadATRRatio){g_spreadBlock++;return false;}if(!SessionOK()){g_sessionBlock++;return false;}if(!CooldownOK()){g_cooldownBlock++;return false;}return true;}

void ResetTracker(){g_trackTicket=-1;g_trackEntry=0;g_trackInitialRisk=0;g_trackMAE=0;g_trackMFE=0;g_trackOpen=0;}

void StartTracker(int ticket){
   if(ticket<=0)return;
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES))return;
   g_trackTicket=ticket;
   g_trackEntry=OrderOpenPrice();
   g_trackInitialRisk=MathAbs(OrderOpenPrice()-OrderStopLoss());
   g_trackMAE=0;
   g_trackMFE=0;
   g_trackOpen=OrderOpenTime();
}

void UpdateTracker(){
   if(g_trackTicket<0)return;
   if(!OrderSelect(g_trackTicket,SELECT_BY_TICKET,MODE_TRADES)){return;}
   if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber){ResetTracker();return;}
   double favorable=0,adverse=0;
   if(OrderType()==OP_BUY){
      favorable=MathMax(0,Bid-g_trackEntry);
      adverse=MathMax(0,g_trackEntry-Bid);
   }else if(OrderType()==OP_SELL){
      favorable=MathMax(0,g_trackEntry-Ask);
      adverse=MathMax(0,Ask-g_trackEntry);
   }else return;
   if(favorable>g_trackMFE)g_trackMFE=favorable;
   if(adverse>g_trackMAE)g_trackMAE=adverse;
}

string ExitReasonFromHistory(){
   double cp=OrderClosePrice(),sl=OrderStopLoss(),tp=OrderTakeProfit();
   double tol=MathMax(3*Point,MarketInfo(_Symbol,MODE_SPREAD)*Point*2.0);
   if(tp>0&&MathAbs(cp-tp)<=tol)return "TP";
   if(sl>0&&MathAbs(cp-sl)<=tol)return "SL";
   return "OTHER";
}

void RecordClosedTrade(){
   if(g_trackTicket<0)return;
   if(!OrderSelect(g_trackTicket,SELECT_BY_TICKET,MODE_HISTORY))return;
   if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber){ResetTracker();return;}
   double result=OrderProfit()+OrderSwap()+OrderCommission();
   double maePts=g_trackMAE/Point,mfePts=g_trackMFE/Point;
   double maeR=(g_trackInitialRisk>0?g_trackMAE/g_trackInitialRisk:0);
   double mfeR=(g_trackInitialRisk>0?g_trackMFE/g_trackInitialRisk:0);
   double durationMin=(OrderCloseTime()-g_trackOpen)/60.0;
   string dir=(OrderType()==OP_BUY?"BUY":"SELL");
   string reason=ExitReasonFromHistory();
   LogCSV("EXIT",dir+"|"+reason,result,maePts,mfePts,maeR,mfeR,durationMin);
   if(InpVerboseLog)Print("v1.32 EXIT ticket=",g_trackTicket," dir=",dir," reason=",reason," result=",DoubleToString(result,2)," MAEpt=",DoubleToString(maePts,1)," MFEpt=",DoubleToString(mfePts,1)," MAER=",DoubleToString(maeR,2)," MFER=",DoubleToString(mfeR,2)," durationMin=",DoubleToString(durationMin,1));
   ResetTracker();
}

void SyncTracker(){
   if(g_trackTicket>=0){
      if(OrderSelect(g_trackTicket,SELECT_BY_TICKET,MODE_TRADES))return;
      if(OrderSelect(g_trackTicket,SELECT_BY_TICKET,MODE_HISTORY)){RecordClosedTrade();return;}
   }
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;
      if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;
      StartTracker(OrderTicket());
      return;
   }
}

bool SendOrder(int type,double atr){
   double minStop=MarketInfo(_Symbol,MODE_STOPLEVEL)*Point;
   double sd=MathMax(atr*InpSLMult,minStop+2*Point),td=MathMax(atr*InpTPMult,minStop+2*Point);
   double p=(type==OP_BUY?Ask:Bid);
   double sl=(type==OP_BUY?p-sd:p+sd),tp=(type==OP_BUY?p+td:p-td);
   sl=NormalizeDouble(sl,Digits);tp=NormalizeDouble(tp,Digits);
   double lots=LotRisk(sd);
   ResetLastError();
   int tk=OrderSend(_Symbol,type,lots,p,5,sl,tp,type==OP_BUY?"AI v1.32 BUY":"AI v1.32 SELL",InpMagicNumber,0,clrNONE);
   if(tk<0){int e=GetLastError();g_err++;LogCSV("ORDER_ERROR",IntegerToString(e));return false;}
   g_lastTradeBar=iTime(_Symbol,_Period,0);
   if(type==OP_BUY)g_buyOrd++;else g_sellOrd++;
   StartTracker(tk);
   LogCSV("ENTRY",type==OP_BUY?"BUY":"SELL",lots,sd/Point,td/Point,atr/Point);
   return true;
}

void Manage(){
   double atr=iATR(_Symbol,_Period,InpATRPeriod,0);if(atr<=0)return;
   double minStop=MarketInfo(_Symbol,MODE_STOPLEVEL)*Point;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;
      if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;
      double op=OrderOpenPrice(),sl=OrderStopLoss(),tp=OrderTakeProfit();
      if(OrderType()==OP_BUY){
         double pd=Bid-op;
         if((InpManagementMode==0||InpManagementMode==1)&&pd>=atr*InpBEStartMult){double ns=NormalizeDouble(op+atr*InpBELockMult,Digits);if((sl==0||ns>sl+Point)&&Bid-ns>=minStop)OrderModify(OrderTicket(),op,ns,tp,0,clrNONE);}
         if((InpManagementMode==0||InpManagementMode==2)&&pd>=atr*InpTrailStartMult){double ns=NormalizeDouble(Bid-atr*InpTrailDistMult,Digits);if((sl==0||ns>sl+Point)&&Bid-ns>=minStop)OrderModify(OrderTicket(),op,ns,tp,0,clrNONE);}
      }else if(OrderType()==OP_SELL){
         double pd=op-Ask;
         if((InpManagementMode==0||InpManagementMode==1)&&pd>=atr*InpBEStartMult){double ns=NormalizeDouble(op-atr*InpBELockMult,Digits);if((sl==0||ns<sl-Point)&&ns-Ask>=minStop)OrderModify(OrderTicket(),op,ns,tp,0,clrNONE);}
         if((InpManagementMode==0||InpManagementMode==2)&&pd>=atr*InpTrailStartMult){double ns=NormalizeDouble(Ask+atr*InpTrailDistMult,Digits);if((sl==0||ns<sl-Point)&&ns-Ask>=minStop)OrderModify(OrderTicket(),op,ns,tp,0,clrNONE);}
      }
   }
}

void Analyze(){
   if(iBars(_Symbol,_Period)<InpMacroEMA+20)return;
   g_bars++;
   double c=iClose(_Symbol,_Period,1),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1),m1=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1),m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2),adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1),rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1),atr=iATR(_Symbol,_Period,InpATRPeriod,1);
   if(atr<=0)return;
   int bs=ScoreBuy(c,f,s,m1,m2,adx,rsi,atr),ss=ScoreSell(c,f,s,m1,m2,adx,rsi,atr);
   bool bp=InpAllowBuy&&bs>=InpBuyMinScore,sp=InpAllowSell&&ss>=InpSellMinScore;
   if(bp)g_buySig++;if(sp)g_sellSig++;
   if(!MarketOK(atr)||OpenTrades()>=InpMaxTrades)return;
   int d=-1;
   if(bp&&(!sp||bs>ss))d=OP_BUY;else if(sp&&(!bp||ss>bs))d=OP_SELL;
   if(d==OP_BUY){LogCSV("SIGNAL","BUY",bs,adx,rsi,atr/Point);SendOrder(OP_BUY,atr);}
   else if(d==OP_SELL){LogCSV("SIGNAL","SELL",ss,adx,rsi,atr/Point);SendOrder(OP_SELL,atr);}
   if(InpVerboseLog)Print("v1.32 bar=",TimeToString(iTime(_Symbol,_Period,1))," BUYscore=",bs," SELLscore=",ss," ATRpts=",DoubleToString(atr/Point,1)," ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1));
}

void ClosedStats(){
   g_wins=0;g_losses=0;g_streak=0;g_maxWinStreak=0;g_maxLossStreak=0;int last=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY))continue;
      if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;
      double p=OrderProfit()+OrderSwap()+OrderCommission();
      if(p>0){g_wins++;if(last==1)g_streak++;else{g_streak=1;last=1;}g_maxWinStreak=MathMax(g_maxWinStreak,g_streak);}
      else if(p<0){g_losses++;if(last==-1)g_streak++;else{g_streak=1;last=-1;}g_maxLossStreak=MathMax(g_maxLossStreak,g_streak);}
   }
}

void Summary(){
   ClosedStats();
   Print("===== AI TRADING BOT v1.32 =====");
   Print("BUY signals=",g_buySig," orders=",g_buyOrd," | SELL signals=",g_sellSig," orders=",g_sellOrd);
   Print("Wins=",g_wins," Losses=",g_losses," maxWinStreak=",g_maxWinStreak," maxLossStreak=",g_maxLossStreak);
   Print("Blocks spread=",g_spreadBlock," ATR=",g_atrBlock," session=",g_sessionBlock," cooldown=",g_cooldownBlock," orderErrors=",g_err);
   Print("ManagementMode=",InpManagementMode," Risk=",DoubleToString(InpRiskPct,2),"%");
}

int OnInit(){LogCSV("INIT","v1.32");Print("INIT_OK AI Trading Bot v1.32");return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){SyncTracker();Summary();LogCSV("FINAL","v1.32",g_buyOrd,g_sellOrd,g_err);Comment("");}
void OnTick(){SyncTracker();UpdateTracker();Manage();if(NewBar())Analyze();}
