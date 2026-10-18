#property strict
#property version   "1.20"
#property description "AI Trading Bot v1.20 - Diagnostic Engine for MT4"

// ================================================================
// AI Trading Bot v1.20 - Diagnostic Engine
// Purpose: diagnose why signals are blocked before enabling trading.
// Default behavior: diagnostic only, NO orders are sent.
// ================================================================

enum ENUM_AI_DECISION { AI_WAIT=0, AI_BUY=1, AI_SELL=2 };

input string InpProject = "AI Trading Bot v1.20";
input bool   InpDiagnosticMode = true;
input bool   InpDemoSafeMode    = true;
input bool   InpUseExternalAI   = false;
input string InpAIEndpoint      = "";
input int    InpAITimeoutMs     = 3000;

input double InpRiskPct         = 0.25;
input double InpMaxLots         = 2.0;
input int    InpMaxTrades       = 1;
input double InpMaxOpenRiskPct  = 0.50;

input int    InpFastEMA         = 8;
input int    InpSlowEMA         = 21;
input int    InpMacroEMA        = 200;
input int    InpADXPeriod       = 14;
input double InpADXMin          = 20.0;
input int    InpRSIPeriod       = 14;
input double InpRSIBuyMin       = 50.0;
input double InpRSIBuyMax       = 68.0;
input double InpRSISellMin      = 32.0;
input double InpRSISellMax      = 50.0;
input int    InpATRPeriod       = 14;
input double InpMinATRPoints    = 20.0;

input double InpSLMult          = 1.5;
input double InpTPMult          = 3.0;
input double InpBEStartMult     = 1.2;
input double InpBELockMult      = 0.1;
input double InpTrailStartMult  = 1.8;
input double InpTrailDistMult   = 1.0;

input double InpMaxSpreadPoints = 30.0;
input double InpMaxSpreadATR    = 0.20;
input int    InpStartHour       = 7;
input int    InpEndHour         = 20;
input int    InpFridayCloseHour = 21;
input int    InpCooldownBars    = 3;
input int    InpMinScore        = 5;
input int    InpMagic           = 8883100;

// ---------- diagnostics ----------
long gBars=0, gMarketPass=0;
long gSpreadBlocked=0, gATRBlocked=0, gSessionBlocked=0;
long gRiskBlocked=0, gCooldownBlocked=0;
long gBuyCandidates=0, gSellCandidates=0;
long gBuyScorePass=0, gSellScorePass=0;
long gApprovedBuy=0, gApprovedSell=0;
long gOrderAttempts=0, gOrdersSuccess=0, gOrderErrors=0;
long gExternalAIWait=0;
int  gLastOrderBar=-1000000;
string gLastDecision="WAIT";
string gLastBlock="NONE";
int gLastBuyScore=0, gLastSellScore=0;

// ---------- helpers ----------
double Pt(){ return(MarketInfo(Symbol(),MODE_POINT)); }
int Dig(){ return((int)MarketInfo(Symbol(),MODE_DIGITS)); }

int CountOpenTrades(){
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--){
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()==Symbol() && OrderMagicNumber()==InpMagic) n++;
   }
   return n;
}

bool NewBar(){
   static datetime last=0;
   datetime t=iTime(Symbol(),Period(),0);
   if(t==0 || t==last) return false;
   last=t;
   return true;
}

bool SessionOK(datetime t){
   int h=TimeHour(t), dow=TimeDayOfWeek(t);
   if(dow==0 || dow==6) return false;
   if(dow==5 && h>=InpFridayCloseHour) return false;
   return(h>=InpStartHour && h<InpEndHour);
}

bool SpreadOK(double atr){
   double spreadPts=(Ask-Bid)/Pt();
   if(spreadPts>InpMaxSpreadPoints) return false;
   if(atr>0 && (Ask-Bid)>(atr*InpMaxSpreadATR)) return false;
   return true;
}

bool RiskOK(){
   if(CountOpenTrades()>=InpMaxTrades) return false;
   return true;
}

bool CooldownOK(int shift){
   if(gLastOrderBar<0) return true;
   return((gBars-gLastOrderBar)>InpCooldownBars);
}

int BuyScore(int s){
   double c=iClose(Symbol(),Period(),s);
   double fast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double slow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double macro1=iMA(Symbol(),Period(),InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double macro2=iMA(Symbol(),Period(),InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,s);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,s);
   double atr=iATR(Symbol(),Period(),InpATRPeriod,s);
   double fastPrev=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double slowPrev=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double cPrev=iClose(Symbol(),Period(),s+1);
   int score=0;
   if(c>macro1 && macro1>macro2) score++;
   if(fast>slow) score++;
   if(adx>=InpADXMin) score++;
   if(rsi>=InpRSIBuyMin && rsi<=InpRSIBuyMax) score++;
   if(atr/Pt()>=InpMinATRPoints) score++;
   if(fastPrev<=slowPrev && fast>slow) score++;
   if(c>fast && cPrev<=fastPrev) score++;
   return score;
}

int SellScore(int s){
   double c=iClose(Symbol(),Period(),s);
   double fast=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double slow=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double macro1=iMA(Symbol(),Period(),InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,s);
   double macro2=iMA(Symbol(),Period(),InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,s);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,s);
   double atr=iATR(Symbol(),Period(),InpATRPeriod,s);
   double fastPrev=iMA(Symbol(),Period(),InpFastEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double slowPrev=iMA(Symbol(),Period(),InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,s+1);
   double cPrev=iClose(Symbol(),Period(),s+1);
   int score=0;
   if(c<macro1 && macro1<macro2) score++;
   if(fast<slow) score++;
   if(adx>=InpADXMin) score++;
   if(rsi>=InpRSISellMin && rsi<=InpRSISellMax) score++;
   if(atr/Pt()>=InpMinATRPoints) score++;
   if(fastPrev>=slowPrev && fast<slow) score++;
   if(c<fast && cPrev>=fastPrev) score++;
   return score;
}

string GateText(bool b){ return b ? "PASS" : "BLOCK"; }

void PrintDiagnostics(int shift, double atr, double adx, double rsi, bool spreadOK, bool sessionOK, bool riskOK, bool cooldownOK){
   double spreadPts=(Ask-Bid)/Pt();
   Print("[v1.20] BAR #",gBars," ",TimeToString(iTime(Symbol(),Period(),shift),TIME_DATE|TIME_MINUTES),
         " Spread=",DoubleToString(spreadPts,1)," ATRpts=",DoubleToString(atr/Pt(),1),
         " ADX=",DoubleToString(adx,1)," RSI=",DoubleToString(rsi,1));
   Print("[v1.20] MARKET: Spread=",GateText(spreadOK)," ATR=",GateText(atr/Pt()>=InpMinATRPoints)," Session=",GateText(sessionOK),
         " Risk=",GateText(riskOK)," Cooldown=",GateText(cooldownOK));
   Print("[v1.20] SCORE: BUY=",gLastBuyScore,"/7 SELL=",gLastSellScore,"/7 Decision=",gLastDecision," Block=",gLastBlock);
}

void Dashboard(){
   string s="";
   s += "AI Trading Bot v1.20 - Diagnostic Engine\n";
   s += "Symbol: "+Symbol()+"  TF: "+IntegerToString(Period())+"\n";
   s += "Mode: "+(InpDiagnosticMode?"DIAGNOSTIC":"TRADING")+"  Safe: "+(InpDemoSafeMode?"ON":"OFF")+"\n";
   s += "Bars="+IntegerToString((int)gBars)+"  MarketPass="+IntegerToString((int)gMarketPass)+"\n";
   s += "BUY cand="+IntegerToString((int)gBuyCandidates)+" scorePass="+IntegerToString((int)gBuyScorePass)+" approved="+IntegerToString((int)gApprovedBuy)+"\n";
   s += "SELL cand="+IntegerToString((int)gSellCandidates)+" scorePass="+IntegerToString((int)gSellScorePass)+" approved="+IntegerToString((int)gApprovedSell)+"\n";
   s += "Blocks S="+IntegerToString((int)gSpreadBlocked)+" A="+IntegerToString((int)gATRBlocked)+" H="+IntegerToString((int)gSessionBlocked)+" R="+IntegerToString((int)gRiskBlocked)+" C="+IntegerToString((int)gCooldownBlocked)+"\n";
   s += "Orders attempts="+IntegerToString((int)gOrderAttempts)+" success="+IntegerToString((int)gOrdersSuccess)+" errors="+IntegerToString((int)gOrderErrors)+"\n";
   s += "Last: "+gLastDecision+" / "+gLastBlock+"  Score B/S="+IntegerToString(gLastBuyScore)+"/"+IntegerToString(gLastSellScore);
   Comment(s);
}

void FinalReport(){
   Print("============================================================");
   Print("FINAL DIAGNOSTIC v1.20");
   Print("Bars analyzed      = ",gBars);
   Print("Market pass        = ",gMarketPass);
   Print("Spread blocked     = ",gSpreadBlocked);
   Print("ATR blocked        = ",gATRBlocked);
   Print("Session blocked    = ",gSessionBlocked);
   Print("Risk blocked       = ",gRiskBlocked);
   Print("Cooldown blocked   = ",gCooldownBlocked);
   Print("BUY candidates     = ",gBuyCandidates);
   Print("SELL candidates    = ",gSellCandidates);
   Print("BUY score >= min   = ",gBuyScorePass);
   Print("SELL score >= min  = ",gSellScorePass);
   Print("BUY approved       = ",gApprovedBuy);
   Print("SELL approved      = ",gApprovedSell);
   Print("Order attempts     = ",gOrderAttempts);
   Print("Orders success     = ",gOrdersSuccess);
   Print("Order errors       = ",gOrderErrors);
   Print("External AI WAIT   = ",gExternalAIWait);
   Print("============================================================");
}

int OnInit(){
   Print("AI Trading Bot v1.20 initialized. DiagnosticMode=",InpDiagnosticMode," DemoSafeMode=",InpDemoSafeMode);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason){
   Dashboard();
   FinalReport();
   Comment("");
}

void OnTick(){
   if(!NewBar()) return;
   gBars++;
   int shift=1;
   gLastDecision="WAIT";
   gLastBlock="NONE";

   double atr=iATR(Symbol(),Period(),InpATRPeriod,shift);
   double adx=iADX(Symbol(),Period(),InpADXPeriod,PRICE_CLOSE,MODE_MAIN,shift);
   double rsi=iRSI(Symbol(),Period(),InpRSIPeriod,PRICE_CLOSE,shift);

   bool spreadOK=SpreadOK(atr);
   bool atrOK=(atr/Pt()>=InpMinATRPoints);
   bool sessionOK=SessionOK(iTime(Symbol(),Period(),shift));
   bool riskOK=RiskOK();
   bool cooldownOK=CooldownOK(shift);

   if(!spreadOK) gSpreadBlocked++;
   if(!atrOK) gATRBlocked++;
   if(!sessionOK) gSessionBlocked++;
   if(!riskOK) gRiskBlocked++;
   if(!cooldownOK) gCooldownBlocked++;

   if(!spreadOK){ gLastBlock="SPREAD"; PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK); Dashboard(); return; }
   if(!atrOK){ gLastBlock="ATR"; PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK); Dashboard(); return; }
   if(!sessionOK){ gLastBlock="SESSION"; PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK); Dashboard(); return; }

   gMarketPass++;
   gBuyCandidates++;
   gSellCandidates++;
   gLastBuyScore=BuyScore(shift);
   gLastSellScore=SellScore(shift);
   if(gLastBuyScore>=InpMinScore) gBuyScorePass++;
   if(gLastSellScore>=InpMinScore) gSellScorePass++;

   bool buySignal=(gLastBuyScore>=InpMinScore && gLastBuyScore>gLastSellScore);
   bool sellSignal=(gLastSellScore>=InpMinScore && gLastSellScore>gLastBuyScore);

   if(!buySignal && !sellSignal){
      gLastBlock="NO_SIGNAL";
      PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK);
      Dashboard();
      return;
   }

   if(buySignal) gLastDecision="BUY"; else gLastDecision="SELL";

   if(!riskOK){ gLastBlock="RISK"; PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK); Dashboard(); return; }
   if(!cooldownOK){ gLastBlock="COOLDOWN"; PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK); Dashboard(); return; }

   if(InpUseExternalAI){
      // External AI is intentionally quarantined in v1.20 until an explicit API contract exists.
      gExternalAIWait++;
      gLastBlock="EXTERNAL_AI_NOT_CONFIGURED";
      gLastDecision="WAIT";
      PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK);
      Dashboard();
      return;
   }

   if(buySignal) gApprovedBuy++; else gApprovedSell++;
   gLastBlock="APPROVED";
   PrintDiagnostics(shift,atr,adx,rsi,spreadOK,sessionOK,riskOK,cooldownOK);

   // v1.20 diagnostic release never sends orders unless both switches are explicitly disabled.
   if(InpDiagnosticMode || InpDemoSafeMode){
      gLastBlock="SAFE_MODE";
      Dashboard();
      return;
   }

   // Execution is deliberately not implemented in this diagnostic release.
   gOrderAttempts++;
   gOrderErrors++;
   gLastBlock="EXECUTOR_DISABLED_V1_20";
   Dashboard();
}
