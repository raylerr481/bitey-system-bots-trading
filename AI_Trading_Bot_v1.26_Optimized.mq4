#property strict
#property version   "1.26"
#property description "AI Trading Bot v1.26 - Optimized Backtest Engine"

input bool   InpEnableTrading=true;
input bool   InpDemoSafeMode=false;
input double InpRiskPct=0.25;
input double InpMaxLots=2.0;
input int    InpMaxTrades=1;
input int    InpMagicNumber=8883160;

input int    InpFastEMA=8;
input int    InpSlowEMA=21;
input int    InpMacroEMA=200;
input int    InpADXPeriod=14;
input double InpADXMin=20.0;
input int    InpRSIPeriod=14;
input double InpRSIBuyMin=52.0;
input double InpRSIBuyMax=67.0;
input double InpRSISellMin=33.0;
input double InpRSISellMax=48.0;
input int    InpATRPeriod=14;
input double InpMinATRPoints=15.0;
input double InpSLMult=1.30;
input double InpTPMult=2.60;
input double InpBEStartMult=1.10;
input double InpBELockMult=0.10;
input double InpTrailStartMult=1.70;
input double InpTrailDistMult=0.90;
input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
input int    InpCooldownBars=3;
input int    InpMinScore=5;
input bool   InpUseMacroSlope=true;
input bool   InpUseH4Filter=true;

int g_bars=0,g_buySignals=0,g_sellSignals=0,g_orders=0,g_errors=0,g_wins=0,g_losses=0;
datetime g_lastBar=0,g_lastTradeBar=0;

bool NewBar(){datetime t=iTime(_Symbol,_Period,0); if(t==0||t==g_lastBar)return false; g_lastBar=t; return true;}
bool SessionOK(){int h=TimeHour(iTime(_Symbol,_Period,1)); return h>=InpStartHour&&h<InpEndHour;}
bool FridayOK(){datetime t=iTime(_Symbol,_Period,1); return !(TimeDayOfWeek(t)==5&&TimeHour(t)>=InpFridayCloseHour);}
int CountOpen(){int n=0; for(int i=OrdersTotal()-1;i>=0;i--) if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) if(OrderSymbol()==_Symbol&&OrderMagicNumber()==InpMagicNumber&&(OrderType()==OP_BUY||OrderType()==OP_SELL)) n++; return n;}

double LotByRisk(double slPoints){
 if(slPoints<=0)return 0;
 double risk=AccountBalance()*InpRiskPct/100.0;
 double tv=MarketInfo(_Symbol,MODE_TICKVALUE), ts=MarketInfo(_Symbol,MODE_TICKSIZE);
 if(tv<=0||ts<=0)return 0;
 double lossPerLot=slPoints*Point/ts*tv;
 if(lossPerLot<=0)return 0;
 double lot=risk/lossPerLot;
 double minLot=MarketInfo(_Symbol,MODE_MINLOT),maxLot=MarketInfo(_Symbol,MODE_MAXLOT),step=MarketInfo(_Symbol,MODE_LOTSTEP);
 maxLot=MathMin(maxLot,InpMaxLots); lot=MathMin(lot,maxLot);
 if(step>0)lot=MathFloor(lot/step)*step;
 if(lot<minLot)return 0;
 return NormalizeDouble(lot,2);
}

int ScoreBuy(int sh){
 double c=iClose(_Symbol,_Period,sh), f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh), s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
 double m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh), m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh), r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh), atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1), sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 int x=0;
 if(c>m)x++;
 if(f>s)x++;
 if(InpUseMacroSlope && m>m2)x++;
 if(adx>=InpADXMin)x++;
 if(r>=InpRSIBuyMin&&r<=InpRSIBuyMax)x++;
 if(atr/Point>=InpMinATRPoints)x++;
 if(fp<=sp&&f>s)x++;
 if(c>f&&iClose(_Symbol,_Period,sh+1)<=fp)x++;
 return x;
}
int ScoreSell(int sh){
 double c=iClose(_Symbol,_Period,sh), f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh), s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh);
 double m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh), m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh), r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh), atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1), sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 int x=0;
 if(c<m)x++;
 if(f<s)x++;
 if(InpUseMacroSlope && m<m2)x++;
 if(adx>=InpADXMin)x++;
 if(r>=InpRSISellMin&&r<=InpRSISellMax)x++;
 if(atr/Point>=InpMinATRPoints)x++;
 if(fp>=sp&&f<s)x++;
 if(c<f&&iClose(_Symbol,_Period,sh+1)>=fp)x++;
 return x;
}

bool H4Buy(){if(!InpUseH4Filter)return true; double c=iClose(_Symbol,PERIOD_H4,1),e=iMA(_Symbol,PERIOD_H4,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1),e2=iMA(_Symbol,PERIOD_H4,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2); return c>e&&e>e2;}
bool H4Sell(){if(!InpUseH4Filter)return true; double c=iClose(_Symbol,PERIOD_H4,1),e=iMA(_Symbol,PERIOD_H4,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1),e2=iMA(_Symbol,PERIOD_H4,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2); return c<e&&e<e2;}

bool CooldownOK(){if(g_lastTradeBar==0)return true; int shift=iBarShift(_Symbol,_Period,g_lastTradeBar,false); return shift>=InpCooldownBars;}

void Manage(){
 double atr=iATR(_Symbol,_Period,InpATRPeriod,1); if(atr<=0)return;
 for(int i=OrdersTotal()-1;i>=0;i--) if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)){
  if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;
  if(OrderType()==OP_BUY){double gain=Bid-OrderOpenPrice(); if(gain>=atr*InpBEStartMult){double sl=NormalizeDouble(OrderOpenPrice()+atr*InpBELockMult,Digits); if(OrderStopLoss()<sl)OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE);} if(gain>=atr*InpTrailStartMult){double sl=NormalizeDouble(Bid-atr*InpTrailDistMult,Digits); if(sl>OrderStopLoss())OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE);}}
  if(OrderType()==OP_SELL){double gain=OrderOpenPrice()-Ask; if(gain>=atr*InpBEStartMult){double sl=NormalizeDouble(OrderOpenPrice()-atr*InpBELockMult,Digits); if(OrderStopLoss()==0||OrderStopLoss()>sl)OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE);} if(gain>=atr*InpTrailStartMult){double sl=NormalizeDouble(Ask+atr*InpTrailDistMult,Digits); if(OrderStopLoss()==0||sl<OrderStopLoss())OrderModify(OrderTicket(),OrderOpenPrice(),sl,OrderTakeProfit(),0,clrNONE);}}
 }
}

void Trade(int dir,double atr){
 if(!InpEnableTrading||InpDemoSafeMode)return;
 if(CountOpen()>=InpMaxTrades||!CooldownOK())return;
 double slDist=atr*InpSLMult,tpDist=atr*InpTPMult;
 double slPts=slDist/Point,lot=LotByRisk(slPts); if(lot<=0)return;
 RefreshRates(); int ticket=-1; double sl,tp;
 if(dir==1){sl=NormalizeDouble(Bid-slDist,Digits);tp=NormalizeDouble(Ask+tpDist,Digits);ticket=OrderSend(_Symbol,OP_BUY,lot,Ask,5,sl,tp,"Bitey v1.26 BUY",InpMagicNumber,0,clrNONE);if(ticket>0){g_orders++;g_lastTradeBar=iTime(_Symbol,_Period,0);}else g_errors++;}
 if(dir==-1){sl=NormalizeDouble(Ask+slDist,Digits);tp=NormalizeDouble(Bid-tpDist,Digits);ticket=OrderSend(_Symbol,OP_SELL,lot,Bid,5,sl,tp,"Bitey v1.26 SELL",InpMagicNumber,0,clrNONE);if(ticket>0){g_orders++;g_lastTradeBar=iTime(_Symbol,_Period,0);}else g_errors++;}
}

void Analyze(){
 g_bars++; int sh=1; double atr=iATR(_Symbol,_Period,InpATRPeriod,sh); if(atr<=0)return; double bid=MarketInfo(_Symbol,MODE_BID),ask=MarketInfo(_Symbol,MODE_ASK),spread=(ask-bid)/Point;
 if(spread>InpMaxSpreadPoints||spread/(atr/Point)>InpMaxSpreadATRRatio||atr/Point<InpMinATRPoints||!SessionOK()||!FridayOK())return;
 int b=ScoreBuy(sh),s=ScoreSell(sh); bool buy=b>=InpMinScore&&H4Buy(),sell=s>=InpMinScore&&H4Sell();
 if(buy&&sell){double c=iClose(_Symbol,_Period,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh);if(c>=m)sell=false;else buy=false;}
 if(buy){g_buySignals++;Trade(1,atr);} else if(sell){g_sellSignals++;Trade(-1,atr);}
}

int OnInit(){Print("AI TRADING BOT v1.26 - OPTIMIZED BACKTEST | MAGIC=",InpMagicNumber);Print("Risk=",InpRiskPct," SL=",InpSLMult," TP=",InpTPMult," MinScore=",InpMinScore," H4Filter=",InpUseH4Filter);return(INIT_SUCCEEDED);}
void OnTick(){Manage();if(NewBar())Analyze();}
void OnDeinit(const int reason){Print("FINAL v1.26 | Bars=",g_bars," BUY signals=",g_buySignals," SELL signals=",g_sellSignals," Orders=",g_orders," Errors=",g_errors);}
