#property strict
#property version   "1.4.2"
#property description "MT4 local state + HTTPS telemetry bridge for Bitey SBT"

input int    InpExportSeconds       = 10;
input string InpStateFile           = "MT4_MCP_state.json";
input string InpCommandFile         = "MT4_MCP_commands.txt";
input bool   InpAllowCommands       = false;

input bool   InpSbtEnabled          = true;
input string InpSbtURL              = "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/bitey-report";
input string InpSbtToken            = "";
input int    InpWebRequestTimeoutMs  = 5000;

input string InpBotName             = "Turtle_v1_26";
input string InpBotStrategy         = "TURTLE";
input string InpBotVersion          = "1.26";
input int    InpBotMagic            = 1222026;
input string InpBotTimeframe        = "H1";

string JsonEscape(string s)
{
   StringReplace(s,"\\","\\\\");
   StringReplace(s,"\"","\\\"");
   StringReplace(s,"\r","\\r");
   StringReplace(s,"\n","\\n");
   return s;
}

string AccountMode()
{
   if(IsDemo()) return "DEMO";
   return "REAL";
}

string TimeframeName(int tf)
{
   switch(tf)
   {
      case PERIOD_M1: return "M1";
      case PERIOD_M5: return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1: return "H1";
      case PERIOD_H4: return "H4";
      case PERIOD_D1: return "D1";
      case PERIOD_W1: return "W1";
      case PERIOD_MN1: return "MN1";
   }
   return IntegerToString(tf);
}

void WriteState()
{
   int h=FileOpen(InpStateFile,FILE_COMMON|FILE_TXT|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
   if(h==INVALID_HANDLE) return;

   string j="{";
   j += "\"time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",";
   j += "\"account\":{";
   j += "\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   j += "\"equity\":"+DoubleToString(AccountEquity(),2)+",";
   j += "\"free_margin\":"+DoubleToString(AccountFreeMargin(),2)+",";
   j += "\"currency\":\""+JsonEscape(AccountCurrency())+"\",";
   j += "\"broker\":\""+JsonEscape(AccountCompany())+"\",";
   j += "\"server\":\""+JsonEscape(AccountServer())+"\",";
   j += "\"mode\":\""+AccountMode()+"\"},";
   j += "\"market\":{";
   j += "\"symbol\":\""+JsonEscape(Symbol())+"\",";
   j += "\"timeframe\":\""+TimeframeName(Period())+"\",";
   j += "\"bid\":"+DoubleToString(Bid,Digits)+",";
   j += "\"ask\":"+DoubleToString(Ask,Digits)+",";
   j += "\"spread_points\":"+DoubleToString((Ask-Bid)/Point,1)+"},";
   j += "\"terminal\":{";
   j += "\"build\":"+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD))+",";
   j += "\"trade_allowed\":"+(IsTradeAllowed()?"true":"false")+"},";
   j += "\"positions\":[";
   bool first=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderType()>OP_SELL) continue;
      if(!first) j+=",";
      first=false;
      j+="{\"ticket\":"+IntegerToString(OrderTicket())+",";
      j+="\"symbol\":\""+JsonEscape(OrderSymbol())+"\",";
      j+="\"type\":"+IntegerToString(OrderType())+",";
      j+="\"lots\":"+DoubleToString(OrderLots(),2)+",";
      j+="\"open_price\":"+DoubleToString(OrderOpenPrice(),Digits)+",";
      j+="\"stop_loss\":"+DoubleToString(OrderStopLoss(),Digits)+",";
      j+="\"take_profit\":"+DoubleToString(OrderTakeProfit(),Digits)+",";
      j+="\"profit\":"+DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),2)+",";
      j+="\"magic\":"+IntegerToString(OrderMagicNumber())+",";
      j+="\"comment\":\""+JsonEscape(OrderComment())+"\"}";
   }
   j+="]}";
   FileWriteString(h,j);
   FileClose(h);
}

string BuildSbtPayload()
{
   string j="{";
   j += "\"source\":\"MT4_DESKTOP\",";
   j += "\"symbol\":\""+JsonEscape(Symbol())+"\",";
   j += "\"timeframe\":\""+TimeframeName(Period())+"\",";
   j += "\"timestamp\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",";
   j += "\"mode\":\""+AccountMode()+"\",";
   j += "\"execution_enabled\":"+(IsTradeAllowed()?"true":"false")+",";
   j += "\"bot\":{";
   j += "\"name\":\""+JsonEscape(InpBotName)+"\",";
   j += "\"strategy\":\""+JsonEscape(InpBotStrategy)+"\",";
   j += "\"version\":\""+JsonEscape(InpBotVersion)+"\",";
   j += "\"magic\":"+IntegerToString(InpBotMagic)+",";
   j += "\"timeframe\":\""+JsonEscape(InpBotTimeframe)+"\"},";
   j += "\"account\":{";
   j += "\"broker\":\""+JsonEscape(AccountCompany())+"\",";
   j += "\"server\":\""+JsonEscape(AccountServer())+"\",";
   j += "\"mode\":\""+AccountMode()+"\",";
   j += "\"currency\":\""+JsonEscape(AccountCurrency())+"\",";
   j += "\"balance\":"+DoubleToString(AccountBalance(),2)+",";
   j += "\"equity\":"+DoubleToString(AccountEquity(),2)+"},";
   j += "\"market\":{";
   j += "\"bid\":"+DoubleToString(Bid,Digits)+",";
   j += "\"ask\":"+DoubleToString(Ask,Digits)+",";
   j += "\"spread_points\":"+DoubleToString((Ask-Bid)/Point,1)+"},";
   j += "\"terminal\":{";
   j += "\"build\":"+IntegerToString((int)TerminalInfoInteger(TERMINAL_BUILD))+",";
   j += "\"expert_name\":\""+JsonEscape(MQLInfoString(MQL_PROGRAM_NAME))+"\",";
   j += "\"trade_allowed\":"+(IsTradeAllowed()?"true":"false")+"},";
   j += "\"turtle\":{";
   j += "\"system\":\""+JsonEscape(InpBotStrategy)+"\",";
   j += "\"magic\":"+IntegerToString(InpBotMagic)+"},";
   j += "\"metrics\":{";
   j += "\"positions_open\":"+IntegerToString(OrdersTotal())+",";
   j += "\"history_total\":"+IntegerToString(OrdersHistoryTotal())+"}";
   j += "}";
   return j;
}

bool SendToSbt(string payload)
{
   if(!InpSbtEnabled) return false;
   if(StringLen(InpSbtURL)<10) return false;

   // WebRequest() expects a char[] body, while StringToCharArray() writes to uchar[].
   // Convert explicitly to avoid overload/type ambiguity in MetaEditor.
   uchar utf8[];
   char data[];
   char result[];
   string result_headers="";
   string headers="Content-Type: application/json\r\n";
   if(StringLen(InpSbtToken)>0)
      headers += "x-mt4-token: "+InpSbtToken+"\r\n";

   int utf8_size=StringToCharArray(payload,utf8,0,WHOLE_ARRAY,CP_UTF8);
   int data_size=utf8_size;
   if(data_size>0 && utf8[data_size-1]==0)
      data_size--;

   if(data_size>0)
   {
      ArrayResize(data,data_size);
      for(int i=0;i<data_size;i++)
         data[i]=(char)utf8[i];
   }

   ResetLastError();
   int code=WebRequest("POST",InpSbtURL,headers,InpWebRequestTimeoutMs,data,result,result_headers);
   int err=GetLastError();

   if(code>=200 && code<300)
   {
      string response=CharArrayToString(result);
      int h=FileOpen("MT4_Bitey_AI_response.json",FILE_COMMON|FILE_TXT|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
      if(h!=INVALID_HANDLE)
      {
         FileWriteString(h,response);
         FileClose(h);
      }
      Comment("BITEY IA / SBT\nTelemetry: OK HTTP ",code,"\nMode: ",AccountMode()," | Bot: ",InpBotName," v",InpBotVersion,"\nAI response: MT4_Bitey_AI_response.json");
      Print("Bitey SBT telemetry sent: HTTP ",code);
      Print("Bitey IA response stored: MT4_Bitey_AI_response.json");
      return true;
   }

   if(code==-1)
      Print("Bitey SBT WebRequest failed: terminal_error=",err," url=",InpSbtURL);
   else
      Print("Bitey SBT telemetry rejected: HTTP ",code," terminal_error=",err," response=",CharArrayToString(result));
   return false;
}

void ExportAndSend()
{
   WriteState();
   if(InpSbtEnabled)
      SendToSbt(BuildSbtPayload());
}

void OnTimer(){ ExportAndSend(); }

int OnInit()
{
   EventSetTimer(MathMax(1,InpExportSeconds));
   ExportAndSend();
   Print("Turtle_MT4_MCP_Bridge v1.4.2 initialized; SBT telemetry=",(InpSbtEnabled?"ON":"OFF"),"; interval=",InpExportSeconds,"s");
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); }
void OnTick(){ }
