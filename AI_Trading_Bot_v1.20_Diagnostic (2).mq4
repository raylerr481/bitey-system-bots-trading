#property strict
#property version   "1.20"
#property description "AI Trading Bot v1.20 - Diagnostic Engine (corrected)"

// DIAGNOSTIC BUILD ONLY.
// It NEVER sends market orders. Its purpose is to identify exactly which
// market, signal, risk or execution gate prevents a trade from being approved.

enum ENUM_AI_DECISION { AI_WAIT=0, AI_BUY=1, AI_SELL=2 };

input bool   InpDiagnosticMode   = true;
input bool   InpDemoSafeMode     = true;
input bool   InpUseExternalAI    = false; // Kept OFF: no external request in diagnostic build.

input double InpRiskPct          = 0.25;
input double InpMaxLots          = 2.0;
input int    InpMaxTrades        = 1;
input double InpMaxOpenRiskPct   = 0.50;

input int    InpFastEMA          = 8;
input int    InpSlowEMA          = 21;
input int    InpMacroEMA         = 200;
input int    InpADXPeriod        = 14;
input double InpADXMin           = 20.0;
input int    InpRSIPeriod        = 14;
input double InpRSIBuyMin        = 50.0;
input double InpRSIBuyMax        = 68.0;
input double InpRSISellMin       = 32.0;
input double InpRSISellMax       = 50.0;
input int    InpATRPeriod        = 14;
input double InpMinATRPoints     = 20.0;

input double InpSLMult           = 1.5;
input double InpTPMult           = 3.0;
input int    InpMaxSpreadPoints  = 30;
input double InpMaxSpreadATR     = 0.20;
input int    InpStartHour        = 7;
input int    InpEndHour          = 20;
input int    InpFridayCloseHour  = 21;
input int    InpCooldownBars     = 3;
input int    InpMinScore         = 5;
input int    InpMagic            = 8883100;

// ------------------------------------------------------------
// Diagnostic counters
// ------------------------------------------------------------
long g_bars=0;
long g_market_pass=0;
long g_spread_block=0;
long g_atr_block=0;
long g_session_block=0;
long g_friday_block=0;
long g_buy_candidates=0;
long g_sell_candidates=0;
long g_buy_score_pass=0;
long g_sell_score_pass=0;
long g_buy_approved=0;
long g_sell_approved=0;
long g_score_below=0;
long g_no_signal=0;
long g_risk_block=0;
long g_cooldown_block=0;
long g_ai_block=0;
long g_external_ai_wait=0;
long g_order_attempts=0;
long g_order_success=0;
long g_order_errors=0;
long g_invalid_data=0;
long g_open_trades_seen=0;

int g_last_signal_bar=-1000000000;
int g_max_spread=0;
double g_max_spread_atr_ratio=0.0;
double g_min_atr_points=1.0e20;
double g_max_adx=0.0;
double g_sum_spread=0.0;
long g_spread_samples=0;

string DecisionName(ENUM_AI_DECISION d)
{
   if(d==AI_BUY)  return "BUY";
   if(d==AI_SELL) return "SELL";
   return "WAIT";
}

bool NewBar()
{
   static datetime lastBarTime=0;
   datetime currentBarTime=iTime(_Symbol,_Period,0);
   if(currentBarTime<=0) return false;
   if(currentBarTime==lastBarTime) return false;
   lastBarTime=currentBarTime;
   return true;
}

int SpreadPoints()
{
   RefreshRates();
   if(Point<=0.0) return 0;
   return (int)MathRound((Ask-Bid)/Point);
}

double ATRPoints(int shift=1)
{
   if(Point<=0.0) return 0.0;
   double a=iATR(_Symbol,_Period,InpATRPeriod,shift);
   if(a<=0.0) return 0.0;
   return a/Point;
}

bool SessionOK()
{
   datetime t=iTime(_Symbol,_Period,1);
   if(t<=0) return false;
   int h=TimeHour(t);
   if(InpStartHour<=InpEndHour)
      return (h>=InpStartHour && h<InpEndHour);
   return (h>=InpStartHour || h<InpEndHour);
}

bool FridayOK()
{
   datetime t=iTime(_Symbol,_Period,1);
   if(t<=0) return false;
   int dow=TimeDayOfWeek(t);
   int h=TimeHour(t);
   if(dow==5 && h>=InpFridayCloseHour) return false;
   return true;
}

int OpenTrades()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderSymbol()!=_Symbol) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(OrderType()==OP_BUY || OrderType()==OP_SELL) n++;
   }
   return n;
}

bool CooldownOK()
{
   if(g_last_signal_bar<0) return true;
   int currentBar=iBars(_Symbol,_Period)-1;
   return (currentBar-g_last_signal_bar>=InpCooldownBars);
}

bool RiskOK()
{
   int open=OpenTrades();
   if(open>g_open_trades_seen) g_open_trades_seen=open;
   if(open>=InpMaxTrades) return false;
   return true;
}

int BuyScore(int &sMacro,int &sEMA,int &sADX,int &sRSI,int &sATR,int &sCross,int &sConfirm)
{
   sMacro=sEMA=sADX=sRSI=sATR=sCross=sConfirm=0;

   double c=iClose(_Symbol,_Period,1);
   double c2=iClose(_Symbol,_Period,2);
   double fast=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double fast2=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double slow=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double slow2=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double macro=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double macro2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1);
   double atrp=ATRPoints(1);

   if(c>macro && macro>macro2) sMacro=1;
   if(fast>slow && fast>fast2) sEMA=1;
   if(adx>=InpADXMin) sADX=1;
   if(rsi>=InpRSIBuyMin && rsi<=InpRSIBuyMax) sRSI=1;
   if(atrp>=InpMinATRPoints) sATR=1;
   if(fast>slow && fast2<=slow2) sCross=1;
   if(c>fast && c>c2) sConfirm=1;

   return sMacro+sEMA+sADX+sRSI+sATR+sCross+sConfirm;
}

int SellScore(int &sMacro,int &sEMA,int &sADX,int &sRSI,int &sATR,int &sCross,int &sConfirm)
{
   sMacro=sEMA=sADX=sRSI=sATR=sCross=sConfirm=0;

   double c=iClose(_Symbol,_Period,1);
   double c2=iClose(_Symbol,_Period,2);
   double fast=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double fast2=iMA(_Symbol,_Period,InpFastEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double slow=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double slow2=iMA(_Symbol,_Period,InpSlowEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double macro=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,1);
   double macro2=iMA(_Symbol,_Period,InpMacroEMA,0,MODE_EMA,PRICE_CLOSE,2);
   double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1);
   double atrp=ATRPoints(1);

   if(c<macro && macro<macro2) sMacro=1;
   if(fast<slow && fast<fast2) sEMA=1;
   if(adx>=InpADXMin) sADX=1;
   if(rsi>=InpRSISellMin && rsi<=InpRSISellMax) sRSI=1;
   if(atrp>=InpMinATRPoints) sATR=1;
   if(fast<slow && fast2>=slow2) sCross=1;
   if(c<fast && c<c2) sConfirm=1;

   return sMacro+sEMA+sADX+sRSI+sATR+sCross+sConfirm;
}

ENUM_AI_DECISION TechnicalDecision(int buyScore,int sellScore)
{
   if(buyScore>=InpMinScore && buyScore>sellScore) return AI_BUY;
   if(sellScore>=InpMinScore && sellScore>buyScore) return AI_SELL;
   return AI_WAIT;
}

void PrintScoreDetails(string side,int score,int a,int b,int c,int d,int e,int f,int g)
{
   Print("[v1.20 SCORE] ",side,
         " score=",score,"/7",
         " Macro=",a," EMA=",b," ADX=",c," RSI=",d,
         " ATR=",e," Cross=",f," Confirm=",g);
}

void ProcessBar()
{
   g_bars++;

   int totalBars=iBars(_Symbol,_Period);
   if(totalBars<InpMacroEMA+10)
   {
      g_invalid_data++;
      if(g_bars<=5)
         Print("[v1.20 BLOCK] insufficient history. Bars=",totalBars,
               " required>=",InpMacroEMA+10);
      return;
   }

   int spread=SpreadPoints();
   double atrp=ATRPoints(1);
   double ratio=(atrp>0.0 ? ((double)spread/atrp) : 999.0);
   double adx=iADX(_Symbol,_Period,InpADXPeriod,PRICE_CLOSE,MODE_MAIN,1);
   double rsi=iRSI(_Symbol,_Period,InpRSIPeriod,PRICE_CLOSE,1);

   if(spread>g_max_spread) g_max_spread=spread;
   if(ratio>g_max_spread_atr_ratio) g_max_spread_atr_ratio=ratio;
   if(atrp<g_min_atr_points) g_min_atr_points=atrp;
   if(adx>g_max_adx) g_max_adx=adx;
   g_sum_spread+=(double)spread;
   g_spread_samples++;

   bool spreadOK=(spread<=InpMaxSpreadPoints && ratio<=InpMaxSpreadATR);
   bool atrOK=(atrp>=InpMinATRPoints);
   bool sessionOK=SessionOK();
   bool fridayOK=FridayOK();

   if(!spreadOK)  g_spread_block++;
   if(!atrOK)     g_atr_block++;
   if(!sessionOK) g_session_block++;
   if(!fridayOK)  g_friday_block++;

   bool marketOK=(spreadOK && atrOK && sessionOK && fridayOK);
   if(marketOK) g_market_pass++;

   int bm,be,ba,br,bt,bx,bc;
   int sm,se,sa,sr,st,sx,sc;
   int buyScore=BuyScore(bm,be,ba,br,bt,bx,bc);
   int sellScore=SellScore(sm,se,sa,sr,st,sx,sc);

   if(buyScore>0) g_buy_candidates++;
   if(sellScore>0) g_sell_candidates++;
   if(buyScore>=InpMinScore) g_buy_score_pass++;
   if(sellScore>=InpMinScore) g_sell_score_pass++;

   ENUM_AI_DECISION decision=TechnicalDecision(buyScore,sellScore);

   if(decision==AI_WAIT)
   {
      g_no_signal++;
      if(buyScore<InpMinScore && sellScore<InpMinScore)
         g_score_below++;
   }

   bool cooldownOK=CooldownOK();
   bool riskOK=RiskOK();
   if(!cooldownOK) g_cooldown_block++;
   if(!riskOK) g_risk_block++;

   // No network calls in this diagnostic build. If enabled accidentally,
   // the signal is explicitly blocked and counted.
   bool aiOK=true;
   if(InpUseExternalAI)
   {
      aiOK=false;
      g_external_ai_wait++;
      g_ai_block++;
   }

   bool approved=(decision!=AI_WAIT && marketOK && cooldownOK && riskOK && aiOK);

   if(decision!=AI_WAIT)
   {
      if(decision==AI_BUY)  g_buy_approved++;
      if(decision==AI_SELL) g_sell_approved++;

      string reason="APPROVED";
      if(!marketOK) reason="BLOCKED_MARKET";
      else if(!cooldownOK) reason="BLOCKED_COOLDOWN";
      else if(!riskOK) reason="BLOCKED_RISK";
      else if(!aiOK) reason="BLOCKED_EXTERNAL_AI";

      Print("[v1.20 DECISION] ",DecisionName(decision),
            " score=",(decision==AI_BUY?buyScore:sellScore),"/7",
            " -> ",reason,
            " spread=",spread,
            " ATRpts=",DoubleToString(atrp,1),
            " ratio=",DoubleToString(ratio,3),
            " session=",sessionOK,
            " friday=",fridayOK,
            " cooldown=",cooldownOK,
            " risk=",riskOK,
            " AI=",aiOK);

      if(approved)
      {
         // Record the signal as approved, but NEVER send an order.
         g_last_signal_bar=iBars(_Symbol,_Period)-1;
         Print("[v1.20 SIGNAL APPROVED] ",DecisionName(decision),
               " score=",(decision==AI_BUY?buyScore:sellScore),"/7",
               " -- diagnostic only, no order sent.");
      }
   }

   // Always show the first 10 bars. Thereafter, print only meaningful bars
   // so the tester Journal remains readable.
   if(g_bars<=10 || decision!=AI_WAIT || !marketOK)
   {
      Print("[v1.20 BAR] #",g_bars,
            " time=",TimeToString(iTime(_Symbol,_Period,1),TIME_DATE|TIME_MINUTES),
            " spread=",spread,
            " atr=",DoubleToString(atrp,1),
            " ratio=",DoubleToString(ratio,3),
            " ADX=",DoubleToString(adx,1),
            " RSI=",DoubleToString(rsi,1),
            " BUY=",buyScore,
            " SELL=",sellScore,
            " decision=",DecisionName(decision),
            " market=",marketOK,
            " cooldown=",cooldownOK,
            " risk=",riskOK);
      PrintScoreDetails("BUY",buyScore,bm,be,ba,br,bt,bx,bc);
      PrintScoreDetails("SELL",sellScore,sm,se,sa,sr,st,sx,sc);
   }
}

void FinalDiagnostic()
{
   double avgSpread=(g_spread_samples>0 ? g_sum_spread/g_spread_samples : 0.0);
   Print("============================================================");
   Print("FINAL DIAGNOSTIC v1.20");
   Print("Symbol=",_Symbol," Period=",_Period," BarsAnalyzed=",g_bars);
   Print("------------------------------------------------------------");
   Print("Market: PASS=",g_market_pass,
         " SpreadBlock=",g_spread_block,
         " ATRBlock=",g_atr_block,
         " SessionBlock=",g_session_block,
         " FridayBlock=",g_friday_block);
   Print("Signals: BUY candidates=",g_buy_candidates,
         " SELL candidates=",g_sell_candidates,
         " BUY score>=",InpMinScore," => ",g_buy_score_pass,
         " SELL score>=",InpMinScore," => ",g_sell_score_pass);
   Print("Technical decisions: BUY=",g_buy_approved,
         " SELL=",g_sell_approved,
         " WAIT=",g_no_signal,
         " ScoreBelow=",g_score_below);
   Print("Risk/Cooldown: RiskBlock=",g_risk_block,
         " CooldownBlock=",g_cooldown_block,
         " MaxOpenSeen=",g_open_trades_seen);
   Print("AI: ExternalAI=",InpUseExternalAI,
         " AIBlock=",g_ai_block,
         " ExternalAIWait=",g_external_ai_wait);
   Print("Execution: Attempts=",g_order_attempts,
         " Success=",g_order_success,
         " Errors=",g_order_errors,
         " NOTE=diagnostic build sends no orders");
   Print("Data: Invalid=",g_invalid_data);
   Print("Observed: AvgSpread=",DoubleToString(avgSpread,2),
         " MaxSpread=",g_max_spread,
         " MaxSpreadATR=",DoubleToString(g_max_spread_atr_ratio,3),
         " MinATRPoints=",DoubleToString(g_min_atr_points,1),
         " MaxADX=",DoubleToString(g_max_adx,1));
   Print("Config: MaxSpread=",InpMaxSpreadPoints,
         " MaxSpreadATR=",DoubleToString(InpMaxSpreadATR,3),
         " MinATR=",DoubleToString(InpMinATRPoints,1),
         " MinScore=",InpMinScore,
         " Session=",InpStartHour,"-",InpEndHour,
         " FridayClose=",InpFridayCloseHour);
   Print("Safety: DemoSafeMode=",InpDemoSafeMode,
         " DiagnosticMode=",InpDiagnosticMode);
   Print("============================================================");
}

int OnInit()
{
   g_min_atr_points=1.0e20;
   Print("AI Trading Bot v1.20 Diagnostic Engine initialized.");
   Print("IMPORTANT: corrected diagnostic build does NOT send orders.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   FinalDiagnostic();
   Comment("");
}

// Called by Strategy Tester as well; returning 0 keeps this a pure diagnostic.
double OnTester()
{
   FinalDiagnostic();
   return 0.0;
}

void OnTick()
{
   if(NewBar()) ProcessBar();
}
