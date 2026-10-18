#property strict
#property version   "1.35"
#property description "Bitey IA 8-strategy adaptive MT4 EA. AI advisory + local Risk Gate."

#include <AI_Bridge.mqh>
#include <Market_Regime.mqh>
#include <Trading_Metrics.mqh>
#include <Strategy_Spectrum.mqh>

// ============================================================
// AI MODE
// ============================================================

enum ENUM_AI_MODE
{
   AI_OFF   = 0,
   AI_ASSIST = 1,
   AI_FILTER = 2
};

input ENUM_AI_MODE InpAIMode = AI_ASSIST;

input string InpAIEndpoint =
   "https://bitey-ia-suprabrain.onrender.com/api/v2/trading/analyze";

input string InpAIAuthToken = "";
input int    InpAITimeoutMs = 5000;
input double InpAIMinConfidence = 0.60;


// ============================================================
// ADAPTIVE STRATEGY AUDIT
// ============================================================

input int    InpAuditBars        = 1500;
input int    InpAuditHorizonBars = 15;

input double InpAuditSLMult = 1.30;
input double InpAuditTPMult = 2.60;

input int InpAuditRefreshBars = 20;


// ============================================================
// TRADING / RISK
// ============================================================

input bool   InpAllowBuy  = true;
input bool   InpAllowSell = true;

input double InpRiskPct = 0.25;

input int InpMaxTrades = 1;

input int InpMaxSpreadPoints = 30;

input double InpMaxSpreadATRRatio = 0.20;


// ============================================================
// INDICATORS
// ============================================================

input int InpATRPeriod = 14;
input int InpADXPeriod = 14;
input double InpADXMin = 20.0;

input int InpRSIPeriod = 14;

input int InpFastEMA = 8;
input int InpSlowEMA = 21;
input int InpMacroEMA = 200;


// ============================================================
// SL / TP
// ============================================================

input double InpSLMult = 1.30;
input double InpTPMult = 2.60;


// ============================================================
// SESSION / COOLDOWN
// ============================================================

input int InpStartHour = 7;
input int InpEndHour   = 20;

input int InpCooldownBars = 3;


// ============================================================
// MAGIC
// ============================================================

input int InpMagicNumber = 8883200;


// ============================================================
// REPORTING
// ============================================================

input bool InpWriteCSV = true;

input string InpCSVFile =
   "AI_Trading_Bot_v1.35_Bitey.csv";

input bool InpAutoReport = true;

input string InpAdaptiveReportFile =
   "BiteyAdaptiveReport.tch";


// ============================================================
// SBT
// ============================================================

input bool InpEnableSBTReport = true;

input string InpSBTEndpoint =
   "https://bitey-system-bots-trading-api.onrender.com";

input string InpSBTToken = "";

input int InpSBTTimeoutMs = 5000;


// ============================================================
// GLOBAL STATE
// ============================================================

StrategyAudit g_audits[STRATEGY_COUNT];

int    g_bestStrategy = -1;
double g_bestScore    = 0.0;

AITradingSignal g_lastAI;

bool g_lastAIValid = false;

datetime g_lastBarTime = 0;

int g_barsSinceAudit = 0;


// ============================================================
// INIT
// ============================================================

int OnInit()
{
   Print("==========================================");
   Print("Bitey IA v1.35");
   Print("8-strategy adaptive MT4 bot");
   Print("Execution: ", InpEnableExecution ? "ON" : "OFF");
   Print("AI mode: ", InpAIMode);
   Print("SBT endpoint: ", InpSBTEndpoint);
   Print("==========================================");

   RefreshAudit();

   return(INIT_SUCCEEDED);
}


// ============================================================
// STRATEGY AUDIT
// ============================================================

void RefreshAudit()
{
   g_bestStrategy = -1;
   g_bestScore = 0.0;

   for(int i = 0; i < STRATEGY_COUNT; i++)
   {
      AuditStrategy(
         Symbol(),
         Period(),
         i,
         InpAuditBars,
         InpAuditHorizonBars,
         InpAuditSLMult,
         InpAuditTPMult,
         g_audits[i]
      );

      FinalizeAudit(g_audits[i]);

      if(g_audits[i].trades >= 10)
      {
         if(g_bestStrategy < 0 ||
            g_audits[i].score > g_bestScore)
         {
            g_bestStrategy = i;
            g_bestScore = g_audits[i].score;
         }
      }
   }
}


// ============================================================
// AI PERMISSION
// ============================================================

bool AIAllows(
   int localSignal,
   AITradingSignal &ai
)
{
   if(InpAIMode == AI_OFF)
      return(true);

   if(InpAIMode == AI_ASSIST)
      return(true);

   if(InpAIMode == AI_FILTER)
   {
      if(!ai.risk_allowed)
         return(false);

      if(ai.confidence < InpAIMinConfidence)
         return(false);

      if(localSignal > 0 &&
         ai.action != "BUY")
         return(false);

      if(localSignal < 0 &&
         ai.action != "SELL")
         return(false);

      return(true);
   }

   return(false);
}


// ============================================================
// SBT REPORT
// ============================================================

void SendSBTReport(
   AITradingSignal &ai,
   bool ai_ok
)
{
   if(!InpEnableSBTReport)
      return;

   if(InpSBTEndpoint == "")
      return;

   string url = InpSBTEndpoint;

   if(StringSubstr(
      url,
      StringLen(url) - 1,
      1
   ) == "/")
   {
      url = StringSubstr(
         url,
         0,
         StringLen(url) - 1
      );
   }

   url = url + "/api/v1/mt4/bitey-report";


   string headers =
      "Content-Type: application/json\r\n";


   if(InpSBTToken != "")
   {
      headers =
         headers +
         "X-MT4-Token: " +
         InpSBTToken +
         "\r\n";
   }


   string mode =
      InpAIMode == AI_OFF
      ? "AI_OFF"
      :
      (
         InpAIMode == AI_ASSIST
         ? "AI_ASSIST"
         : "AI_FILTER"
      );


   string body = "{";

   body += "\"source\":\"MT4\",";
   body += "\"symbol\":\"" + Symbol() + "\",";
   body += "\"timeframe\":\"" + IntegerToString(Period()) + "\",";
   body += "\"mode\":\"" + mode + "\",";
   body += "\"execution_enabled\":" +
           (InpEnableExecution ? "true" : "false") + ",";

   body += "\"best_strategy\":\"" +
           IntegerToString(g_bestStrategy) + "\",";

   body += "\"best_score\":" +
           DoubleToString(g_bestScore, 4) + ",";

   body += "\"ai_ok\":" +
           (ai_ok ? "true" : "false") + ",";

   body += "\"ai_action\":\"" +
           ai.action + "\",";

   body += "\"ai_confidence\":" +
           DoubleToString(ai.confidence, 4) + ",";

   body += "\"ai_risk_allowed\":" +
           (ai.risk_allowed ? "true" : "false") + ",";

   body += "\"ai_strategy\":\"" +
           ai.strategy + "\",";

   body += "\"ai_reason\":\"" +
           ai.reason + "\"";

   body += "}";


   char data[];
   char result[];

   StringToCharArray(
      body,
      data,
      0,
      WHOLE_ARRAY,
      CP_UTF8
   );


   string result_headers = "";

   int code = WebRequest(
      "POST",
      url,
      headers,
      InpSBTTimeoutMs,
      data,
      result,
      result_headers
   );


   if(code >= 200 && code < 300)
   {
      Print(
         "SBT report accepted. HTTP=",
         code
      );
   }
   else
   {
      Print(
         "SBT report failed. HTTP=",
         code,
         " error=",
         GetLastError()
      );
   }
}


// ============================================================
// RADAR
// ============================================================

void UpdateRadar()
{
   Comment(
      "BITEY IA v1.35\n",
      "============================\n",

      "Symbol: ", Symbol(),
      "  TF: ", Period(), "\n",

      "Best strategy: ",
      g_bestStrategy,
      "\n",

      "Best score: ",
      DoubleToString(g_bestScore, 3),
      "\n",

      "AI action: ",
      g_lastAI.action,
      "\n",

      "AI confidence: ",
      DoubleToString(
         g_lastAI.confidence,
         2
      ),
      "\n",

      "AI risk: ",
      g_lastAI.risk_allowed
         ? "ALLOWED"
         : "BLOCKED",
      "\n",

      "SBT: ",
      InpEnableSBTReport
         ? "ON"
         : "OFF",
      "\n",

      "Execution: ",
      InpEnableExecution
         ? "ON"
         : "OFF",
      "\n",

      "----------------------------\n",

      "8-STRATEGY AUDIT\n",

      "0 Trend       T=",
      g_audits[0].trades,
      " PF=",
      DoubleToString(
         g_audits[0].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[0].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[0].score,
         2
      ),
      "\n",

      "1 MeanRev     T=",
      g_audits[1].trades,
      " PF=",
      DoubleToString(
         g_audits[1].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[1].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[1].score,
         2
      ),
      "\n",

      "2 Momentum    T=",
      g_audits[2].trades,
      " PF=",
      DoubleToString(
         g_audits[2].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[2].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[2].score,
         2
      ),
      "\n",

      "3 Breakout    T=",
      g_audits[3].trades,
      " PF=",
      DoubleToString(
         g_audits[3].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[3].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[3].score,
         2
      ),
      "\n",

      "4 Session     T=",
      g_audits[4].trades,
      " PF=",
      DoubleToString(
         g_audits[4].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[4].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[4].score,
         2
      ),
      "\n",

      "5 Divergence  T=",
      g_audits[5].trades,
      " PF=",
      DoubleToString(
         g_audits[5].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[5].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[5].score,
         2
      ),
      "\n",

      "6 Range       T=",
      g_audits[6].trades,
      " PF=",
      DoubleToString(
         g_audits[6].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[6].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[6].score,
         2
      ),
      "\n",

      "7 Fractal HTF  T=",
      g_audits[7].trades,
      " PF=",
      DoubleToString(
         g_audits[7].profit_factor,
         2
      ),
      " E=",
      DoubleToString(
         g_audits[7].expectancy,
         2
      ),
      " S=",
      DoubleToString(
         g_audits[7].score,
         2
      )
   );
}


// ============================================================
// TRADE ENGINE
// ============================================================

void TryTrade()
{
   if(!InpEnableExecution)
      return;

   // Risk Gate remains authoritative.

   if(g_bestStrategy < 0)
      return;

   // Spread filter
   double spread =
      MarketInfo(Symbol(), MODE_SPREAD);

   if(spread > InpMaxSpreadPoints)
      return;


   // Local strategy signal
   int localSignal =
      StrategySignal(
         Symbol(),
         Period(),
         g_bestStrategy
      );

   if(localSignal == 0)
      return;


   // AI filter
   if(!AIAllows(
      localSignal,
      g_lastAI
   ))
      return;


   // ATR
   double atr =
      iATR(
         Symbol(),
         Period(),
         InpATRPeriod,
         0
      );

   if(atr <= 0)
      return;


   double slDistance =
      atr * InpSLMult;

   double tpDistance =
      atr * InpTPMult;


   // BUY
   if(localSignal > 0 &&
      InpAllowBuy)
   {
      double price = Ask;

      double sl =
         price - slDistance;

      double tp =
         price + tpDistance;

      // Risk-based lot calculation
      double lots =
         CalculateRiskLots(
            slDistance
         );

      if(lots <= 0)
         return;

      OrderSend(
         Symbol(),
         OP_BUY,
         lots,
         price,
         10,
         sl,
         tp,
         "BiteyIA_v1.35_8S",
         InpMagicNumber,
         0,
         clrNONE
      );
   }


   // SELL
   if(localSignal < 0 &&
      InpAllowSell)
   {
      double price = Bid;

      double sl =
         price + slDistance;

      double tp =
         price - tpDistance;

      double lots =
         CalculateRiskLots(
            slDistance
         );

      if(lots <= 0)
         return;

      OrderSend(
         Symbol(),
         OP_SELL,
         lots,
         price,
         10,
         sl,
         tp,
         "BiteyIA_v1.35_8S",
         InpMagicNumber,
         0,
         clrNONE
      );
   }
}


// ============================================================
// MAIN LOOP
// ============================================================

void OnTick()
{
   RefreshMarketMetrics();

   UpdateMarketRegime();

   if(Time[0] == g_lastBarTime)
      return;

   g_lastBarTime = Time[0];

   g_barsSinceAudit++;

   if(g_barsSinceAudit >= InpAuditRefreshBars)
   {
      RefreshAudit();

      g_barsSinceAudit = 0;
   }


   // AI snapshot
   bool ai_ok =
      AIAnalyzeSnapshot(
         InpAIEndpoint,
         InpAIAuthToken,
         Symbol(),
         Period(),
         g_lastAI
      );

   g_lastAIValid = ai_ok;


   UpdateRadar();

   SendSBTReport(
      g_lastAI,
      ai_ok
   );

   TryTrade();


   Print(
      "Bitey v1.35 | ",
      Symbol(),
      " | best=",
      g_bestStrategy,
      " | score=",
      DoubleToString(
         g_bestScore,
         3
      ),
      " | AI=",
      g_lastAI.action,
      " | conf=",
      DoubleToString(
         g_lastAI.confidence,
         2
      )
   );
}