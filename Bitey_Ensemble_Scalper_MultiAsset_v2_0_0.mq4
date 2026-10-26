//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v2_0_0.mq4                     |
//| Multi-asset ensemble scalper / day-trader for MT4                 |
//|                                                                  |
//| v2.0.0 improvements over v1.4/v1.7:                              |
//|  - Smarter risk vs MinLot (crypto-friendly sizing)               |
//|  - Volatility regime filter + opportunity ranking                |
//|  - Stronger equity curve & daily/monthly protection              |
//|  - Improved expectancy ban + soft demotion                       |
//|  - Better cost / spread filtering                                |
//|  - Cleaner adaptive exits + commission-aware break-even          |
//|  - More robust symbol universe handling                          |
//|                                                                  |
//| NOT performance-validated. Always test on demo / Strategy Tester |
//| before live use. Trade at your own risk.                         |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "Bitey Ensemble Scalper v2.0.0 - Multi-asset, regime-aware, cost-aware, risk-controlled"

#define EA_VERSION          "2.0.0"
#define MAX_SYMBOLS         128
#define HARD_MAX_POSITIONS  6

//--- Universe & Timeframes
input string           InpSymbolsCSV            = "";           // Blank = all symbols in Market Watch
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_M15;
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102027;

//--- Risk Management (reference capital for percentage calculations)
input double           InpReferenceCapitalUSD   = 500.0;
input double           InpRiskPctPerTrade       = 0.45;         // Slightly lower than 0.5 for safety
input double           InpMaxAggregateRiskPct   = 2.2;
input double           InpDailyLossPct          = 2.5;          // Blocks NEW entries
input double           InpMonthlyLossPct        = 6.0;          // Hard equity halt
input int              InpMaxOpenPositions      = 5;
input double           InpMaxLotsFX             = 0.30;
input double           InpMaxLotsOther          = 0.15;         // Raised slightly for crypto viability
input double           InpMinRiskMoney          = 1.50;         // Soft floor for risk budget

//--- Costs (round-turn commission per 1.00 lot)
input double           InpCommissionPerLotFX    = 10.0;
input double           InpCommissionPerLotOther = 15.0;
input double           InpMaxCostR              = 0.28;         // Tighter than 0.30

//--- Direction
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- Signal Engine
input int              InpFamilyMinVotes        = 3;
input double           InpTrendADX              = 20.0;
input double           InpMinADX                = 11.0;
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.45;
input double           InpRewardRisk            = 1.85;
input double           InpMinATRPct             = 0.08;         // Min ATR as % of price (dead market filter)
input double           InpMaxATRPct             = 3.50;         // Extreme volatility filter

//--- Execution Filters
input double           InpMaxSpreadPctOfStop    = 9.0;
input int              InpMaxSpreadPoints       = 0;            // 0 = off
input int              InpMaxQuoteAgeSec        = 90;
input int              InpSlippagePoints        = 18;
input int              InpMinBars               = 300;
input bool             InpUseSessionFilter      = true;
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 5;
input int              InpReentryBars           = 2;
input int              InpMaxHoldBars           = 42;

//--- Rollover
input bool             InpBlockRollover         = true;
input bool             InpFlatBeforeRollover    = true;
input int              InpRolloverStartMin      = 1410;         // 23:30
input int              InpRolloverEndMin        = 15;           // 00:15

//--- Circuit Breakers
input int              InpMaxConsecLosses       = 3;
input int              InpLossStreakPauseMin    = 75;
input int              InpExpectancyWindow      = 18;
input int              InpExpectancyMinTrades   = 10;
input int              InpExpectancyBanHours    = 18;
input double           InpExpectancySoftThreshold = -0.35;      // Soft demotion score penalty

//--- Adaptive Exits
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.40;
input double           InpBreakEvenLockATR      = 0.12;
input double           InpTrailStartATR         = 1.70;
input double           InpTrailDistanceATR      = 1.15;
input double           InpTrailStepATR          = 0.08;
input double           InpTPExpandTriggerATR    = 1.40;
input double           InpTPExpandBufferATR     = 0.90;
input double           InpTPExpandStepATR       = 0.22;
input double           InpTPExpandADXMin        = 21.0;
input double           InpTPMaxDistanceATR      = 4.8;
input double           InpNetTargetR            = 0.0;          // 0 = off

//--- Control
input bool             InpEnableTrading         = true;
input bool             InpLogRejects            = false;
input bool             InpLogCandidates         = true;

//--- Internal
string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
datetime g_lastDailyBlockLog = 0;
datetime g_equityHaltUntil = 0;

string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   if(g_symbolCount <= 0)
   {
      Print("INIT_ERROR | no symbols found");
      return(INIT_FAILED);
   }
   for(int i = 0; i < g_symbolCount; i++)
   {
      g_lastBar[i] = 0;
      SymbolSelect(g_symbols[i], true);
   }
   EventSetTimer(1);
   Print("BITEY_ENSEMBLE_INIT | version=", EA_VERSION,
         " | symbols=", g_symbolCount,
         " | maxPositions=", MaxPositions(),
         " | tf=", (int)InpSignalTF,
         " | trading=", (InpEnableTrading ? "ON" : "OFF"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick()  { RunCycle(); }
void OnTimer() { RunCycle(); }

int MaxPositions()
{
   return((int)MathMin(HARD_MAX_POSITIONS, MathMax(1, InpMaxOpenPositions)));
}

//+------------------------------------------------------------------+
//| Symbol helpers                                                    |
//+------------------------------------------------------------------+
string AssetKey(string s)
{
   StringToUpper(s);
   if(StringLen(s) > 0 && StringGetChar(s, 0) == '#') s = StringSubstr(s, 1);
   string k = "";
   for(int i = 0; i < StringLen(s) && StringLen(k) < 6; i++)
   {
      int ch = StringGetChar(s, i);
      bool alnum = ((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z'));
      if(!alnum) break;
      k += CharToString((uchar)ch);
   }
   return(k);
}

bool IsCrypto(string sym)
{
   string k = AssetKey(sym);
   string p[16] = {"BTC","XBT","ETH","SOL","XRP","LTC","BCH","DOG","ADA","DOT","LIN","AVA","BNB","NEA","HYP","TON"};
   for(int i = 0; i < 16; i++)
      if(StringFind(k, p[i]) == 0) return(true);
   return(false);
}

bool IsCcy(string c)
{
   string l[8] = {"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   for(int i = 0; i < 8; i++)
      if(c == l[i]) return(true);
   return(false);
}

bool IsForex(string sym)
{
   string k = AssetKey(sym);
   if(StringLen(k) != 6) return(false);
   return(IsCcy(StringSubstr(k, 0, 3)) && IsCcy(StringSubstr(k, 3, 3)));
}

double CommissionPerLot(string sym)
{
   return(IsForex(sym) ? InpCommissionPerLotFX : InpCommissionPerLotOther);
}

double LotCap(string sym)
{
   return(IsForex(sym) ? InpMaxLotsFX : InpMaxLotsOther);
}

void ParseSymbols()
{
   g_symbolCount = 0;
   string csv = InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   if(StringLen(csv) == 0)
   {
      int total = SymbolsTotal(true);
      for(int i = 0; i < total && g_symbolCount < MAX_SYMBOLS; i++)
         AddSymbol(SymbolName(i, true));
      return;
   }
   while(StringLen(csv) > 0 && g_symbolCount < MAX_SYMBOLS)
   {
      int p = StringFind(csv, ",");
      string s;
      if(p < 0) { s = csv; csv = ""; }
      else { s = StringSubstr(csv, 0, p); csv = StringSubstr(csv, p + 1); }
      StringTrimLeft(s); StringTrimRight(s);
      AddSymbol(s);
   }
}

void AddSymbol(string s)
{
   if(StringLen(s) <= 0) return;
   string k = AssetKey(s);
   if(StringLen(k) < 3) return;
   for(int i = 0; i < g_symbolCount; i++)
      if(g_keys[i] == k) return;
   g_symbols[g_symbolCount] = s;
   g_keys[g_symbolCount] = k;
   g_symbolCount++;
}

//+------------------------------------------------------------------+
//| Main cycle                                                        |
//+------------------------------------------------------------------+
void RunCycle()
{
   if(!IsTesting())
   {
      uint nowTick = GetTickCount();
      if(g_lastCycleTick != 0 && (nowTick - g_lastCycleTick) < 850) return;
      g_lastCycleTick = nowTick;
   }

   ManageExits();

   // Equity halt check
   if(g_equityHaltUntil > 0 && TimeCurrent() < g_equityHaltUntil)
   {
      if(g_lastHeartbeat == 0 || TimeCurrent() - g_lastHeartbeat >= 300)
      {
         g_lastHeartbeat = TimeCurrent();
         Print("EQUITY_HALT_ACTIVE | until=", TimeToString(g_equityHaltUntil));
      }
      return;
   }

   int maxPos = MaxPositions();
   bool lossBlock = LossStreakBlock();
   int limit = (lossBlock ? 0 : g_symbolCount);
   int nc = 0;

   for(int i = 0; i < limit; i++)
   {
      string sym = g_symbols[i];
      datetime bt = iTime(sym, InpSignalTF, 0);
      if(bt <= 0 || bt == g_lastBar[i]) continue;
      g_lastBar[i] = bt;

      if(CountOpenPositions() + nc >= maxPos) { Reject(sym, "MAX_POSITIONS"); continue; }

      int cmd; double score; string why;
      if(!Prefilter(sym, why)) { Reject(sym, why); continue; }
      if(!Analyze(sym, cmd, score, why)) { Reject(sym, why); continue; }
      if(cmd == OP_BUY && !InpAllowBuy)  { Reject(sym, "BUY_DISABLED"); continue; }
      if(cmd == OP_SELL && !InpAllowSell) { Reject(sym, "SELL_DISABLED"); continue; }

      // Soft expectancy demotion
      if(SymbolExpectancySoftPenalty(sym))
         score *= 0.72;

      g_candSym[nc] = sym;
      g_candCmd[nc] = cmd;
      g_candScore[nc] = score;
      nc++;
   }

   if(nc > 0)
   {
      // Sort by score descending
      for(int a = 0; a < nc - 1; a++)
         for(int b = a + 1; b < nc; b++)
            if(g_candScore[b] > g_candScore[a])
            {
               string ts = g_candSym[a];  g_candSym[a] = g_candSym[b];  g_candSym[b] = ts;
               int    tc = g_candCmd[a];  g_candCmd[a] = g_candCmd[b];  g_candCmd[b] = tc;
               double td = g_candScore[a]; g_candScore[a] = g_candScore[b]; g_candScore[b] = td;
            }

      double dailyLimit = InpReferenceCapitalUSD * InpDailyLossPct / 100.0;
      double dayNet = TodayNet();
      if(dayNet <= -dailyLimit)
      {
         if(g_lastDailyBlockLog == 0 || TimeCurrent() - g_lastDailyBlockLog >= 300)
         {
            g_lastDailyBlockLog = TimeCurrent();
            Print("DAILY_LOSS_BLOCK | dayNet=", DoubleToString(dayNet, 2),
                  " limit=-", DoubleToString(dailyLimit, 2));
         }
      }
      else
      {
         for(int c = 0; c < nc; c++)
         {
            if(CountOpenPositions() >= maxPos) break;
            OpenTrade(g_candSym[c], g_candCmd[c], g_candScore[c]);
         }
      }
   }

   // Heartbeat + monthly equity check
   datetime now = TimeCurrent();
   if(g_lastHeartbeat == 0 || now - g_lastHeartbeat >= 300)
   {
      g_lastHeartbeat = now;
      double monthNet = MonthNet();
      double monthLimit = InpReferenceCapitalUSD * InpMonthlyLossPct / 100.0;
      if(monthNet <= -monthLimit)
      {
         g_equityHaltUntil = now + 6 * 3600; // 6h cool-down
         Print("MONTHLY_EQUITY_HALT | monthNet=", DoubleToString(monthNet, 2),
               " limit=-", DoubleToString(monthLimit, 2), " | halt 6h");
      }
      Print("HEARTBEAT | v", EA_VERSION,
            " open=", CountOpenPositions(), "/", maxPos,
            " dayNet=", DoubleToString(dayNet, 2),
            " monthNet=", DoubleToString(monthNet, 2),
            " symbols=", g_symbolCount,
            " lossStreakPause=", (lossBlock ? "ON" : "off"));
   }
}

void Reject(string sym, string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=", sym, " | reason=", reason);
}

//+------------------------------------------------------------------+
//| Prefilters                                                        |
//+------------------------------------------------------------------+
bool QuoteFresh(string sym)
{
   datetime qt = (datetime)MarketInfo(sym, MODE_TIME);
   if(qt <= 0) return(false);
   int age = (int)(TimeCurrent() - qt);
   return(age >= -5 && age <= InpMaxQuoteAgeSec);
}

bool SessionOK(string sym)
{
   if(!InpUseSessionFilter || IsCrypto(sym)) return(true);
   int h = TimeHour(TimeCurrent());
   if(InpSessionStartHour < InpSessionEndHour)
      return(h >= InpSessionStartHour && h < InpSessionEndHour);
   return(h >= InpSessionStartHour || h < InpSessionEndHour);
}

bool InRolloverWindow()
{
   datetime t = TimeCurrent();
   int m = TimeHour(t) * 60 + TimeMinute(t);
   if(InpRolloverStartMin > InpRolloverEndMin)
      return(m >= InpRolloverStartMin || m < InpRolloverEndMin);
   return(m >= InpRolloverStartMin && m < InpRolloverEndMin);
}

bool Prefilter(string sym, string &why)
{
   why = "";
   if(!IsTradeAllowed()) { why = "TERMINAL_TRADING_NOT_ALLOWED"; return(false); }
   if(InpBlockRollover && InRolloverWindow()) { why = "ROLLOVER_WINDOW"; return(false); }
   if(MarketInfo(sym, MODE_TRADEALLOWED) == 0) { why = "SYMBOL_TRADING_DISABLED"; return(false); }
   if(iBars(sym, InpSignalTF) < InpMinBars) { why = "INSUFFICIENT_HISTORY"; return(false); }
   if(!QuoteFresh(sym)) { why = "STALE_QUOTE"; return(false); }
   if(!SessionOK(sym)) { why = "OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetKey(sym))) { why = "POSITION_ALREADY_OPEN"; return(false); }
   if(InCooldown(sym)) { why = "COOLDOWN"; return(false); }
   if(SymbolExpectancyBad(sym)) { why = "NEGATIVE_EXPECTANCY_BAN"; return(false); }

   double bid = MarketInfo(sym, MODE_BID), ask = MarketInfo(sym, MODE_ASK), point = MarketInfo(sym, MODE_POINT);
   if(bid <= 0 || ask < bid || point <= 0) { why = "INVALID_QUOTE"; return(false); }
   if(InpMaxSpreadPoints > 0 && (ask - bid) / point > InpMaxSpreadPoints)
   { why = "SPREAD_POINTS_CAP"; return(false); }
   return(true);
}

//+------------------------------------------------------------------+
//| Signal: 4 families x variants, regime-aware                       |
//+------------------------------------------------------------------+
void Vote(bool buy, bool sell, int &b, int &s)
{
   if(buy && !sell) b++;
   else if(sell && !buy) s++;
}

int FamilyDir(int b, int s)
{
   if(b >= InpFamilyMinVotes && b > 2 * s) return(1);
   if(s >= InpFamilyMinVotes && s > 2 * b) return(-1);
   return(0);
}

bool Analyze(string sym, int &cmd, double &score, string &why)
{
   cmd = -1; score = 0.0; why = "";
   int tf = InpSignalTF;
   double c1 = iClose(sym, tf, 1), c2 = iClose(sym, tf, 2);
   double atr = iATR(sym, tf, InpATRPeriod, 1);
   double adx = iADX(sym, tf, 14, PRICE_CLOSE, MODE_MAIN, 1);
   double rsi14 = iRSI(sym, tf, 14, PRICE_CLOSE, 1);

   if(c1 <= 0 || c2 <= 0 || atr <= 0 || adx < 0 || rsi14 < 0)
   { why = "INDICATOR_DATA_INVALID"; return(false); }
   if(adx < InpMinADX) { why = "DEAD_MARKET_ADX"; return(false); }

   // Volatility regime filter
   double atrPct = (atr / c1) * 100.0;
   if(atrPct < InpMinATRPct) { why = "ATR_TOO_LOW"; return(false); }
   if(atrPct > InpMaxATRPct) { why = "ATR_TOO_HIGH"; return(false); }

   // Family 0: EMA stack
   int tb = 0, tsl = 0;
   int per[9] = {5, 8, 10, 13, 21, 34, 50, 89, 144};
   double ema[9];
   for(int e = 0; e < 9; e++)
   {
      ema[e] = iMA(sym, tf, per[e], 0, MODE_EMA, PRICE_CLOSE, 1);
      if(ema[e] <= 0) { why = "EMA_UNAVAILABLE"; return(false); }
   }
   for(int e2 = 0; e2 < 8; e2++)
      Vote(ema[e2] > ema[e2+1] && c1 > ema[e2],
           ema[e2] < ema[e2+1] && c1 < ema[e2], tb, tsl);

   // Family 1: RSI momentum
   int mb = 0, ms = 0;
   int rp[8] = {5, 7, 9, 11, 14, 18, 21, 28};
   for(int r = 0; r < 8; r++)
   {
      double rv = iRSI(sym, tf, rp[r], PRICE_CLOSE, 1);
      double rprev = iRSI(sym, tf, rp[r], PRICE_CLOSE, 2);
      Vote(rv > 52 && rv > rprev && rv < 75,
           rv < 48 && rv < rprev && rv > 25, mb, ms);
   }

   // Family 2: Donchian breakout
   int bb = 0, bs = 0;
   int lb[8] = {5, 7, 9, 12, 15, 18, 22, 30};
   for(int d = 0; d < 8; d++)
   {
      int hi = iHighest(sym, tf, MODE_HIGH, lb[d], 2);
      int lo = iLowest(sym, tf, MODE_LOW, lb[d], 2);
      double hh = (hi >= 0 ? iHigh(sym, tf, hi) : 0.0);
      double ll = (lo >= 0 ? iLow(sym, tf, lo) : 0.0);
      Vote(hh > 0 && c1 > hh && c1 > c2,
           ll > 0 && c1 < ll && c1 < c2, bb, bs);
   }

   // Family 3: Bollinger re-entry
   int rb = 0, rs = 0;
   int bp[8] = {8, 10, 12, 14, 18, 20, 24, 30};
   for(int m = 0; m < 8; m++)
   {
      double up = iBands(sym, tf, bp[m], 2.0, 0, PRICE_CLOSE, MODE_UPPER, 1);
      double lw = iBands(sym, tf, bp[m], 2.0, 0, PRICE_CLOSE, MODE_LOWER, 1);
      Vote(c2 < lw && c1 > lw && c1 > c2,
           c2 > up && c1 < up && c1 < c2, rb, rs);
   }

   int dT = FamilyDir(tb, tsl), dM = FamilyDir(mb, ms);
   int dB = FamilyDir(bb, bs), dR = FamilyDir(rb, rs);
   int dir = 0, agree = 0, win = 0;

   if(adx >= InpTrendADX)
   {
      int upF = 0, dnF = 0;
      if(dT > 0) upF++; else if(dT < 0) dnF++;
      if(dM > 0) upF++; else if(dM < 0) dnF++;
      if(dB > 0) upF++; else if(dB < 0) dnF++;

      if(upF >= 2 && dnF == 0 && dT > 0) { dir = 1;  agree = upF; win = tb + mb + bb; }
      else if(dnF >= 2 && upF == 0 && dT < 0) { dir = -1; agree = dnF; win = tsl + ms + bs; }
      else { why = "TREND_REGIME_NO_CONSENSUS"; return(false); }

      if(InpUseHTFFilter)
      {
         double hc = iClose(sym, InpHTF, 1);
         double he = iMA(sym, InpHTF, 50, 0, MODE_EMA, PRICE_CLOSE, 1);
         if(hc <= 0 || he <= 0) { why = "HTF_DATA_UNAVAILABLE"; return(false); }
         if((dir > 0 && hc <= he) || (dir < 0 && hc >= he))
         { why = "HTF_BIAS_AGAINST"; return(false); }
      }
   }
   else
   {
      // Range regime: mean-reversion only
      if(dR > 0 && rsi14 <= 38.0 && dM >= 0) { dir = 1;  agree = 1; win = rb; }
      else if(dR < 0 && rsi14 >= 62.0 && dM <= 0) { dir = -1; agree = 1; win = rs; }
      else { why = "RANGE_REGIME_NO_SETUP"; return(false); }
   }

   double stopRef = atr * InpStopATR;
   double costR = EntryCostR(sym, stopRef);
   // Score: consensus + votes + ADX bonus - cost penalty - extreme vol penalty
   score = 12.0 * agree + win + MathMin(adx, 45.0) / 3.5
           - 35.0 * MathMin(costR, 1.8)
           - (atrPct > 2.0 ? (atrPct - 2.0) * 4.0 : 0.0);

   cmd = (dir > 0 ? OP_BUY : OP_SELL);
   return(true);
}

//+------------------------------------------------------------------+
//| Cost helpers                                                      |
//+------------------------------------------------------------------+
double EntryCostR(string sym, double stopDist)
{
   double tv = MarketInfo(sym, MODE_TICKVALUE), ts = MarketInfo(sym, MODE_TICKSIZE);
   double bid = MarketInfo(sym, MODE_BID), ask = MarketInfo(sym, MODE_ASK);
   if(tv <= 0 || ts <= 0 || stopDist <= 0 || bid <= 0 || ask < bid) return(99.0);
   double stopPerLot = (stopDist / ts) * tv;
   double costPerLot = ((ask - bid) / ts) * tv + CommissionPerLot(sym);
   if(stopPerLot <= 0) return(99.0);
   return(costPerLot / stopPerLot);
}

//+------------------------------------------------------------------+
//| Order entry                                                       |
//+------------------------------------------------------------------+
bool OpenTrade(string sym, int cmd, double score)
{
   double bid = MarketInfo(sym, MODE_BID), ask = MarketInfo(sym, MODE_ASK);
   double point = MarketInfo(sym, MODE_POINT);
   int digits = (int)MarketInfo(sym, MODE_DIGITS);
   double atr = iATR(sym, InpSignalTF, InpATRPeriod, 1);

   if(bid <= 0 || ask < bid || point <= 0 || atr <= 0)
   { Reject(sym, "ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { Reject(sym, "STALE_QUOTE_AT_ENTRY"); return(false); }

   double spreadPrice = ask - bid;
   double brokerMin = (MathMax(MarketInfo(sym, MODE_STOPLEVEL),
                               MarketInfo(sym, MODE_FREEZELEVEL)) + 2.0) * point;
   double stopDist = MathMax(atr * InpStopATR, spreadPrice + brokerMin);
   double targetDist = MathMax(stopDist * InpRewardRisk, spreadPrice + brokerMin);

   if(spreadPrice > stopDist * InpMaxSpreadPctOfStop / 100.0)
   {
      if(InpLogRejects)
         Print("SPREAD_VS_STOP_REJECT | symbol=", sym,
               " spread=", DoubleToString(spreadPrice, digits),
               " stop=", DoubleToString(stopDist, digits));
      return(false);
   }

   double entry = (cmd == OP_BUY ? ask : bid);
   double sl = NormalizeDouble(cmd == OP_BUY ? entry - stopDist : entry + stopDist, digits);
   double tp = NormalizeDouble(cmd == OP_BUY ? entry + targetDist : entry - targetDist, digits);
   stopDist = MathAbs(entry - sl);

   bool ok = false;
   if(cmd == OP_BUY)
      ok = (sl > 0 && tp > 0 && sl < bid - brokerMin * 0.5 && tp > bid + brokerMin * 0.5);
   else
      ok = (sl > ask + brokerMin * 0.5 && tp > 0 && tp < ask - brokerMin * 0.5);
   if(!ok)
   {
      Print("STOP_PREFLIGHT_REJECT | symbol=", sym,
            " SL=", DoubleToString(sl, digits), " TP=", DoubleToString(tp, digits));
      return(false);
   }

   double costR = EntryCostR(sym, stopDist);
   if(costR > InpMaxCostR)
   {
      Print("COST_REJECT | symbol=", sym, " costR=", DoubleToString(costR, 3),
            " max=", DoubleToString(InpMaxCostR, 3));
      return(false);
   }

   // Risk budget
   double maxAgg = InpReferenceCapitalUSD * InpMaxAggregateRiskPct / 100.0;
   double openRisk = CurrentOpenRisk();
   double remaining = maxAgg - openRisk;
   double perTrade = InpReferenceCapitalUSD * InpRiskPctPerTrade / 100.0;
   if(remaining <= InpMinRiskMoney)
   {
      Print("RISK_REJECT | symbol=", sym, " reason=AGGREGATE_RISK_CAP",
            " open=", DoubleToString(openRisk, 2), " remaining=", DoubleToString(remaining, 2));
      return(false);
   }
   double budget = MathMin(perTrade, remaining);

   // Smart lot calculation (handles minLot better)
   double lots = LotsForRisk(sym, stopDist, budget);
   if(lots <= 0)
   {
      // Fallback: try with slightly higher budget if minLot is the problem
      double minLot = MarketInfo(sym, MODE_MINLOT);
      double riskAtMin = EstimateRisk(sym, minLot, stopDist);
      if(riskAtMin > 0 && riskAtMin <= budget * 1.35 && riskAtMin <= remaining)
      {
         lots = minLot;
         Print("LOT_FALLBACK | symbol=", sym, " using minLot=", DoubleToString(minLot, 2),
               " risk=", DoubleToString(riskAtMin, 2));
      }
      else
      {
         Print("RISK_REJECT | symbol=", sym, " reason=MIN_LOT_EXCEEDS_BUDGET",
               " budget=", DoubleToString(budget, 2), " minRisk=", DoubleToString(riskAtMin, 2));
         return(false);
      }
   }

   double risk = EstimateRisk(sym, lots, stopDist);

   if(!InpEnableTrading)
   {
      if(InpLogCandidates)
         Print("DRY_RUN | symbol=", sym, " side=", (cmd == OP_BUY ? "BUY" : "SELL"),
               " score=", DoubleToString(score, 1),
               " lots=", DoubleToString(lots, 2), " risk=", DoubleToString(risk, 2),
               " costR=", DoubleToString(costR, 3));
      return(false);
   }

   if(IsTradeContextBusy()) { Reject(sym, "TRADE_CONTEXT_BUSY"); return(false); }

   ResetLastError();
   int ticket = OrderSend(sym, cmd, lots, entry, InpSlippagePoints, sl, tp,
                          "Bitey Ens v" + EA_VERSION, InpMagic, 0, clrNONE);
   if(ticket < 0)
   {
      int err = GetLastError();
      Print("ORDER_REJECTED | symbol=", sym, " side=", (cmd == OP_BUY ? "BUY" : "SELL"),
            " error=", err, " lots=", DoubleToString(lots, 2));
      return(false);
   }

   Print("ORDER_ACCEPTED | ticket=", ticket, " symbol=", sym,
         " side=", (cmd == OP_BUY ? "BUY" : "SELL"),
         " lots=", DoubleToString(lots, 2), " risk=", DoubleToString(risk, 2),
         " costR=", DoubleToString(costR, 3), " score=", DoubleToString(score, 1),
         " SL=", DoubleToString(sl, digits), " TP=", DoubleToString(tp, digits));
   return(true);
}

//+------------------------------------------------------------------+
//| Exit management                                                   |
//+------------------------------------------------------------------+
bool CloseTicket(int ticket, string reason)
{
   if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES) || OrderCloseTime() > 0)
      return(false);
   string sym = OrderSymbol();
   int type = OrderType();
   double lots = OrderLots();
   double px = (type == OP_BUY ? MarketInfo(sym, MODE_BID) : MarketInfo(sym, MODE_ASK));
   int digits = (int)MarketInfo(sym, MODE_DIGITS);
   if(px <= 0) return(false);
   double net = OrderProfit() + OrderSwap() + OrderCommission();
   ResetLastError();
   bool ok = OrderClose(ticket, lots, NormalizeDouble(px, digits), InpSlippagePoints, clrNONE);
   Print("CLOSE | reason=", reason, " ticket=", ticket, " symbol=", sym,
         " net=", DoubleToString(net, 2), " ok=", (ok ? "true" : "false"),
         " error=", (ok ? 0 : GetLastError()));
   return(ok);
}

void ManageExits()
{
   bool rollover = (InpFlatBeforeRollover && InRolloverWindow());
   for(int pos = OrdersTotal() - 1; pos >= 0; pos--)
   {
      if(!OrderSelect(pos, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      int type = OrderType();
      if(type != OP_BUY && type != OP_SELL) continue;

      int ticket = OrderTicket();
      string sym = OrderSymbol();
      double point = MarketInfo(sym, MODE_POINT);
      double bid = MarketInfo(sym, MODE_BID), ask = MarketInfo(sym, MODE_ASK);
      if(point <= 0 || bid <= 0 || ask <= 0) continue;
      int digits = (int)MarketInfo(sym, MODE_DIGITS);
      double entry = OrderOpenPrice(), oldSL = OrderStopLoss(), oldTP = OrderTakeProfit();
      double lots = OrderLots();
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      double atr = iATR(sym, InpSignalTF, InpATRPeriod, 1);

      if(rollover) { CloseTicket(ticket, "ROLLOVER_FLAT"); continue; }
      if(InpMaxHoldBars > 0)
      {
         int barsOpen = iBarShift(sym, InpSignalTF, OrderOpenTime(), false);
         if(barsOpen >= InpMaxHoldBars) { CloseTicket(ticket, "TIME_EXIT"); continue; }
      }
      if(atr <= 0) continue;

      if(InpNetTargetR > 0.0)
      {
         double refRisk = EstimateRisk(sym, lots, atr * InpStopATR);
         if(refRisk < 1.0e11 && net >= InpNetTargetR * refRisk)
         { CloseTicket(ticket, "NET_TARGET_R"); continue; }
      }
      if(!InpEnableAdaptiveExits) continue;

      double minDist = (MarketInfo(sym, MODE_STOPLEVEL) + MarketInfo(sym, MODE_FREEZELEVEL) + 2.0) * point;
      double price = (type == OP_BUY ? bid : ask);
      double favorable = (type == OP_BUY ? price - entry : entry - price);
      double newSL = oldSL, newTP = oldTP;

      // Commission-aware break-even
      double tvv = MarketInfo(sym, MODE_TICKVALUE), tss = MarketInfo(sym, MODE_TICKSIZE);
      double commPrice = (tvv > 0 && tss > 0 ? CommissionPerLot(sym) * tss / tvv : 0.0);

      if(InpBreakEvenTriggerATR > 0 && favorable >= atr * InpBreakEvenTriggerATR)
      {
         double lockDist = atr * InpBreakEvenLockATR + commPrice;
         double be = (type == OP_BUY ? entry + lockDist : entry - lockDist);
         if(type == OP_BUY  && (newSL <= 0 || be > newSL) && be < bid - minDist) newSL = be;
         if(type == OP_SELL && (newSL <= 0 || be < newSL) && be > ask + minDist) newSL = be;
      }

      // ATR trailing
      if(InpTrailStartATR > 0 && InpTrailDistanceATR > 0 && favorable >= atr * InpTrailStartATR)
      {
         double tr = (type == OP_BUY ? bid - atr * InpTrailDistanceATR
                                     : ask + atr * InpTrailDistanceATR);
         if(type == OP_BUY  && tr > newSL + atr * InpTrailStepATR && tr < bid - minDist) newSL = tr;
         if(type == OP_SELL && (newSL <= 0 || tr < newSL - atr * InpTrailStepATR) && tr > ask + minDist) newSL = tr;
      }
      newSL = (newSL > 0 ? NormalizeDouble(newSL, digits) : 0);

      bool slUp = false;
      if(type == OP_BUY)  slUp = (newSL > 0 && (oldSL <= 0 || newSL > oldSL + point * 0.5));
      else                slUp = (newSL > 0 && (oldSL <= 0 || newSL < oldSL - point * 0.5));

      // Adaptive TP expansion
      double adx = iADX(sym, InpSignalTF, 14, PRICE_CLOSE, MODE_MAIN, 1);
      bool tpUp = false;
      if(oldTP > 0 && favorable >= atr * InpTPExpandTriggerATR && adx >= InpTPExpandADXMin)
      {
         double remainingToTP = (type == OP_BUY ? oldTP - bid : ask - oldTP);
         if(remainingToTP <= atr * InpTPExpandBufferATR)
         {
            double curDist = MathAbs(oldTP - entry);
            double want = MathMin(atr * InpTPMaxDistanceATR,
                                  MathMax(curDist, favorable + atr * InpTPExpandBufferATR));
            double prop = NormalizeDouble(type == OP_BUY ? entry + want : entry - want, digits);
            if(type == OP_BUY  && prop > oldTP + atr * InpTPExpandStepATR) { newTP = prop; tpUp = true; }
            if(type == OP_SELL && prop < oldTP - atr * InpTPExpandStepATR) { newTP = prop; tpUp = true; }
         }
      }

      if(slUp || tpUp)
      {
         ResetLastError();
         bool mod = OrderModify(ticket, entry,
                                (slUp ? newSL : oldSL),
                                (tpUp ? newTP : oldTP), 0, clrNONE);
         if(mod)
            Print("ADAPTIVE_MODIFY | ticket=", ticket, " symbol=", sym,
                  " SL ", DoubleToString(oldSL, digits), "->", DoubleToString(slUp ? newSL : oldSL, digits),
                  " TP ", DoubleToString(oldTP, digits), "->", DoubleToString(tpUp ? newTP : oldTP, digits));
      }
   }
}

//+------------------------------------------------------------------+
//| Position & risk helpers                                           |
//+------------------------------------------------------------------+
int CountOpenPositions()
{
   int cnt = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderType() == OP_BUY || OrderType() == OP_SELL) cnt++;
   }
   return(cnt);
}

bool HasPositionForKey(string key)
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderType() > OP_SELL) continue;
      if(AssetKey(OrderSymbol()) == key) return(true);
   }
   return(false);
}

bool InCooldown(string sym)
{
   datetime lastClose = 0;
   double lastNet = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic || OrderSymbol() != sym) continue;
      if(OrderType() > OP_SELL) continue;
      if(OrderCloseTime() > lastClose)
      {
         lastClose = OrderCloseTime();
         lastNet = OrderProfit() + OrderSwap() + OrderCommission();
      }
      break;
   }
   if(lastClose <= 0) return(false);
   int bars = iBarShift(sym, InpSignalTF, lastClose, false);
   if(lastNet < 0) return(bars < InpCooldownBars);
   return(bars < InpReentryBars);
}

double TodayNet()
{
   double sum = 0;
   datetime dayStart = iTime(Symbol(), PERIOD_D1, 0);
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderCloseTime() < dayStart) break;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   // Add floating
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(sum);
}

double MonthNet()
{
   double sum = 0;
   datetime now = TimeCurrent();
   int y = TimeYear(now), m = TimeMonth(now);
   for(int i = OrdersHistoryTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      datetime ct = OrderCloseTime();
      if(TimeYear(ct) != y || TimeMonth(ct) != m) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   for(int j = OrdersTotal() - 1; j >= 0; j--)
   {
      if(!OrderSelect(j, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   return(sum);
}

double CurrentOpenRisk()
{
   double risk = 0;
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != InpMagic) continue;
      if(OrderType() > OP_SELL) continue;
      string sym = OrderSymbol();
      double atr = iATR(sym, InpSignalTF, InpATRPeriod, 1);
      if(atr <= 0) continue;
      double stopDist = atr * InpStopATR;
      if(OrderStopLoss() > 0)
         stopDist = MathAbs(OrderOpenPrice() - OrderStopLoss());
      risk += EstimateRisk(sym, OrderLots(), stopDist);
   }
   return(risk);
}

bool LossStreakBlock()
{
   if(InpMaxConsecLosses <= 0) return(false);
   int streak = 0;
   datetime newest = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && streak < InpMaxConsecLosses + 2; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic || OrderType() > OP_SELL) continue;
      double net = OrderProfit() + OrderSwap() + OrderCommission();
      if(net < 0)
      {
         streak++;
         if(OrderCloseTime() > newest) newest = OrderCloseTime();
      }
      else break;
   }
   if(streak < InpMaxConsecLosses) return(false);
   return((TimeCurrent() - newest) < InpLossStreakPauseMin * 60);
}

bool SymbolExpectancyBad(string sym)
{
   if(InpExpectancyWindow <= 0 || InpExpectancyMinTrades <= 0) return(false);
   int cnt = 0, seen = 0;
   double sum = 0.0;
   datetime last = 0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && seen < 400 && cnt < InpExpectancyWindow; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber() != InpMagic || OrderSymbol() != sym || OrderType() > OP_SELL) continue;
      cnt++;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
      if(OrderCloseTime() > last) last = OrderCloseTime();
   }
   if(cnt < InpExpectancyMinTrades || sum >= 0.0) return(false);
   return((TimeCurrent() - last) < InpExpectancyBanHours * 3600);
}

bool SymbolExpectancySoftPenalty(string sym)
{
   if(InpExpectancyWindow <= 0) return(false);
   int cnt = 0;
   double sum = 0.0;
   for(int i = OrdersHistoryTotal() - 1; i >= 0 && cnt < InpExpectancyWindow; i--)
   {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      if(OrderMagicNumber() != InpMagic || OrderSymbol() != sym || OrderType() > OP_SELL) continue;
      cnt++;
      sum += OrderProfit() + OrderSwap() + OrderCommission();
   }
   if(cnt < InpExpectancyMinTrades) return(false);
   double avg = sum / cnt;
   return(avg < InpExpectancySoftThreshold);
}

//+------------------------------------------------------------------+
//| Sizing                                                            |
//+------------------------------------------------------------------+
double EstimateRisk(string sym, double lots, double stopDist)
{
   double tv = MarketInfo(sym, MODE_TICKVALUE), ts = MarketInfo(sym, MODE_TICKSIZE);
   if(tv <= 0 || ts <= 0 || lots <= 0 || stopDist <= 0) return(1.0e12);
   return(((stopDist / ts) * tv + CommissionPerLot(sym)) * lots);
}

int LotDigits(double step)
{
   if(step >= 1.0) return(0);
   if(step >= 0.1) return(1);
   if(step >= 0.01) return(2);
   return(3);
}

double LotsForRisk(string sym, double stopDist, double riskMoney)
{
   double tv = MarketInfo(sym, MODE_TICKVALUE), ts = MarketInfo(sym, MODE_TICKSIZE);
   double minLot = MarketInfo(sym, MODE_MINLOT);
   double maxLot = MarketInfo(sym, MODE_MAXLOT);
   double step = MarketInfo(sym, MODE_LOTSTEP);
   if(riskMoney <= 0 || tv <= 0 || ts <= 0 || stopDist <= 0 ||
      minLot <= 0 || maxLot < minLot || step <= 0) return(0.0);

   double lossPerLot = (stopDist / ts) * tv + CommissionPerLot(sym);
   if(lossPerLot <= 0) return(0.0);

   double lots = MathFloor(riskMoney / lossPerLot / step + 1e-9) * step;
   lots = MathMin(lots, maxLot);
   lots = MathMin(lots, LotCap(sym));
   lots = MathFloor(lots / step + 1e-9) * step;
   lots = NormalizeDouble(lots, LotDigits(step));

   if(lots < minLot) return(0.0);
   if(EstimateRisk(sym, lots, stopDist) > riskMoney + 0.05) return(0.0);
   return(lots);
}
//+------------------------------------------------------------------+
