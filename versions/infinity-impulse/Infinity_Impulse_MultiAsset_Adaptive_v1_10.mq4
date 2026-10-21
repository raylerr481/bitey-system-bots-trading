//+------------------------------------------------------------------+
//| Infinity_Impulse_MultiAsset_Adaptive_v1.mq4                      |
//| Multi-symbol MT4 EA: adaptive ATR stops and spread-aware sizing   |
//| Original XAUUSD source preserved; this is a separate candidate.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "MarketWatch multi-asset impulse EA with ATR/spread-adaptive risk sizing"

input double InpRiskPercent       = 0.50;   // Risk budget per trade (% of balance)
input int    InpMaxPositions      = 2;      // Global maximum open positions for this EA
input int    InpMagicNumber       = 202651;
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input int    InpEMAPeriod         = 50;
input int    InpBBPeriod          = 20;
input double InpBBDeviation       = 2.0;
input int    InpATRPeriod         = 14;
input double InpSL_ATR_Multiplier = 1.50;
input double InpTP_ATR_Multiplier = 3.00;
input double InpSpreadSLFactor    = 1.50;   // Widen stop to accommodate spread
input double InpSpreadTPFactor    = 4.00;   // Target remains proportional to spread
input int    InpSlippage          = 10;
input bool   InpOnlyMarketWatch   = true;   // true = all symbols shown in Market Watch
input bool   InpAllowBuy          = true;
input bool   InpAllowSell         = true;

string   g_symbols[];
datetime g_lastBar[];
datetime g_lastAttemptBar[];

int OnInit()
{
   ArrayResize(g_symbols, 0);
   ArrayResize(g_lastBar, 0);
   ArrayResize(g_lastAttemptBar, 0);
   Print("Infinity_Impulse_MultiAsset_Adaptive_v1 initialized. Symbols are discovered from Market Watch; no fixed XAUUSD symbol.");
   return(INIT_SUCCEEDED);
}

void OnTick()
{
   RefreshRates();
   int total = SymbolsTotal(InpOnlyMarketWatch);
   if(total <= 0) return;

   for(int i=0; i<total; i++)
   {
      string symbol = SymbolName(i, InpOnlyMarketWatch);
      if(symbol == "") continue;
      if(!SymbolSelect(symbol, true)) continue;
      ProcessSymbol(symbol);
   }
}

void ProcessSymbol(string symbol)
{
   int idx = EnsureSymbol(symbol);
   if(idx < 0) return;

   datetime barTime = iTime(symbol, InpTimeframe, 0);
   if(barTime <= 0) return;
   if(g_lastBar[idx] == barTime) return;
   g_lastBar[idx] = barTime;

   if(iBars(symbol, InpTimeframe) < MathMax(InpEMAPeriod, MathMax(InpBBPeriod, InpATRPeriod)) + 5)
   {
      Print("SYMBOL_WAIT | symbol=",symbol," reason=INSUFFICIENT_HISTORY");
      return;
   }

   if(CountOpenPositions() >= InpMaxPositions) return;
   if(HasOpenPosition(symbol)) return;
   if(g_lastAttemptBar[idx] == barTime) return;

   double point = MarketInfo(symbol, MODE_POINT);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   double tickSizePoints = MarketInfo(symbol, MODE_TICKSIZE);
   double tickSize = tickSizePoints * point; // MODE_TICKSIZE is reported in points by MT4
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   double atr = iATR(symbol, InpTimeframe, InpATRPeriod, 1);
   if(point <= 0 || ask <= 0 || bid <= 0 || tickSize <= 0 || tickValue <= 0 || atr <= 0)
   {
      Print("SYMBOL_REJECT | symbol=",symbol," reason=INVALID_MARKET_METADATA");
      return;
   }

   double ema = iMA(symbol, InpTimeframe, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, 1);
   double upper = iBands(symbol, InpTimeframe, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_UPPER, 1);
   double lower = iBands(symbol, InpTimeframe, InpBBPeriod, InpBBDeviation, 0, PRICE_CLOSE, MODE_LOWER, 1);
   double close1 = iClose(symbol, InpTimeframe, 1);
   double open1 = iOpen(symbol, InpTimeframe, 1);
   if(ema <= 0 || upper <= 0 || lower <= 0 || close1 <= 0 || open1 <= 0) return;

   bool buySignal = InpAllowBuy && close1 > upper && close1 > ema && close1 > open1;
   bool sellSignal = InpAllowSell && close1 < lower && close1 < ema && close1 < open1;
   if(!buySignal && !sellSignal) return;

   double spreadPrice = MathMax(0, ask-bid);
   // No fixed max-spread rejection. SL/TP adapt to current spread and ATR.
   double slDistance = MathMax(atr * InpSL_ATR_Multiplier, spreadPrice * InpSpreadSLFactor);
   double tpDistance = MathMax(atr * InpTP_ATR_Multiplier, spreadPrice * InpSpreadTPFactor);

   int stopLevelPoints = (int)MarketInfo(symbol, MODE_STOPLEVEL);
   double minStopDistance = (stopLevelPoints + 2) * point;
   slDistance = MathMax(slDistance, minStopDistance);
   tpDistance = MathMax(tpDistance, minStopDistance);

   // Size against the full stop distance plus current spread, not a fixed XAUUSD point count.
   double riskDistance = slDistance + spreadPrice;
   double lossPerLot = (riskDistance / tickSize) * tickValue;
   double riskMoney = AccountBalance() * InpRiskPercent / 100.0;
   if(lossPerLot <= 0 || riskMoney <= 0) return;

   double rawLots = riskMoney / lossPerLot;
   double minLot = MarketInfo(symbol, MODE_MINLOT);
   double maxLot = MarketInfo(symbol, MODE_MAXLOT);
   double lotStep = MarketInfo(symbol, MODE_LOTSTEP);
   if(minLot <= 0 || maxLot < minLot || lotStep <= 0) return;

   // Never round upward to minimum lot if that would exceed the risk budget.
   double lots = MathFloor(rawLots / lotStep + 1e-8) * lotStep;
   int lotDigits = LotDigits(lotStep);
   lots = NormalizeDouble(lots, lotDigits);
   if(lots < minLot)
   {
      Print("SYMBOL_REJECT | symbol=",symbol," reason=MINIMUM_LOT_EXCEEDS_RISK_BUDGET",
            " riskBudget=",DoubleToString(riskMoney,2),
            " estimatedMinLotRisk=",DoubleToString(lossPerLot*minLot,2),
            " spreadPrice=",DoubleToString(spreadPrice,digits));
      return;
   }
   if(lots > maxLot) lots = maxLot;

   double marginCheck = AccountFreeMarginCheck(symbol, buySignal ? OP_BUY : OP_SELL, lots);
   if(marginCheck <= 0)
   {
      Print("SYMBOL_REJECT | symbol=",symbol," reason=INSUFFICIENT_FREE_MARGIN");
      return;
   }

   int orderType = buySignal ? OP_BUY : OP_SELL;
   double price = buySignal ? ask : bid;
   double sl = buySignal ? price-slDistance : price+slDistance;
   double tp = buySignal ? price+tpDistance : price-tpDistance;
   price = NormalizeDouble(price, digits);
   sl = NormalizeDouble(sl, digits);
   tp = NormalizeDouble(tp, digits);

   // Prevent duplicate attempts on the same closed-bar signal, even after broker rejection.
   g_lastAttemptBar[idx] = barTime;
   ResetLastError();
   int ticket = OrderSend(symbol, orderType, lots, price, InpSlippage, sl, tp,
                          "Infinity_Impulse_MultiAsset_Adaptive_v1",
                          InpMagicNumber, 0, buySignal ? clrDodgerBlue : clrTomato);
   if(ticket > 0)
   {
      Print("ORDER_ACCEPTED | symbol=",symbol," ticket=",ticket,
            " side=",buySignal ? "BUY" : "SELL",
            " lots=",DoubleToString(lots,lotDigits),
            " riskBudget=",DoubleToString(riskMoney,2),
            " spreadPrice=",DoubleToString(spreadPrice,digits),
            " slDistance=",DoubleToString(slDistance,digits),
            " tpDistance=",DoubleToString(tpDistance,digits));
   }
   else
   {
      int err = GetLastError();
      Print("ORDER_REJECTED | symbol=",symbol," error=",err,
            " lots=",DoubleToString(lots,lotDigits),
            " spreadPrice=",DoubleToString(spreadPrice,digits),
            " note=No fixed spread ceiling; broker execution rules may still reject order");
   }
}

int EnsureSymbol(string symbol)
{
   int n = ArraySize(g_symbols);
   for(int i=0; i<n; i++) if(g_symbols[i] == symbol) return i;
   if(ArrayResize(g_symbols, n+1) != n+1) return -1;
   if(ArrayResize(g_lastBar, n+1) != n+1) return -1;
   if(ArrayResize(g_lastAttemptBar, n+1) != n+1) return -1;
   g_symbols[n] = symbol;
   g_lastBar[n] = 0;
   g_lastAttemptBar[n] = 0;
   return n;
}

int CountOpenPositions()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

bool HasOpenPosition(string symbol)
{
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagicNumber || OrderSymbol() != symbol) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) return true;
   }
   return false;
}

int LotDigits(double step)
{
   for(int d=0; d<=8; d++)
      if(MathAbs(step - NormalizeDouble(step,d)) < 1e-8) return d;
   return 2;
}
//+------------------------------------------------------------------+
