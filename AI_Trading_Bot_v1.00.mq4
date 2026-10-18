#property strict
#property version   "6.00"
#property description "EA Agresivo Mensual - rebuilt MQL4 EA with scoring, ATR exits and persistent risk controls"

// ================================================================
// EA_Agresivo_Mensual_v6.00.mq4
// Complete rebuild from the v5.x design.
// Platform: MetaTrader 4 / MQL4
// ================================================================

enum ENUM_MARKET_REGIME
{
   REGIME_UNDEFINED = 0,
   REGIME_TREND_UP,
   REGIME_TREND_DOWN,
   REGIME_RANGE,
   REGIME_HIGH_VOLATILITY
};

// ------------------------- Risk ----------------------------------
input double InpRiskPct          = 0.75;
input double InpMaxLots          = 2.00;
input int    InpMaxTrades        = 2;
input double InpMaxOpenRiskPct   = 1.50;
input int    InpSlippage          = 5;

// ------------------------- Protection ----------------------------
input double InpDailyLossPct     = 3.00;
input double InpWeeklyLossPct    = 6.00;
input double InpMonthDDPct       = 10.00;
input double InpMonthProfitLock  = 5.00;
input double InpProfitStopPct    = 10.00;
input double InpRiskAfterLock    = 0.50;

// ------------------------- Signal --------------------------------
input int    InpFastEMA          = 8;
input int    InpSlowEMA          = 21;
input int    InpMacroEMA         = 200;
input int    InpADXPeriod        = 14;
input double InpADXMin           = 20.0;
input double InpADXRangeMax      = 17.0;
input int    InpRSIPeriod        = 14;
input double InpRSIBuyMin        = 50.0;
input double InpRSIBuyMax        = 68.0;
input double InpRSISellMin       = 32.0;
input double InpRSISellMax       = 50.0;

// ------------------------- ATR / exits ---------------------------
input int    InpATRPeriod        = 14;
input double InpMinATRPoints     = 20.0;
input double InpMaxSpreadATR     = 0.20;
input double InpSLMult           = 1.50;
input double InpTPMult           = 3.00;
input double InpBEStartMult      = 1.20;
input double InpBELockMult       = 0.10;
input double InpTrailStartMult   = 1.80;
input double InpTrailDistMult    = 1.00;

// ------------------------- Entry score ---------------------------
input int    InpMinScore         = 5;
input double InpMinCrossPips     = 2.0;
input bool   InpUseCross         = true;
input bool   InpUsePullback      = true;
input bool   InpUseConfirmation  = true;

// ------------------------- Market filters -----------------------
input double InpMaxSpreadPoints  = 30.0;
input int    InpStartHour        = 7;
input int    InpEndHour          = 20;
input int    InpFridayCloseHour  = 21;
input int    InpCooldownBars     = 3;

// ------------------------- EA ------------------------------------
input int    InpMagic            = 8883001;
input bool   InpShowDashboard    = true;
input bool   InpCloseAllAtProfit = false;

string GV_PREFIX = "EA600_";

datetime g_lastBarTime = 0;
datetime g_lastBuyTime = 0;
datetime g_lastSellTime = 0;
int      g_lastDayKey = -1;
int      g_lastWeekKey = -1;
int      g_lastMonthKey = -1;
double   g_dayStartEquity = 0.0;
double   g_weekStartEquity = 0.0;
double   g_monthStartEquity = 0.0;
bool     g_dayHalted = false;
bool     g_weekHalted = false;
bool     g_monthHalted = false;
bool     g_profitHalted = false;
ENUM_MARKET_REGIME g_regime = REGIME_UNDEFINED;

// ================================================================
// Utility
// ================================================================

string RegimeToString(ENUM_MARKET_REGIME r)
{
   if(r == REGIME_TREND_UP)       return "TREND UP";
   if(r == REGIME_TREND_DOWN)     return "TREND DOWN";
   if(r == REGIME_RANGE)          return "RANGE";
   if(r == REGIME_HIGH_VOLATILITY)return "HIGH VOL";
   return "UNDEFINED";
}

int DigitsForSymbol()
{
   return (int)MarketInfo(Symbol(), MODE_DIGITS);
}

double PipSize()
{
   if(DigitsForSymbol() == 3 || DigitsForSymbol() == 5)
      return Point * 10.0;
   return Point;
}

double NormalizePrice(double price)
{
   return NormalizeDouble(price, DigitsForSymbol());
}

double NormalizeLots(double lots)
{
   double minLot  = MarketInfo(Symbol(), MODE_MINLOT);
   double maxLot  = MarketInfo(Symbol(), MODE_MAXLOT);
   double lotStep = MarketInfo(Symbol(), MODE_LOTSTEP);

   if(lotStep <= 0.0) lotStep = 0.01;
   if(maxLot > InpMaxLots) maxLot = InpMaxLots;
   if(lots < minLot) return 0.0;
   if(lots > maxLot) lots = maxLot;

   lots = MathFloor(lots / lotStep + 1e-8) * lotStep;
   if(lots < minLot) return 0.0;
   return NormalizeDouble(lots, 2);
}

string KeyPrefix()
{
   return GV_PREFIX + Symbol() + "_" + IntegerToString(InpMagic) + "_";
}

int DayKey(datetime t)
{
   return TimeYear(t) * 10000 + TimeMonth(t) * 100 + TimeDay(t);
}

int MonthKey(datetime t)
{
   return TimeYear(t) * 100 + TimeMonth(t);
}

int WeekKey(datetime t)
{
   // Stable broker-time week grouping. Sunday is the first day of the group.
   int doy = TimeDayOfYear(t);
   return TimeYear(t) * 100 + (doy / 7);
}

double LoadGV(string name, double fallback)
{
   if(GlobalVariableCheck(name)) return GlobalVariableGet(name);
   GlobalVariableSet(name, fallback);
   return fallback;
}

void SaveGV(string name, double value)
{
   GlobalVariableSet(name, value);
}

// ================================================================
// Lifecycle
// ================================================================

int OnInit()
{
   if(InpRiskPct <= 0.0 || InpMaxLots <= 0.0 || InpMaxTrades < 1)
   {
      Print("INIT ERROR: invalid risk/trade inputs.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpFastEMA >= InpSlowEMA || InpSlowEMA >= InpMacroEMA)
   {
      Print("INIT ERROR: EMA periods must satisfy Fast < Slow < Macro.");
      return INIT_PARAMETERS_INCORRECT;
   }

   if(InpSLMult <= 0.0 || InpTPMult <= 0.0 || InpATRPeriod < 1)
   {
      Print("INIT ERROR: invalid ATR/exit parameters.");
      return INIT_PARAMETERS_INCORRECT;
   }

   UpdatePeriodState(true);
   g_lastBarTime = iTime(Symbol(), Period(), 0);
   Print("EA_Agresivo_Mensual_v6.00 initialized on ", Symbol(), " TF=", Period());
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(InpShowDashboard) Comment("");
}

void OnTick()
{
   if(Bars < InpMacroEMA + 20) return;

   UpdatePeriodState(false);
   ManageOpenPositions();

   if(InpShowDashboard) DrawDashboard();

   if(IsFridayCloseTime())
   {
      CloseAllEAOrders("Friday close");
      return;
   }

   if(CheckRiskLimits()) return;
   if(!IsNewBar()) return;
   if(!IsTradingSession()) return;
   if(!MarketFilterOK()) return;
   if(CountOpenTrades() >= InpMaxTrades) return;
   if(OpenRiskPct() >= InpMaxOpenRiskPct) return;

   g_regime = DetectMarketRegime();

   if(g_regime == REGIME_RANGE || g_regime == REGIME_HIGH_VOLATILITY || g_regime == REGIME_UNDEFINED)
      return;

   int buyScore = BuyScore();
   int sellScore = SellScore();

   if(buyScore >= InpMinScore && buyScore > sellScore)
   {
      if(CanOpenBuy()) OpenBuy();
   }
   else if(sellScore >= InpMinScore && sellScore > buyScore)
   {
      if(CanOpenSell()) OpenSell();
   }
}

// ================================================================
// Period state / persistent risk
// ================================================================

void UpdatePeriodState(bool force)
{
   datetime now = TimeCurrent();
   int d = DayKey(now);
   int w = WeekKey(now);
   int m = MonthKey(now);
   string p = KeyPrefix();

   if(force || d != g_lastDayKey)
   {
      g_lastDayKey = d;
      string k = p + "DAY_" + IntegerToString(d);
      g_dayStartEquity = LoadGV(k, AccountEquity());
      g_dayHalted = false;
   }

   if(force || w != g_lastWeekKey)
   {
      g_lastWeekKey = w;
      string k = p + "WEEK_" + IntegerToString(w);
      g_weekStartEquity = LoadGV(k, AccountEquity());
      g_weekHalted = false;
   }

   if(force || m != g_lastMonthKey)
   {
      g_lastMonthKey = m;
      string k = p + "MONTH_" + IntegerToString(m);
      g_monthStartEquity = LoadGV(k, AccountEquity());
      g_monthHalted = false;
      g_profitHalted = false;
   }
}

bool CheckRiskLimits()
{
   double eq = AccountEquity();

   if(g_dayStartEquity > 0.0)
   {
      double dd = (g_dayStartEquity - eq) / g_dayStartEquity * 100.0;
      if(dd >= InpDailyLossPct) g_dayHalted = true;
   }

   if(g_weekStartEquity > 0.0)
   {
      double dd = (g_weekStartEquity - eq) / g_weekStartEquity * 100.0;
      if(dd >= InpWeeklyLossPct) g_weekHalted = true;
   }

   if(g_monthStartEquity > 0.0)
   {
      double ret = (eq - g_monthStartEquity) / g_monthStartEquity * 100.0;
      double dd = (g_monthStartEquity - eq) / g_monthStartEquity * 100.0;

      if(dd >= InpMonthDDPct) g_monthHalted = true;
      if(InpProfitStopPct > 0.0 && ret >= InpProfitStopPct) g_profitHalted = true;

      if(InpCloseAllAtProfit && g_profitHalted)
         CloseAllEAOrders("Monthly profit target reached");
   }

   return (g_dayHalted || g_weekHalted || g_monthHalted || g_profitHalted);
}

double CurrentRiskPct()
{
   double risk = InpRiskPct;
   if(g_monthStartEquity > 0.0)
   {
      double ret = (AccountEquity() - g_monthStartEquity) / g_monthStartEquity * 100.0;
      if(ret >= InpMonthProfitLock && InpRiskAfterLock > 0.0)
         risk = MathMin(risk, InpRiskAfterLock);
   }
   return risk;
}

// ================================================================
// Market regime / indicators
// ================================================================

ENUM_MARKET_REGIME DetectMarketRegime()
{
   double atr = iATR(Symbol(), Period(), InpATRPeriod, 1);
   double atrPts = atr / Point;
   double adx = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);

   double c1 = iClose(Symbol(), Period(), 1);
   double macro1 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double macro2 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double fast = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double slow = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);

   if(atrPts >= InpMinATRPoints * 3.0)
      return REGIME_HIGH_VOLATILITY;

   if(adx >= InpADXMin && c1 > macro1 && macro1 > macro2 && fast > slow)
      return REGIME_TREND_UP;

   if(adx >= InpADXMin && c1 < macro1 && macro1 < macro2 && fast < slow)
      return REGIME_TREND_DOWN;

   if(adx <= InpADXRangeMax)
      return REGIME_RANGE;

   return REGIME_UNDEFINED;
}

bool MacroBull()
{
   double c1 = iClose(Symbol(), Period(), 1);
   double m1 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double m2 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   return (c1 > m1 && m1 > m2);
}

bool MacroBear()
{
   double c1 = iClose(Symbol(), Period(), 1);
   double m1 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double m2 = iMA(Symbol(), Period(), InpMacroEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   return (c1 < m1 && m1 < m2);
}

bool FastBull()
{
   double f1 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double s1 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   return f1 > s1;
}

bool FastBear()
{
   double f1 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double s1 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   return f1 < s1;
}

bool ADXBullStrong()
{
   double adx = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   double pdi = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_PLUSDI, 1);
   double mdi = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MINUSDI, 1);
   return (adx >= InpADXMin && pdi > mdi);
}

bool ADXBearStrong()
{
   double adx = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   double pdi = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_PLUSDI, 1);
   double mdi = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MAIN, 1);
   // Correct minus-DI read is done below to keep this function explicit.
   mdi = iADX(Symbol(), Period(), InpADXPeriod, PRICE_CLOSE, MODE_MINUSDI, 1);
   return (adx >= InpADXMin && mdi > pdi);
}

bool BuyRSI()
{
   double r = iRSI(Symbol(), Period(), InpRSIPeriod, PRICE_CLOSE, 1);
   return (r >= InpRSIBuyMin && r <= InpRSIBuyMax);
}

bool SellRSI()
{
   double r = iRSI(Symbol(), Period(), InpRSIPeriod, PRICE_CLOSE, 1);
   return (r >= InpRSISellMin && r <= InpRSISellMax);
}

bool BuyCross()
{
   if(!InpUseCross) return false;
   double f1 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double f2 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double s1 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double s2 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double sep = MathAbs(f1 - s1) / PipSize();
   return (f2 <= s2 && f1 > s1 && sep >= InpMinCrossPips);
}

bool SellCross()
{
   if(!InpUseCross) return false;
   double f1 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double f2 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double s1 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double s2 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 2);
   double sep = MathAbs(f1 - s1) / PipSize();
   return (f2 >= s2 && f1 < s1 && sep >= InpMinCrossPips);
}

bool BuyPullback()
{
   if(!InpUsePullback) return false;
   double ema21 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema8 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double low1 = iLow(Symbol(), Period(), 1);
   double close1 = iClose(Symbol(), Period(), 1);
   double open1 = iOpen(Symbol(), Period(), 1);
   return (ema8 > ema21 && low1 <= ema21 && close1 > ema8 && close1 > open1);
}

bool SellPullback()
{
   if(!InpUsePullback) return false;
   double ema21 = iMA(Symbol(), Period(), InpSlowEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double ema8 = iMA(Symbol(), Period(), InpFastEMA, 0, MODE_EMA, PRICE_CLOSE, 1);
   double high1 = iHigh(Symbol(), Period(), 1);
   double close1 = iClose(Symbol(), Period(), 1);
   double open1 = iOpen(Symbol(), Period(), 1);
   return (ema8 < ema21 && high1 >= ema21 && close1 < ema8 && close1 < open1);
}

bool BuyConfirmation()
{
   if(!InpUseConfirmation) return false;
   double close1 = iClose(Symbol(), Period(), 1);
   double high2 = iHigh(Symbol(), Period(), 2);
   double open1 = iOpen(Symbol(), Period(), 1);
   return (close1 > open1 && close1 > high2);
}

bool SellConfirmation()
{
   if(!InpUseConfirmation) return false;
   double close1 = iClose(Symbol(), Period(), 1);
   double low2 = iLow(Symbol(), Period(), 2);
   double open1 = iOpen(Symbol(), Period(), 1);
   return (close1 < open1 && close1 < low2);
}

int BuyScore()
{
   int score = 0;
   if(MacroBull()) score++;
   if(FastBull()) score++;
   if(ADXBullStrong()) score++;
   if(BuyRSI()) score++;
   if(BuyCross()) score++;
   if(BuyPullback()) score++;
   if(BuyConfirmation()) score++;
   return score;
}

int SellScore()
{
   int score = 0;
   if(MacroBear()) score++;
   if(FastBear()) score++;
   if(ADXBearStrong()) score++;
   if(SellRSI()) score++;
   if(SellCross()) score++;
   if(SellPullback()) score++;
   if(SellConfirmation()) score++;
   return score;
}

// ================================================================
// Market filters / timing
// ================================================================

bool IsNewBar()
{
   datetime t = iTime(Symbol(), Period(), 0);
   if(t == g_lastBarTime) return false;
   g_lastBarTime = t;
   return true;
}

bool IsTradingSession()
{
   int h = TimeHour(TimeCurrent());

   if(InpStartHour == InpEndHour) return true;

   if(InpStartHour < InpEndHour)
      return (h >= InpStartHour && h < InpEndHour);

   // Overnight session.
   return (h >= InpStartHour || h < InpEndHour);
}

bool IsFridayCloseTime()
{
   int dow = TimeDayOfWeek(TimeCurrent());
   int h = TimeHour(TimeCurrent());
   return (dow == 5 && h >= InpFridayCloseHour);
}

bool MarketFilterOK()
{
   RefreshRates();
   double spreadPts = (Ask - Bid) / Point;
   if(spreadPts > InpMaxSpreadPoints) return false;

   double atr = iATR(Symbol(), Period(), InpATRPeriod, 1);
   if(atr <= 0.0) return false;
   if((atr / Point) < InpMinATRPoints) return false;

   if(InpMaxSpreadATR > 0.0 && (Ask - Bid) / atr > InpMaxSpreadATR)
      return false;

   return true;
}

bool CooldownOK(datetime lastTime)
{
   if(lastTime <= 0) return true;
   int shift = iBarShift(Symbol(), Period(), lastTime, true);
   if(shift < 0) return true;
   return (shift >= InpCooldownBars);
}

bool CanOpenBuy()
{
   if(g_regime != REGIME_TREND_UP) return false;
   if(!CooldownOK(g_lastBuyTime)) return false;
   return true;
}

bool CanOpenSell()
{
   if(g_regime != REGIME_TREND_DOWN) return false;
   if(!CooldownOK(g_lastSellTime)) return false;
   return true;
}

// ================================================================
// Risk / lot calculation
// ================================================================

double CalculateLotSize(double stopDistance)
{
   if(stopDistance <= 0.0) return 0.0;

   double equity = AccountEquity();
   double riskMoney = equity * CurrentRiskPct() / 100.0;
   if(riskMoney <= 0.0) return 0.0;

   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize  = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   double moneyPerLot = (stopDistance / tickSize) * tickValue;
   if(moneyPerLot <= 0.0) return 0.0;

   double lots = riskMoney / moneyPerLot;
   return NormalizeLots(lots);
}

double OpenRiskPct()
{
   double equity = AccountEquity();
   if(equity <= 0.0) return 0.0;

   double totalRiskMoney = 0.0;
   double tickValue = MarketInfo(Symbol(), MODE_TICKVALUE);
   double tickSize = MarketInfo(Symbol(), MODE_TICKSIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(OrderStopLoss() <= 0.0) continue;

      double distance = MathAbs(OrderOpenPrice() - OrderStopLoss());
      totalRiskMoney += (distance / tickSize) * tickValue * OrderLots();
   }

   return totalRiskMoney / equity * 100.0;
}

// ================================================================
// Broker stop validation
// ================================================================

bool StopsValid(int type, double price, double sl, double tp)
{
   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double minDist   = MathMax(stopLevel, freeze);

   if(type == OP_BUY)
   {
      if(sl > 0.0 && price - sl < minDist) return false;
      if(tp > 0.0 && tp - price < minDist) return false;
   }
   else if(type == OP_SELL)
   {
      if(sl > 0.0 && sl - price < minDist) return false;
      if(tp > 0.0 && price - tp < minDist) return false;
   }
   return true;
}

// ================================================================
// Order entry
// ================================================================

bool OpenBuy()
{
   RefreshRates();
   double atr = iATR(Symbol(), Period(), InpATRPeriod, 1);
   if(atr <= 0.0) return false;

   double stopDistance = atr * InpSLMult;
   double tpDistance = atr * InpTPMult;
   double lots = CalculateLotSize(stopDistance);
   if(lots <= 0.0)
   {
      Print("BUY blocked: calculated lot size is zero.");
      return false;
   }

   if(OpenRiskPct() >= InpMaxOpenRiskPct)
      return false;

   double price = Ask;
   double sl = NormalizePrice(price - stopDistance);
   double tp = NormalizePrice(price + tpDistance);

   if(!StopsValid(OP_BUY, price, sl, tp))
   {
      Print("BUY blocked: broker stop/freeze level rejects SL/TP.");
      return false;
   }

   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_BUY, lots, price, InpSlippage, sl, tp,
                          "EA600 BUY", InpMagic, 0, clrNONE);
   if(ticket < 0)
   {
      int err = GetLastError();
      Print("BUY OrderSend failed. Error=", err, " lots=", DoubleToString(lots,2),
            " price=", DoubleToString(price,DigitsForSymbol()),
            " SL=", DoubleToString(sl,DigitsForSymbol()),
            " TP=", DoubleToString(tp,DigitsForSymbol()));
      return false;
   }

   g_lastBuyTime = TimeCurrent();
   Print("BUY opened. Ticket=", ticket, " lots=", DoubleToString(lots,2));
   return true;
}

bool OpenSell()
{
   RefreshRates();
   double atr = iATR(Symbol(), Period(), InpATRPeriod, 1);
   if(atr <= 0.0) return false;

   double stopDistance = atr * InpSLMult;
   double tpDistance = atr * InpTPMult;
   double lots = CalculateLotSize(stopDistance);
   if(lots <= 0.0)
   {
      Print("SELL blocked: calculated lot size is zero.");
      return false;
   }

   if(OpenRiskPct() >= InpMaxOpenRiskPct)
      return false;

   double price = Bid;
   double sl = NormalizePrice(price + stopDistance);
   double tp = NormalizePrice(price - tpDistance);

   if(!StopsValid(OP_SELL, price, sl, tp))
   {
      Print("SELL blocked: broker stop/freeze level rejects SL/TP.");
      return false;
   }

   ResetLastError();
   int ticket = OrderSend(Symbol(), OP_SELL, lots, price, InpSlippage, sl, tp,
                          "EA600 SELL", InpMagic, 0, clrNONE);
   if(ticket < 0)
   {
      int err = GetLastError();
      Print("SELL OrderSend failed. Error=", err, " lots=", DoubleToString(lots,2),
            " price=", DoubleToString(price,DigitsForSymbol()),
            " SL=", DoubleToString(sl,DigitsForSymbol()),
            " TP=", DoubleToString(tp,DigitsForSymbol()));
      return false;
   }

   g_lastSellTime = TimeCurrent();
   Print("SELL opened. Ticket=", ticket, " lots=", DoubleToString(lots,2));
   return true;
}

// ================================================================
// Position management
// ================================================================

void ManageOpenPositions()
{
   RefreshRates();
   double atr = iATR(Symbol(), Period(), InpATRPeriod, 0);
   if(atr <= 0.0) return;

   double stopLevel = MarketInfo(Symbol(), MODE_STOPLEVEL) * Point;
   double freeze    = MarketInfo(Symbol(), MODE_FREEZELEVEL) * Point;
   double minDist   = MathMax(stopLevel, freeze);

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int type = OrderType();
      double open = OrderOpenPrice();
      double current = (type == OP_BUY ? Bid : Ask);
      double profitDistance = (type == OP_BUY ? current - open : open - current);
      if(profitDistance <= 0.0) continue;

      double newSL = OrderStopLoss();
      bool modify = false;

      // Break-even + lock.
      if(profitDistance >= atr * InpBEStartMult)
      {
         double beSL;
         if(type == OP_BUY)
         {
            beSL = NormalizePrice(open + atr * InpBELockMult);
            if((newSL <= 0.0 || beSL > newSL) && current - beSL >= minDist)
            {
               newSL = beSL;
               modify = true;
            }
         }
         else
         {
            beSL = NormalizePrice(open - atr * InpBELockMult);
            if((newSL <= 0.0 || beSL < newSL) && beSL - current >= minDist)
            {
               newSL = beSL;
               modify = true;
            }
         }
      }

      // ATR trailing.
      if(profitDistance >= atr * InpTrailStartMult)
      {
         double trailSL;
         if(type == OP_BUY)
         {
            trailSL = NormalizePrice(current - atr * InpTrailDistMult);
            if((newSL <= 0.0 || trailSL > newSL) && current - trailSL >= minDist)
            {
               newSL = trailSL;
               modify = true;
            }
         }
         else
         {
            trailSL = NormalizePrice(current + atr * InpTrailDistMult);
            if((newSL <= 0.0 || trailSL < newSL) && trailSL - current >= minDist)
            {
               newSL = trailSL;
               modify = true;
            }
         }
      }

      if(modify && MathAbs(newSL - OrderStopLoss()) >= Point)
      {
         ResetLastError();
         bool ok = OrderModify(OrderTicket(), OrderOpenPrice(), newSL,
                               OrderTakeProfit(), 0, clrNONE);
         if(!ok)
         {
            int err = GetLastError();
            Print("OrderModify failed. Ticket=", OrderTicket(),
                  " Error=", err,
                  " newSL=", DoubleToString(newSL,DigitsForSymbol()));
         }
      }
   }
}

void CloseAllEAOrders(string reason)
{
   RefreshRates();

   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;

      int type = OrderType();
      double price = (type == OP_BUY ? Bid : Ask);
      ResetLastError();
      bool ok = OrderClose(OrderTicket(), OrderLots(), price, InpSlippage, clrNONE);
      if(!ok)
      {
         int err = GetLastError();
         Print("OrderClose failed. Ticket=", OrderTicket(),
               " Error=", err, " reason=", reason);
      }
      else
      {
         Print("Order closed. Ticket=", OrderTicket(), " reason=", reason);
      }
   }
}

int CountOpenTrades()
{
   int count = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) count++;
   }
   return count;
}

// ================================================================
// Statistics
// ================================================================

double NetProfit()
{
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      total += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return total;
}

double GrossProfit()
{
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double p = OrderProfit() + OrderSwap() + OrderCommission();
      if(p > 0.0) total += p;
   }
   return total;
}

double GrossLoss()
{
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double p = OrderProfit() + OrderSwap() + OrderCommission();
      if(p < 0.0) total += -p;
   }
   return total;
}

double TotalCommission()
{
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      total += OrderCommission();
   }
   return total;
}

double TotalSwap()
{
   double total = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      total += OrderSwap();
   }
   return total;
}

int TotalClosedTrades()
{
   int total = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) total++;
   }
   return total;
}

int WinningTrades()
{
   int total = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      double p = OrderProfit() + OrderSwap() + OrderCommission();
      if(p > 0.0) total++;
   }
   return total;
}

double WinRate()
{
   int trades = TotalClosedTrades();
   if(trades <= 0) return 0.0;
   return (double)WinningTrades() / trades * 100.0;
}

double ProfitFactor()
{
   double gp = GrossProfit();
   double gl = GrossLoss();
   if(gl <= 0.0) return 0.0;
   return gp / gl;
}

double AverageWin()
{
   int wins = WinningTrades();
   if(wins <= 0) return 0.0;
   return GrossProfit() / wins;
}

double AverageLoss()
{
   int losses = TotalClosedTrades() - WinningTrades();
   if(losses <= 0) return 0.0;
   return GrossLoss() / losses;
}

double CurrentMonthNet()
{
   datetime now = TimeCurrent();
   int y = TimeYear(now);
   int m = TimeMonth(now);
   double total = 0.0;

   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderSymbol() != Symbol() || OrderMagicNumber() != InpMagic) continue;
      if(OrderType() != OP_BUY && OrderType() != OP_SELL) continue;
      if(TimeYear(OrderCloseTime()) == y && TimeMonth(OrderCloseTime()) == m)
         total += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return total;
}

double CurrentMonthReturnPct()
{
   if(g_monthStartEquity <= 0.0) return 0.0;
   return (AccountEquity() - g_monthStartEquity) / g_monthStartEquity * 100.0;
}

double CurrentDrawdownPct()
{
   double bal = AccountBalance();
   double eq = AccountEquity();
   if(bal <= 0.0) return 0.0;
   if(eq >= bal) return 0.0;
   return (bal - eq) / bal * 100.0;
}

string StatusText()
{
   if(g_dayHalted) return "HALTED: DAILY DD";
   if(g_weekHalted) return "HALTED: WEEKLY DD";
   if(g_monthHalted) return "HALTED: MONTH DD";
   if(g_profitHalted) return "HALTED: MONTH PROFIT";
   return "ACTIVE";
}

// ================================================================
// Dashboard
// ================================================================

void DrawDashboard()
{
   double monthRet = CurrentMonthReturnPct();
   double currentRisk = CurrentRiskPct();
   double openRisk = OpenRiskPct();
   double pf = ProfitFactor();

   string dashboard = "";
   dashboard += "EA Agresivo Mensual v6.00\n";
   dashboard += "--------------------------------\n";
   dashboard += "Symbol: " + Symbol() + " | TF: " + IntegerToString(Period()) + "\n";
   dashboard += "Regime: " + RegimeToString(g_regime) + "\n";
   dashboard += "BUY score: " + IntegerToString(BuyScore()) + " / " + IntegerToString(InpMinScore);
   dashboard += " | SELL score: " + IntegerToString(SellScore()) + " / " + IntegerToString(InpMinScore) + "\n";
   dashboard += "Balance: " + DoubleToString(AccountBalance(), 2) + " | Equity: " + DoubleToString(AccountEquity(), 2) + "\n";
   dashboard += "Net profit: " + DoubleToString(NetProfit(), 2) + " | Month: " + DoubleToString(CurrentMonthNet(), 2);
   dashboard += " (" + DoubleToString(monthRet, 2) + "%)\n";
   dashboard += "Gross +: " + DoubleToString(GrossProfit(), 2) + " | Gross -: " + DoubleToString(GrossLoss(), 2) + "\n";
   dashboard += "Commission: " + DoubleToString(TotalCommission(), 2) + " | Swap: " + DoubleToString(TotalSwap(), 2) + "\n";
   dashboard += "Profit factor: " + DoubleToString(pf, 2) + " | Win rate: " + DoubleToString(WinRate(), 1) + "%\n";
   dashboard += "Trades: " + IntegerToString(TotalClosedTrades());
   dashboard += " | Avg win: " + DoubleToString(AverageWin(), 2);
   dashboard += " | Avg loss: " + DoubleToString(AverageLoss(), 2) + "\n";
   dashboard += "Drawdown: " + DoubleToString(CurrentDrawdownPct(), 2) + "%\n";
   dashboard += "Open trades: " + IntegerToString(CountOpenTrades());
   dashboard += " | Open risk: " + DoubleToString(openRisk, 2) + "%";
   dashboard += " | Current risk: " + DoubleToString(currentRisk, 2) + "%\n";
   dashboard += "Status: " + StatusText();

   Comment(dashboard);
}
