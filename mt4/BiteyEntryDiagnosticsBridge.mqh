//+------------------------------------------------------------------+
//| Bitey MT4 Entry Diagnostics Bridge                               |
//| Contract: bitey-mt4-entry-diagnostics-v1                         |
//| Research/diagnostics only. Does NOT place broker orders.         |
//+------------------------------------------------------------------+
#property strict

input string BiteyDiagnosticsURL = "https://bitey-system-bots-trading.onrender.com/api/v1/mt4/bitey-entry-diagnostics";
input string BiteyMT4Token = "";
input bool   BiteyDiagnosticsEnabled = true;
input int    BiteyWebRequestTimeoutMs = 5000;

string BiteyJsonEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
}

string BiteyNum(double value, int digits=8)
{
   if(value == EMPTY_VALUE) return "null";
   return DoubleToString(value, digits);
}

string BiteyNullable(double value, int digits=8)
{
   if(value == EMPTY_VALUE) return "null";
   return DoubleToString(value, digits);
}

bool BiteySendEntryDiagnostic(
   int ticket,
   string symbol,
   string timeframe,
   string side,
   datetime timestamp,
   double entryPrice,
   double exitPrice,
   double pnl,
   double rMultiple,
   double score,
   double scoreGap,
   double rsi,
   double adx,
   double atr,
   double emaFast,
   double emaSlow,
   double ema200,
   string regime,
   string htfDirection,
   string exitReason,
   int durationBars,
   double maePct,
   double mfePct
)
{
   if(!BiteyDiagnosticsEnabled || StringLen(BiteyDiagnosticsURL) == 0)
      return false;

   string body = "{";
   body += "\"source\":\"AI_Trading_Bot_v1.34_Bitey\",";
   body += "\"symbol\":\"" + BiteyJsonEscape(symbol) + "\",";
   body += "\"timeframe\":\"" + BiteyJsonEscape(timeframe) + "\",";
   body += "\"report_type\":\"entry_diagnostics\",";
   body += "\"trades\":[{";
   body += "\"ticket\":" + IntegerToString(ticket) + ",";
   body += "\"symbol\":\"" + BiteyJsonEscape(symbol) + "\",";
   body += "\"timeframe\":\"" + BiteyJsonEscape(timeframe) + "\",";
   body += "\"side\":\"" + BiteyJsonEscape(side) + "\",";
   body += "\"timestamp\":\"" + TimeToString(timestamp, TIME_DATE|TIME_SECONDS) + "\",";
   body += "\"entry_price\":" + BiteyNum(entryPrice) + ",";
   body += "\"exit_price\":" + BiteyNum(exitPrice) + ",";
   body += "\"pnl\":" + BiteyNum(pnl,2) + ",";
   body += "\"r_multiple\":" + BiteyNullable(rMultiple,4) + ",";
   body += "\"score\":" + BiteyNullable(score,4) + ",";
   body += "\"score_gap\":" + BiteyNullable(scoreGap,4) + ",";
   body += "\"rsi\":" + BiteyNullable(rsi,4) + ",";
   body += "\"adx\":" + BiteyNullable(adx,4) + ",";
   body += "\"atr\":" + BiteyNullable(atr,8) + ",";
   body += "\"ema_fast\":" + BiteyNullable(emaFast,8) + ",";
   body += "\"ema_slow\":" + BiteyNullable(emaSlow,8) + ",";
   body += "\"ema_200\":" + BiteyNullable(ema200,8) + ",";
   body += "\"regime\":\"" + BiteyJsonEscape(regime) + "\",";
   body += "\"htf_direction\":\"" + BiteyJsonEscape(htfDirection) + "\",";
   body += "\"exit_reason\":\"" + BiteyJsonEscape(exitReason) + "\",";
   body += "\"duration_bars\":" + IntegerToString(durationBars) + ",";
   body += "\"mae_pct\":" + BiteyNullable(maePct,6) + ",";
   body += "\"mfe_pct\":" + BiteyNullable(mfePct,6);
   body += "}]}";

   char post[];
   char result[];
   string headers = "Content-Type: application/json\\r\\n";
   if(StringLen(BiteyMT4Token) > 0)
      headers += "X-MT4-Token: " + BiteyMT4Token + "\\r\\n";

   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   ResetLastError();

   string responseHeaders;
   int status = WebRequest(
      "POST",
      BiteyDiagnosticsURL,
      headers,
      BiteyWebRequestTimeoutMs,
      post,
      result,
      responseHeaders
   );

   if(status >= 200 && status < 300)
      return true;

   Print("Bitey diagnostics WebRequest failed. HTTP=", status,
         " error=", GetLastError(),
         " response=", CharArrayToString(result));
   return false;
}
