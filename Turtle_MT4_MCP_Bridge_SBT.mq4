//+------------------------------------------------------------------+
//| Turtle_MT4_MCP_Bridge_SBT.mq4                                   |
//| MT4 -> SBT closed-trade evidence bridge                        |
//| Version 1.40                                                     |
//|                                                                  |
//| IMPORTANT:                                                        |
//| This EA does NOT open or modify trades.                          |
//| Trade execution remains entirely inside the Turtle EA.           |
//+------------------------------------------------------------------+
#property strict
#property version   "1.40"
#property description "MT4 to SBT closed-trade evidence bridge"
#property description "Execution remains entirely inside MT4"

//==================================================================
// INPUTS
//==================================================================

input string InpSbtClosedTradeURL =
   "https://bitey-system-bots-trading-api.onrender.com/api/v1/mt4/trade-closed";

input string InpMT4Token = "";

input int InpPollSeconds = 2;
input int InpWebRequestTimeoutMs = 8000;

input int InpMagicNumber = 1222026;
input bool InpOnlyMagic = true;

input string InpSymbolFilter = "";

input bool InpVerbose = true;

// Operational capital used by SBT risk context.
// This does NOT modify the MT4 account balance.
input double InpSbtOperationalCapitalUSD = 500.0;

//==================================================================
// CONSTANTS
//==================================================================

string BRIDGE_VERSION = "bridge-1.40";
string BRIDGE_NAME    = "Turtle_MT4_MCP_Bridge_SBT";

//==================================================================
// STATE
//==================================================================

string StateKey()
{
   return(
      "BITEY_SBT_BRIDGE_LAST_" +
      IntegerToString(AccountNumber()) +
      "_" +
      IntegerToString(InpMagicNumber)
   );
}

//==================================================================
// STRING HELPERS
//==================================================================

string Esc(string value)
{
   StringReplace(value, "\\", "\\\\");
   StringReplace(value, "\"", "\\\"");
   StringReplace(value, "\r", "\\r");
   StringReplace(value, "\n", "\\n");

   return value;
}

//------------------------------------------------------------------

string Num(double value, int digits = 8)
{
   return DoubleToString(value, digits);
}

//------------------------------------------------------------------

string Iso(datetime t)
{
   if(t <= 0)
      return "";

   return TimeToString(t, TIME_DATE | TIME_SECONDS);
}

//==================================================================
// ACCOUNT MODE
//==================================================================

string AccountMode()
{
   if(IsTesting())
      return "DEMO_TESTER";

   if(IsDemo())
      return "DEMO";

   return "REAL";
}

//==================================================================
// ORDER FILTER
//==================================================================

bool IsEligibleHistoryOrder()
{
   int type = OrderType();

   if(type != OP_BUY && type != OP_SELL)
      return false;

   if(OrderCloseTime() <= 0)
      return false;

   if(InpOnlyMagic)
   {
      if(OrderMagicNumber() != InpMagicNumber)
         return false;
   }

   if(StringLen(InpSymbolFilter) > 0)
   {
      if(OrderSymbol() != InpSymbolFilter)
         return false;
   }

   return true;
}

//==================================================================
// R MULTIPLE
//==================================================================

double CalcRMultiple()
{
   double sl = OrderStopLoss();

   if(sl <= 0)
      return EMPTY_VALUE;

   double risk = 0.0;
   double move = 0.0;

   if(OrderType() == OP_BUY)
   {
      risk = OrderOpenPrice() - sl;
      move = OrderClosePrice() - OrderOpenPrice();
   }
   else
   if(OrderType() == OP_SELL)
   {
      risk = sl - OrderOpenPrice();
      move = OrderOpenPrice() - OrderClosePrice();
   }

   if(risk <= 0)
      return EMPTY_VALUE;

   return(move / risk);
}

//==================================================================
// EXIT REASON
//==================================================================

string ExitReason()
{
   double pointValue = MarketInfo(OrderSymbol(), MODE_POINT);

   double stopLevel =
      MarketInfo(OrderSymbol(), MODE_STOPLEVEL) * pointValue;

   double tolerance =
      MathMax(pointValue * 3.0, stopLevel);

   if(OrderTakeProfit() > 0)
   {
      if(MathAbs(OrderClosePrice() - OrderTakeProfit())
         <= tolerance * 2.0)
      {
         return "TAKE_PROFIT";
      }
   }

   if(OrderStopLoss() > 0)
   {
      if(MathAbs(OrderClosePrice() - OrderStopLoss())
         <= tolerance * 2.0)
      {
         return "STOP_LOSS";
      }
   }

   string comment = OrderComment();

   string lowerComment = comment;
   StringToLower(lowerComment);

   if(StringFind(lowerComment, "[sl]") >= 0)
      return "STOP_LOSS";

   if(StringFind(lowerComment, "stop") >= 0)
      return "STOP_LOSS";

   if(StringFind(lowerComment, "[tp]") >= 0)
      return "TAKE_PROFIT";

   if(StringFind(lowerComment, "take") >= 0)
      return "TAKE_PROFIT";

   return "OTHER";
}

//==================================================================
// SIDE
//==================================================================

string OrderSide()
{
   if(OrderType() == OP_BUY)
      return "BUY";

   if(OrderType() == OP_SELL)
      return "SELL";

   return "UNKNOWN";
}

//==================================================================
// TIMEFRAME
//==================================================================

string CurrentTimeframe()
{
   return EnumToString((ENUM_TIMEFRAMES)Period());
}

//==================================================================
// BUILD JSON
//==================================================================

string BuildBody()
{
   double pnl =
      OrderProfit() +
      OrderCommission() +
      OrderSwap();

   double r = CalcRMultiple();

   string body = "";

   body += "{";

   // --------------------------------------------------------------
   // Bridge identity
   // --------------------------------------------------------------

   body += "\"source\":\"" + BRIDGE_NAME + "\",";
   body += "\"bridge_version\":\"" + BRIDGE_VERSION + "\",";

   // --------------------------------------------------------------
   // Account
   // --------------------------------------------------------------

   body += "\"account_mode\":\"" + AccountMode() + "\",";
   body += "\"account_number\":" +
           IntegerToString(AccountNumber()) + ",";

   body += "\"broker\":\"" +
           Esc(AccountCompany()) + "\",";

   // --------------------------------------------------------------
   // Trade identity
   // --------------------------------------------------------------

   body += "\"ticket\":" +
           IntegerToString(OrderTicket()) + ",";

   body += "\"magic\":" +
           IntegerToString(OrderMagicNumber()) + ",";

   body += "\"bot_id\":\"TURTLE_MT4_MCP\",";
   body += "\"strategy\":\"TURTLE_CLASSIC\",";

   // --------------------------------------------------------------
   // Market
   // --------------------------------------------------------------

   body += "\"symbol\":\"" +
           Esc(OrderSymbol()) + "\",";

   body += "\"timeframe\":\"" +
           CurrentTimeframe() + "\",";

   body += "\"side\":\"" +
           OrderSide() + "\",";

   // --------------------------------------------------------------
   // Position
   // --------------------------------------------------------------

   body += "\"lots\":" +
           Num(OrderLots(), 2) + ",";

   body += "\"open_time\":\"" +
           Esc(Iso(OrderOpenTime())) + "\",";

   body += "\"close_time\":\"" +
           Esc(Iso(OrderCloseTime())) + "\",";

   body += "\"open_price\":" +
           Num(OrderOpenPrice(), Digits) + ",";

   body += "\"close_price\":" +
           Num(OrderClosePrice(), Digits) + ",";

   body += "\"stop_loss\":" +
           Num(OrderStopLoss(), Digits) + ",";

   body += "\"take_profit\":" +
           Num(OrderTakeProfit(), Digits) + ",";

   // --------------------------------------------------------------
   // Financial result
   // --------------------------------------------------------------

   body += "\"pnl\":" +
           Num(pnl, 2) + ",";

   body += "\"profit\":" +
           Num(OrderProfit(), 2) + ",";

   body += "\"commission\":" +
           Num(OrderCommission(), 2) + ",";

   body += "\"swap\":" +
           Num(OrderSwap(), 2) + ",";

   body += "\"cost\":" +
           Num(
              OrderCommission() +
              OrderSwap(),
              2
           ) + ",";

   body += "\"exit_reason\":\"" +
           ExitReason() + "\",";

   // --------------------------------------------------------------
   // R multiple
   // --------------------------------------------------------------

   if(r == EMPTY_VALUE)
   {
      body += "\"r_multiple\":null,";
   }
   else
   {
      body += "\"r_multiple\":" +
              Num(r, 6) + ",";
   }

   // --------------------------------------------------------------
   // Metadata
   // --------------------------------------------------------------

   body += "\"metadata\":{";

   body += "\"account_balance\":" +
           Num(AccountBalance(), 2) + ",";

   body += "\"account_equity\":" +
           Num(AccountEquity(), 2) + ",";

   body += "\"account_free_margin\":" +
           Num(AccountFreeMargin(), 2) + ",";

   body += "\"sbt_operational_capital_usd\":" +
           Num(InpSbtOperationalCapitalUSD, 2) + ",";

   body += "\"terminal_company\":\"" +
           Esc(AccountCompany()) + "\",";

   body += "\"comment\":\"" +
           Esc(OrderComment()) + "\"";

   body += "}";

   // --------------------------------------------------------------
   // Final JSON closure
   // --------------------------------------------------------------

   body += "}";

   return body;
}

//==================================================================
// SEND CLOSED TRADE
//==================================================================

bool PostClosedTrade()
{
   string body = BuildBody();

   char post[];
   char result[];

   // Convert JSON to UTF-8.
   int converted =
      StringToCharArray(
         body,
         post,
         0,
         -1,
         CP_UTF8
      );

   // StringToCharArray includes terminating zero.
   if(converted > 0)
   {
      int size = ArraySize(post);

      if(size > 0 && post[size - 1] == 0)
         ArrayResize(post, size - 1);
   }

   string headers =
      "Content-Type: application/json; charset=utf-8\r\n";

   if(StringLen(InpMT4Token) > 0)
   {
      headers +=
         "X-MT4-Token: " +
         InpMT4Token +
         "\r\n";
   }

   string responseHeaders = "";

   ResetLastError();

   int status =
      WebRequest(
         "POST",
         InpSbtClosedTradeURL,
         headers,
         InpWebRequestTimeoutMs,
         post,
         result,
         responseHeaders
      );

   int errorCode = GetLastError();

   string response = "";

   if(ArraySize(result) > 0)
   {
      response =
         CharArrayToString(
            result,
            0,
            ArraySize(result),
            CP_UTF8
         );
   }

   if(InpVerbose)
   {
      Print(
         BRIDGE_NAME,
         " ticket=",
         IntegerToString(OrderTicket()),
         " HTTP=",
         IntegerToString(status),
         " error=",
         IntegerToString(errorCode),
         " response=",
         response
      );
   }

   if(status >= 200 && status < 300)
      return true;

   return false;
}

//==================================================================
// FIND HIGHEST TICKET
//==================================================================

int FindHighestEligibleTicket()
{
   int total = OrdersHistoryTotal();

   int highestTicket = 0;

   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(!IsEligibleHistoryOrder())
         continue;

      int ticket = OrderTicket();

      if(ticket > highestTicket)
         highestTicket = ticket;
   }

   return highestTicket;
}

//==================================================================
// BASELINE
//==================================================================

void BaselineHistory()
{
   int newestTicket = FindHighestEligibleTicket();

   GlobalVariableSet(
      StateKey(),
      (double)newestTicket
   );

   if(InpVerbose)
   {
      Print(
         BRIDGE_NAME,
         ": history baseline ticket=",
         IntegerToString(newestTicket)
      );
   }
}

//==================================================================
// SORT TICKETS
//==================================================================

void SortTickets(int &tickets[])
{
   int count = ArraySize(tickets);

   for(int a = 0; a < count - 1; a++)
   {
      for(int b = a + 1; b < count; b++)
      {
         if(tickets[b] < tickets[a])
         {
            int temp = tickets[a];

            tickets[a] = tickets[b];
            tickets[b] = temp;
         }
      }
   }
}

//==================================================================
// PROCESS CLOSED TRADES
//==================================================================

void ProcessClosedTrades()
{
   int total = OrdersHistoryTotal();

   if(total <= 0)
      return;

   int maxTicket =
      (int)GlobalVariableGet(StateKey());

   int selectedTickets[];

   ArrayResize(selectedTickets, 0);

   // --------------------------------------------------------------
   // Collect new eligible trades
   // --------------------------------------------------------------

   for(int i = 0; i < total; i++)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(!IsEligibleHistoryOrder())
         continue;

      int ticket = OrderTicket();

      if(ticket <= maxTicket)
         continue;

      int size = ArraySize(selectedTickets);

      ArrayResize(
         selectedTickets,
         size + 1
      );

      selectedTickets[size] = ticket;
   }

   int count = ArraySize(selectedTickets);

   if(count <= 0)
      return;

   SortTickets(selectedTickets);

   // --------------------------------------------------------------
   // Send sequentially
   // --------------------------------------------------------------

   for(int k = 0; k < count; k++)
   {
      int ticket = selectedTickets[k];

      if(!OrderSelect(
            ticket,
            SELECT_BY_TICKET,
            MODE_HISTORY
         ))
      {
         continue;
      }

      if(!IsEligibleHistoryOrder())
         continue;

      bool sent = PostClosedTrade();

      // IMPORTANT:
      // Only advance state after successful HTTP 2xx.
      if(sent)
      {
         maxTicket = ticket;

         GlobalVariableSet(
            StateKey(),
            (double)maxTicket
         );
      }
      else
      {
         // Stop here so the failed trade is retried
         // on the next timer cycle.
         break;
      }
   }
}

//==================================================================
// INIT
//==================================================================

int OnInit()
{
   if(StringLen(InpSbtClosedTradeURL) <= 0)
   {
      Print(
         BRIDGE_NAME,
         ": ERROR - SBT URL is empty."
      );

      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpSbtOperationalCapitalUSD <= 0)
   {
      Print(
         BRIDGE_NAME,
         ": ERROR - operational capital must be > 0."
      );

      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpPollSeconds < 1)
   {
      Print(
         BRIDGE_NAME,
         ": invalid polling interval."
      );

      return INIT_PARAMETERS_INCORRECT;
   }

   // Create timer.
   EventSetTimer(
      MathMax(1, InpPollSeconds)
   );

   // First installation:
   // establish a baseline so old history isn't resent.
   if(!GlobalVariableCheck(StateKey()))
   {
      BaselineHistory();
   }

   Print(
      BRIDGE_NAME,
      " initialized.",
      " AccountMode=",
      AccountMode(),
      " Account=",
      IntegerToString(AccountNumber()),
      " Magic=",
      IntegerToString(InpMagicNumber),
      " SBTCapital=$",
      DoubleToString(
         InpSbtOperationalCapitalUSD,
         2
      ),
      " Execution=MT4_ONLY"
   );

   return INIT_SUCCEEDED;
}

//==================================================================
// DEINIT
//==================================================================

void OnDeinit(const int reason)
{
   EventKillTimer();

   if(InpVerbose)
   {
      Print(
         BRIDGE_NAME,
         " stopped. reason=",
         IntegerToString(reason)
      );
   }
}

//==================================================================
// TIMER
//==================================================================

void OnTimer()
{
   ProcessClosedTrades();
}

//==================================================================
// TICK
//==================================================================

void OnTick()
{
   // Intentionally empty.
   //
   // This bridge NEVER opens, closes, modifies,
   // or deletes MT4 orders.
   //
   // Trading execution belongs to the Turtle EA.
}

//+------------------------------------------------------------------+