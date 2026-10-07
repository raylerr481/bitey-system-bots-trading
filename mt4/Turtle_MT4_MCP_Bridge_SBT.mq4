//+------------------------------------------------------------------+
//| Turtle_MT4_MCP_Bridge_SBT.mq4                                   |
//| MT4 -> SBT closed-trade evidence bridge.                        |
//| Execution remains entirely inside MT4.                          |
//+------------------------------------------------------------------+
#property strict
#property version "1.30"

input string InpSbtClosedTradeURL = "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/trade-closed";
input string InpMT4Token = "";
input int    InpPollSeconds = 2;
input int    InpWebRequestTimeoutMs = 8000;
input int    InpMagicNumber = 1222026;
input bool   InpOnlyMagic = true;
input string InpSymbolFilter = "";
input bool   InpVerbose = true;

string StateKey() {
   return "BITEY_SBT_BRIDGE_LAST_" + IntegerToString(AccountNumber()) + "_" + IntegerToString(InpMagicNumber);
}

string Esc(string s) {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\n", "\\n");
   return s;
}

string Num(double v, int d=8) { return DoubleToString(v, d); }

string Iso(datetime t) {
   if(t <= 0) return "";
   return TimeToString(t, TIME_DATE|TIME_SECONDS);
}

bool IsEligibleHistoryOrder() {
   int type = OrderType();
   if(type != OP_BUY && type != OP_SELL) return false;
   if(OrderCloseTime() <= 0) return false;
   if(InpOnlyMagic && OrderMagicNumber() != InpMagicNumber) return false;
   if(StringLen(InpSymbolFilter) > 0 && OrderSymbol() != InpSymbolFilter) return false;
   return true;
}

double CalcRMultiple() {
   double sl = OrderStopLoss();
   if(sl <= 0) return EMPTY_VALUE;
   double risk = 0.0;
   double move = 0.0;
   if(OrderType() == OP_BUY) {
      risk = OrderOpenPrice() - sl;
      move = OrderClosePrice() - OrderOpenPrice();
   } else {
      risk = sl - OrderOpenPrice();
      move = OrderOpenPrice() - OrderClosePrice();
   }
   if(risk <= 0) return EMPTY_VALUE;
   return move / risk;
}

string ExitReason() {
   double tol = MathMax(Point * 3.0, MarketInfo(OrderSymbol(), MODE_STOPLEVEL) * Point);
   if(OrderTakeProfit() > 0 && MathAbs(OrderClosePrice() - OrderTakeProfit()) <= tol * 2.0) return "TAKE_PROFIT";
   if(OrderStopLoss() > 0 && MathAbs(OrderClosePrice() - OrderStopLoss()) <= tol * 2.0) return "STOP_LOSS";
   string c = OrderComment();
   if(StringFind(c, "[sl]") >= 0 || StringFind(c, "stop") >= 0) return "STOP_LOSS";
   if(StringFind(c, "[tp]") >= 0 || StringFind(c, "take") >= 0) return "TAKE_PROFIT";
   return "OTHER";
}

string BuildBody() {
   double pnl = OrderProfit() + OrderCommission() + OrderSwap();
   double r = CalcRMultiple();
   string body = "{";
   body += "\"source\":\"Turtle_MT4_MCP_Bridge_SBT\",";
   body += "\"account_mode\":\"MT4_TERMINAL\",";
   body += "\"ticket\":" + IntegerToString(OrderTicket()) + ",";
   body += "\"magic\":" + IntegerToString(OrderMagicNumber()) + ",";
   body += "\"bot_id\":\"TURTLE_MT4_MCP\",";
   body += "\"strategy\":\"TURTLE_CLASSIC\",";
   body += "\"version\":\"bridge-1.30\",";
   body += "\"symbol\":\"" + Esc(OrderSymbol()) + "\",";
   body += "\"timeframe\":\"" + Esc(EnumToString((ENUM_TIMEFRAMES)Period())) + "\",";
   body += "\"side\":\"" + (OrderType() == OP_BUY ? "BUY" : "SELL") + "\",";
   body += "\"lots\":" + Num(OrderLots(), 2) + ",";
   body += "\"open_time\":\"" + Esc(Iso(OrderOpenTime())) + "\",";
   body += "\"close_time\":\"" + Esc(Iso(OrderCloseTime())) + "\",";
   body += "\"open_price\":" + Num(OrderOpenPrice(), Digits) + ",";
   body += "\"close_price\":" + Num(OrderClosePrice(), Digits) + ",";
   body += "\"stop_loss\":" + Num(OrderStopLoss(), Digits) + ",";
   body += "\"take_profit\":" + Num(OrderTakeProfit(), Digits) + ",";
   body += "\"pnl\":" + Num(pnl, 2) + ",";
   body += "\"commission\":" + Num(OrderCommission(), 2) + ",";
   body += "\"swap\":" + Num(OrderSwap(), 2) + ",";
   body += "\"cost\":" + Num(OrderCommission() + OrderSwap(), 2) + ",";
   body += "\"exit_reason\":\"" + ExitReason() + "\",";
   if(r == EMPTY_VALUE) body += "\"r_multiple\":null,";
   else body += "\"r_multiple\":" + Num(r, 6) + ",";
   body += "\"metadata\":{";
   body += "\"account_number\":" + IntegerToString(AccountNumber()) + ",";
   body += "\"broker\":\"" + Esc(AccountCompany()) + "\",";
   body += "\"account_balance\":" + Num(AccountBalance(), 2) + ",";
   body += "\"account_equity\":" + Num(AccountEquity(), 2) + ",";
   body += "\"sbt_operational_capital_usd\":500.0,";
   body += "\"comment\":\"" + Esc(OrderComment()) + "\"";
   body += "}}";
   return body;
}

bool PostClosedTrade() {
   string body = BuildBody();
   char post[];
   char result[];
   StringToCharArray(body, post, 0, -1, CP_UTF8);
   int n = ArraySize(post);
   if(n > 0 && post[n-1] == 0) ArrayResize(post, n-1);

   string headers = "Content-Type: application/json; charset=utf-8\r\n";
   if(StringLen(InpMT4Token) > 0) headers += "X-MT4-Token: " + InpMT4Token + "\r\n";
   ResetLastError();
   string responseHeaders;
   int status = WebRequest("POST", InpSbtClosedTradeURL, headers, InpWebRequestTimeoutMs, post, result, responseHeaders);
   int err = GetLastError();

   if(InpVerbose)
      Print("SBT close evidence ticket=", OrderTicket(), " HTTP=", status, " error=", err,
            " response=", CharArrayToString(result));
   return status >= 200 && status < 300;
}

void BaselineHistory() {
   int total = OrdersHistoryTotal();
   datetime newest = 0;
   int newestTicket = 0;
   for(int i=0;i<total;i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEligibleHistoryOrder()) continue;
      datetime ct = OrderCloseTime();
      if(ct > newest || (ct == newest && OrderTicket() > newestTicket)) {
         newest = ct;
         newestTicket = OrderTicket();
      }
   }
   GlobalVariableSet(StateKey(), (double)newestTicket);
}

void ProcessClosedTrades() {
   int total = OrdersHistoryTotal();
   int maxTicket = (int)GlobalVariableGet(StateKey());
   int selected[];
   ArrayResize(selected, 0);

   for(int i=0;i<total;i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(!IsEligibleHistoryOrder()) continue;
      int ticket = OrderTicket();
      if(ticket <= maxTicket) continue;
      int sz = ArraySize(selected);
      ArrayResize(selected, sz+1);
      selected[sz] = ticket;
   }

   int count = ArraySize(selected);
   for(int a=0;a<count-1;a++) for(int b=a+1;b<count;b++) if(selected[b] < selected[a]) {
      int tmp=selected[a]; selected[a]=selected[b]; selected[b]=tmp;
   }

   for(int k=0;k<count;k++) {
      if(!OrderSelect(selected[k], SELECT_BY_TICKET, MODE_HISTORY)) continue;
      if(!PostClosedTrade()) continue;
      maxTicket = selected[k];
      GlobalVariableSet(StateKey(), (double)maxTicket);
   }
}

int OnInit() {
   EventSetTimer(MathMax(1, InpPollSeconds));
   if(!GlobalVariableCheck(StateKey())) BaselineHistory();
   Print("Turtle_MT4_MCP_Bridge_SBT initialized. MT4 stays ON; closed-trade evidence only. SBT cap=$500.");
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTimer() { ProcessClosedTrades(); }
void OnTick() { /* Timer-driven; no trading commands. */ }
//+------------------------------------------------------------------+
