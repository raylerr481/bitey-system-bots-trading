//+------------------------------------------------------------------+
//| Evidence Lab v1.02 - MT4 telemetry and resilient SBT bridge      |
//| Trading is ALWAYS enabled. This module never switches Demo/Real. |
//| HTTP failures never block broker execution or local evidence.    |
//+------------------------------------------------------------------+
#property strict

input string EL102_URL = "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/evidence";
input string EL102_TOKEN = "";
input bool   EL102_TELEMETRY_ENABLED = true;
input int    EL102_TIMEOUT_MS = 5000;
input int    EL102_BASE_BACKOFF_SEC = 30;
input int    EL102_MAX_BACKOFF_SEC = 300;
input string EL102_EXPERIMENT_ID = "INTRADAY-EURUSD-ENSEMBLE-M15";
input int    EL102_MAGIC = 5102026;
input string EL102_LEDGER_FILE = "EvidenceLab_v1_02.csv";

datetime g_el102_next_allowed = 0;
int      g_el102_consecutive_failures = 0;
int      g_el102_last_http = 0;
string   g_el102_last_status = "INIT";

string EL102_Escape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
}

string EL102_Num(double value, int digits=8)
{
   if(value == EMPTY_VALUE) return "null";
   return DoubleToString(value, digits);
}

bool EL102_TradingAlwaysEnabled()
{
   // Permanent contract: this module never disables trading.
   return true;
}

void EL102_WriteLedger(
   string event_type,
   string side,
   int ticket,
   double lots,
   double price,
   double sl,
   double tp,
   double pnl,
   string note
)
{
   int h = FileOpen(
      EL102_LEDGER_FILE,
      FILE_CSV|FILE_READ|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE,
      ';'
   );
   if(h == INVALID_HANDLE)
   {
      Print("Evidence Lab ledger open failed. error=", GetLastError());
      return;
   }

   if(FileSize(h) == 0)
   {
      FileWrite(h,
         "timestamp","account","symbol","experiment_id","magic",
         "event","side","ticket","lots","price","sl","tp","pnl","note"
      );
   }

   FileSeek(h, 0, SEEK_END);
   FileWrite(h,
      TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      IntegerToString(AccountNumber()),
      Symbol(),
      EL102_EXPERIMENT_ID,
      IntegerToString(EL102_MAGIC),
      event_type,
      side,
      IntegerToString(ticket),
      DoubleToString(lots,2),
      DoubleToString(price,Digits),
      DoubleToString(sl,Digits),
      DoubleToString(tp,Digits),
      DoubleToString(pnl,2),
      note
   );
   FileClose(h);
}

int EL102_BackoffSeconds(int http_status)
{
   int n = g_el102_consecutive_failures;
   if(n < 1) n = 1;

   int seconds = EL102_BASE_BACKOFF_SEC;
   if(http_status == 429)
      seconds = 120;
   else if(http_status == 503 || http_status == 502 || http_status == 504)
      seconds = 90;
   else if(http_status >= 400)
      seconds = 60;

   for(int i=1; i<n && seconds < EL102_MAX_BACKOFF_SEC; i++)
      seconds = MathMin(seconds * 2, EL102_MAX_BACKOFF_SEC);

   return MathMin(seconds, EL102_MAX_BACKOFF_SEC);
}

bool EL102_CanSend()
{
   if(!EL102_TELEMETRY_ENABLED) return false;
   if(g_el102_next_allowed == 0) return true;
   return TimeCurrent() >= g_el102_next_allowed;
}

bool EL102_Send(string payload)
{
   if(!EL102_CanSend())
      return false;

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(EL102_TOKEN) > 0)
      headers += "X-MT4-Token: " + EL102_TOKEN + "\r\n";

   StringToCharArray(payload, post, 0, StringLen(payload), CP_UTF8);
   ResetLastError();

   string response_headers;
   int status = WebRequest(
      "POST",
      EL102_URL,
      headers,
      EL102_TIMEOUT_MS,
      post,
      result,
      response_headers
   );

   g_el102_last_http = status;

   if(status >= 200 && status < 300)
   {
      g_el102_consecutive_failures = 0;
      g_el102_next_allowed = 0;
      g_el102_last_status = "OK";
      return true;
   }

   g_el102_consecutive_failures++;
   int wait_seconds = EL102_BackoffSeconds(status);
   g_el102_next_allowed = TimeCurrent() + wait_seconds;

   if(status == 429)
      g_el102_last_status = "BACKOFF_429";
   else if(status == 503 || status == 502 || status == 504)
      g_el102_last_status = "BACKOFF_SERVER";
   else
      g_el102_last_status = "BACKOFF_ERROR";

   Print(
      "Evidence Lab v1.02 telemetry failed. HTTP=", status,
      " error=", GetLastError(),
      " retry_in=", wait_seconds, "s",
      " status=", g_el102_last_status
   );

   // Deliberately do not return a trading-control signal.
   // Trading remains enabled and broker execution is independent.
   return false;
}

void EL102_RecordTrade(
   string event_type,
   string side,
   int ticket,
   double lots,
   double price,
   double sl,
   double tp,
   double pnl,
   string note
)
{
   EL102_WriteLedger(event_type, side, ticket, lots, price, sl, tp, pnl, note);

   if(!EL102_TELEMETRY_ENABLED) return;

   string payload = "{";
   payload += "\"source\":\"EvidenceLab_MT4_v1.02\",";
   payload += "\"experiment_id\":\"" + EL102_Escape(EL102_EXPERIMENT_ID) + "\",";
   payload += "\"trading_enabled\":true,";
   payload += "\"account\":" + IntegerToString(AccountNumber()) + ",";
   payload += "\"symbol\":\"" + EL102_Escape(Symbol()) + "\",";
   payload += "\"timeframe\":\"" + IntegerToString(Period()) + "\",";
   payload += "\"magic\":" + IntegerToString(EL102_MAGIC) + ",";
   payload += "\"event\":\"" + EL102_Escape(event_type) + "\",";
   payload += "\"side\":\"" + EL102_Escape(side) + "\",";
   payload += "\"ticket\":" + IntegerToString(ticket) + ",";
   payload += "\"lots\":" + EL102_Num(lots,2) + ",";
   payload += "\"price\":" + EL102_Num(price,Digits) + ",";
   payload += "\"sl\":" + EL102_Num(sl,Digits) + ",";
   payload += "\"tp\":" + EL102_Num(tp,Digits) + ",";
   payload += "\"pnl\":" + EL102_Num(pnl,2) + ",";
   payload += "\"balance\":" + EL102_Num(AccountBalance(),2) + ",";
   payload += "\"equity\":" + EL102_Num(AccountEquity(),2) + ",";
   payload += "\"open_trades\":" + IntegerToString(OrdersTotal()) + ",";
   payload += "\"telemetry_status\":\"" + EL102_Escape(g_el102_last_status) + "\"";
   payload += "}";

   EL102_Send(payload);
}

void EL102_RecordSnapshot(
   string regime,
   string strategy,
   string direction,
   double score,
   double atr,
   double rsi,
   double adx
)
{
   string note = "snapshot";
   EL102_WriteLedger(
      "SNAPSHOT", direction, -1, 0, Bid, 0, 0, 0, note
   );

   if(!EL102_TELEMETRY_ENABLED) return;

   string payload = "{";
   payload += "\"source\":\"EvidenceLab_MT4_v1.02\",";
   payload += "\"experiment_id\":\"" + EL102_Escape(EL102_EXPERIMENT_ID) + "\",";
   payload += "\"trading_enabled\":true,";
   payload += "\"account\":" + IntegerToString(AccountNumber()) + ",";
   payload += "\"symbol\":\"" + EL102_Escape(Symbol()) + "\",";
   payload += "\"timeframe\":\"" + IntegerToString(Period()) + "\",";
   payload += "\"magic\":" + IntegerToString(EL102_MAGIC) + ",";
   payload += "\"regime\":\"" + EL102_Escape(regime) + "\",";
   payload += "\"strategy\":\"" + EL102_Escape(strategy) + "\",";
   payload += "\"direction\":\"" + EL102_Escape(direction) + "\",";
   payload += "\"score\":" + EL102_Num(score,4) + ",";
   payload += "\"market\":{";
   payload += "\"bid\":" + EL102_Num(Bid,Digits) + ",";
   payload += "\"ask\":" + EL102_Num(Ask,Digits) + ",";
   payload += "\"atr\":" + EL102_Num(atr,Digits) + ",";
   payload += "\"rsi\":" + EL102_Num(rsi,4) + ",";
   payload += "\"adx\":" + EL102_Num(adx,4);
   payload += "},";
   payload += "\"account_state\":{";
   payload += "\"balance\":" + EL102_Num(AccountBalance(),2) + ",";
   payload += "\"equity\":" + EL102_Num(AccountEquity(),2) + ",";
   payload += "\"open_trades\":" + IntegerToString(OrdersTotal());
   payload += "},";
   payload += "\"telemetry_status\":\"" + EL102_Escape(g_el102_last_status) + "\"";
   payload += "}";

   EL102_Send(payload);
}

string EL102_Status()
{
   return StringFormat(
      "EvidenceLab v1.02 | trading=ALWAYS_ON | HTTP=%d | status=%s | failures=%d | next=%s",
      g_el102_last_http,
      g_el102_last_status,
      g_el102_consecutive_failures,
      (g_el102_next_allowed > 0 ? TimeToString(g_el102_next_allowed, TIME_DATE|TIME_SECONDS) : "READY")
   );
}
