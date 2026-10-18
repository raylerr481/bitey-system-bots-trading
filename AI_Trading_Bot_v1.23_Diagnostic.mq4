#property strict
#property version   "1.23"
#property description "AI Trading Bot v1.23 - Diagnostic Gate Audit"

input bool   InpDiagnosticMode=true;
input bool   InpDemoSafeMode=true;
input bool   InpUseExternalAI=false;
input string InpAIEndpoint="";
input double InpRiskPct=0.25;
input double InpMaxLots=2.0;
input int    InpMaxTrades=1;
input double InpMaxOpenRiskPct=0.50;

input int    InpFastEMA=8;
input int    InpSlowEMA=21;
input int    InpMacroEMA=200;
input int    InpADXPeriod=14;
input double InpADXMin=20.0;
input int    InpRSIPeriod=14;
input double InpRSIBuyMin=50.0;
input double InpRSIBuyMax=68.0;
input double InpRSISellMin=32.0;
input double InpRSISellMax=50.0;
input int    InpATRPeriod=14;
input double InpMinATRPoints=20.0;
input double InpSLMult=1.5;
input double InpTPMult=3.0;

input int    InpMaxSpreadPoints=30;
input double InpMaxSpreadATRRatio=0.20;
input int    InpStartHour=7;
input int    InpEndHour=20;
input int    InpFridayCloseHour=21;
input int    InpCooldownBars=3;
input int    InpMinScore=5;
input int    InpMagicNumber=8883130;

int g_bars=0,g_spreadBlocks=0,g_atrBlocks=0,g_sessionBlocks=0,g_fridayBlocks=0;
int g_marketBlocks=0,g_cooldownBlocks=0,g_riskBlocks=0;
int g_buyCandidates=0,g_sellCandidates=0,g_buyScoreOK=0,g_sellScoreOK=0;
int g_buyDecisions=0,g_sellDecisions=0,g_buyApproved=0,g_sellApproved=0;
int g_orderAttempts=0,g_orderSuccess=0,g_orderErrors=0;
int g_lastDecision=0,g_lastBuyScore=0,g_lastSellScore=0;
datetime g_lastBar=0;
string g_lastStatus="STARTING";
string g_lastGate="NONE";

string DecisionText(int d){ if(d==1)return "BUY"; if(d==-1)return "SELL"; return "WAIT"; }

bool IsNewBar(){ datetime t=iTime(_Symbol,_Period,0); if(t==0)return false; if(t!=g_lastBar){g_lastBar=t;return true;} return false; }

int CountOpen(){int n=0;for(int i=OrdersTotal()-1;i>=0;i--)if(OrderSelect(i,SELECT_BY_POS,MODE_TRADES))if(OrderSymbol()==_Symbol&&OrderMagicNumber()==InpMagicNumber)n++;return n;}

bool SessionOK(){int h=TimeHour(iTime(_Symbol,_Period,1));return h>=InpStartHour&&h<InpEndHour;}
bool FridayOK(){datetime t=iTime(_Symbol,_Period,1);return !(TimeDayOfWeek(t)==5&&TimeHour(t)>=InpFridayCloseHour);}

int BuyScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh);
 double m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 int x=0;if(c>m&&m>m2)x++;if(f>s)x++;if(adx>=InpADXMin)x++;if(r>=InpRSIBuyMin&&r<=InpRSIBuyMax)x++;if(atr/Point>=InpMinATRPoints)x++;
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);if(fp<=sp&&f>s)x++;
 if(c>f&&iClose(_Symbol,_Period,sh+1)<=fp)x++;return x;
}
int SellScore(int sh){
 double c=iClose(_Symbol,_Period,sh),f=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh),s=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh),m=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh);
 double m2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),r=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh),atr=iATR(_Symbol,_Period,InpATRPeriod,sh);
 int x=0;if(c<m&&m<m2)x++;if(f<s)x++;if(adx>=InpADXMin)x++;if(r>=InpRSISellMin&&r<=InpRSISellMax)x++;if(atr/Point>=InpMinATRPoints)x++;
 double fp=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,sh+1),sp=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,sh+1);if(fp>=sp&&f<s)x++;
 if(c<f&&iClose(_Symbol,_Period,sh+1)>=fp)x++;return x;
}

void PrintSignature(){
 Print("============================================================");
 Print("AI TRADING BOT v1.23 - DIAGNOSTIC GATE AUDIT");
 Print("MAGIC=",InpMagicNumber," SYMBOL=",_Symbol," TF=",Period());
 Print("DiagnosticMode=",InpDiagnosticMode," DemoSafeMode=",InpDemoSafeMode);
 Print("SpreadLimit=",InpMaxSpreadPoints," MinATR=",InpMinATRPoints," MinScore=",InpMinScore);
 Print("============================================================");
}

void PrintFinal(){
 Print("================ FINAL DIAGNOSTIC v1.23 ================");
 Print("BarsAnalyzed=",g_bars);
 Print("SpreadBlock=",g_spreadBlocks," ATRBlock=",g_atrBlocks," SessionBlock=",g_sessionBlocks," FridayBlock=",g_fridayBlocks);
 Print("MarketBlockedSignals=",g_marketBlocks," CooldownBlocked=",g_cooldownBlocks," RiskBlocked=",g_riskBlocks);
 Print("BUY candidates=",g_buyCandidates," SELL candidates=",g_sellCandidates);
 Print("BUY scoreOK=",g_buyScoreOK," SELL scoreOK=",g_sellScoreOK);
 Print("BUY decisions=",g_buyDecisions," SELL decisions=",g_sellDecisions);
 Print("BUY approved=",g_buyApproved," SELL approved=",g_sellApproved);
 Print("OrderAttempts=",g_orderAttempts," OrderSuccess=",g_orderSuccess," OrderErrors=",g_orderErrors);
 Print("LastDecision=",DecisionText(g_lastDecision)," LastStatus=",g_lastStatus," LastGate=",g_lastGate);
 Print("=========================================================");
}

void Panel(double spread,double atr,double adx,double rsi){
 string s="AI TRADING BOT v1.23 - DIAGNOSTIC\n";
 s+="Bars: "+IntegerToString(g_bars)+" | Spread: "+DoubleToString(spread,1)+" / "+IntegerToString(InpMaxSpreadPoints)+"\n";
 s+="ATR: "+DoubleToString(atr/Point,1)+" | ADX: "+DoubleToString(adx,1)+" | RSI: "+DoubleToString(rsi,1)+"\n";
 s+="BUY: "+IntegerToString(g_buyCandidates)+" cand / "+IntegerToString(g_buyScoreOK)+" score / "+IntegerToString(g_buyApproved)+" approved\n";
 s+="SELL: "+IntegerToString(g_sellCandidates)+" cand / "+IntegerToString(g_sellScoreOK)+" score / "+IntegerToString(g_sellApproved)+" approved\n";
 s+="Blocks: spread="+IntegerToString(g_spreadBlocks)+" ATR="+IntegerToString(g_atrBlocks)+" session="+IntegerToString(g_sessionBlocks)+" risk="+IntegerToString(g_riskBlocks)+"\n";
 s+="Decision: "+DecisionText(g_lastDecision)+" | "+g_lastStatus+" | "+g_lastGate+"\n";
 s+="ORDERS: "+(InpDiagnosticMode?"DISABLED - DIAGNOSTIC ONLY":"ENABLED")+" | SAFE="+(InpDemoSafeMode?"ON":"OFF");
 Comment(s);
}

void Analyze(){
 int sh=1; g_bars++;
 double bid=MarketInfo(_Symbol,MODE_BID),ask=MarketInfo(_Symbol,MODE_ASK),spread=(ask-bid)/Point;
 double atr=iATR(_Symbol,_Period,InpATRPeriod,sh),adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,sh),rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,sh);
 int bs=BuyScore(sh),ss=SellScore(sh); g_lastBuyScore=bs;g_lastSellScore=ss;g_lastDecision=0;g_lastGate="NONE";g_lastStatus="NO SIGNAL";
 bool market=true;
 if(spread>InpMaxSpreadPoints){g_spreadBlocks++;market=false;g_lastGate="SPREAD";}
 if(atr/Point<InpMinATRPoints){g_atrBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="ATR";}
 if(!SessionOK()){g_sessionBlocks++;market=false;if(g_lastGate=="NONE")g_lastGate="SESSION";}
 if(!FridayOK()){g_fridayBlocks++;market=false;if(g_lastGate=="FRIDAY"||g_lastGate=="NONE")g_lastGate="FRIDAY";}
 bool buy=(bs>=InpMinScore),sell=(ss>=InpMinScore);
 if(buy)g_buyScoreOK++;if(sell)g_sellScoreOK++;
 if(buy){g_buyCandidates++;g_buyDecisions++;g_lastDecision=1;}
 if(sell){g_sellCandidates++;g_sellDecisions++;if(g_lastDecision==0)g_lastDecision=-1;}
 if(buy||sell){g_lastStatus="SIGNAL FOUND";}
 if(!market){g_marketBlocks++;g_lastStatus="SIGNAL/MARKET BLOCKED";}
 if(market&&(buy||sell)){
   if(CountOpen()>=InpMaxTrades){g_riskBlocks++;g_lastStatus="SIGNAL FOUND - RISK BLOCKED";g_lastGate="MAX TRADES";}
   else {g_buyApproved+=(buy?1:0);g_sellApproved+=(sell?1:0);g_lastStatus="SIGNAL FOUND - APPROVED";g_lastGate="APPROVED";}
 }
 if(g_bars<=10 || g_bars%25==0)
   Print("v1.23 BAR ",g_bars," time=",TimeToString(iTime(_Symbol,_Period,sh))," spread=",DoubleToString(spread,1)," ATRpts=",DoubleToString(atr/Point,1)," ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1)," BUY=",bs," SELL=",ss," decision=",DecisionText(g_lastDecision)," status=",g_lastStatus," gate=",g_lastGate);
 Panel(spread,atr,adx,rsi);
}

int OnInit(){PrintSignature();return(INIT_SUCCEEDED);}
void OnDeinit(const int reason){PrintFinal();Comment("");}
void OnTick(){if(IsNewBar())Analyze();}
