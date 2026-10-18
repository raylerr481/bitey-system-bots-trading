#property strict
#property version   "1.27"
#property description "AI Trading Bot v1.27 - Rebuilt Balanced Backtest"

// ============================================================
// AI Trading Bot v1.27
// Rebuilt execution engine for MT4 Strategy Tester.
// Purpose: balanced BUY/SELL signal generation, conservative risk,
// detailed diagnostics, and reproducible backtesting.
// ============================================================

input bool   InpAllowBuy             = true;
input bool   InpAllowSell            = true;
input double InpRiskPct              = 0.25;
input int    InpMaxTrades            = 1;
input double InpMaxLots              = 2.0;

input int    InpMaxSpreadPoints      = 30;
input double InpMaxSpreadATRRatio    = 0.20;
input int    InpATRPeriod             = 14;
input double InpMinATRPoints          = 20.0;
input int    InpADXPeriod             = 14;
input double InpADXMin                = 20.0;

input int    InpRSIPeriod             = 14;
input double InpRSIBuyMin             = 50.0;
input double InpRSIBuyMax             = 68.0;
input double InpRSISellMin            = 32.0;
input double InpRSISellMax            = 50.0;

input int    InpFastEMA               = 8;
input int    InpSlowEMA               = 21;
input int    InpMacroEMA              = 200;
input bool   InpUseMacroSlope         = true;
input bool   InpUseHTFTrendFilter     = false;
input ENUM_TIMEFRAMES InpHTF          = PERIOD_H4;

input int    InpBuyMinScore           = 5;
input int    InpSellMinScore          = 5;

input double InpSLMult                = 1.30;
input double InpTPMult                = 2.60;
input double InpBEStartMult           = 1.10;
input double InpBELockMult            = 0.05;
input double InpTrailStartMult        = 1.60;
input double InpTrailDistMult         = 0.90;

input int    InpStartHour             = 7;
input int    InpEndHour               = 20;
input int    InpFridayCloseHour       = 21;
input int    InpCooldownBars          = 3;
input int    InpMagicNumber            = 8883170;
input int    InpSlippage               = 5;
input bool   InpVerboseLog             = true;

// -------------------- diagnostics -----------------------------
long gBars = 0;
long gMarketBlocks = 0;
long gSpreadBlocks = 0;
long gATRBlocks = 0;
long gATRRatioBlocks = 0;
long gSessionBlocks = 0;
long gCooldownBlocks = 0;
long gScoreWaits = 0;
long gBuyPotential = 0;
long gSellPotential = 0;
long gBuyApproved = 0;
long gSellApproved = 0;
long gBuyOrders = 0;
long gSellOrders = 0;
long gOrderErrors = 0;
long gBuyScoreSum = 0;
long gSellScoreSum = 0;
long gBothPass = 0;

datetime gLastBar = 0;
datetime gLastTradeBar = 0;

// ============================================================
// Helpers
// ============================================================

void Log(string s)
{
   if(InpVerboseLog) Print(s);
}

bool IsNewBar()
{
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0) return false;
   if(t != gLastBar)
   {
      gLastBar = t;
      return true;
   }
   return false;
}

int BarsSinceTrade()
{
   if(gLastTradeBar == 0) return 999999;
   int shift = iBarShift(_Symbol, _Period, gLastTradeBar, false);
   if(shift < 0) return 999999;
   return shift;
}

int OpenTradesCount()
{
   int count = 0;
   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol) continue;
      if(OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

bool SessionOK()
{
   int h = TimeHour(TimeCurrent());
   int dow = TimeDayOfWeek(TimeCurrent());

   if(dow == 0 || dow == 6) return false;
   if(dow == 5 && h >= InpFridayCloseHour) return false;

   if(InpStartHour < InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);

   return (h >= InpStartHour || h < InpEndHour);
}

bool CooldownOK()
{
   return (BarsSinceTrade() >= InpCooldownBars);
}

double NormalizeLots(double lots)
{
   double minLot = MarketInfo(_Symbol, MODE_MINLOT);
   double maxLot = MarketInfo(_Symbol, MODE_MAXLOT);
   double step   = MarketInfo(_Symbol, MODE_LOTSTEP);

   if(step <= 0) step = 0.01;
   if(maxLot <= 0) maxLot = InpMaxLots;
   if(minLot <= 0) minLot = step;

   lots = MathMin(lots, InpMaxLots);
   lots = MathMin(lots, maxLot);
   lots = MathFloor(lots / step) * step;
   lots = MathMax(lots, minLot);

   int digits = 2;
   if(step >= 1.0) digits = 0;
   else if(step >= 0.1) digits = 1;
   else if(step >= 0.01) digits = 2;
   else digits = 3;

   return NormalizeDouble(lots, digits);
}

double LotsByRisk(double slDistance)
{
   if(slDistance <= 0) return 0;

   double riskMoney = AccountBalance() * InpRiskPct / 100.0;
   double tickValue = MarketInfo(_Symbol, MODE_TICKVALUE);
   double tickSize  = MarketInfo(_Symbol, MODE_TICKSIZE);

   if(riskMoney <= 0 || tickValue <= 0 || tickSize <= 0)
      return NormalizeLots(MarketInfo(_Symbol, MODE_MINLOT));

   double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return NormalizeLots(MarketInfo(_Symbol, MODE_MINLOT));

   return NormalizeLots(riskMoney / lossPerLot);
}

bool StopDistanceOK(double price, double stop)
{
   double minStop = MarketInfo(_Symbol, MODE_STOPLEVEL) * Point;
   if(minStop <= 0) return true;
   return (MathAbs(price - stop) >= minStop);
}

bool HTFTrendOK(bool buy)
{
   if(!InpUseHTFTrendFilter) return true;

   double h1 = iMA(_Symbol, InpHTF, InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double h2 = iMA(_Symbol, InpHTF, InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double hc = iClose(_Symbol, InpHTF, 1);

   if(h1 <= 0 || h2 <= 0 || hc <= 0) return false;

   if(buy)  return (hc > h1 && h1 >= h2);
   return (hc < h1 && h1 <= h2);
}

// ============================================================
// Signal engine
// Score components are intentionally symmetric.
// ============================================================

int BuyScore(double c1, double fast1, double slow1, double macro1,
             double fast2, double slow2, double macro2,
             double adx, double rsi, double atr)
{
   int s = 0;

   if(c1 > macro1) s++;                                      // macro location
   if(fast1 > slow1) s++;                                   // EMA direction
   if(InpUseMacroSlope && macro1 > macro2) s++;              // macro slope
   if(adx >= InpADXMin) s++;                                // trend strength
   if(rsi >= InpRSIBuyMin && rsi <= InpRSIBuyMax) s++;       // RSI
   if(fast1 > fast2 && slow1 >= slow2) s++;                  // momentum
   if(c1 > fast1 && fast1 > slow1) s++;                     // confirmation

   return s;
}

int SellScore(double c1, double fast1, double slow1, double macro1,
              double fast2, double slow2, double macro2,
              double adx, double rsi, double atr)
{
   int s = 0;

   if(c1 < macro1) s++;                                      // macro location
   if(fast1 < slow1) s++;                                   // EMA direction
   if(InpUseMacroSlope && macro1 < macro2) s++;              // macro slope
   if(adx >= InpADXMin) s++;                                // trend strength
   if(rsi >= InpRSISellMin && rsi <= InpRSISellMax) s++;     // RSI
   if(fast1 < fast2 && slow1 <= slow2) s++;                  // momentum
   if(c1 < fast1 && fast1 < slow1) s++;                     // confirmation

   return s;
}

// ============================================================
// Execution
// ============================================================

bool SendBuy(double atr)
{
   RefreshRates();
   double price = Ask;
   double slDist = atr * InpSLMult;
   double tpDist = atr * InpTPMult;

   double minStop = MarketInfo(_Symbol, MODE_STOPLEVEL) * Point;
   if(slDist < minStop) slDist = minStop;
   if(tpDist < minStop) tpDist = minStop;

   double sl = NormalizeDouble(price - slDist, Digits);
   double tp = NormalizeDouble(price + tpDist, Digits);

   if(!StopDistanceOK(price, sl) || !StopDistanceOK(price, tp))
   {
      gOrderErrors++;
      Log("BUY blocked: invalid stop distance");
      return false;
   }

   double lots = LotsByRisk(slDist);
   if(lots <= 0) { gOrderErrors++; return false; }

   ResetLastError();
   int ticket = OrderSend(_Symbol, OP_BUY, lots, price, InpSlippage,
                          sl, tp, "AI_v1.27_BUY", InpMagicNumber, 0, clrNONE);

   if(ticket < 0)
   {
      int err = GetLastError();
      gOrderErrors++;
      Print("BUY OrderSend ERROR=", err, " lots=", DoubleToString(lots,2),
            " price=", DoubleToString(price,Digits),
            " SL=", DoubleToString(sl,Digits),
            " TP=", DoubleToString(tp,Digits));
      return false;
   }

   gBuyOrders++;
   gLastTradeBar = iTime(_Symbol, _Period, 0);
   Print("BUY OPEN ticket=", ticket, " lots=", DoubleToString(lots,2),
         " price=", DoubleToString(price,Digits),
         " SL=", DoubleToString(sl,Digits),
         " TP=", DoubleToString(tp,Digits));
   return true;
}

bool SendSell(double atr)
{
   RefreshRates();
   double price = Bid;
   double slDist = atr * InpSLMult;
   double tpDist = atr * InpTPMult;

   double minStop = MarketInfo(_Symbol, MODE_STOPLEVEL) * Point;
   if(slDist < minStop) slDist = minStop;
   if(tpDist < minStop) tpDist = minStop;

   double sl = NormalizeDouble(price + slDist, Digits);
   double tp = NormalizeDouble(price - tpDist, Digits);

   if(!StopDistanceOK(price, sl) || !StopDistanceOK(price, tp))
   {
      gOrderErrors++;
      Log("SELL blocked: invalid stop distance");
      return false;
   }

   double lots = LotsByRisk(slDist);
   if(lots <= 0) { gOrderErrors++; return false; }

   ResetLastError();
   int ticket = OrderSend(_Symbol, OP_SELL, lots, price, InpSlippage,
                          sl, tp, "AI_v1.27_SELL", InpMagicNumber, 0, clrNONE);

   if(ticket < 0)
   {
      int err = GetLastError();
      gOrderErrors++;
      Print("SELL OrderSend ERROR=", err, " lots=", DoubleToString(lots,2),
            " price=", DoubleToString(price,Digits),
            " SL=", DoubleToString(sl,Digits),
            " TP=", DoubleToString(tp,Digits));
      return false;
   }

   gSellOrders++;
   gLastTradeBar = iTime(_Symbol, _Period, 0);
   Print("SELL OPEN ticket=", ticket, " lots=", DoubleToString(lots,2),
         " price=", DoubleToString(price,Digits),
         " SL=", DoubleToString(sl,Digits),
         " TP=", DoubleToString(tp,Digits));
   return true;
}

void ManagePositions()
{
   double atr = iATR(_Symbol, _Period, InpATRPeriod, 0);
   if(atr <= 0) return;

   RefreshRates();

   for(int i=OrdersTotal()-1; i>=0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != _Symbol || OrderMagicNumber() != InpMagicNumber) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      double open = OrderOpenPrice();
      double oldSL = OrderStopLoss();
      double tp = OrderTakeProfit();
      double newSL = oldSL;
      bool modify = false;

      if(OrderType() == OP_BUY)
      {
         double profitDist = Bid - open;
         if(profitDist >= atr * InpBEStartMult)
         {
            double be = open + atr * InpBELockMult;
            if(oldSL < be) { newSL = be; modify = true; }
         }

         if(profitDist >= atr * InpTrailStartMult)
         {
            double trail = Bid - atr * InpTrailDistMult;
            if(trail > newSL && trail > open)
            {
               newSL = trail;
               modify = true;
            }
         }

         newSL = NormalizeDouble(newSL, Digits);
         if(modify && newSL > oldSL && newSL < Bid)
         {
            ResetLastError();
            if(!OrderModify(OrderTicket(), open, newSL, tp, 0, clrNONE))
               Print("BUY OrderModify ERROR=", GetLastError(), " ticket=", OrderTicket());
         }
      }
      else if(OrderType() == OP_SELL)
      {
         double profitDist = open - Ask;
         if(profitDist >= atr * InpBEStartMult)
         {
            double be = open - atr * InpBELockMult;
            if(oldSL == 0 || oldSL > be) { newSL = be; modify = true; }
         }

         if(profitDist >= atr * InpTrailStartMult)
         {
            double trail = Ask + atr * InpTrailDistMult;
            if(oldSL == 0 || trail < newSL)
            {
               newSL = trail;
               modify = true;
            }
         }

         newSL = NormalizeDouble(newSL, Digits);
         if(modify && newSL > Ask)
         {
            if(oldSL == 0 || newSL < oldSL)
            {
               ResetLastError();
               if(!OrderModify(OrderTicket(), open, newSL, tp, 0, clrNONE))
                  Print("SELL OrderModify ERROR=", GetLastError(), " ticket=", OrderTicket());
            }
         }
      }
   }
}

// ============================================================
// Main analysis
// ============================================================

void Analyze()
{
   gBars++;

   if(!SessionOK()) { gSessionBlocks++; return; }
   if(OpenTradesCount() >= InpMaxTrades) { gMarketBlocks++; return; }
   if(!CooldownOK()) { gCooldownBlocks++; return; }

   double spreadPts = (Ask - Bid) / Point;
   double atr = iATR(_Symbol, _Period, InpATRPeriod, 1);
   if(atr <= 0) return;

   if(spreadPts > InpMaxSpreadPoints)
   {
      gSpreadBlocks++;
      return;
   }

   double atrPts = atr / Point;
   if(atrPts < InpMinATRPoints)
   {
      gATRBlocks++;
      return;
   }

   if((Ask - Bid) > atr * InpMaxSpreadATRRatio)
   {
      gATRRatioBlocks++;
      return;
   }

   double c1     = iClose(_Symbol, _Period, 1);
   double fast1  = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double fast2  = iMA(_Symbol, _Period, InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double slow1  = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow2  = iMA(_Symbol, _Period, InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double macro1 = iMA(_Symbol, _Period, InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double macro2 = iMA(_Symbol, _Period, InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double adx    = iADX(_Symbol, _Period, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   double rsi    = iRSI(_Symbol, _Period, InpRSIPeriod, PRICE_CLOSE, 1);

   if(c1 <= 0 || fast1 <= 0 || slow1 <= 0 || macro1 <= 0 || adx <= 0 || rsi <= 0)
      return;

   bool buyHTF = HTFTrendOK(true);
   bool sellHTF = HTFTrendOK(false);

   int buyScore = BuyScore(c1, fast1, slow1, macro1, fast2, slow2, macro2, adx, rsi, atr);
   int sellScore = SellScore(c1, fast1, slow1, macro1, fast2, slow2, macro2, adx, rsi, atr);

   gBuyScoreSum += buyScore;
   gSellScoreSum += sellScore;

   bool buyPass = InpAllowBuy && buyHTF && buyScore >= InpBuyMinScore;
   bool sellPass = InpAllowSell && sellHTF && sellScore >= InpSellMinScore;

   if(buyScore >= InpBuyMinScore) gBuyPotential++;
   if(sellScore >= InpSellMinScore) gSellPotential++;

   if(buyPass) gBuyApproved++;
   if(sellPass) gSellApproved++;

   string decision = "WAIT";

   if(buyPass && sellPass)
   {
      gBothPass++;
      if(buyScore > sellScore) decision = "BUY";
      else if(sellScore > buyScore) decision = "SELL";
      else decision = "WAIT_EQUAL";
   }
   else if(buyPass)
      decision = "BUY";
   else if(sellPass)
      decision = "SELL";
   else
      gScoreWaits++;

   if(InpVerboseLog && (decision != "WAIT" && decision != "WAIT_EQUAL"))
   {
      Print("SIGNAL v1.27 ", decision,
            " scoreB=", buyScore,
            " scoreS=", sellScore,
            " close=", DoubleToString(c1,Digits),
            " EMA8=", DoubleToString(fast1,Digits),
            " EMA21=", DoubleToString(slow1,Digits),
            " EMA200=", DoubleToString(macro1,Digits),
            " ADX=", DoubleToString(adx,1),
            " RSI=", DoubleToString(rsi,1),
            " ATRpts=", DoubleToString(atrPts,1),
            " spread=", DoubleToString(spreadPts,1));
   }

   if(decision == "BUY") SendBuy(atr);
   else if(decision == "SELL") SendSell(atr);
}

// ============================================================
// MT4 lifecycle
// ============================================================

int OnInit()
{
   Print("INIT_OK AI Trading Bot v1.27");
   Print("Symbol=", _Symbol, " Period=", Period(),
         " Risk=", DoubleToString(InpRiskPct,2), "%",
         " BuyMin=", InpBuyMinScore,
         " SellMin=", InpSellMinScore,
         " HTFFilter=", InpUseHTFTrendFilter);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   double avgBuy = (gBars > 0 ? (double)gBuyScoreSum / gBars : 0.0);
   double avgSell = (gBars > 0 ? (double)gSellScoreSum / gBars : 0.0);

   Print("FINAL DIAGNOSTIC v1.27");
   Print("Bars=", gBars,
         " SessionBlocks=", gSessionBlocks,
         " SpreadBlocks=", gSpreadBlocks,
         " ATRBlocks=", gATRBlocks,
         " ATRRatioBlocks=", gATRRatioBlocks,
         " CooldownBlocks=", gCooldownBlocks,
         " MarketBlocks=", gMarketBlocks);
   Print("BuyPotential=", gBuyPotential,
         " SellPotential=", gSellPotential,
         " BuyApproved=", gBuyApproved,
         " SellApproved=", gSellApproved,
         " BothPass=", gBothPass,
         " BuyOrders=", gBuyOrders,
         " SellOrders=", gSellOrders,
         " OrderErrors=", gOrderErrors);
   Print("AvgScoreB=", DoubleToString(avgBuy,3),
         " AvgScoreS=", DoubleToString(avgSell,3),
         " ScoreWaits=", gScoreWaits);
}

void OnTick()
{
   ManagePositions();
   if(IsNewBar()) Analyze();
}
