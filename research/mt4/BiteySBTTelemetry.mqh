#ifndef __BITEY_SBT_TELEMETRY_MQH__
#define __BITEY_SBT_TELEMETRY_MQH__

// Research telemetry only. Never put a GitHub PAT or database service-role key here.
// The token, if used, must be a dedicated rotatable MT4 ingestion token.
// Add the Worker URL to MT4: Tools > Options > Expert Advisors > Allow WebRequest.
input bool   SBT_EnableTelemetry = true;
input string SBT_TelemetryURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/signal-event";
input string SBT_TelemetryToken = "";
input int    SBT_TelemetryTimeoutMs = 1500;

// Sends one already-serialized JSON event. Call once per closed bar with a batched
// model array; do not call once per tick or once per model. Never blocks trading
// decisions on HTTP success and never changes order permissions.
bool SBT_SendTelemetryJSON(const string payload)
{
   if(!SBT_EnableTelemetry || StringLen(SBT_TelemetryURL) < 12)
      return(false);

   char postData[];
   char responseData[];
   string responseHeaders;
   int n = StringToCharArray(payload, postData, 0, WHOLE_ARRAY, CP_UTF8);
   if(n <= 1)
   {
      Print("SBT TELEMETRY | result=SKIPPED | reason=EMPTY_PAYLOAD");
      return(false);
   }
   ArrayResize(postData, n - 1); // omit terminating NUL

   string headers = "Content-Type: application/json\r\n";
   if(StringLen(SBT_TelemetryToken) > 0)
      headers += "X-MT4-Token: " + SBT_TelemetryToken + "\r\n";

   ResetLastError();
   int status = WebRequest("POST", SBT_TelemetryURL, headers,
                           SBT_TelemetryTimeoutMs, postData,
                           responseData, responseHeaders);
   if(status < 200 || status >= 300)
   {
      Print("SBT TELEMETRY | result=FAILED | http=", status,
            " | error=", GetLastError());
      return(false);
   }

   Print("SBT TELEMETRY | result=ACCEPTED | http=", status);
   return(true);
}
#endif
