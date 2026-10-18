#property strict
#property version   "1.25"
#property description "AI Trading Bot v1.25 - Backtest Execution"

input bool   InpDiagnosticMode=false;
input bool   InpDemoSafeMode=false;
input double InpRiskPct=0.25;
input double InpMaxLots=2.0;
input int    InpMaxTrades=1;
input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
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
input int    InpMinScore=5;
input int    InpCooldownBars=3;
input double InpSLMult=1.5;
input double InpTPMult=3.0;
input double InpBEStartMult=1.2;
input double InpBELockMult=0.1;
input double InpTrailStartMult=1.8;
input double InpTrailDistMult=1.0;
input int    InpMagicNumber=8883150;
input int    InpSlippage=5;

int g_bars=0,g_signals=0,g_orders=0,g_orderErrors=0,g_blocks=0;
datetime g_lastBar=0,g_lastEntryBar=0;

bool NewBar(){datetime t=iTime(_Symbol,_Period,0);if(t==0)return false;if(t!=g_lastBar){g_lastBar=t;return true;}return false;}
bool SessionOK(){int h=TimeHour(iTime(_Symbol,_Period,1));return h>=InpStartHour&&h<InpEndHour;}
bool FridayOK(){datetime t=iTime(_Symbol,_Period,1);return !(TimeDayOfWeek(t)==5&&TimeHour(t)>=InpFridayCloseHour);}
int OpenTrades(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES)&&OrderSymbol()==_Symbol&&OrderMagicNumber()==InpMagicNumber)n++;return n;}
bool CooldownOK(){if(g_lastEntryBar==0)return true;int sh=iBarShift(_Symbol,_Period,g_lastEntryBar,true);return sh>=InpCooldownBars||sh<0;}

int BuyScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh),m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);int x=0;
 if(c>m&&m>m2)x++; if(f>s)x++; if(adx>=InpADXMin)x++; if(r>=InpRSIBuyMin&&r<=InpRSIBuyMax)x++; if(atr/Point>=InpMinATRPoints)x++; if(fp<=sp&&f>s)x++; if(c>f&&iClose(_Symbol,_Period,sh+1)<=fp)x++; return x;
}
int SellScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh),m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);int x=0;
 if(c<m&&m<m2)x++; if(f<s)x++; if(adx>=InpADXMin)x++; if(r>=InpRSISellMin&&r<=InpRSISellMax)x++; if(atr/Point>=InpMinATRPoints)x++; if(fp>=sp&&f<s)x++; if(c<f&&iClose(_Symbol,_Period,sh+1)>=fp)x++; return x;
}

double LotsByRisk(double slPoints){
 if(slPoints<=0)return 0;
 double riskMoney=AccountBalance()*InpRiskPct/100.0;
 double tickValue=MarketInfo(_Symbol,MODE_TICKVALUE),tickSize=MarketInfo(_Symbol,MODE_TICKSIZE);
 if(tickValue<=0||tickSize<=0)return 0;
 double lossPerLot=slPoints*Point/tickSize*tickValue;
 if(lossPerLot<=0)return 0;
 double lots=riskMoney/lossPerLot;
 double minLot=MarketInfo(_Symbol,MODE_MINLOT),maxLot=MarketInfo(_Symbol,MODE_MAXLOT),step=MarketInfo(_Symbol,MODE_LOTSTEP);
 maxLot=MathMin(maxLot,InpMaxLots); lots=MathMin(lots,maxLot); lots=MathFloor(lots/step)*step;
 if(lots<minLot)lots=minLot;
 return NormalizeDouble(lots,2);
}

bool SendTrade(int dir,double atr){
 RefreshRates(); double slPts=atr/Point*InpSLMult,tpPts=atr/Point*InpTPMult; double lots=LotsByRisk(slPts); if(lots<=0){g_orderErrors++;Print("v1.25 LOT ERROR");return false;}
 double price,sl,tp; int type;
 if(dir==1){type=OP_BUY;price=Ask;sl=NormalizeDouble(price-slPts*Point,Digits);tp=NormalizeDouble(price+tpPts*Point,Digits);}
 else {type=OP_SELL;price=Bid;sl=NormalizeDouble(price+slPts*Point,Digits);tp=NormalizeDouble(price-tpPts*Point,Digits);}
 ResetLastError(); int ticket=OrderSend(_Symbol,type,lots,price,InpSlippage,sl,tp,"AI v1.25",InpMagicNumber,0,clrNONE);
 if(ticket<0){int e=GetLastError();g_orderErrors++;Print("v1.25 OrderSend ERROR=",e," dir=",dir," lots=",DoubleToString(lots,2));return false;}
 g_orders++;g_lastEntryBar=iTime(_Symbol,_Period,0);Print("v1.25 ORDER OPENED ticket=",ticket," type=",type," lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,Digits)," TP=",DoubleToString(tp,Digits));return true;
}

void Manage(){
 double atr=iATR(_Symbol,_Period,InpATRPeriod,0); if(atr<=0)return;
 for(int i=OrdersTotal()-1;i>=0;i--){if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES))continue;if(OrderSymbol()!=_Symbol||OrderMagicNumber()!=InpMagicNumber)continue;
  RefreshRates(); double op=OrderOpenPrice(),sl=OrderStopLoss(),tp=OrderTakeProfit(),newSL=sl;
  if(OrderType()==OP_BUY){double profit=Bid-op;if(profit>=atr*InpBEStartMult)newSL=MathMax(newSL,NormalizeDouble(op+atr*InpBELockMult,Digits));if(profit>=atr*InpTrailStartMult)newSL=MathMax(newSL,NormalizeDouble(Bid-atr*InpTrailDistMult,Digits));if(newSL>sl+Point)OrderModify(OrderTicket(),op,newSL,tp,0,clrNONE);}
  if(OrderType()==OP_SELL){double profit=op-Ask;if(profit>=atr*InpBEStartMult){double be=NormalizeDouble(op-atr*InpBELockMult,Digits);newSL=(sl==0?be:MathMin(sl,be));}if(profit>=atr*InpTrailStartMult){double tr=NormalizeDouble(Ask+atr*InpTrailDistMult,Digits);newSL=(newSL==0?tr:MathMin(newSL,tr));}if(sl==0||newSL<sl-Point)OrderModify(OrderTicket(),op,newSL,tp,0,clrNONE);}
 }
}

void Analyze(){
 g_bars++;int sh=1;double bid=MarketInfo(_Symbol,MODE_BID),ask=MarketInfo(_Symbol,MODE_ASK),spread=(ask-bid)/Point,atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 if(atr<=0)return;
 if(spread>InpMaxSpreadPoints||spread/(atr/Point)>InpMaxSpreadATRRatio||atr/Point<InpMinATRPoints||!SessionOK()||!FridayOK()){g_blocks++;return;}
 if(OpenTrades()>=InpMaxTrades||!CooldownOK()){g_blocks++;return;}
 int b=BuyScore(sh),s=SellScore(sh);int dir=0;if(b>=InpMinScore&&b>s)dir=1;else if(s>=InpMinScore&&s>b)dir=-1;if(dir==0)return;
 g_signals++;Print("v1.25 SIGNAL ",dir==1?"BUY":"SELL"," score=",dir==1?b:s," ATRpts=",DoubleToString(atr/Point,1));
 if(InpDiagnosticMode||InpDemoSafeMode){Print("v1.25 EXECUTION DISABLED");return;}
 SendTrade(dir,atr);
}

int OnInit(){Print("================================================");Print("AI TRADING BOT v1.25 - BACKTEST EXECUTION");Print("MODE Diagnostic=",InpDiagnosticMode," Safe=",InpDemoSafeMode," Risk=",InpRiskPct,"% Magic=",InpMagicNumber);Print("================================================");return INIT_SUCCEEDED;}
void OnDeinit(const int reason){Print("FINAL v1.25 Bars=",g_bars," Signals=",g_signals," Blocks=",g_blocks," Orders=",g_orders," OrderErrors=",g_orderErrors);}
void OnTick(){Manage();if(NewBar())Analyze();}
