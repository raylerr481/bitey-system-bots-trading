#property strict
#property version   "1.29"
#property description "AI Trading Bot v1.29 - Signal and Trade Audit"

input bool   InpAllowBuy=true;
input bool   InpAllowSell=true;
input double InpRiskPct=0.25;
input int    InpMaxTrades=1;
input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int    InpATRPeriod=14;
input double InpMinATRPoints=20.0;
input int    InpADXPeriod=14;
input double InpADXMin=20.0;
input int    InpRSIPeriod=14;
input double InpRSIBuyMin=50.0;
input double InpRSIBuyMax=68.0;
input double InpRSISellMin=32.0;
input double InpRSISellMax=50.0;
input int    InpFastEMA=8;
input int    InpSlowEMA=21;
input int    InpMacroEMA=200;
input bool   InpUseMacroSlope=true;
input bool   InpUseHTFTrend=false;
input ENUM_TIMEFRAMES InpHTF=PERIOD_H4;
input int    InpBuyMinScore=5;
input int    InpSellMinScore=5;
input double InpSLMult=1.30;
input double InpTPMult=2.60;
input double InpBEStartMult=1.10;
input double InpBELockMult=0.05;
input double InpTrailStartMult=1.60;
input double InpTrailDistMult=0.90;
input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
input int    InpCooldownBars=3;
input int    InpMagicNumber=8883190;
input bool   InpAuditCSV=true;

int gBars=0,gBlockedSpread=0,gBlockedATR=0,gBlockedSession=0,gBlockedCooldown=0;
int gBuyPotential=0,gSellPotential=0,gBuyApproved=0,gSellApproved=0,gBuyOrders=0,gSellOrders=0,gOrderErrors=0;
datetime gLastBar=0,gLastTradeBar=0;

string GVPrefix(){return("ATB129_"+_Symbol+"_"+IntegerToString(Period())+"_");}

bool NewBar(){datetime t=iTime(_Symbol,_Period,0); if(t!=gLastBar){gLastBar=t;return(true);} return(false);}

int OpenTrades(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--){if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)&&OrderSymbol()==_Symbol&&OrderMagicNumber()==InpMagicNumber)n++;}return(n);}

bool SessionOK(){int h=TimeHour(TimeCurrent());if(h<InpStartHour||h>=InpEndHour)return(false);if(TimeDayOfWeek(TimeCurrent())==5&&h>=InpFridayCloseHour)return(false);return(true);}

bool CooldownOK(){if(gLastTradeBar==0)return(true);int shift=iBarShift(_Symbol,_Period,gLastTradeBar,false);return(shift>=InpCooldownBars);}

double ATR(int s){return(iATR(_Symbol,_Period,InpATRPeriod,s));}

double LotByRisk(double slDistance){double riskMoney=AccountBalance()*InpRiskPct/100.0;double tv=MarketInfo(_Symbol,MODE_TICKVALUE);double ts=MarketInfo(_Symbol,MODE_TICKSIZE);double step=MarketInfo(_Symbol,MODE_LOTSTEP);double minLot=MarketInfo(_Symbol,MODE_MINLOT);double maxLot=MarketInfo(_Symbol,MODE_MAXLOT);if(tv<=0||ts<=0||slDistance<=0)return(minLot);double lossPerLot=(slDistance/ts)*tv;if(lossPerLot<=0)return(minLot);double lots=riskMoney/lossPerLot;lots=MathMin(lots,maxLot);lots=MathFloor(lots/step)*step;lots=MathMax(lots,minLot);return(NormalizeDouble(lots,2));}

void Audit(string phase,string decision,int bs,int ss,double atr,double adx,double rsi,double spread,double macroSlope,double htf,int err){
   if(InpAuditCSV){string f="AI_Trading_Bot_v1.29_Audit.csv";int h=FileOpen(f,FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_WRITE,';');if(h!=INVALID_HANDLE){FileSeek(h,0,SEEK_END);if(FileSize(h)==0)FileWrite(h,"time","symbol","tf","phase","decision","buyScore","sellScore","atrPts","adx","rsi","spreadPts","macroSlopePts","htf","error");FileWrite(h,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),_Symbol,Period(),phase,decision,bs,ss,atr/Point,adx,rsi,spread/Point,macroSlope/Point,htf,err);FileClose(h);}}
}

int ScoreBuy(double c1,double f1,double s1,double m1,double m2,double adx,double rsi,double atr,bool htfBull){int s=0;if(c1>m1&&( !InpUseMacroSlope || m1>m2))s++;if(f1>s1)s++;if(adx>=InpADXMin)s++;if(rsi>=InpRSIBuyMin&&rsi<=InpRSIBuyMax)s++;if(atr/Point>=InpMinATRPoints)s++;if(iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2)<=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,2)&&f1>s1)s++;if(c1>f1&&f1>s1)s++;if(InpUseHTFTrend&&htfBull)s++;return(s);}
int ScoreSell(double c1,double f1,double s1,double m1,double m2,double adx,double rsi,double atr,bool htfBear){int s=0;if(c1<m1&&( !InpUseMacroSlope || m1<m2))s++;if(f1<s1)s++;if(adx>=InpADXMin)s++;if(rsi>=InpRSISellMin&&rsi<=InpRSISellMax)s++;if(atr/Point>=InpMinATRPoints)s++;if(iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2)>=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,2)&&f1<s1)s++;if(c1<f1&&f1<s1)s++;if(InpUseHTFTrend&&htfBear)s++;return(s);}

bool SendTrade(int type,double atr,int bs,int ss,double adx,double rsi,double spread,double macroSlope,double htf){double price=(type==OP_BUY?Ask:Bid);double slDist=MathMax(atr*InpSLMult,MarketInfo(_Symbol,MODE_STOPLEVEL)*Point+Point);double tpDist=MathMax(atr*InpTPMult,MarketInfo(_Symbol,MODE_STOPLEVEL)*Point+Point);double sl=(type==OP_BUY?price-slDist:price+slDist);double tp=(type==OP_BUY?price+tpDist:price-tpDist);sl=NormalizeDouble(sl,Digits);tp=NormalizeDouble(tp,Digits);double lots=LotByRisk(slDist);ResetLastError();int ticket=OrderSend(_Symbol,type,lots,price,5,sl,tp,"AI129",InpMagicNumber,0,clrNONE);int e=GetLastError();if(ticket<0){gOrderErrors++;Audit("ORDER_ERROR",type==OP_BUY?"BUY":"SELL",bs,ss,atr,adx,rsi,spread,macroSlope,htf,e);Print("v1.29 OrderSend error=",e);return(false);}gLastTradeBar=iTime(_Symbol,_Period,0);if(type==OP_BUY)gBuyOrders++;else gSellOrders++;Audit("ORDER_OPEN",type==OP_BUY?"BUY":"SELL",bs,ss,atr,adx,rsi,spread,macroSlope,htf,0);return(true);}

void Manage(){for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;double atr=ATR(0);if(atr<=0)continue;double op=OrderOpenPrice(),sl=OrderStopLoss();if(OrderType()==OP_BUY){double profit=Bid-op;if(profit>=atr*InpBEStartMult){double nsl=NormalizeDouble(op+atr*InpBELockMult,Digits);if(sl<nsl)OrderModify(OrderTicket(),op,nsl,OrderTakeProfit(),0,clrNONE);}if(profit>=atr*InpTrailStartMult){double nsl=NormalizeDouble(Bid-atr*InpTrailDistMult,Digits);if(nsl>OrderStopLoss())OrderModify(OrderTicket(),op,nsl,OrderTakeProfit(),0,clrNONE);}}else if(OrderType()==OP_SELL){double profit=op-Ask;if(profit>=atr*InpBEStartMult){double nsl=NormalizeDouble(op-atr*InpBELockMult,Digits);if(sl==0||sl>nsl)OrderModify(OrderTicket(),op,nsl,OrderTakeProfit(),0,clrNONE);}if(profit>=atr*InpTrailStartMult){double nsl=NormalizeDouble(Ask+atr*InpTrailDistMult,Digits);if(OrderStopLoss()==0||nsl<OrderStopLoss())OrderModify(OrderTicket(),op,nsl,OrderTakeProfit(),0,clrNONE);}}}}

void Analyze(){gBars++;double atr=ATR(1);double spread=Ask-Bid;double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);double rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1);double c1=iClose(_Symbol,_Period,1);double f1=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);double s1=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);double m1=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1);double m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2);double macroSlope=m1-m2;double htf1=iMA(_Symbol,InpHTF,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1);double htf2=iMA(_Symbol,InpHTF,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2);bool htfBull=htf1>htf2&&c1>htf1;bool htfBear=htf1<htf2&&c1<htf1;
 if(!SessionOK()){gBlockedSession++;Audit("BLOCK","SESSION",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}if(spread/Point>InpMaxSpreadPoints){gBlockedSpread++;Audit("BLOCK","SPREAD",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}if(atr/Point<InpMinATRPoints){gBlockedATR++;Audit("BLOCK","ATR",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}if(atr>0&&spread/atr>InpMaxSpreadATRRatio){gBlockedSpread++;Audit("BLOCK","SPREAD_ATR",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}if(!CooldownOK()){gBlockedCooldown++;Audit("BLOCK","COOLDOWN",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}if(OpenTrades()>=InpMaxTrades){Audit("BLOCK","MAX_TRADES",0,0,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);return;}
 int bs=ScoreBuy(c1,f1,s1,m1,m2,adx,rsi,atr,htfBull);int ss=ScoreSell(c1,f1,s1,m1,m2,adx,rsi,atr,htfBear);if(bs>=InpBuyMinScore)gBuyPotential++;if(ss>=InpSellMinScore)gSellPotential++;string d="WAIT";if(bs>=InpBuyMinScore&&ss>=InpSellMinScore)d=(bs>ss?"BUY":"SELL");else if(bs>=InpBuyMinScore)d="BUY";else if(ss>=InpSellMinScore)d="SELL";if(d=="BUY"){gBuyApproved++;if(InpAllowBuy)SendTrade(OP_BUY,atr,bs,ss,adx,rsi,spread,macroSlope,htf1-htf2);}else if(d=="SELL"){gSellApproved++;if(InpAllowSell)SendTrade(OP_SELL,atr,bs,ss,adx,rsi,spread,macroSlope,htf1-htf2);}Audit("SIGNAL",d,bs,ss,atr,adx,rsi,spread,macroSlope,htf1-htf2,0);}

void FinalReport(){Print("=== AI TRADING BOT v1.29 AUDIT ===");Print("Bars=",gBars," BuyPotential=",gBuyPotential," SellPotential=",gSellPotential);Print("BuyApproved=",gBuyApproved," SellApproved=",gSellApproved);Print("BuyOrders=",gBuyOrders," SellOrders=",gSellOrders," OrderErrors=",gOrderErrors);Print("Blocks Spread=",gBlockedSpread," ATR=",gBlockedATR," Session=",gBlockedSession," Cooldown=",gBlockedCooldown);}

int OnInit(){Print("INIT_OK v1.29 Audit");return(INIT_SUCCEEDED);}void OnDeinit(const int reason){FinalReport();}
void OnTick(){Manage();if(NewBar())Analyze();}
