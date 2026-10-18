#property strict
#property version   "1.990"
#property description "Bitey SBT v1.99 research telemetry bridge; never places orders."
#property description "Sends structured observations created by this EA, not arbitrary MT4/other-EA logs."

#include "mt4/BiteySBTStructuredTelemetry.mqh"

input bool SendOneEventPerClosedBar = true;
input bool SendInitializationEvent = true;
input bool IncludeMarketSnapshot = true;
input int  MinimumSecondsBetweenEvents = 10;

datetime g_lastClosedBar = 0;
datetime g_lastSentAt = 0;

int OnInit()
{
   Print("SBT99 BRIDGE READY | trading=DISABLED | symbol=", Symbol(),
         " | timeframe=", Period(),
         " | telemetry=", SBT99_EnableTelemetry,
         " | route=", SBT99_TelemetryURL,
         " | note=EA_ONLY_EVENTS_NOT_GLOBAL_EXPERT_TAB_CAPTURE");

   if(SendInitializationEvent)
      SBT99_LogEvent("bridge_init",
                     "Telemetry bridge initialized; no order functions exist in this EA.",
                     "OBSERVE",
                     "INITIALIZED_NO_TRADING");

   g_lastClosedBar = 0;
   g_lastSentAt = 0;
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(!SendOneEventPerClosedBar) return;
   if(Bars < 30) return;

   datetime closedBar = iTime(Symbol(), Period(), 1);
   if(closedBar <= 0 || closedBar == g_lastClosedBar) return;
   g_lastClosedBar = closedBar;

   datetime now = TimeCurrent();
   if(g_lastSentAt > 0 && now - g_lastSentAt < MinimumSecondsBetweenEvents)
   {
      Print("SBT99 BRIDGE | result=SKIPPED | reason=RATE_LIMIT | bar=",
            TimeToString(closedBar, TIME_DATE|TIME_SECONDS));
      return;
   }
   g_lastSentAt = now;

   string msg = "Closed-bar observation only";
   if(IncludeMarketSnapshot)
      msg = "closed_bar=" + TimeToString(closedBar, TIME_DATE|TIME_SECONDS)
          + "; close=" + DoubleToString(iClose(Symbol(), Period(), 1), Digits)
          + "; spread_points=" + DoubleToString(MarketInfo(Symbol(), MODE_SPREAD), 1)
          + "; atr14=" + DoubleToString(iATR(Symbol(), Period(), 14, 1), Digits)
          + "; rsi14=" + DoubleToString(iRSI(Symbol(), Period(), 14, PRICE_CLOSE, 1), 2)
          + "; adx14=" + DoubleToString(iADX(Symbol(), Period(), 14, PRICE_CLOSE, MODE_MAIN, 1), 2);

   bool sent = SBT99_LogEvent("closed_bar_observation", msg,
                              "OBSERVE", "TELEMETRY_ONLY_NO_TRADE");
   Print("SBT99 BRIDGE STATUS | sent=", sent,
         " | trading=DISABLED | bar=", TimeToString(closedBar, TIME_DATE|TIME_SECONDS));
}

void OnDeinit(const int reason)
{
   Print("SBT99 BRIDGE STOPPED | reason=", reason,
         " | note=deinit event is logged locally only");
}
