
#property strict
#property version   "1.25"
#property description "Bitey SBT Multi-Model Engine - USD500 logical allocation"

enum EngineMode
{
   OBSERVE_ONLY = 0,
   DEMO_EXECUTION = 1
};

input EngineMode InpMode = OBSERVE_ONLY;
input int      InpMagic = 2036125;
input double   InpOperatingCapitalUSD = 500.0;
input double   InpRiskPerTradeUSD = 1.25;
input double   InpHardRiskCapUSD = 2.00;
input double   InpDailyLossLimitUSD = 10.00;
input int      InpMaxTradesPerDay = 3;
input int      InpMaxOpenTrades = 1;

input int      InpMaxSpreadPoints = 35;
input int      InpSlippagePoints = 10;
input int      InpATRPeriod = 14;
input double   InpStopATR = 1.30;
input double   InpTargetATR = 2.60;
input int      InpMaxHoldBars = 6;

input int      InpFastEMA = 8;
input int      InpSlowEMA = 21;
input int      InpTrendEMA = 200;
input int      InpRSIPeriod = 14;
input int      InpADXPeriod = 14;
input double   InpTrendADXMin = 18.0;
input int      InpDonchianPeriod = 20;

input int      InpValidationBars = 240;
input int      InpForwardBars = 6;
input int      InpMinEvidenceSamples = 12;
input double   InpMinEvidenceWinRate = 0.42;
input double   InpMinAverageR = 0.02;
input int      InpMinVotes = 2;

input bool     InpUseSessionFilter = true;
input int      InpSessionStartHour = 7;
input int      InpSessionEndHour = 20;
input bool     InpExportCSV = true;

datetime g_lastBar = 0;

struct ModelEvidence
{
   int samples;
   int wins;
   int losses;
   double netR;
   double winRate;
};

ModelEvidence g_buy[4];
ModelEvidence g_sell[4];

string ModelName(int i)
{
   if(i == 0) return "TREND";
   if(i == 1) return "MOMENTUM";
   if(i == 2) return "DONCHIAN";
   return "MEANREV";
}

double ClampValue(double x, double lo, double hi)
{
   if(x < lo) return lo;
   if(x > hi) return hi;
   return x;
}

datetime StartOfDay(datetime t)
{
   return StrToTime(TimeToString(t, TIME_DATE));
}

bool NewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);
   if(t <= 0) return false;

   if(t != g_lastBar)
   {
      g_lastBar = t;
      return true;
   }
   return false;
}

double GetATR(int shift)
{
   return iATR(Symbol(), Period(), InpATRPeriod, shift);
}

// MODE_TICKSIZE is expressed in points in MQL4.
// Convert it to price units before calculating monetary risk.
double MoneyPerPriceUnitPerLot()
{
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSizePoints = MarketInfo(Symbol(), MODE_TICKSIZE);

   if(tickValue <= 0 || tickSizePoints <= 0 || Point <= 0)
      return 0;

   double tickSizePrice = tickSizePoints * Point;
   if(tickSizePrice <= 0) return 0;

   return tickValue / tickSizePrice;
}

double RiskMoney(double stopDistance, double lots)
{
   double value = MoneyPerPriceUnitPerLot();
   if(value <= 0 || stopDistance <= 0 || lots <= 0)
      return 1.0e9;

   return stopDistance * value * lots;
}

double NormalizeLotsDown(double lots)
{
   double minLot = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot = MarketInfo(Symbol(), MODE_MAXLOT);
   double step = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(minLot <= 0 || maxLot <= 0 || step <= 0)
      return 0;

   lots = MathMin(lots, maxLot);
   lots = MathFloor((lots + 1e-10) / step) * step;
   lots = NormalizeDouble(lots, 2);

   // Never round up to the broker minimum if that would exceed risk.
   if(lots < minLot) return 0;

   return lots;
}

bool InSession()
{
   if(!InpUseSessionFilter) return true;

   int h = TimeHour(TimeCurrent());

   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   if(InpSessionStartHour < InpSessionEndHour)
      return (h >= InpSessionStartHour &&
              h < InpSessionEndHour);

   return (h >= InpSessionStartHour ||
           h < InpSessionEndHour);
}

int CountOpenTrades()
{
   int count = 0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol() ||
         OrderMagicNumber() != InpMagic)
         continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         count++;
   }

   return count;
}

int TradesOpenedToday()
{
   int count = 0;
   datetime dayStart = StartOfDay(TimeCurrent());

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() == Symbol() &&
         OrderMagicNumber() == InpMagic &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) &&
         OrderOpenTime() >= dayStart)
         count++;
   }

   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() == Symbol() &&
         OrderMagicNumber() == InpMagic &&
         (OrderType() == OP_BUY || OrderType() == OP_SELL) &&
         OrderOpenTime() >= dayStart)
         count++;
   }

   return count;
}

double PnLToday()
{
   double pnl = 0;
   datetime dayStart = StartOfDay(TimeCurrent());

   // Include floating P/L for this EA's open positions.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol() ||
         OrderMagicNumber() != InpMagic)
         continue;

      if(OrderType() == OP_BUY || OrderType() == OP_SELL)
         pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   // Include trades closed today.
   for(int j = OrdersHistoryTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_HISTORY))
         continue;

      if(OrderSymbol() != Symbol() ||
         OrderMagicNumber() != InpMagic)
         continue;

      if((OrderType() == OP_BUY || OrderType() == OP_SELL) &&
         OrderCloseTime() >= dayStart)
         pnl += OrderProfit() + OrderSwap() + OrderCommission();
   }

   return pnl;
}

// Output signals: +1 BUY, -1 SELL, 0 no signal.
bool GetModelSignals(int shift, int &trend, int &momentum,
                     int &breakout, int &meanrev)
{
   trend = 0;
   momentum = 0;
   breakout = 0;
   meanrev = 0;

   int requiredBars = MathMax(InpTrendEMA, InpDonchianPeriod)
                      + InpForwardBars + 10;

   if(iBars(Symbol(), Period()) < requiredBars)
      return false;

   double close = iClose(Symbol(), Period(), shift);
   double emaFast = iMA(Symbol(), Period(), InpFastEMA,
                        0, MODE_EMA, PRICE_CLOSE, shift);
   double emaSlow = iMA(Symbol(), Period(), InpSlowEMA,
                        0, MODE_EMA, PRICE_CLOSE, shift);
   double emaTrend = iMA(Symbol(), Period(), InpTrendEMA,
                         0, MODE_EMA, PRICE_CLOSE, shift);
   double rsi = iRSI(Symbol(), Period(), InpRSIPeriod,
                     PRICE_CLOSE, shift);
   double adx = iADX(Symbol(), Period(), InpADXPeriod,
                     PRICE_CLOSE, MODE_MAIN, shift);
   double plusDI = iADX(Symbol(), Period(), InpADXPeriod,
                        PRICE_CLOSE, MODE_PLUSDI, shift);
   double minusDI = iADX(Symbol(), Period(), InpADXPeriod,
                         PRICE_CLOSE, MODE_MINUSDI, shift);
   double atr = GetATR(shift);

   if(atr <= 0) return false;

   // Model 1: trend following.
   if(close > emaTrend && emaFast > emaSlow &&
      adx >= InpTrendADXMin && plusDI > minusDI)
      trend = 1;

   if(close < emaTrend && emaFast < emaSlow &&
      adx >= InpTrendADXMin && minusDI > plusDI)
      trend = -1;

   // Model 2: short-term momentum, normalized by ATR.
   double oldClose = iClose(Symbol(), Period(), shift + 3);
   double normalizedMove = (close - oldClose) / atr;

   if(normalizedMove >= 0.65 && close > emaSlow)
      momentum = 1;

   if(normalizedMove <= -0.65 && close < emaSlow)
      momentum = -1;

   // Model 3: Donchian breakout, using only earlier bars.
   int hi = iHighest(Symbol(), Period(), MODE_HIGH,
                     InpDonchianPeriod, shift + 1);
   int lo = iLowest(Symbol(), Period(), MODE_LOW,
                    InpDonchianPeriod, shift + 1);

   if(hi >= 0 && close > iHigh(Symbol(), Period(), hi))
      breakout = 1;

   if(lo >= 0 && close < iLow(Symbol(), Period(), lo))
      breakout = -1;

   // Model 4: mean reversion only in a weak-trend regime.
   if(adx < InpTrendADXMin && rsi <= 30)
      meanrev = 1;

   if(adx < InpTrendADXMin && rsi >= 70)
      meanrev = -1;

   return true;
}

// Historical outcome in R units. Same-bar SL/TP conflicts count as a loss.
// Outcomes without a stop/target hit are marked to the close at the horizon.
double HistoricalOutcomeR(int direction, int shift)
{
   double atr = GetATR(shift);
   if(atr <= 0) return 0;

   double entry = iClose(Symbol(), Period(), shift);
   double stopDist = atr * InpStopATR;
   double targetDist = atr * InpTargetATR;

   double sl = (direction > 0 ? entry - stopDist
                              : entry + stopDist);
   double tp = (direction > 0 ? entry + targetDist
                              : entry - targetDist);

   int endShift = shift - InpForwardBars;
   if(endShift < 1) return 0;

   for(int k = shift - 1; k >= endShift; k--)
   {
      double high = iHigh(Symbol(), Period(), k);
      double low = iLow(Symbol(), Period(), k);

      bool hitSL = (direction > 0 ? low <= sl : high >= sl);
      bool hitTP = (direction > 0 ? high >= tp : low <= tp);

      if(hitSL) return -1.0;
      if(hitTP) return InpTargetATR / InpStopATR;
   }

   double finalClose = iClose(Symbol(), Period(), endShift);
   double rawR = (direction > 0 ? finalClose - entry
                                : entry - finalClose) / stopDist;

   return ClampValue(rawR, -1.0, InpTargetATR / InpStopATR);
}

void ResetEvidence()
{
   for(int i = 0; i < 4; i++)
   {
      g_buy[i].samples = 0;
      g_buy[i].wins = 0;
      g_buy[i].losses = 0;
      g_buy[i].netR = 0;
      g_buy[i].winRate = 0;

      g_sell[i].samples = 0;
      g_sell[i].wins = 0;
      g_sell[i].losses = 0;
      g_sell[i].netR = 0;
      g_sell[i].winRate = 0;
   }
}

void AddOutcome(ModelEvidence &e, double resultR)
{
   e.samples++;
   e.netR += resultR;

   if(resultR > 0) e.wins++;
   else if(resultR < 0) e.losses++;
}

void BuildEvidence()
{
   ResetEvidence();

   int bars = iBars(Symbol(), Period());
   int maxShift = MathMin(InpValidationBars,
                          bars - InpForwardBars - 2);

   // The oldest evaluated signal must have enough future bars available.
   for(int shift = maxShift; shift > InpForwardBars + 2; shift--)
   {
      int t, m, b, r;

      if(!GetModelSignals(shift, t, m, b, r))
         continue;

      int sig[4];
      sig[0] = t;
      sig[1] = m;
      sig[2] = b;
      sig[3] = r;

      for(int model = 0; model < 4; model++)
      {
         if(sig[model] == 1)
         {
            double outcomeBuy = HistoricalOutcomeR(1, shift);
            AddOutcome(g_buy[model], outcomeBuy);
         }
         else if(sig[model] == -1)
         {
            double outcomeSell = HistoricalOutcomeR(-1, shift);
            AddOutcome(g_sell[model], outcomeSell);
         }
      }
   }

   for(int j = 0; j < 4; j++)
   {
      if(g_buy[j].samples > 0)
         g_buy[j].winRate = (double)g_buy[j].wins /
                            g_buy[j].samples;

      if(g_sell[j].samples > 0)
         g_sell[j].winRate = (double)g_sell[j].wins /
                             g_sell[j].samples;
   }
}

bool EvidencePass(ModelEvidence &e)
{
   if(e.samples < InpMinEvidenceSamples)
      return false;

   double averageR = e.netR / e.samples;

   return (e.winRate >= InpMinEvidenceWinRate &&
           averageR > InpMinAverageR);
}

void ExportEvidence()
{
   if(!InpExportCSV) return;

   int handle = FileOpen("Bitey_SBT_Evidence_v1_25.csv",
                         FILE_CSV | FILE_READ | FILE_WRITE |
                         FILE_SHARE_READ, ';');

   if(handle == INVALID_HANDLE)
   {
      Print("CSV unavailable. Error=", GetLastError());
      return;
   }

   if(FileSize(handle) == 0)
   {
      FileWrite(handle, "time", "symbol", "period", "model",
                "side", "samples", "wins", "losses",
                "win_rate", "net_R", "average_R");
   }

   FileSeek(handle, 0, SEEK_END);

   for(int i = 0; i < 4; i++)
   {
      double avgBuy = (g_buy[i].samples > 0 ?
                       g_buy[i].netR / g_buy[i].samples : 0);
      double avgSell = (g_sell[i].samples > 0 ?
                        g_sell[i].netR / g_sell[i].samples : 0);

      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE |
                TIME_SECONDS), Symbol(), Period(), ModelName(i),
                "BUY", g_buy[i].samples, g_buy[i].wins,
                g_buy[i].losses, DoubleToString(g_buy[i].winRate, 4),
                DoubleToString(g_buy[i].netR, 4),
                DoubleToString(avgBuy, 4));

      FileWrite(handle, TimeToString(TimeCurrent(), TIME_DATE |
                TIME_SECONDS), Symbol(), Period(), ModelName(i),
                "SELL", g_sell[i].samples, g_sell[i].wins,
                g_sell[i].losses, DoubleToString(g_sell[i].winRate, 4),
                DoubleToString(g_sell[i].netR, 4),
                DoubleToString(avgSell, 4));
   }

   FileClose(handle);
}

double AllowedRiskUSD()
{
   if(InpOperatingCapitalUSD <= 0) return 0;

   return MathMin(MathMin(InpRiskPerTradeUSD,
                          InpHardRiskCapUSD),
                  InpOperatingCapitalUSD * 0.004);
}

double CalculateLots(int command, double stopDistance)
{
   double allowedRisk = AllowedRiskUSD();
   double valuePerPrice = MoneyPerPriceUnitPerLot();

   if(allowedRisk <= 0 || stopDistance <= 0 ||
      valuePerPrice <= 0)
      return 0;

   double rawLots = allowedRisk /
                    (stopDistance * valuePerPrice);
   double lots = NormalizeLotsDown(rawLots);

   if(lots <= 0) return 0;

   // Refuse the order if broker lot granularity would exceed risk.
   if(RiskMoney(stopDistance, lots) > allowedRisk + 0.01)
      return 0;

   ResetLastError();
   double freeMarginAfter = AccountFreeMarginCheck(Symbol(),
                                                    command, lots);
   int marginError = GetLastError();

   if(freeMarginAfter <= 0 || marginError == 134)
      return 0;

   return lots;
}

bool RiskGate()
{
   if(InpMode != DEMO_EXECUTION)
   {
      Print("OBSERVE_ONLY: no order sent.");
      return false;
   }

   if(!IsTradeAllowed())
   {
      Print("RISK_GATE: terminal or EA trading disabled.");
      return false;
   }

   if(IsTradeContextBusy())
   {
      Print("RISK_GATE: trade context busy.");
      return false;
   }

   if(MarketInfo(Symbol(), MODE_TRADEALLOWED) == 0)
   {
      Print("RISK_GATE: trading disabled for symbol.");
      return false;
   }

   if(MarketInfo(Symbol(), MODE_SPREAD) > InpMaxSpreadPoints)
   {
      Print("RISK_GATE: spread too high.");
      return false;
   }

   if(!InSession())
   {
      Print("RISK_GATE: outside configured session.");
      return false;
   }

   if(CountOpenTrades() >= InpMaxOpenTrades)
   {
      Print("RISK_GATE: maximum open trades reached.");
      return false;
   }

   if(TradesOpenedToday() >= InpMaxTradesPerDay)
   {
      Print("RISK_GATE: daily trade limit reached.");
      return false;
   }

   double dailyLimit = MathMin(InpDailyLossLimitUSD,
                               InpOperatingCapitalUSD * 0.02);

   if(PnLToday() <= -dailyLimit)
   {
      Print("RISK_GATE: daily loss limit reached. PnL=",
            DoubleToString(PnLToday(), 2));
      return false;
   }

   return true;
}

void ManageOpenTrades()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES))
         continue;

      if(OrderSymbol() != Symbol() ||
         OrderMagicNumber() != InpMagic)
         continue;

      if(OrderType() != OP_BUY && OrderType() != OP_SELL)
         continue;

      int barsHeld = iBarShift(Symbol(), Period(),
                               OrderOpenTime(), false);

      if(barsHeld < 0 || barsHeld < InpMaxHoldBars)
         continue;

      RefreshRates();

      double closePrice = (OrderType() == OP_BUY ? Bid : Ask);
      ResetLastError();

      bool closed = OrderClose(OrderTicket(), OrderLots(),
                               closePrice, InpSlippagePoints,
                               clrNONE);

      if(!closed)
         Print("TIME_EXIT failed. Ticket=", OrderTicket(),
               " error=", GetLastError());
      else
         Print("TIME_EXIT completed. Ticket=", OrderTicket());
   }
}

void PlaceTrade(int direction)
{
   if(!RiskGate()) return;

   double atr = GetATR(1);
   if(atr <= 0)
   {
      Print("RISK_GATE: ATR unavailable.");
      return;
   }

   double stopDistance = atr * InpStopATR;
   double targetDistance = atr * InpTargetATR;
   int command = (direction > 0 ? OP_BUY : OP_SELL);

   double lots = CalculateLots(command, stopDistance);
   if(lots <= 0)
   {
      Print("RISK_GATE: lot size below safe broker minimum or margin check failed.");
      return;
   }

   int stopLevel = (int)MarketInfo(Symbol(), MODE_STOPLEVEL);
   int freezeLevel = (int)MarketInfo(Symbol(), MODE_FREEZELEVEL);
   int requiredLevel = MathMax(stopLevel, freezeLevel) + 2;

   if(stopDistance / Point < requiredLevel ||
      targetDistance / Point < requiredLevel)
   {
      Print("RISK_GATE: stop/target too close for broker restrictions.");
      return;
   }

   RefreshRates();

   double price = (command == OP_BUY ? Ask : Bid);
   double sl = (command == OP_BUY ?
                price - stopDistance : price + stopDistance);
   double tp = (command == OP_BUY ?
                price + targetDistance : price - targetDistance);

   price = NormalizeDouble(price, Digits);
   sl = NormalizeDouble(sl, Digits);
   tp = NormalizeDouble(tp, Digits);

   double risk = RiskMoney(stopDistance, lots);
   if(risk > AllowedRiskUSD() + 0.01)
   {
      Print("RISK_GATE: risk exceeds configured allocation.");
      return;
   }

   string comment = (direction > 0 ?
                     "Bitey125 BUY" : "Bitey125 SELL");

   ResetLastError();

   int ticket = OrderSend(Symbol(), command, lots, price,
                          InpSlippagePoints, sl, tp,
                          comment, InpMagic, 0, clrNONE);

   if(ticket < 0)
   {
      Print("OrderSend failed. Error=", GetLastError(),
            " lots=", DoubleToString(lots, 2));
      return;
   }

   Print("ORDER OPENED. Ticket=", ticket,
         " side=", (direction > 0 ? "BUY" : "SELL"),
         " lots=", DoubleToString(lots, 2),
         " estimated stop risk USD=", DoubleToString(risk, 2),
         " allocation USD=", DoubleToString(InpOperatingCapitalUSD, 2));
}

void EvaluateEngine()
{
   BuildEvidence();
   ExportEvidence();

   int trend, momentum, breakout, meanrev;

   if(!GetModelSignals(1, trend, momentum, breakout, meanrev))
   {
      Print("DATA_GATE: insufficient history or indicator data.");
      return;
   }

   int signals[4];
   signals[0] = trend;
   signals[1] = momentum;
   signals[2] = breakout;
   signals[3] = meanrev;

   int buyVotes = 0;
   int sellVotes = 0;
   string summary = "";

   for(int i = 0; i < 4; i++)
   {
      if(signals[i] == 1 && EvidencePass(g_buy[i]))
         buyVotes++;

      if(signals[i] == -1 && EvidencePass(g_sell[i]))
         sellVotes++;

      double buyAvg = (g_buy[i].samples > 0 ?
                       g_buy[i].netR / g_buy[i].samples : 0);
      double sellAvg = (g_sell[i].samples > 0 ?
                        g_sell[i].netR / g_sell[i].samples : 0);

      summary += ModelName(i) +
         " signal=" + IntegerToString(signals[i]) +
         " BUY n=" + IntegerToString(g_buy[i].samples) +
         " wr=" + DoubleToString(g_buy[i].winRate, 2) +
         " avgR=" + DoubleToString(buyAvg, 2) +
         " SELL n=" + IntegerToString(g_sell[i].samples) +
         " wr=" + DoubleToString(g_sell[i].winRate, 2) +
         " avgR=" + DoubleToString(sellAvg, 2) + " | ";
   }

   Print("BITEY SBT v1.25 | ", Symbol(),
         " TF=", Period(),
         " BUY votes=", buyVotes,
         " SELL votes=", sellVotes,
         " | ", summary);

   if(buyVotes >= InpMinVotes && sellVotes == 0)
      PlaceTrade(1);
   else if(sellVotes >= InpMinVotes && buyVotes == 0)
      PlaceTrade(-1);
   else
      Print("DECISION=WAIT: insufficient evidence or conflicting directions.");
}

int OnInit()
{
   if(InpOperatingCapitalUSD <= 0 ||
      InpRiskPerTradeUSD <= 0 ||
      InpHardRiskCapUSD <= 0 ||
      InpStopATR <= 0 ||
      InpTargetATR <= 0 ||
      InpMaxOpenTrades < 1 ||
      InpMaxTradesPerDay < 1 ||
      InpMinVotes < 1 || InpMinVotes > 4 ||
      InpForwardBars < 1 ||
      InpValidationBars <= InpForwardBars)
   {
      Print("INIT FAILED: invalid risk or validation parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   g_lastBar = 0;

   Print("Bitey SBT Multi-Model Engine v1.25 initialized.",
         " Mode=", (InpMode == OBSERVE_ONLY ?
                    "OBSERVE_ONLY" : "DEMO_EXECUTION"),
         " AllocationUSD=", DoubleToString(InpOperatingCapitalUSD, 2),
         " MaxRiskUSD=", DoubleToString(AllowedRiskUSD(), 2),
         " Default mode is observe-only.");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   Print("Bitey SBT v1.25 stopped. Reason=", reason);
}

void OnTick()
{
   ManageOpenTrades();

   if(NewBar())
      EvaluateEngine();
}