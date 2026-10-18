#property strict
#property version   "1.24"
#property description "AI Trading Bot v1.24 - Diagnostic Trace"

input bool   InpDiagnosticMode=true;
input bool   InpDemoSafeMode=true;
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
input int    InpMagicNumber=8883140;

int g_bars=0;
int g_marketEvaluated=0,g_marketBlocked=0;
int g_spreadBlocks=0,g_ratioBlocks=0,g_atrBlocks=0,g_sessionBlocks=0,g_fridayBlocks=0;
int g_buySignal=0,g_sellSignal=0,g_buyScoreOK=0,g_sellScoreOK=0;
int g_buyApproved=0,g_sellApproved=0,g_cooldownBlocks=0,g_riskBlocks=0;
int g_orderAttempts=0,g_orderSuccess=0,g_orderErrors=0;
int g_buyMacro=0,g_buyEMA=0,g_buyADX=0,g_buyRSI=0,g_buyATR=0,g_buyCross=0,g_buyConfirm=0;
int g_sellMacro=0,g_sellEMA=0,g_sellADX=0,g_sellRSI=0,g_sellATR=0,g_sellCross=0,g_sellConfirm=0;
int g_lastBuy=0,g_lastSell=0,g_lastDecision=0;
datetime g_lastBar=0;
string g_lastGate="NONE",g_lastStatus="STARTING";

string DText(int d){if(d==1)return "BUY";if(d==-1)return "SELL";return "WAIT";}
bool NewBar(){datetime t=iTime(_Symbol,_Period,0);if(t==0)return false;if(t!=g_lastBar){g_lastBar=t;return true;}return false;}
bool SessionOK(){int h=TimeHour(iTime(_Symbol,_Period,1));return(h>=InpStartHour&&h<InpEndHour);}
bool FridayOK(){datetime t=iTime(_Symbol,_Period,1);return!(TimeDayOfWeek(t)==5&&TimeHour(t)>=InpFridayCloseHour);}

int BuyScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh),m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 int x=0;
 if(c>m&&m>m2){x++;g_buyMacro++;} if(f>s){x++;g_buyEMA++;} if(adx>=InpADXMin){x++;g_buyADX++;} if(r>=InpRSIBuyMin&&r<=InpRSIBuyMax){x++;g_buyRSI++;} if(atr/Point>=InpMinATRPoints){x++;g_buyATR++;} if(fp<=sp&&f>s){x++;g_buyCross++;} if(c>f&&iClose(_Symbol,_Period,sh+1)<=fp){x++;g_buyConfirm++;}
 return x;
}
int SellScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh),m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);
 int x=0;
 if(c<m&&m<m2){x++;g_sellMacro++;} if(f<s){x++;g_sellEMA++;} if(adx>=InpADXMin){x++;g_sellADX++;} if(r>=InpRSISellMin&&r<=InpRSISellMax){x++;g_sellRSI++;} if(atr/Point>=InpMinATRPoints){x++;g_sellATR++;} if(fp>=sp&&f<s){x++;g_sellCross++;} if(c<f&&iClose(_Symbol,_Period,sh+1)>=fp){x++;g_sellConfirm++;}
 return x;
}

void Sig(){
 Print("============================================================");
 Print("AI TRADING BOT v1.24 - DIAGNOSTIC TRACE - EXECUTED");
 Print("SIGNATURE v1.24 / MAGIC=",InpMagicNumber," / SYMBOL=",_Symbol," / PERIOD=",Period());
 Print("DiagnosticMode=",InpDiagnosticMode," DemoSafeMode=",InpDemoSafeMode);
 Print("SpreadLimit=",InpMaxSpreadPoints," RatioLimit=",DoubleToString(InpMaxSpreadATRRatio,3)," MinATR=",DoubleToString(InpMinATRPoints,1)," MinScore=",InpMinScore);
 Print("============================================================");
}
void Final(){
 Print("================ FINAL DIAGNOSTIC v1.24 ==================");
 Print("BarsAnalyzed=",g_bars," MarketEvaluated=",g_marketEvaluated," MarketBlocked=",g_marketBlocked);
 Print("SpreadBlock=",g_spreadBlocks," RatioBlock=",g_ratioBlocks," ATRBlock=",g_atrBlocks," SessionBlock=",g_sessionBlocks," FridayBlock=",g_fridayBlocks);
 Print("BUY signal=",g_buySignal," scoreOK=",g_buyScoreOK," approved=",g_buyApproved);
 Print("SELL signal=",g_sellSignal," scoreOK=",g_sellScoreOK," approved=",g_sellApproved);
 Print("CooldownBlocked=",g_cooldownBlocks," RiskBlocked=",g_riskBlocks);
 Print("OrderAttempts=",g_orderAttempts," OrderSuccess=",g_orderSuccess," OrderErrors=",g_orderErrors);
 Print("BUY components macro=",g_buyMacro," EMA=",g_buyEMA," ADX=",g_buyADX," RSI=",g_buyRSI," ATR=",g_buyATR," Cross=",g_buyCross," Confirm=",g_buyConfirm);
 Print("SELL components macro=",g_sellMacro," EMA=",g_sellEMA," ADX=",g_sellADX," RSI=",g_sellRSI," ATR=",g_sellATR," Cross=",g_sellCross," Confirm=",g_sellConfirm);
 Print("LAST decision=",DText(g_lastDecision)," status=",g_lastStatus," gate=",g_lastGate);
 Print("===========================================================");
}

void Analyze(){
 int sh=1; g_bars++;
 double bid=MarketInfo(_Symbol,MODE_BID),ask=MarketInfo(_Symbol,MODE_ASK);
 double spread=(ask-bid)/Point;
 double atr=iATR(_Symbol,_Period,InpATRPeriod,sh),adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh);
 int bs=BuyScore(sh),ss=SellScore(sh); g_lastBuy=bs;g_lastSell=ss;g_lastDecision=0;g_lastGate="NONE";g_lastStatus="NO SIGNAL";
 g_marketEvaluated++;
 bool market=true;
 if(spread>InpMaxSpreadPoints){g_spreadBlocks++;market=false;g_lastGate="SPREAD";}
 if(atr<=0 || atr/Point<InpMinATRPoints){g_atrBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="ATR";}
 if(atr>0 && spread/(atr/Point)>InpMaxSpreadATRRatio){g_ratioBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="SPREAD/ATR";}
 if(!SessionOK()){g_sessionBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="SESSION";}
 if(!FridayOK()){g_fridayBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="FRIDAY";}
 bool buy=(bs>=InpMinScore),sell=(ss>=InpMinScore);
 if(buy){g_buySignal++;g_buyScoreOK++;g_lastDecision=1;}
 if(sell){g_sellSignal++;g_sellScoreOK++;if(g_lastDecision==0)g_lastDecision=-1;}
 if(!market)g_marketBlocked++;
 if(buy||sell)g_lastStatus=(market?"SIGNAL FOUND":"SIGNAL FOUND - MARKET BLOCKED");
 if(market&&(buy||sell)){g_lastStatus="SIGNAL FOUND - APPROVED IN DIAGNOSTIC";g_lastGate="APPROVED";if(buy)g_buyApproved++;if(sell)g_sellApproved++;}
 if(g_bars<=12 || g_bars%25==0 || buy || sell){
  Print("v1.24 BAR=",g_bars," TIME=",TimeToString(iTime(_Symbol,_Period,sh))," SPREAD=",DoubleToString(spread,1)," ATRpts=",DoubleToString(atr/Point,1)," ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1)," BUY=",bs," SELL=",ss," DECISION=",DText(g_lastDecision)," STATUS=",g_lastStatus," GATE=",g_lastGate);
 }
 string p="AI TRADING BOT v1.24\n";
 p+="EXECUTED | Bars="+IntegerToString(g_bars)+"\n";
 p+="Spread="+DoubleToString(spread,1)+" / "+IntegerToString(InpMaxSpreadPoints)+" | ATR="+DoubleToString(atr/Point,1)+" | ADX="+DoubleToString(adx,1)+" | RSI="+DoubleToString(rsi,1)+"\n";
 p+="BUY="+IntegerToString(bs)+" SELL="+IntegerToString(ss)+" | Decision="+DText(g_lastDecision)+"\n";
 p+="MarketBlocks S="+IntegerToString(g_spreadBlocks)+" R="+IntegerToString(g_ratioBlocks)+" A="+IntegerToString(g_atrBlocks)+" H="+IntegerToString(g_sessionBlocks)+" F="+IntegerToString(g_fridayBlocks)+"\n";
 p+="BUY sig/approved="+IntegerToString(g_buySignal)+"/"+IntegerToString(g_buyApproved)+" SELL="+IntegerToString(g_sellSignal)+"/"+IntegerToString(g_sellApproved)+"\n";
 p+="ORDERS DISABLED: DIAGNOSTIC";
 Comment(p);
}

int OnInit(){Sig();Print("INIT_OK v1.24");return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){Print("DEINIT v1.24 reason=",reason);Final();Comment("");}
void OnTick(){if(NewBar())Analyze();}
