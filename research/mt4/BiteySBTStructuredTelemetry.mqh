#ifndef __BITEY_SBT_STRUCTURED_TELEMETRY_MQH__
#define __BITEY_SBT_STRUCTURED_TELEMETRY_MQH__

// Research-only telemetry. Never place GitHub PATs or database service keys here.
// Configure a dedicated ingestion token on the MT4 terminal, if the backend requires it.
// WebRequest requires the Worker origin in Tools > Options > Expert Advisors.
// WebRequest does not execute in Strategy Tester; use live-chart/demo terminal smoke tests.

input bool   SBT99_EnableTelemetry = true;
input string SBT99_TelemetryURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/signal-event";
input string SBT99_TelemetryToken = "";
input int    SBT99_TimeoutMs = 1200;

string SBT99_JsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   StringReplace(value, "\t", "\\t");
   return value;
}

string SBT99_IsoLike(datetime value)
{
   // MT4 datetime has no timezone metadata. This string intentionally has NO Z suffix.
   string s = TimeToString(value, TIME_DATE|TIME_SECONDS);
   StringReplace(s, ".", "-");
   StringReplace(s, " ", "T");
   return s;
}

bool SBT99_PostJSON(string payload)
{
   if(!SBT99_EnableTelemetry || StringLen(SBT99_TelemetryURL) < 12)
      return false;

   char body[];
   char response[];
   string responseHeaders;
   int count = StringToCharArray(payload, body, 0, WHOLE_ARRAY, CP_UTF8);
   if(count <= 1)
   {
      Print("SBT99 TELEMETRY | result=SKIPPED | reason=EMPTY_PAYLOAD");
      return false;
   }
   ArrayResize(body, count - 1); // remove terminating NUL

   string headers = "Content-Type: application/json\r\n";
   if(StringLen(SBT99_TelemetryToken) > 0)
      headers += "X-MT4-Token: " + SBT99_TelemetryToken + "\r\n";

   ResetLastError();
   int status = WebRequest("POST", SBT99_TelemetryURL, headers,
                           SBT99_TimeoutMs, body, response, responseHeaders);
   if(status < 200 || status >= 300)
   {
      int err = GetLastError();
      Print("SBT99 TELEMETRY | result=FAILED | http=", status,
            " | error=", err, " | note=verify_allowlist_and_backend_route");
      return false;
   }

   Print("SBT99 TELEMETRY | result=ACCEPTED | http=", status);
   return true;
}

// Use this function instead of Print() for events that must also be transmitted.
// This does NOT intercept Print() calls made by other EAs or MT4 itself.
bool SBT99_LogEvent(string eventType, string message, string decision, string reason)
{
   datetime barTime = iTime(Symbol(), Period(), 1);
   string eventId = Symbol() + "-" + IntegerToString(Period()) + "-" +
                    IntegerToString((int)barTime) + "-" + eventType;
   string utcNow = SBT99_IsoLike(TimeGMT());

   string payload = "{"
      + "\"schema_version\":\"1.0\","
      + "\"event_id\":\"" + SBT99_JsonEscape(eventId) + "\","
      + "\"event_time_utc\":\"" + SBT99_JsonEscape(utcNow) + "Z\","
      + "\"broker_time\":\"" + SBT99_JsonEscape(SBT99_IsoLike(TimeCurrent())) + "\","
      + "\"bar_time\":\"" + SBT99_JsonEscape(SBT99_IsoLike(barTime)) + "\","
      + "\"event_type\":\"" + SBT99_JsonEscape(eventType) + "\","
      + "\"symbol\":\"" + SBT99_JsonEscape(Symbol()) + "\","
      + "\"timeframe\":\"" + IntegerToString(Period()) + "\","
      + "\"ea_version\":\"1.99-research-telemetry\","
      + "\"source_commit\":\"research-v1.99-telemetry-and-evidence\","
      + "\"risk_policy\":\"ALL_ACCOUNTS_REAL_RISK\","
      + "\"decision\":\"" + SBT99_JsonEscape(decision) + "\","
      + "\"reason\":\"" + SBT99_JsonEscape(reason) + "\","
      + "\"message\":\"" + SBT99_JsonEscape(message) + "\","
      + "\"evidence_type\":\"LIVE_TERMINAL_OBSERVATION\","
      + "\"spread_points\":" + DoubleToString(MarketInfo(Symbol(), MODE_SPREAD), 1) + ","
      + "\"bid\":" + DoubleToString(MarketInfo(Symbol(), MODE_BID), Digits) + ","
      + "\"ask\":" + DoubleToString(MarketInfo(Symbol(), MODE_ASK), Digits) + ","
      + "\"atr\":" + DoubleToString(iATR(Symbol(), Period(), 14, 1), Digits) + ","
      + "\"rsi\":" + DoubleToString(iRSI(Symbol(), Period(), 14, PRICE_CLOSE, 1), 2) + ","
      + "\"adx\":" + DoubleToString(iADX(Symbol(), Period(), 14, PRICE_CLOSE, MODE_MAIN, 1), 2) + ","
      + "\"holdout_metrics\":null,"
      + "\"order\":null"
      + "}";

   Print("SBT99 EVENT | type=", eventType, " | symbol=", Symbol(),
         " | timeframe=", Period(), " | decision=", decision,
         " | reason=", reason, " | message=", message);
   return SBT99_PostJSON(payload);
}
#endif
