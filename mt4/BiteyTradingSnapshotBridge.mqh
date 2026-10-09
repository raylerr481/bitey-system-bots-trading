//+------------------------------------------------------------------+
//| Bitey MT4 Trading Snapshot Bridge                                |
//| Contract: bitey-mt4-trading-snapshot-v1                          |
//| Read/analysis bridge. Does NOT place broker orders.               |
//+------------------------------------------------------------------+
#property strict

input string BiteySnapshotURL = "https://bitey-system-bots-trading.raylerr481.workers.dev/api/v1/mt4/bitey-report";
input string BiteyMT4Token = "";
input bool   BiteySnapshotEnabled = true;
input int    BiteyWebRequestTimeoutMs = 5000;

string BiteySnapshotEscape(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");
   return value;
}

string BiteySnapshotNum(double value, int digits=8)
{
   if(value == EMPTY_VALUE) return "null";
   return DoubleToString(value, digits);
}

// Call this from OnTick() or on a new-bar event.
// The values are intentionally supplied by the EA so this bridge remains generic.
bool BiteySendTradingSnapshot(
   string symbol,
   string timeframe,
   string mode,
   string regime,
   double hurst,
   string bestStrategy,
   double bestScore,
   double scoreGap,
   string htfDirection,
   double bid,
   double ask,
   double atr,
   double rsi,
   double adx,
   double balance,
   double equity,
   int openTrades
)
{
   if(!BiteySnapshotEnabled || StringLen(BiteySnapshotURL) == 0)
      return false;

   string body = "{";
   body += "\"source\":\"Bitey_MT4_Snapshot_Bridge\",";
   body += "\"symbol\":\"" + BiteySnapshotEscape(symbol) + "\",";
   body += "\"timeframe\":\"" + BiteySnapshotEscape(timeframe) + "\",";
   body += "\"mode\":\"" + BiteySnapshotEscape(mode) + "\",";
   body += "\"execution_enabled\":false,";
   body += "\"regime\":\"" + BiteySnapshotEscape(regime) + "\",";
   body += "\"hurst\":" + BiteySnapshotNum(hurst,4) + ",";
   body += "\"best_strategy\":\"" + BiteySnapshotEscape(bestStrategy) + "\",";
   body += "\"best_score\":" + BiteySnapshotNum(bestScore,4) + ",";
   body += "\"metrics\":{\"score_gap\":" + BiteySnapshotNum(scoreGap,4) + ",\"htf_direction\":\"" + BiteySnapshotEscape(htfDirection) + "\"},";
   body += "\"market\":{\"bid\":" + BiteySnapshotNum(bid,Digits) + ",\"ask\":" + BiteySnapshotNum(ask,Digits) + ",\"atr\":" + BiteySnapshotNum(atr,Digits) + ",\"rsi\":" + BiteySnapshotNum(rsi,4) + ",\"adx\":" + BiteySnapshotNum(adx,4) + "},";
   body += "\"account\":{\"balance\":" + BiteySnapshotNum(balance,2) + ",\"equity\":" + BiteySnapshotNum(equity,2) + ",\"open_trades\":" + IntegerToString(openTrades) + "}";
   body += "}";

   char post[];
   char result[];
   string headers = "Content-Type: application/json\r\n";
   if(StringLen(BiteyMT4Token) > 0)
      headers += "X-MT4-Token: " + BiteyMT4Token + "\r\n";

   StringToCharArray(body, post, 0, StringLen(body), CP_UTF8);
   ResetLastError();

   string responseHeaders;
   int status = WebRequest("POST", BiteySnapshotURL, headers,
                           BiteyWebRequestTimeoutMs, post, result, responseHeaders);

   if(status >= 200 && status < 300)
      return true;

   Print("Bitey snapshot WebRequest failed. HTTP=", status,
         " error=", GetLastError(),
         " response=", CharArrayToString(result));
   return false;
}

// Backward-compatible overload. Existing Turtle EA builds continue to compile.
bool BiteySendTurtleSnapshot(
   string symbol,string timeframe,string mode,string regime,double hurst,
   string bestStrategy,double bestScore,double scoreGap,string htfDirection,
   double bid,double ask,double atr,double rsi,double adx,double balance,
   double equity,int openTrades,int campaignId,int campaignSystem,
   int campaignDirection,int campaignUnits,double campaignLastEntry,
   double campaignN,bool campaignActive,bool s1SkipNext,bool s1SkipLatched)
{
   return BiteySendTurtleSnapshot(symbol,timeframe,mode,regime,hurst,bestStrategy,
      bestScore,scoreGap,htfDirection,bid,ask,atr,rsi,adx,balance,equity,
      openTrades,campaignId,campaignSystem,campaignDirection,campaignUnits,
      campaignLastEntry,campaignN,campaignActive,s1SkipNext,s1SkipLatched,
      "UNKNOWN","UNKNOWN",0,EMPTY_VALUE,campaignLastEntry,"",EMPTY_VALUE,EMPTY_VALUE);
}

// Extended Turtle snapshot with campaign state. Read-only telemetry only.
bool BiteySendTurtleSnapshot(
   string symbol,string timeframe,string mode,string regime,double hurst,
   string bestStrategy,double bestScore,double scoreGap,string htfDirection,
   double bid,double ask,double atr,double rsi,double adx,double balance,
   double equity,int openTrades,int campaignId,int campaignSystem,
   int campaignDirection,int campaignUnits,double campaignLastEntry,
   double campaignN,bool campaignActive,bool s1SkipNext,bool s1SkipLatched,
   string entryReason,string entrySystem,int breakoutPeriod,double breakoutLevel,
   double entryPrice,string entryTime,double nAtEntry,double initialStop)
{
   if(!BiteySnapshotEnabled || StringLen(BiteySnapshotURL)==0) return false;

   string body="{";
   body += "\"source\":\"Bitey_MT4_Turtle_v1_26\",";
   body += "\"symbol\":\"" + BiteySnapshotEscape(symbol) + "\",";
   body += "\"timeframe\":\"" + BiteySnapshotEscape(timeframe) + "\",";
   body += "\"mode\":\"" + BiteySnapshotEscape(mode) + "\",";
   body += "\"execution_enabled\":false,";
   body += "\"regime\":\"" + BiteySnapshotEscape(regime) + "\",";
   body += "\"hurst\":" + BiteySnapshotNum(hurst,4) + ",";
   body += "\"best_strategy\":\"" + BiteySnapshotEscape(bestStrategy) + "\",";
   body += "\"best_score\":" + BiteySnapshotNum(bestScore,4) + ",";
   body += "\"metrics\":{\"score_gap\":" + BiteySnapshotNum(scoreGap,4) +
           ",\"htf_direction\":\"" + BiteySnapshotEscape(htfDirection) + "\"},";
   body += "\"market\":{\"bid\":" + BiteySnapshotNum(bid,Digits) +
           ",\"ask\":" + BiteySnapshotNum(ask,Digits) +
           ",\"atr\":" + BiteySnapshotNum(atr,Digits) +
           ",\"rsi\":" + BiteySnapshotNum(rsi,4) +
           ",\"adx\":" + BiteySnapshotNum(adx,4) + "},";
   body += "\"account\":{\"balance\":" + BiteySnapshotNum(balance,2) +
           ",\"equity\":" + BiteySnapshotNum(equity,2) +
           ",\"open_trades\":" + IntegerToString(openTrades) + "},";
   body += "\"turtle\":{\"campaign_id\":" + IntegerToString(campaignId) +
           ",\"campaign_system\":" + IntegerToString(campaignSystem) +
           ",\"campaign_direction\":" + IntegerToString(campaignDirection) +
           ",\"campaign_units\":" + IntegerToString(campaignUnits) +
           ",\"campaign_last_entry\":" + BiteySnapshotNum(campaignLastEntry,Digits) +
           ",\"campaign_n\":" + BiteySnapshotNum(campaignN,Digits) +
           ",\"campaign_active\":" + (campaignActive?"true":"false") +
           ",\"s1_skip_next\":" + (s1SkipNext?"true":"false") +
           ",\"s1_skip_latched\":" + (s1SkipLatched?"true":"false") +
           ",\"entry_reason\":\"" + BiteySnapshotEscape(entryReason) + "\"" +
           ",\"entry_system\":\"" + BiteySnapshotEscape(entrySystem) + "\"" +
           ",\"breakout_period\":" + IntegerToString(breakoutPeriod) +
           ",\"breakout_level\":" + BiteySnapshotNum(breakoutLevel,Digits) +
           ",\"entry_price\":" + BiteySnapshotNum(entryPrice,Digits) +
           ",\"entry_time\":\"" + BiteySnapshotEscape(entryTime) + "\"" +
           ",\"n_at_entry\":" + BiteySnapshotNum(nAtEntry,Digits) +
           ",\"initial_stop\":" + BiteySnapshotNum(initialStop,Digits) + "}";
   body += "}";

   char post[]; char result[];
   string headers="Content-Type: application/json\r\n";
   if(StringLen(BiteyMT4Token)>0) headers += "X-MT4-Token: " + BiteyMT4Token + "\r\n";
   StringToCharArray(body,post,0,StringLen(body),CP_UTF8);
   ResetLastError();
   string responseHeaders;
   int status=WebRequest("POST",BiteySnapshotURL,headers,BiteyWebRequestTimeoutMs,
                         post,result,responseHeaders);
   if(status>=200 && status<300) return true;
   Print("Bitey Turtle snapshot WebRequest failed. HTTP=",status,
         " error=",GetLastError()," response=",CharArrayToString(result));
   return false;
}
