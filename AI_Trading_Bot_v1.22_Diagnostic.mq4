//+------------------------------------------------------------------+
//| AI Trading Bot v1.22 - Diagnostic Engine                         |
//| MT4 / MQL4                                                       |
//| Diagnostic mode - NO ORDERS                                      |
//+------------------------------------------------------------------+
#property strict
#property version   "1.22"
#property description "AI-assisted diagnostic trading engine"

//==================================================================
// INPUTS
//==================================================================

input bool   InpDiagnosticMode   = true;
input bool   InpDemoSafeMode     = true;
input bool   InpUseExternalAI    = false;
input string InpAIEndpoint       = "";

input double InpRiskPct          = 0.25;
input double InpMaxLots          = 2.0;
input int    InpMaxTrades        = 1;

input int    InpFastEMA           = 8;
input int    InpSlowEMA           = 21;
input int    InpMacroEMA          = 200;

input int    InpADXPeriod         = 14;
input double InpADXMin            = 20.0;

input int    InpRSIPeriod         = 14;
input double InpRSIBuyMin         = 50.0;
input double InpRSIBuyMax         = 68.0;
input double InpRSISellMin        = 32.0;
input double InpRSISellMax        = 50.0;

input int    InpATRPeriod         = 14;
input double InpMinATRPoints      = 20.0;

input double InpSLMult            = 1.5;
input double InpTPMult            = 3.0;

input int    InpMaxSpreadPoints   = 30;
input double InpSpreadATRRatio    = 0.20;

input int    InpStartHour         = 7;
input int    InpEndHour           = 20;
input int    InpFridayCloseHour   = 21;

input int    InpCooldownBars      = 3;
input int    InpMinScore          = 5;

input int    InpMagicNumber       = 8883120;

//==================================================================
// GLOBAL VARIABLES
//==================================================================

datetime g_lastBar = 0;
datetime g_lastTradeBar = 0;

long g_bars = 0;

long g_spreadBlock = 0;
long g_atrBlock = 0;
long g_sessionBlock = 0;
long g_fridayBlock = 0;

long g_buyCandidates = 0;
long g_sellCandidates = 0;

long g_buyScoreOK = 0;
long g_sellScoreOK = 0;

long g_buyDecisions = 0;
long g_sellDecisions = 0;

long g_buyApproved = 0;
long g_sellApproved = 0;

long g_marketBlocked = 0;
long g_spreadOnlyBlocked = 0;
long g_otherMarketBlocked = 0;

long g_riskBlocked = 0;
long g_cooldownBlocked = 0;

long g_noSignal = 0;
long g_scoreBelow = 0;

long g_orderAttempts = 0;
long g_orderSuccess = 0;
long g_orderErrors = 0;

double g_maxSpread = 0.0;
double g_minATR = 999999999.0;
double g_maxADX = 0.0;
double g_maxSpreadATR = 0.0;

int g_csvHandle = INVALID_HANDLE;

string g_lastStatus = "INIT";
string g_lastGate = "NONE";

//==================================================================
// INITIALIZATION
//==================================================================

int OnInit()
{
   Print("================================================");
   Print("AI TRADING BOT v1.22");
   Print("DIAGNOSTIC ENGINE");
   Print("================================================");

   Print("Diagnostic Mode = ", InpDiagnosticMode);
   Print("Demo Safe Mode  = ", InpDemoSafeMode);
   Print("Spread Limit    = ", InpMaxSpreadPoints);
   Print("Minimum Score   = ", InpMinScore);

   // ---------------------------------------------------------------
   // CSV
   // ---------------------------------------------------------------

   g_csvHandle = FileOpen(
      "AI_Trading_Bot_v1.22_Diagnostic.csv",
      FILE_CSV | FILE_WRITE | FILE_SHARE_READ,
      ';'
   );

   if(g_csvHandle != INVALID_HANDLE)
   {
      FileWrite(
         g_csvHandle,
         "TIME",
         "BAR",
         "SPREAD",
         "ATR",
         "ADX",
         "RSI",
         "BUY_SCORE",
         "SELL_SCORE",
         "DECISION",
         "STATUS",
         "GATE",
         "MARKET_OK",
         "COOLDOWN_OK",
         "RISK_OK"
      );

      FileFlush(g_csvHandle);
   }
   else
   {
      Print(
         "CSV ERROR = ",
         GetLastError()
      );
   }

   return(INIT_SUCCEEDED);
}

//==================================================================
// DEINITIALIZATION
//==================================================================

void OnDeinit(const int reason)
{
   PrintFinalDiagnostic();

   if(g_csvHandle != INVALID_HANDLE)
   {
      FileClose(g_csvHandle);
      g_csvHandle = INVALID_HANDLE;
   }

   Comment("");
}

//==================================================================
// MAIN
//==================================================================

void OnTick()
{
   if(Bars < InpMacroEMA + 20)
      return;

   if(Time[0] == g_lastBar)
      return;

   g_lastBar = Time[0];

   g_bars++;

   AnalyzeBar();
}

//==================================================================
// ANALYZE BAR
//==================================================================

void AnalyzeBar()
{
   double spread = 0.0;

   if(Point > 0.0)
      spread = (Ask - Bid) / Point;

   if(spread > g_maxSpread)
      g_maxSpread = spread;

   //---------------------------------------------------------------
   // INDICATORS
   //---------------------------------------------------------------

   double atr = iATR(
      Symbol(),
      Period(),
      InpATRPeriod,
      1
   );

   double atrPoints = 0.0;

   if(Point > 0.0)
      atrPoints = atr / Point;

   if(atrPoints < g_minATR)
      g_minATR = atrPoints;

   double adx = iADX(
      Symbol(),
      Period(),
      InpADXPeriod,
      PRICE_CLOSE,
      MODE_MAIN,
      1
   );

   double rsi = iRSI(
      Symbol(),
      Period(),
      InpRSIPeriod,
      PRICE_CLOSE,
      1
   );

   if(adx > g_maxADX)
      g_maxADX = adx;

   double spreadATR = 0.0;

   if(atr > 0.0)
      spreadATR = (Ask - Bid) / atr;

   if(spreadATR > g_maxSpreadATR)
      g_maxSpreadATR = spreadATR;

   //---------------------------------------------------------------
   // MARKET FILTERS
   //---------------------------------------------------------------

   bool spreadOK = true;
   bool atrOK = true;
   bool sessionOK = true;
   bool fridayOK = true;

   if(spread > InpMaxSpreadPoints)
   {
      spreadOK = false;
      g_spreadBlock++;
   }

   if(atrPoints < InpMinATRPoints)
   {
      atrOK = false;
      g_atrBlock++;
   }

   int hour = TimeHour(TimeCurrent());

   if(hour < InpStartHour ||
      hour >= InpEndHour)
   {
      sessionOK = false;
      g_sessionBlock++;
   }

   int day = TimeDayOfWeek(TimeCurrent());

   if(day == 5 &&
      hour >= InpFridayCloseHour)
   {
      fridayOK = false;
      g_fridayBlock++;
   }

   bool marketOK =
      spreadOK &&
      atrOK &&
      sessionOK &&
      fridayOK;

   //---------------------------------------------------------------
   // SCORES
   //---------------------------------------------------------------

   int buyScore = BuyScore();
   int sellScore = SellScore();

   if(buyScore > 0)
      g_buyCandidates++;

   if(sellScore > 0)
      g_sellCandidates++;

   if(buyScore >= InpMinScore)
      g_buyScoreOK++;

   if(sellScore >= InpMinScore)
      g_sellScoreOK++;

   //---------------------------------------------------------------
   // DECISION
   //---------------------------------------------------------------

   int decision = 0;

   if(buyScore >= InpMinScore &&
      buyScore > sellScore)
   {
      decision = 1;
      g_buyDecisions++;
   }
   else
   if(sellScore >= InpMinScore &&
      sellScore > buyScore)
   {
      decision = -1;
      g_sellDecisions++;
   }
   else
   {
      g_noSignal++;

      if(buyScore > 0 ||
         sellScore > 0)
      {
         g_scoreBelow++;
      }
   }

   //---------------------------------------------------------------
   // EXTERNAL AI SAFETY
   //---------------------------------------------------------------

   bool aiOK = true;

   if(InpUseExternalAI)
   {
      // Until the endpoint is validated, external AI
      // cannot authorize an operation.
      aiOK = false;
      decision = 0;
   }

   //---------------------------------------------------------------
   // MARKET GATE
   //---------------------------------------------------------------

   if(decision != 0 &&
      !marketOK)
   {
      g_marketBlocked++;

      bool spreadOnly =
         !spreadOK &&
         atrOK &&
         sessionOK &&
         fridayOK;

      if(spreadOnly)
         g_spreadOnlyBlocked++;
      else
         g_otherMarketBlocked++;

      g_lastStatus = "SIGNAL_BLOCKED";
      g_lastGate = "MARKET";

      WriteCSV(
         spread,
         atrPoints,
         adx,
         rsi,
         buyScore,
         sellScore,
         decision,
         g_lastStatus,
         g_lastGate,
         marketOK,
         true,
         false
      );

      UpdatePanel(
         spread,
         atrPoints,
         adx,
         rsi,
         buyScore,
         sellScore,
         decision,
         g_lastStatus
      );

      return;
   }

   //---------------------------------------------------------------
   // COOLDOWN
   //---------------------------------------------------------------

   bool cooldownOK = true;

   if(decision != 0)
   {
      cooldownOK = !CooldownActive();

      if(!cooldownOK)
      {
         g_cooldownBlocked++;

         g_lastStatus = "SIGNAL_BLOCKED";
         g_lastGate = "COOLDOWN";

         WriteCSV(
            spread,
            atrPoints,
            adx,
            rsi,
            buyScore,
            sellScore,
            decision,
            g_lastStatus,
            g_lastGate,
            marketOK,
            false,
            true
         );

         UpdatePanel(
            spread,
            atrPoints,
            adx,
            rsi,
            buyScore,
            sellScore,
            decision,
            g_lastStatus
         );

         return;
      }
   }

   //---------------------------------------------------------------
   // RISK
   //---------------------------------------------------------------

   bool riskOK = true;

   if(decision != 0)
   {
      riskOK = RiskGate();

      if(!riskOK)
      {
         g_riskBlocked++;

         g_lastStatus = "SIGNAL_BLOCKED";
         g_lastGate = "RISK";

         WriteCSV(
            spread,
            atrPoints,
            adx,
            rsi,
            buyScore,
            sellScore,
            decision,
            g_lastStatus,
            g_lastGate,
            marketOK,
            cooldownOK,
            false
         );

         UpdatePanel(
            spread,
            atrPoints,
            adx,
            rsi,
            buyScore,
            sellScore,
            decision,
            g_lastStatus
         );

         return;
      }
   }

   //---------------------------------------------------------------
   // AI GATE
   //---------------------------------------------------------------

   if(!aiOK)
   {
      if(decision != 0)
      {
         g_lastStatus = "SIGNAL_BLOCKED";
         g_lastGate = "AI";
      }
      else
      {
         g_lastStatus = "NO_SIGNAL";
         g_lastGate = "AI";
      }

      WriteCSV(
         spread,
         atrPoints,
         adx,
         rsi,
         buyScore,
         sellScore,
         decision,
         g_lastStatus,
         g_lastGate,
         marketOK,
         cooldownOK,
         riskOK
      );

      UpdatePanel(
         spread,
         atrPoints,
         adx,
         rsi,
         buyScore,
         sellScore,
         decision,
         g_lastStatus
      );

      return;
   }

   //---------------------------------------------------------------
   // APPROVED
   //---------------------------------------------------------------

   if(decision == 1)
   {
      g_buyApproved++;
      g_lastStatus = "APPROVED_BUY";
      g_lastGate = "ALL";
   }
   else
   if(decision == -1)
   {
      g_sellApproved++;
      g_lastStatus = "APPROVED_SELL";
      g_lastGate = "ALL";
   }
   else
   {
      g_lastStatus = "NO_SIGNAL";
      g_lastGate = "NONE";
   }

   WriteCSV(
      spread,
      atrPoints,
      adx,
      rsi,
      buyScore,
      sellScore,
      decision,
      g_lastStatus,
      g_lastGate,
      marketOK,
      cooldownOK,
      riskOK
   );

   UpdatePanel(
      spread,
      atrPoints,
      adx,
      rsi,
      buyScore,
      sellScore,
      decision,
      g_lastStatus
   );

   //---------------------------------------------------------------
   // DIAGNOSTIC MODE = NO ORDERS
   //---------------------------------------------------------------

   if(InpDiagnosticMode ||
      InpDemoSafeMode)
   {
      return;
   }
}

//==================================================================
// BUY SCORE
//==================================================================

int BuyScore()
{
   int score = 0;

   double close1 = Close[1];

   double fast1 =
      iMA(Symbol(), Period(),
          InpFastEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double fast2 =
      iMA(Symbol(), Period(),
          InpFastEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double slow1 =
      iMA(Symbol(), Period(),
          InpSlowEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double slow2 =
      iMA(Symbol(), Period(),
          InpSlowEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double macro1 =
      iMA(Symbol(), Period(),
          InpMacroEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double macro2 =
      iMA(Symbol(), Period(),
          InpMacroEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double adx =
      iADX(Symbol(), Period(),
           InpADXPeriod, PRICE_CLOSE,
           MODE_MAIN, 1);

   double rsi =
      iRSI(Symbol(), Period(),
           InpRSIPeriod, PRICE_CLOSE, 1);

   double atr =
      iATR(Symbol(), Period(),
           InpATRPeriod, 1);

   //---------------------------------------------------------------
   // 1. MACRO TREND
   //---------------------------------------------------------------

   if(close1 > macro1 &&
      macro1 > macro2)
      score++;

   //---------------------------------------------------------------
   // 2. EMA DIRECTION
   //---------------------------------------------------------------

   if(fast1 > slow1)
      score++;

   //---------------------------------------------------------------
   // 3. ADX
   //---------------------------------------------------------------

   if(adx >= InpADXMin)
      score++;

   //---------------------------------------------------------------
   // 4. RSI
   //---------------------------------------------------------------

   if(rsi >= InpRSIBuyMin &&
      rsi <= InpRSIBuyMax)
      score++;

   //---------------------------------------------------------------
   // 5. ATR
   //---------------------------------------------------------------

   if(Point > 0.0 &&
      atr / Point >= InpMinATRPoints)
      score++;

   //---------------------------------------------------------------
   // 6. EMA CROSS
   //---------------------------------------------------------------

   if(fast2 <= slow2 &&
      fast1 > slow1)
      score++;

   //---------------------------------------------------------------
   // 7. CONFIRMATION
   //---------------------------------------------------------------

   if(Close[1] > fast1 &&
      Close[2] <= fast2)
      score++;

   return(score);
}

//==================================================================
// SELL SCORE
//==================================================================

int SellScore()
{
   int score = 0;

   double close1 = Close[1];

   double fast1 =
      iMA(Symbol(), Period(),
          InpFastEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double fast2 =
      iMA(Symbol(), Period(),
          InpFastEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double slow1 =
      iMA(Symbol(), Period(),
          InpSlowEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double slow2 =
      iMA(Symbol(), Period(),
          InpSlowEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double macro1 =
      iMA(Symbol(), Period(),
          InpMacroEMA, 0,
          MODE_EMA, PRICE_CLOSE, 1);

   double macro2 =
      iMA(Symbol(), Period(),
          InpMacroEMA, 0,
          MODE_EMA, PRICE_CLOSE, 2);

   double adx =
      iADX(Symbol(), Period(),
           InpADXPeriod, PRICE_CLOSE,
           MODE_MAIN, 1);

   double rsi =
      iRSI(Symbol(), Period(),
           InpRSIPeriod, PRICE_CLOSE, 1);

   double atr =
      iATR(Symbol(), Period(),
           InpATRPeriod, 1);

   //---------------------------------------------------------------
   // 1. MACRO TREND
   //---------------------------------------------------------------

   if(close1 < macro1 &&
      macro1 < macro2)
      score++;

   //---------------------------------------------------------------
   // 2. EMA DIRECTION
   //---------------------------------------------------------------

   if(fast1 < slow1)
      score++;

   //---------------------------------------------------------------
   // 3. ADX
   //---------------------------------------------------------------

   if(adx >= InpADXMin)
      score++;

   //---------------------------------------------------------------
   // 4. RSI
   //---------------------------------------------------------------

   if(rsi >= InpRSISellMin &&
      rsi <= InpRSISellMax)
      score++;

   //---------------------------------------------------------------
   // 5. ATR
   //---------------------------------------------------------------

   if(Point > 0.0 &&
      atr / Point >= InpMinATRPoints)
      score++;

   //---------------------------------------------------------------
   // 6. EMA CROSS
   //---------------------------------------------------------------

   if(fast2 >= slow2 &&
      fast1 < slow1)
      score++;

   //---------------------------------------------------------------
   // 7. CONFIRMATION
   //---------------------------------------------------------------

   if(Close[1] < fast1 &&
      Close[2] >= fast2)
      score++;

   return(score);
}

//==================================================================
// COOLDOWN
//==================================================================

bool CooldownActive()
{
   if(g_lastTradeBar == 0)
      return(false);

   int shift =
      iBarShift(
         Symbol(),
         Period(),
         g_lastTradeBar,
         true
      );

   if(shift < 0)
      return(false);

   return(
      shift < InpCooldownBars
   );
}

//==================================================================
// RISK GATE
//==================================================================

bool RiskGate()
{
   double balance = AccountBalance();
   double equity = AccountEquity();

   if(balance <= 0.0)
      return(false);

   double dd =
      ((balance - equity) /
       balance) * 100.0;

   // Diagnostic safety limit
   if(dd >= 2.0)
      return(false);

   if(CountOpenTrades() >= InpMaxTrades)
      return(false);

   return(true);
}

//==================================================================
// COUNT OPEN TRADES
//==================================================================

int CountOpenTrades()
{
   int count = 0;

   for(int i = OrdersTotal() - 1;
       i >= 0;
       i--)
   {
      if(!OrderSelect(
         i,
         SELECT_BY_POS,
         MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol())
         continue;

      if(OrderMagicNumber() !=
         InpMagicNumber)
         continue;

      if(OrderType() == OP_BUY ||
         OrderType() == OP_SELL)
      {
         count++;
      }
   }

   return(count);
}

//==================================================================
// CSV WRITER
//==================================================================

void WriteCSV(
   double spread,
   double atr,
   double adx,
   double rsi,
   int buyScore,
   int sellScore,
   int decision,
   string status,
   string gate,
   bool marketOK,
   bool cooldownOK,
   bool riskOK
)
{
   if(g_csvHandle == INVALID_HANDLE)
      return;

   string decisionText = "WAIT";

   if(decision == 1)
      decisionText = "BUY";

   if(decision == -1)
      decisionText = "SELL";

   FileWrite(
      g_csvHandle,
      TimeToString(
         Time[0],
         TIME_DATE | TIME_MINUTES
      ),
      g_bars,
      DoubleToString(spread, 1),
      DoubleToString(atr, 1),
      DoubleToString(adx, 2),
      DoubleToString(rsi, 2),
      buyScore,
      sellScore,
      decisionText,
      status,
      gate,
      marketOK,
      cooldownOK,
      riskOK
   );

   FileFlush(g_csvHandle);
}

//==================================================================
// PANEL
//==================================================================

void UpdatePanel(
   double spread,
   double atr,
   double adx,
   double rsi,
   int buyScore,
   int sellScore,
   int decision,
   string status
)
{
   string decisionText = "WAIT";

   if(decision == 1)
      decisionText = "BUY";

   if(decision == -1)
      decisionText = "SELL";

   string panel = "";

   panel +=
      "AI TRADING BOT v1.22\n";

   panel +=
      "DIAGNOSTIC ENGINE\n";
   panel +=
      "-----------------------------\n";

   panel +=
      "Status: " +
      status + "\n";

   panel +=
      "Decision: " +
      decisionText + "\n";

   panel +=
      "Spread: " +
      DoubleToString(spread,1) +
      " / " +
      IntegerToString(
         InpMaxSpreadPoints
      ) + "\n";

   panel +=
      "ATR: " +
      DoubleToString(atr,1) +
      " pts\n";

   panel +=
      "ADX: " +
      DoubleToString(adx,1) +
      "\n";

   panel +=
      "RSI: " +
      DoubleToString(rsi,1) +
      "\n";

   panel +=
      "BUY SCORE: " +
      IntegerToString(buyScore) +
      "/7\n";

   panel +=
      "SELL SCORE: " +
      IntegerToString(sellScore) +
      "/7\n";

   panel +=
      "-----------------------------\n";

   panel +=
      "Bars: " +
      IntegerToString(g_bars) +
      "\n";

   panel +=
      "BUY candidates: " +
      IntegerToString(
         g_buyCandidates
      ) + "\n";

   panel +=
      "SELL candidates: " +
      IntegerToString(
         g_sellCandidates
      ) + "\n";

   panel +=
      "BUY decisions: " +
      IntegerToString(
         g_buyDecisions
      ) + "\n";

   panel +=
      "SELL decisions: " +
      IntegerToString(
         g_sellDecisions
      ) + "\n";

   panel +=
      "BUY approved: " +
      IntegerToString(
         g_buyApproved
      ) + "\n";

   panel +=
      "SELL approved: " +
      IntegerToString(
         g_sellApproved
      ) + "\n";

   panel +=
      "-----------------------------\n";

   panel +=
      "Spread blocks: " +
      IntegerToString(
         g_spreadBlock
      ) + "\n";

   panel +=
      "ATR blocks: " +
      IntegerToString(
         g_atrBlock
      ) + "\n";

   panel +=
      "Session blocks: " +
      IntegerToString(
         g_sessionBlock
      ) + "\n";

   panel +=
      "Risk blocks: " +
      IntegerToString(
         g_riskBlocked
      ) + "\n";

   panel +=
      "Cooldown blocks: " +
      IntegerToString(
         g_cooldownBlocked
      ) + "\n";

   panel +=
      "-----------------------------\n";

   panel +=
      "MAX SPREAD: " +
      DoubleToString(
         g_maxSpread,
         1
      ) + "\n";

   panel +=
      "MIN ATR: " +
      DoubleToString(
         g_minATR,
         1
      ) + "\n";

   panel +=
      "MAX ADX: " +
      DoubleToString(
         g_maxADX,
         1
      ) + "\n";

   panel +=
      "-----------------------------\n";

   panel +=
      "ORDERS: DISABLED";

   Comment(panel);
}

//==================================================================
// FINAL DIAGNOSTIC
//==================================================================

void PrintFinalDiagnostic()
{
   Print("");
   Print("============================================================");
   Print("FINAL DIAGNOSTIC v1.22");
   Print("============================================================");

   Print("BarsAnalyzed           = ",
         g_bars);

   Print("SpreadBlock            = ",
         g_spreadBlock);

   Print("ATRBlock               = ",
         g_atrBlock);

   Print("SessionBlock           = ",
         g_sessionBlock);

   Print("FridayBlock            = ",
         g_fridayBlock);

   Print("BUY candidates         = ",
         g_buyCandidates);

   Print("SELL candidates        = ",
         g_sellCandidates);

   Print("BUY score >= minimum   = ",
         g_buyScoreOK);

   Print("SELL score >= minimum  = ",
         g_sellScoreOK);

   Print("BUY decisions          = ",
         g_buyDecisions);

   Print("SELL decisions         = ",
         g_sellDecisions);

   Print("BUY approved           = ",
         g_buyApproved);

   Print("SELL approved          = ",
         g_sellApproved);

   Print("MarketBlockedSignals   = ",
         g_marketBlocked);

   Print("SpreadOnlyBlocks       = ",
         g_spreadOnlyBlocked);

   Print("OtherMarketBlocks      = ",
         g_otherMarketBlocked);

   Print("RiskBlocked            = ",
         g_riskBlocked);

   Print("CooldownBlocked        = ",
         g_cooldownBlocked);

   Print("NoSignal               = ",
         g_noSignal);

   Print("ScoreBelow             = ",
         g_scoreBelow);

   Print("OrderAttempts          = ",
         g_orderAttempts);

   Print("OrderSuccess           = ",
         g_orderSuccess);

   Print("OrderErrors            = ",
         g_orderErrors);

   Print("MaximumSpread          = ",
         DoubleToString(
            g_maxSpread,
            1
         ));

   Print("MinimumATR             = ",
         DoubleToString(
            g_minATR,
            1
         ));

   Print("MaximumADX             = ",
         DoubleToString(
            g_maxADX,
            2
         ));

   Print("MaximumSpreadATRRatio  = ",
         DoubleToString(
            g_maxSpreadATR,
            4
         ));

   Print("ConfiguredSpreadLimit  = ",
         InpMaxSpreadPoints);

   Print("ConfiguredMinScore     = ",
         InpMinScore);

   Print("DiagnosticMode         = ",
         InpDiagnosticMode);

   Print("DemoSafeMode           = ",
         InpDemoSafeMode);

   Print("============================================================");
}

//+------------------------------------------------------------------+