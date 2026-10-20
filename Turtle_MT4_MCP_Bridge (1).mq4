#property strict
#property version   "1.0"
#property description "Safe MT4 local bridge for MCP Gateway: account, positions and market snapshots"

input int InpExportSeconds = 2;
input string InpStateFile = "MT4_MCP_state.json";
input string InpCommandFile = "MT4_MCP_commands.txt";
input bool InpAllowCommands = false;

string JsonEscape(string s)
{
   StringReplace(s,"\\","\\\\");
   StringReplace(s,"\"","\\\"");
   return s;
}

void WriteState()
{
   int h=FileOpen(InpStateFile,FILE_COMMON|FILE_TXT|FILE_WRITE|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
   if(h==INVALID_HANDLE) return;

   string j="{";
   j += "\"time\":\""+TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS)+"\",";
   j += "\"account\":{\"balance\":"+DoubleToString(AccountBalance(),2)+",\"equity\":"+DoubleToString(AccountEquity(),2)+",\"free_margin\":"+DoubleToString(AccountFreeMargin(),2)+",\"currency\":\""+JsonEscape(AccountCurrency())+"\"},";
   j += "\"market\":{\"symbol\":\""+JsonEscape(Symbol())+"\",\"bid\":"+DoubleToString(Bid,Digits)+",\"ask\":"+DoubleToString(Ask,Digits)+",\"spread_points\":"+DoubleToString((Ask-Bid)/Point,1)+"},";
   j += "\"positions\":[";
   bool first=true;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
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
   j+="],\"history\":[";
   first=true;
   int count=0;
   for(int hidx=OrdersHistoryTotal()-1;hidx>=0 && count<200;hidx--)
   {
      if(!OrderSelect(hidx,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderType()>OP_SELL) continue;
      if(!first) j+=",";
      first=false;
      count++;
      j+="{\"ticket\":"+IntegerToString(OrderTicket())+",";
      j+="\"symbol\":\""+JsonEscape(OrderSymbol())+"\",";
      j+="\"type\":"+IntegerToString(OrderType())+",";
      j+="\"lots\":"+DoubleToString(OrderLots(),2)+",";
      j+="\"open_time\":\""+TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS)+"\",";
      j+="\"close_time\":\""+TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS)+"\",";
      j+="\"open_price\":"+DoubleToString(OrderOpenPrice(),Digits)+",";
      j+="\"close_price\":"+DoubleToString(OrderClosePrice(),Digits)+",";
      j+="\"profit\":"+DoubleToString(OrderProfit()+OrderSwap()+OrderCommission(),2)+",";
      j+="\"magic\":"+IntegerToString(OrderMagicNumber())+",";
      j+="\"comment\":\""+JsonEscape(OrderComment())+"\"}";
   }
   j+="]}";
   FileWriteString(h,j);
   FileClose(h);
}

void OnTimer(){ WriteState(); }

int OnInit()
{
   EventSetTimer(MathMax(1,InpExportSeconds));
   WriteState();
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason){ EventKillTimer(); }
void OnTick(){ }
