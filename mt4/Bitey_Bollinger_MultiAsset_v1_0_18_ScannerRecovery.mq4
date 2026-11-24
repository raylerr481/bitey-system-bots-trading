//+------------------------------------------------------------------+
//| Bitey_Bollinger_MultiAsset_v1_0_18_ScannerRecovery.mq4                  |
//| Multi-asset MT4 EA: Bollinger rebound + Bollinger breakout        |
//| News selector imported conceptually from Bitey Scalper v1.5.62   |
//| News mode is SHADOW ONLY: SCOUT entries are never vetoed.         |
//| No EMA, RSI, MACD, ADX or other indicator is used for signals.     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.180"
#property description "v1.0.18: adaptive crypto quote freshness, quote reinitialization, wider M5 signal-entry window; preserves v1.0.17 daily bank and risk controls."

#define EA_NAME "Bitey_Bollinger_MultiAsset"
#define EA_VER  "1.0.18-SCANNER-RECOVERY"
#define NEWS_MAX_ROWS 300

//--- Universe / scanner
input bool             InpScanMarketWatch       = false;      // false = discover broker symbols; true = Market Watch only
input string           InpSymbolsCSV            = "";         // Optional explicit override; blank = discovered universe
input int              InpMaxSymbols            = 0;           // 0 = ALL broker-listed symbols; >0 = explicit safety cap
input int              InpUniverseRefreshSeconds= 300;         // Re-discover broker universe every N seconds
input int              InpScanIntervalSeconds   = 5;
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input int              InpMinBars               = 250;
input int              InpMaxQuoteAgeSec        = 120;      // Max age for non-crypto quotes
input int              InpCryptoMaxQuoteAgeSec  = 180;      // Crypto freshness allowance; stale/dead prices remain rejected
input bool             InpCryptoExpected24x7    = true;       // Calendar expectation only; live quote/trade permission still required
input bool             InpLogScannerDiagnostics = true;
input int              InpSkipLogThrottleMin    = 30;         // Re-log the same SCAN_SKIP reason for a symbol at most every N minutes
input int              InpDeadQuoteAgeSec       = 86400;      // Quote older than this = dead/delisted symbol -> quarantine
input int              InpDeadRecheckSec        = 600;        // Quarantined symbols are re-checked every N seconds
input int              InpHealthLogMinutes      = 10;         // Scanner health summary interval

//--- Bollinger Bands: the ONLY signal indicator
input int              InpBBPeriod              = 20;
input double           InpBBDeviation           = 2.0;
input ENUM_APPLIED_PRICE InpBBPrice              = PRICE_CLOSE;
input bool             InpEnableRebound         = true;
input bool             InpEnableBreakout        = true;
input bool             InpRequireCandleDirection= true;       // Rejection candle direction for rebound
input int              InpEntryWindowSeconds    = 180;        // M5: process closed-bar signal during first 3 minutes

//--- Adaptive exits. ATR is used ONLY for stop/target sizing and trailing, never for entry signals.
input int              InpATRPeriod             = 14;
input double           InpSL_ATR                = 1.50;
input double           InpMinSL_ATR             = 0.80;
input double           InpMaxSL_ATR             = 3.00;
input bool             InpBreakEvenEnabled      = true;
input double           InpBreakEvenAtR          = 1.00;
input double           InpBreakEvenLockR        = 0.10;
input bool             InpTrailingEnabled       = true;
input double           InpTrailStartR           = 1.50;
input double           InpTrailDistanceATR      = 1.00;
input int              InpModifyThrottleSec     = 5;

//--- Risk and execution
input double           InpNetLossBufferUSD       = 0.40;        // Loss guard: allowed adverse price move (USD) BEYOND all costs (commission + spread + other). 0 = guard off
input double           InpLossGuardRiskFrac      = 0.45;        // Adaptive buffer: this share of the trade's SL risk (USD) is also allowed beyond costs. 0 = fixed buffer only
input double           InpLossGuardMaxBufferUSD  = 1.00;        // Upper clamp for the adaptive buffer (USD beyond costs)
input double           InpLossGuardFloorUSD      = 0.00;        // Optional: never close for loss before the true net loss reaches this (e.g. 0.90). 0 = off
input int              InpLossGuardGraceSec      = 90;          // Do not evaluate the loss guard during the first N seconds after opening
input double           InpOtherCloseCostsPerLotUSD = 0.0;       // Estimated taxes/other close fees per lot when not already in OrderCommission()
input bool             InpPeakLockEnabled        = true;        // Ratchet SL to lock a growing share of the best profit reached
input double           InpPeakLockStartR         = 0.80;        // Start once the best excursion reached this many R
input double           InpPeakLockMinFrac        = 0.40;        // Share of the best excursion locked at StartR
input double           InpPeakLockSlope          = 0.20;        // Extra share locked per additional R of best excursion
input double           InpPeakLockMaxFrac        = 0.75;        // Cap on the locked share
input int              InpMaxEntriesPerHour      = 3;           // Max NEW scout entries per rolling hour (0 = off)
input bool             InpSessionFilterEnabled   = true;        // Non-crypto symbols only trade inside the server-time window below
input int              InpSessionStartHour       = 10;          // Server hour (broker time = PC time + 5h here): ~London open
input int              InpSessionEndHour         = 22;          // Server hour (exclusive): ~NY afternoon
input bool             InpCryptoSessionFilter    = false;       // Also apply the window to crypto symbols
input bool             InpShortsNeedBearishRegime= true;        // SELL signals (incl. rebounds) need H1 close below H1 midline
input int              InpStreakScaleAfter       = 2;           // After N consecutive losses, scale new-entry risk
input double           InpStreakRiskScale        = 0.50;        // Risk multiplier while the loss streak lasts (1 = off)
input int              InpSymbolDayLossLimit     = 2;           // Losses on one symbol in a server day before it is blocked for the day (0 = off)
input double           InpMinTrailStepATR        = 0.10;        // Minimum SL improvement (in ATR) per modify, except the first move to break-even
input double           InpStrategicCapitalUSD   = 500.0;       // Fixed strategy capital; account must be USD
input double           InpRiskPercent           = 0.50;        // 0.5% of strategic capital = USD 2.50
input double           InpRiskUSDOverride       = 0.0;         // Optional fixed USD risk; capped by strategic risk
input double           InpMaxAggregateRiskPct   = 2.50;        // 2.5% of strategic capital = USD 12.50
input double           InpMaxMarginUsePctFree   = 20.0;        // Max margin consumed by new position vs current free margin
input double           InpMinAdaptiveTP_R       = 1.30;
input double           InpTPWidthLowATR         = 1.50;        // BB width / ATR at or below this -> TP = InpMinAdaptiveTP_R
input double           InpTPWidthHighATR        = 4.00;        // BB width / ATR at or above this -> TP = InpMaxAdaptiveTP_R
input double           InpMaxAdaptiveTP_R       = 1.80;
input double           InpSLStructureBufferATR   = 0.25;        // Buffer beyond signal candle extreme
input int              InpMaxOpenPositions      = 5;            // Cap on SCOUT positions only; add-ons do not consume these slots
input int              InpMaxPositionsPerSymbol = 1;
input double           InpMaxSpreadPoints       = 100.0;
input double           InpMaxSpreadPctOfSL      = 20.0;
input int              InpSlippagePoints        = 30;
input int              InpMagic                 = 26112201;
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- v1.0.7 loss control (all gates only block NEW entries; open positions are always managed)
input bool             InpCooldownEnabled       = true;         // After a losing close, wait before re-entering the same symbol
input int              InpCooldownMinutes       = 45;
input bool             InpCooldownBlocksBothSides = false;      // false = only the same direction as the loss; true = whole symbol
input double           InpCooldownMinLossUSD    = 0.50;         // Net loss (incl. commission) that counts as a "loss"; smaller = near-breakeven, ignored
input int              InpHistLookbackHours     = 36;           // How far back closed trades are read for cooldown/breakers
input int              InpMaxConsecLosses       = 4;            // Pause new entries after N consecutive losses (0 = off)
input int              InpConsecLossPauseMin    = 60;
input double           InpSoftDailyLossUSD      = 3.0;          // Soft cap: when the day's realized net <= -USD, pause new entries for InpSoftLossPauseMin after each loss (0 = off)
input int              InpSoftLossPauseMin      = 120;
input double           InpMaxDailyLossUSD       = 5.0;          // Hard cap: stop new entries for the rest of the server day when realized net <= -USD (0 = off)
input bool             InpRegimeFilterEnabled   = true;         // Breakouts must agree with the regime-TF Bollinger midline
input ENUM_TIMEFRAMES  InpRegimeTF              = PERIOD_H1;
input bool             InpCostFilterEnabled     = true;         // Skip trades where spread + commission eat too much of the risk
input double           InpMaxCostPctOfRisk      = 25.0;
input double           InpCommissionPerLotUSD   = 10.0;         // Round-trip, FX/CFD (statement: 0.02 lot = 0.20)
input double           InpCommissionStablePerLotUSD = 15.0;     // Round-trip, crypto / *USDT CFDs (statement: 0.01 lot = 0.15)
input int              InpQuarantineMinutes     = 360;          // Symbol quarantine after order error 133 / 132
input int              InpEntrySkipLogThrottleMin = 15;         // Throttle repeated ENTRY_SKIP / regime logs per symbol+reason
input int              InpMaxPerCurrencyDir     = 2;            // Max open positions long (or short) the same FX currency (0 = off)
input bool             InpBlockUnderlyingDup    = true;         // Only one open position per underlying (SOLUSD/SOLUSDT/SOLUSDT.p = one)
input bool             InpBELockCoversCosts     = true;         // Break-even stop locks at least commission (+spread on sells)

//--- v1.0.17 daily profit bank. Day = server day. dayNet = realized net (incl. commission/swap) + floating net of this EA.
input bool             InpDailyBankEnabled      = true;
input double           InpDailyTargetUSD        = 1.50;        // Day net (USD) at which the day counts as "won"
input bool             InpDailyHaltAtTarget     = true;        // true = close everything and stop trading the rest of the day at target; false = keep trading with a give-back lock
input double           InpDailyGiveBackPct      = 40.0;        // (HaltAtTarget=false) after target, close all if dayNet falls this % below the day's peak
input double           InpDailyLockFloorUSD     = 0.50;        // (HaltAtTarget=false) the lock never sits below this day net
input int              InpDailyEndBankHour      = 22;          // Server hour from which a green day is banked (close all, stop). 0 = off
input double           InpDailyEndBankMinUSD    = 0.30;        // Minimum day net to bank at InpDailyEndBankHour


//--- Funded leverage add-ons: a same-direction add-on is opened on a new Bollinger signal ONLY when the
//--- scout's SL already sits beyond break-even. Add-on risk <= InpAddOnFundPct% of the profit that SL locks,
//--- so if both stops hit the symbol still nets >= 0. Add-on risk is also capped by the normal per-trade
//--- risk and still counts against the absolute aggregate risk cap.
input bool             InpAddOnEnabled          = true;
input double           InpAddOnFundPct          = 100.0;       // % of locked profit the add-on may risk (<=100)
input int              InpMaxAddOnsPerSymbol    = 1;
input double           InpAddOnMinLockedUSD     = 0.10;        // Minimum locked profit before an add-on is allowed
input double           InpAddOnMinScoutR        = 1.00;        // Safety: the scout must have reached at least this R
input int              InpMaxAddOnsTotal        = 5;           // Safety: max simultaneous add-ons across all symbols (separate from the scout cap)
input double           InpAddOnSLScale          = 1.00;        // Multiplier on the add-on's own adaptive SL distance (0.5-2.0)
input double           InpAddOnTPScale          = 1.00;        // Multiplier on the add-on's own adaptive TP distance (0.5-3.0)
input bool             InpAddOnNewsVeto         = true;        // Add-ons (never scouts) are skipped inside a news event window

//--- News guard copied from v1.5.62 file contract. SHADOW ONLY by design.
input bool             InpNewsGuardEnabled      = true;
input bool             InpNewsGuardShadowOnly   = true;        // Must remain true in this release
input string           InpNewsFileName          = "bitey_news_guard.csv";
input bool             InpNewsUseCommonFolder   = true;
input int              InpNewsFileMaxAgeMin     = 30;
input bool             InpNewsUsdAffectsUsdt    = true;
input int              InpNewsLogThrottleMin    = 15;
input int              InpNewsPreProtectLeadMin  = 5;
input int              InpNewsPostProtectMin     = 3;
input double           InpNewsProtectMinNetUSD   = 0.10;
input double           InpNewsProtectKeepPct     = 75.0;

//--- State
string   g_symbols[];
datetime g_lastSignalBar[];
datetime g_lastModify[];
int      g_symbolCount=0;
// Dynamic snapshots preserve per-symbol state during unlimited universe rebuilds.
string   g_oldSymbols[];
datetime g_oldBars[];
datetime g_oldModify[];
datetime g_deadUntil[];
datetime g_skipLogTime[];
string   g_skipReason[];
string   g_oldSkipReason[];
datetime g_oldDead[];
datetime g_oldSkipTime[];
int      g_lastQuoteAge=-1;
datetime g_lastHealthLog=0;
datetime g_lastScan=0;
datetime g_lastUniverseRefresh=0;
datetime g_newsLastLoad=0;
datetime g_newsLastStateLog=0;
datetime g_newsUpdated=0;
bool     g_newsFileOk=false;
int      g_newsCount=0;
string   g_newsScope[NEWS_MAX_ROWS];
string   g_newsKey[NEWS_MAX_ROWS];
datetime g_newsFrom[NEWS_MAX_ROWS];
datetime g_newsUntil[NEWS_MAX_ROWS];
datetime g_newsEvent[NEWS_MAX_ROWS];
string   g_newsReason[NEWS_MAX_ROWS];
string   g_newsLogSymbol[NEWS_MAX_ROWS];
datetime g_newsLogTime[NEWS_MAX_ROWS];
int      g_newsLogCount=0;

//+------------------------------------------------------------------+
string Upper(string value)
{
   StringToUpper(value);
   return(value);
}

// Stablecoin quote detection. Requires position>=2 so forex pairs such as USDCAD, USDCHF,
// USDCNH and USDTRY (which START with USDC/USDT) are NOT mistaken for crypto.
bool HasStableQuote(string s)
{
   string q[]={"USDT","USDC","BUSD","FDUSD"};
   for(int i=0;i<ArraySize(q);i++)
   {
      int p=StringFind(s,q[i]);
      if(p>=2) return(true);
   }
   return(false);
}

// Stock / commodity CFDs quoted against a stablecoin (NFLXUSDT, TXNUSDT, CSCOUSDT, NATGASUSDT...).
// They follow exchange hours, so they are NOT 24/7 crypto and get no crypto priority.
bool IsStockOrCommodityToken(string s)
{
   string b[]={"AAPL","MSFT","AMZN","GOOGL","GOOG","META","TSLA","NVDA","AMD","INTC","NFLX","TXN","CSCO","BABA","PYPL","UBER","DIS","KO","PEP","NKE","JPM","BAC","WMT","XOM","CVX","PFE","ORCL","IBM","QCOM","AVGO","ADBE","CRM","COIN","MSTR","PLTR","SNAP","SHOP","ABNB","BA","GE","GS","MCD","SBUX","VZ","UNH","JNJ","PG","HD","LLY","ARM","SMCI","MU","TSM","NATGAS","XAU","XAG","XPT","XPD","USOIL","UKOIL","BRENT","WTI","OIL","COPPER","CORN","WHEAT","SOYBEAN","COFFEE","SUGAR","COCOA","COTTON"};
   for(int i=0;i<ArraySize(b);i++)
   {
      if(StringFind(s,b[i])!=0) continue;
      string rest=StringSubstr(s,StringLen(b[i]));
      if(StringFind(rest,"USDT")==0 || StringFind(rest,"USDC")==0) return(true);
   }
   return(false);
}

bool IsCryptoSymbol(string symbol)
{
   string s=Upper(symbol);
   // Strip common leading decorations (#BTCUSD, .BTCUSD).
   while(StringLen(s)>0 && !((StringGetCharacter(s,0)>='A' && StringGetCharacter(s,0)<='Z') ||
                             (StringGetCharacter(s,0)>='0' && StringGetCharacter(s,0)<='9')))
      s=StringSubstr(s,1);
   if(s=="") return(false);
   if(IsStockOrCommodityToken(s)) return(false);
   if(HasStableQuote(s)) return(true);
   string bases[]={"BTC","XBT","ETH","XRP","LTC","BCH","ADA","DOT","SOL","DOGE","AVAX","LINK","XLM","TRX","TON","BNB","SHIB","UNI","AAVE","ETC","EOS","FIL","ATOM","NEAR","ALGO","VET","SAND","MANA","AXS","ICP","OP","ARB","APT","SUI","PEPE","FLOKI","INJ","HBAR","XTZ","EGLD","THETA","FTM","MATIC","POL","CRV","COMP","SNX","MKR","ZEC","DASH","XMR","TRUMP","LDO","RUNE","KAS","TIA","SEI","WIF","BONK","JUP"};
   // A base only counts when what follows is a recognised quote currency, a separator or nothing.
   // This stops OP/UNI/SAND/COMP/SEI/ARB etc. from matching unrelated tickers (SANDP500, COMPASS...).
   string quotes[]={"USD","EUR","GBP","JPY","AUD","CAD","CHF","BTC","ETH","BRL","TRY"};
   for(int i=0;i<ArraySize(bases);i++)
   {
      if(StringFind(s,bases[i])!=0) continue;
      string rest=StringSubstr(s,StringLen(bases[i]));
      if(rest=="") return(true);
      ushort c=StringGetCharacter(rest,0);
      if(c=='.' || c=='/' || c=='-' || c=='_' || c=='#') return(true);
      for(int k=0;k<ArraySize(quotes);k++)
         if(StringFind(rest,quotes[k])==0) return(true);
   }
   return(false);
}

bool AddSymbol(string symbol)
{
   StringTrimLeft(symbol); StringTrimRight(symbol);
   if(symbol=="") return(false);
   for(int i=0;i<g_symbolCount;i++) if(g_symbols[i]==symbol) return(true);
   if(InpMaxSymbols>0 && g_symbolCount>=InpMaxSymbols) return(false);
   if(!SymbolSelect(symbol,true)) return(false);
   int next=g_symbolCount+1;
   if(ArrayResize(g_symbols,next)<next || ArrayResize(g_lastSignalBar,next)<next ||
      ArrayResize(g_lastModify,next)<next || ArrayResize(g_deadUntil,next)<next ||
      ArrayResize(g_skipLogTime,next)<next || ArrayResize(g_skipReason,next)<next)
   {
      ArrayResize(g_symbols,g_symbolCount);
      ArrayResize(g_lastSignalBar,g_symbolCount);
      ArrayResize(g_lastModify,g_symbolCount);
      ArrayResize(g_deadUntil,g_symbolCount);
      ArrayResize(g_skipLogTime,g_symbolCount);
      ArrayResize(g_skipReason,g_symbolCount);
      return(false);
   }
   g_symbols[g_symbolCount]=symbol;
   g_lastSignalBar[g_symbolCount]=0;
   g_lastModify[g_symbolCount]=0;
   g_deadUntil[g_symbolCount]=0;
   g_skipLogTime[g_symbolCount]=0;
   g_skipReason[g_symbolCount]="";
   g_symbolCount++;
   return(true);
}

void BuildUniverse()
{
   // Snapshot prior per-symbol state before rebuilding the dynamic arrays.
   int oldCount=g_symbolCount;
   if(ArrayResize(g_oldSymbols,oldCount)<oldCount ||
      ArrayResize(g_oldBars,oldCount)<oldCount ||
      ArrayResize(g_oldModify,oldCount)<oldCount ||
      ArrayResize(g_oldDead,oldCount)<oldCount ||
      ArrayResize(g_oldSkipTime,oldCount)<oldCount ||
      ArrayResize(g_oldSkipReason,oldCount)<oldCount)
   {
      Print("SCANNER_REFRESH_ABORT | reason=STATE_SNAPSHOT_ALLOCATION_FAILED");
      return;
   }
   for(int k=0;k<oldCount;k++)
   {
      g_oldSymbols[k]=g_symbols[k];
      g_oldBars[k]=g_lastSignalBar[k];
      g_oldModify[k]=g_lastModify[k];
      g_oldDead[k]=g_deadUntil[k];
      g_oldSkipTime[k]=g_skipLogTime[k];
      g_oldSkipReason[k]=g_skipReason[k];
   }

   int brokerTotal=0, selected=0, rejected=0;
   bool explicitList=(StringLen(InpSymbolsCSV)>0);
   bool marketWatchOnly=(!explicitList && InpScanMarketWatch);
   string discovered[];
   if(explicitList)
      brokerTotal=StringSplit(InpSymbolsCSV,StringGetCharacter(",",0),discovered);
   else
   {
      // Enumerate the complete symbol catalog exposed by the connected server.
      brokerTotal=SymbolsTotal(marketWatchOnly);
      if(ArrayResize(discovered,brokerTotal)<brokerTotal)
      {
         Print("SCANNER_REFRESH_ABORT | reason=DISCOVERY_ALLOCATION_FAILED listed=",brokerTotal);
         return;
      }
      for(int i=0;i<brokerTotal;i++) discovered[i]=SymbolName(i,marketWatchOnly);
   }

   // Only clear the live universe after discovery memory has been allocated.
   g_symbolCount=0;
   ArrayResize(g_symbols,0);
   ArrayResize(g_lastSignalBar,0);
   ArrayResize(g_lastModify,0);
   ArrayResize(g_deadUntil,0);
   ArrayResize(g_skipLogTime,0);
   ArrayResize(g_skipReason,0);

   // Two passes: crypto instruments first, then every remaining broker symbol.
   // This prevents a long FX list from consuming a finite user cap before crypto.
   int cap=(InpMaxSymbols<=0 ? brokerTotal : MathMin(brokerTotal,InpMaxSymbols));
   for(int pass=0;pass<2 && g_symbolCount<cap;pass++)
   {
      for(int i=0;i<brokerTotal && g_symbolCount<cap;i++)
      {
         string s=discovered[i];
         if(s=="") { rejected++; continue; }
         bool crypto=IsCryptoSymbol(s);
         if((pass==0 && !crypto) || (pass==1 && crypto)) continue;
         int before=g_symbolCount;
         if(AddSymbol(s)) { if(g_symbolCount>before) selected++; }
         else rejected++;
      }
   }

   // Restore state for symbols that survived the refresh.
   for(int n=0;n<g_symbolCount;n++)
   {
      for(int j=0;j<oldCount;j++)
      {
         if(g_symbols[n]==g_oldSymbols[j])
         {
            g_lastSignalBar[n]=g_oldBars[j];
            g_lastModify[n]=g_oldModify[j];
            g_deadUntil[n]=g_oldDead[j];
            g_skipLogTime[n]=g_oldSkipTime[j];
            g_skipReason[n]=g_oldSkipReason[j];
            break;
         }
      }
   }
   g_lastUniverseRefresh=TimeCurrent();
   Print("SCANNER_UNIVERSE_REFRESH | symbols=",g_symbolCount,
         " brokerListed=",brokerTotal,
         " cryptoFirst=true",
         " newlySelected=",selected,
         " rejectedOrDuplicate=",rejected,
         " cap=",(InpMaxSymbols<=0?"ALL":IntegerToString(InpMaxSymbols)),
         " source=",(explicitList?"EXPLICIT_CSV":(marketWatchOnly?"MARKET_WATCH":"ALL_BROKER_SYMBOLS")),
         " refreshSec=",MathMax(60,InpUniverseRefreshSeconds),
         " statePreserved=true",
         " note=ALL_DISCOVERABLE_SYMBOLS_WHEN_CAP_ZERO_TRADE_PERMISSION_REMAINS_BROKER_CONTROLLED");
   Print("CRYPTO_24X7_POLICY | cryptoScanPriority=true calendar=24x7_expected_only actualTrading=FRESH_QUOTE_AND_BROKER_PERMISSION_REQUIRED");
}

bool QuoteReady(string symbol,string &why)
{
   why="";
   g_lastQuoteAge=-1;

   if(MarketInfo(symbol,MODE_TRADEALLOWED)<=0.0)
   {
      why="BROKER_OR_SESSION_TRADE_DISABLED";
      return(false);
   }

   datetime tickTime=(datetime)MarketInfo(symbol,MODE_TIME);
   if(tickTime<=0)
   {
      why="NO_TICK_TIMESTAMP";
      return(false);
   }

   int age=(int)(TimeCurrent()-tickTime);
   g_lastQuoteAge=age;
   int maxAge=InpMaxQuoteAgeSec;
   bool crypto24x7=(IsCryptoSymbol(symbol) && InpCryptoExpected24x7);
   if(crypto24x7) maxAge=MathMax(maxAge,InpCryptoMaxQuoteAgeSec);

   if(age<0 || age>maxAge)
   {
      why="STALE_QUOTE ageSec="+IntegerToString(age)+" maxAgeSec="+IntegerToString(maxAge);
      return(false);
   }

   double bid=MarketInfo(symbol,MODE_BID);
   double ask=MarketInfo(symbol,MODE_ASK);
   double point=MarketInfo(symbol,MODE_POINT);

   // Reinitialize a broker-listed symbol once when its quote fields are incomplete.
   if(bid<=0.0 || ask<=bid || point<=0.0)
   {
      SymbolSelect(symbol,true);
      RefreshRates();
      bid=MarketInfo(symbol,MODE_BID);
      ask=MarketInfo(symbol,MODE_ASK);
      point=MarketInfo(symbol,MODE_POINT);
   }
   if(bid<=0.0 || ask<=bid || point<=0.0)
   {
      why="INVALID_BID_ASK_POINT";
      return(false);
   }

   if(!IsTradeAllowed())
   {
      why="TERMINAL_TRADE_NOT_ALLOWED";
      return(false);
   }
   return(true);
}

bool IsAddOnOrder() { return(StringFind(OrderComment(),"BBM_AD_")==0); }

// kind: 0 = scouts only, 1 = add-ons only
int CountByKind(int kind)
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      bool ad=IsAddOnOrder();
      if((kind==1)==ad) n++;
   }
   return(n);
}

int CountOurPositions(string symbol,int typeFilter)
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(symbol!="" && OrderSymbol()!=symbol) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      if(typeFilter>=0 && t!=typeFilter) continue;
      n++;
   }
   return(n);
}

double PriceValuePerUnit(string symbol)
{
   double point=MarketInfo(symbol,MODE_POINT);
   // MQL4: MODE_TICKSIZE is ALREADY expressed in price units (e.g. 0.00001), not points.
   // Multiplying by point (v1.0.3) inflated the value ~1e10x and forced lots to 0.
   double tickSizePrice=MarketInfo(symbol,MODE_TICKSIZE);
   double tickValue=MarketInfo(symbol,MODE_TICKVALUE);
   if(point<=0.0 || tickSizePrice<=0.0 || tickValue<=0.0) return(0.0);
   return(tickValue/tickSizePrice);
}

double OpenRiskMoney()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      string s=OrderSymbol();
      double v=PriceValuePerUnit(s);
      if(v<=0.0) return(1.0e100); // Unknown contract value: fail closed for new risk
      double stop=OrderStopLoss();
      if(stop<=0.0) return(1.0e100);
      double distance=(type==OP_BUY?OrderOpenPrice()-stop:stop-OrderOpenPrice());
      if(distance>0.0) total+=distance*OrderLots()*v;
   }
   return(total);
}

double StrategyCapitalUSD() { return(InpStrategicCapitalUSD); }

double EntryRiskBudget()
{
   double strategicRisk=StrategyCapitalUSD()*InpRiskPercent/100.0;
   if(InpRiskUSDOverride>0.0) return(MathMin(InpRiskUSDOverride,strategicRisk));
   return(strategicRisk);
}

double AggregateRiskCapUSD() { return(StrategyCapitalUSD()*InpMaxAggregateRiskPct/100.0); }

bool AdaptiveDistances(string symbol,int signal,double entry,double atr,double &slDist,double &tpDist)
{
   if(atr<=0.0 || entry<=0.0) return(false);
   double baseSL=atr*InpSL_ATR;
   double structural=(signal>0 ? entry-iLow(symbol,InpSignalTF,1)+atr*InpSLStructureBufferATR
                               : iHigh(symbol,InpSignalTF,1)-entry+atr*InpSLStructureBufferATR);
   if(structural>atr*InpMaxSL_ATR) return(false); // Never compress a structural stop inside the signal candle.
   slDist=MathMax(atr*InpMinSL_ATR,MathMax(baseSL,structural));
   slDist=MathMin(slDist,atr*InpMaxSL_ATR);
   if(slDist<=0.0) return(false);
   double upper=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,1);
   double lower=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,1);
   double width=(upper>lower ? upper-lower : 0.0);
   double widthAtr=(width>0.0 ? width/atr : 2.0);
   // Linear map of BB-width/ATR onto [MinTP_R, MaxTP_R]; wider band = more room = farther target.
   double span=MathMax(0.01,InpTPWidthHighATR-InpTPWidthLowATR);
   double wpos=MathMax(0.0,MathMin(1.0,(widthAtr-InpTPWidthLowATR)/span));
   double adaptiveR=InpMinAdaptiveTP_R+(InpMaxAdaptiveTP_R-InpMinAdaptiveTP_R)*wpos;
   adaptiveR=MathMax(InpMinAdaptiveTP_R,MathMin(InpMaxAdaptiveTP_R,adaptiveR));
   tpDist=slDist*adaptiveR;
   return(tpDist>0.0);
}

double CalcLots(string symbol,double stopDistance,double riskMoney)
{
   double v=PriceValuePerUnit(symbol);
   double minLot=MarketInfo(symbol,MODE_MINLOT);
   double maxLot=MarketInfo(symbol,MODE_MAXLOT);
   double step=MarketInfo(symbol,MODE_LOTSTEP);
   if(v<=0.0 || stopDistance<=0.0 || riskMoney<=0.0 || step<=0.0 || minLot<=0.0) return(0.0);
   double raw=riskMoney/(stopDistance*v);
   double lots=MathFloor(raw/step+1e-9)*step;
   // Never round UP to broker minimum if that exceeds the money-risk budget.
   if(lots<minLot) return(0.0);
   lots=MathMin(lots,maxLot);
   int lotDigits=2;
   if(step>=1.0) lotDigits=0;
   else if(step>=0.1) lotDigits=1;
   else if(step<0.01) lotDigits=3;
   return(NormalizeDouble(lots,lotDigits));
}

bool IsNewSignalBar(int index,string symbol,datetime &barTime)
{
   barTime=iTime(symbol,InpSignalTF,0);
   if(barTime<=0 || barTime==g_lastSignalBar[index]) return(false);
   g_lastSignalBar[index]=barTime;
   return(true);
}

// Signal codes: 2=breakout buy, 1=rebound buy, -1=rebound sell, -2=breakout sell, 0=none, 99=conflict.
int BollingerSignal(string symbol,string &signalName,string &detail)
{
   signalName="NONE"; detail="";
   if(iBars(symbol,InpSignalTF)<MathMax(InpMinBars,InpBBPeriod+5)) { detail="INSUFFICIENT_HISTORY"; return(0); }
   double upper1=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,1);
   double lower1=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,1);
   double upper2=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_UPPER,2);
   double lower2=iBands(symbol,InpSignalTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_LOWER,2);
   if(upper1<=0.0 || lower1<=0.0 || upper2<=0.0 || lower2<=0.0) { detail="BOLLINGER_DATA_UNAVAILABLE"; return(0); }

   double o1=iOpen(symbol,InpSignalTF,1), c1=iClose(symbol,InpSignalTF,1);
   double h1=iHigh(symbol,InpSignalTF,1), l1=iLow(symbol,InpSignalTF,1);
   double c2=iClose(symbol,InpSignalTF,2);
   bool bull=(c1>o1), bear=(c1<o1);

   bool reboundBuy=(l1<=lower1 && c1>lower1 && (!InpRequireCandleDirection || bull));
   bool reboundSell=(h1>=upper1 && c1<upper1 && (!InpRequireCandleDirection || bear));
   bool breakoutBuy=(c1>upper1 && c2<=upper2);
   bool breakoutSell=(c1<lower1 && c2>=lower2);

   bool buy=(InpEnableRebound && reboundBuy)||(InpEnableBreakout && breakoutBuy);
   bool sell=(InpEnableRebound && reboundSell)||(InpEnableBreakout && breakoutSell);
   if(buy && sell) { signalName="CONFLICT"; detail="OPPOSING_BOLLINGER_SETUPS_SAME_BAR"; return(99); }
   if(!buy && !sell) return(0);

   if(breakoutBuy) { signalName="BREAKOUT_BUY"; return(2); }
   if(reboundBuy) { signalName="REBOUND_BUY"; return(1); }
   if(breakoutSell) { signalName="BREAKOUT_SELL"; return(-2); }
   if(reboundSell) { signalName="REBOUND_SELL"; return(-1); }
   return(0);
}

//--- News guard file contract: #updated_epoch_utc=..., then scope,key,fromEpochUTC,untilEpochUTC,BLOCK,reason,eventEpochUTC
void NewsGuardLoad()
{
   datetime now=TimeGMT();
   if(g_newsLastLoad>0 && now-g_newsLastLoad<30) return;
   g_newsLastLoad=now;
   g_newsCount=0; g_newsFileOk=false; g_newsUpdated=0;
   int flags=FILE_READ|FILE_TXT|FILE_ANSI|FILE_SHARE_READ|FILE_SHARE_WRITE;
   if(InpNewsUseCommonFolder) flags|=FILE_COMMON;
   int h=FileOpen(InpNewsFileName,flags);
   if(h==INVALID_HANDLE)
   {
      if(now-g_newsLastStateLog>=900)
      {
         g_newsLastStateLog=now;
         Print("NEWS_GUARD_STATE | file=",InpNewsFileName," status=FILE_NOT_FOUND_FAIL_OPEN err=",GetLastError());
      }
      return;
   }
   while(!FileIsEnding(h) && g_newsCount<NEWS_MAX_ROWS)
   {
      string line=FileReadString(h);
      StringTrimLeft(line); StringTrimRight(line);
      if(line=="") continue;
      if(StringGetCharacter(line,0)=='#')
      {
         int p=StringFind(line,"updated_epoch_utc=");
         if(p>=0) g_newsUpdated=(datetime)StrToInteger(StringSubstr(line,p+18));
         continue;
      }
      string parts[];
      int n=StringSplit(line,StringGetCharacter(",",0),parts);
      if(n<6 || parts[4]!="BLOCK") continue;
      g_newsScope[g_newsCount]=parts[0];
      g_newsKey[g_newsCount]=Upper(parts[1]);
      g_newsFrom[g_newsCount]=(datetime)StrToInteger(parts[2]);
      g_newsUntil[g_newsCount]=(datetime)StrToInteger(parts[3]);
      g_newsReason[g_newsCount]=parts[5];
      g_newsEvent[g_newsCount]=(n>=7?(datetime)StrToInteger(parts[6]):g_newsFrom[g_newsCount]+900);
      g_newsCount++;
   }
   FileClose(h);
   g_newsFileOk=(g_newsUpdated>0 && now-g_newsUpdated<=InpNewsFileMaxAgeMin*60);
   if(!g_newsFileOk && now-g_newsLastStateLog>=900)
   {
      g_newsLastStateLog=now;
      Print("NEWS_GUARD_STATE | file=",InpNewsFileName," status=STALE_OR_NO_HEADER_FAIL_OPEN updatedUTC=",
            TimeToString(g_newsUpdated,TIME_DATE|TIME_SECONDS)," maxAgeMin=",InpNewsFileMaxAgeMin);
   }
}

void NewsSymbolCurrencies(string symbol,string &c1,string &c2)
{
   c1=""; c2="";
   string s=Upper(symbol);
   if(IsCryptoSymbol(symbol))
   {
      // Crypto priced in USD or a USD stablecoin is exposed to USD news.
      if(InpNewsUsdAffectsUsdt && (HasStableQuote(s) || StringFind(s,"USD")>=3)) c1="USD";
      return;
   }
   if(StringLen(s)>=6)
   {
      string a=StringSubstr(s,0,3), b=StringSubstr(s,3,3);
      string known=" USD EUR GBP JPY CHF CAD AUD NZD MXN ZAR SEK NOK DKK PLN CZK HUF TRY SGD HKD CNH CNY ";
      if(StringFind(known," "+a+" ")>=0 && StringFind(known," "+b+" ")>=0) { c1=a; c2=b; }
   }
}

bool NewsGuardWouldBlock(string symbol,string &why)
{
   why="";
   if(!InpNewsGuardEnabled) return(false);
   NewsGuardLoad();
   if(!g_newsFileOk || g_newsCount<=0) return(false);
   datetime now=TimeGMT();
   string c1,c2; NewsSymbolCurrencies(symbol,c1,c2);
   string us=Upper(symbol);
   for(int i=0;i<g_newsCount;i++)
   {
      if(now<g_newsFrom[i] || now>g_newsUntil[i]) continue;
      bool hit=false;
      if(g_newsScope[i]=="ALL") hit=true;
      else if(g_newsScope[i]=="SYM" && g_newsKey[i]==us) hit=true;
      else if(g_newsScope[i]=="CCY" && StringLen(g_newsKey[i])>0 &&
              (g_newsKey[i]==c1 || g_newsKey[i]==c2)) hit=true;
      if(hit)
      {
         why=g_newsScope[i]+":"+g_newsKey[i]+":"+g_newsReason[i];
         return(true);
      }
   }
   return(false);
}

void NewsShadowLog(string symbol)
{
   if(!InpNewsGuardEnabled) return;
   string why="";
   if(!NewsGuardWouldBlock(symbol,why)) return;
   datetime now=TimeGMT();
   int idx=-1;
   for(int i=0;i<g_newsLogCount;i++) if(g_newsLogSymbol[i]==symbol) { idx=i; break; }
   bool logNow=true;
   if(idx>=0)
   {
      if(now-g_newsLogTime[idx]<InpNewsLogThrottleMin*60) logNow=false;
      else g_newsLogTime[idx]=now;
   }
   else if(g_newsLogCount<NEWS_MAX_ROWS)
   {
      g_newsLogSymbol[g_newsLogCount]=symbol;
      g_newsLogTime[g_newsLogCount]=now;
      g_newsLogCount++;
   }
   if(logNow)
      Print("NEWS_GUARD_SHADOW_WOULD_BLOCK | symbol=",symbol," reason=",why,
            " shadowOnly=true action=SCOUT_ENTRY_NOT_BLOCKED serverTime=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   // Safety invariant: no return value from this function can veto a SCOUT.
}

bool NewsEventNear(string symbol,double &minutesToEvent,string &why)
{
   minutesToEvent=0.0; why="";
   if(!InpNewsGuardEnabled || !g_newsFileOk || g_newsCount<=0) return(false);
   string c1,c2; NewsSymbolCurrencies(symbol,c1,c2);
   string us=Upper(symbol);
   datetime now=TimeGMT();
   bool found=false; double best=0.0;
   for(int i=0;i<g_newsCount;i++)
   {
      bool hit=false;
      if(g_newsScope[i]=="ALL") hit=true;
      else if(g_newsScope[i]=="SYM" && g_newsKey[i]==us) hit=true;
      else if(g_newsScope[i]=="CCY" && StringLen(g_newsKey[i])>0 &&
              (g_newsKey[i]==c1 || g_newsKey[i]==c2)) hit=true;
      if(!hit) continue;
      double mins=(double)(g_newsEvent[i]-now)/60.0;
      if(mins>InpNewsPreProtectLeadMin || mins<-InpNewsPostProtectMin) continue;
      if(!found || MathAbs(mins)<MathAbs(best))
      {
         found=true; best=mins;
         why=g_newsScope[i]+":"+g_newsKey[i]+":"+g_newsReason[i];
      }
   }
   minutesToEvent=best;
   return(found);
}

//--- v1.0.7 loss-control state and helpers
datetime g_cTime[];
double   g_cNet[];
string   g_cSym[];
int      g_cType[];
int      g_cCount=0;
datetime g_cLoad=0;
string   g_qSym[];
datetime g_qUntil[];
int      g_qCount=0;
string   g_lgKey[];
datetime g_lgTime[];
int      g_lgCount=0;

// Returns true when the same key may be logged again (throttled per key).
bool ThrottledLog(string key)
{
   datetime now=TimeCurrent();
   for(int i=0;i<g_lgCount;i++)
   {
      if(g_lgKey[i]!=key) continue;
      if(now-g_lgTime[i]<MathMax(1,InpEntrySkipLogThrottleMin)*60) return(false);
      g_lgTime[i]=now;
      return(true);
   }
   if(g_lgCount>=3000) g_lgCount=0;
   int n=g_lgCount+1;
   if(ArrayResize(g_lgKey,n)<n || ArrayResize(g_lgTime,n)<n) return(true);
   g_lgKey[g_lgCount]=key;
   g_lgTime[g_lgCount]=now;
   g_lgCount=n;
   return(true);
}

bool IsQuarantined(string symbol)
{
   for(int i=0;i<g_qCount;i++)
      if(g_qSym[i]==symbol) return(g_qUntil[i]>TimeCurrent());
   return(false);
}

void QuarantineSymbol(string symbol,int minutes)
{
   datetime until=TimeCurrent()+MathMax(1,minutes)*60;
   for(int i=0;i<g_qCount;i++)
      if(g_qSym[i]==symbol) { g_qUntil[i]=until; return; }
   int n=g_qCount+1;
   if(ArrayResize(g_qSym,n)<n || ArrayResize(g_qUntil,n)<n) return;
   g_qSym[g_qCount]=symbol;
   g_qUntil[g_qCount]=until;
   g_qCount=n;
}

// Closed trades of this EA (magic), newest first. Refreshed lazily at most every 5 seconds.
void LoadClosedCache()
{
   if(g_cLoad>0 && TimeCurrent()-g_cLoad<5) return;
   g_cLoad=TimeCurrent();
   g_cCount=0;
   datetime from=TimeCurrent()-MathMax(1,InpHistLookbackHours)*3600;
   int total=OrdersHistoryTotal();
   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      datetime ct=OrderCloseTime();
      if(ct<=0 || ct<from) continue;
      int n=g_cCount+1;
      if(ArrayResize(g_cTime,n)<n || ArrayResize(g_cNet,n)<n ||
         ArrayResize(g_cSym,n)<n || ArrayResize(g_cType,n)<n) break;
      int pos=g_cCount;
      while(pos>0 && g_cTime[pos-1]<ct)
      {
         g_cTime[pos]=g_cTime[pos-1]; g_cNet[pos]=g_cNet[pos-1];
         g_cSym[pos]=g_cSym[pos-1];   g_cType[pos]=g_cType[pos-1];
         pos--;
      }
      g_cTime[pos]=ct;
      g_cNet[pos]=OrderProfit()+OrderSwap()+OrderCommission();
      g_cSym[pos]=OrderSymbol();
      g_cType[pos]=t;
      g_cCount=n;
   }
}

bool CooldownActive(string symbol,int cmd,string &why)
{
   why="";
   if(!InpCooldownEnabled || InpCooldownMinutes<=0) return(false);
   LoadClosedCache();
   datetime now=TimeCurrent();
   for(int i=0;i<g_cCount;i++)
   {
      if(now-g_cTime[i]>=InpCooldownMinutes*60) break;      // sorted newest first
      if(g_cSym[i]!=symbol) continue;
      if(!InpCooldownBlocksBothSides && g_cType[i]!=cmd) continue;
      if(g_cNet[i]<=-InpCooldownMinLossUSD)
      {
         int left=(int)((InpCooldownMinutes*60-(now-g_cTime[i]))/60);
         why="LOSS_COOLDOWN minLeft="+IntegerToString(left)+" lastNetUSD="+DoubleToString(g_cNet[i],2);
         return(true);
      }
   }
   return(false);
}

// Global stop for NEW entries: daily realized-loss cap and consecutive-loss pause.
bool CircuitBreakerActive(string &why)
{
   why="";
   LoadClosedCache();
   datetime now=TimeCurrent();
   if(InpMaxDailyLossUSD>0.0 || InpSoftDailyLossUSD>0.0)
   {
      datetime dayStart=now-(now%86400);
      double dayNet=0.0; datetime lastDayLoss=0;
      for(int i=0;i<g_cCount;i++)                            // newest first
      {
         if(g_cTime[i]<dayStart) continue;
         dayNet+=g_cNet[i];
         if(lastDayLoss==0 && g_cNet[i]<=-InpCooldownMinLossUSD) lastDayLoss=g_cTime[i];
      }
      if(InpMaxDailyLossUSD>0.0 && dayNet<=-InpMaxDailyLossUSD)
      {
         why="DAILY_HARD_CAP netUSD="+DoubleToString(dayNet,2)+" capUSD="+DoubleToString(InpMaxDailyLossUSD,2);
         return(true);
      }
      if(InpSoftDailyLossUSD>0.0 && InpSoftLossPauseMin>0 && dayNet<=-InpSoftDailyLossUSD &&
         lastDayLoss>0 && now-lastDayLoss<InpSoftLossPauseMin*60)
      {
         int left=(int)((InpSoftLossPauseMin*60-(now-lastDayLoss))/60);
         why="DAILY_SOFT_PAUSE netUSD="+DoubleToString(dayNet,2)+" softUSD="+DoubleToString(InpSoftDailyLossUSD,2)+" minLeft="+IntegerToString(left);
         return(true);
      }
   }
   if(InpMaxConsecLosses>0 && InpConsecLossPauseMin>0)
   {
      int streak=0; datetime lastLoss=0;
      for(int j=0;j<g_cCount;j++)
      {
         if(g_cNet[j]>0.0) break;                            // a win ends the streak
         if(g_cNet[j]<=-InpCooldownMinLossUSD)
         {
            if(streak==0) lastLoss=g_cTime[j];
            streak++;
         }
      }
      if(streak>=InpMaxConsecLosses && now-lastLoss<InpConsecLossPauseMin*60)
      {
         int left=(int)((InpConsecLossPauseMin*60-(now-lastLoss))/60);
         why="CONSEC_LOSS_PAUSE streak="+IntegerToString(streak)+" minLeft="+IntegerToString(left);
         return(true);
      }
   }
   return(false);
}

// Breakouts only in the direction of the regime-TF Bollinger midline. Fails open if data is missing.
bool RegimeAllows(string symbol,int signal,string &why)
{
   why="";
   if(!InpRegimeFilterEnabled) return(true);
   if(InpShortsNeedBearishRegime && signal==-1 && iBars(symbol,InpRegimeTF)>=InpBBPeriod+5)
   {
      double smid=iBands(symbol,InpRegimeTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_MAIN,1);
      double sc=iClose(symbol,InpRegimeTF,1);
      if(smid>0.0 && sc>0.0 && sc>smid) { why="REBOUND_SELL_ABOVE_REGIME_MID close="+DoubleToString(sc,5)+" mid="+DoubleToString(smid,5); return(false); }
   }
   if(MathAbs(signal)!=2) return(true);                      // rebounds are counter-trend by design
   if(iBars(symbol,InpRegimeTF)<InpBBPeriod+5) return(true);
   double mid=iBands(symbol,InpRegimeTF,InpBBPeriod,InpBBDeviation,0,InpBBPrice,MODE_MAIN,1);
   double c=iClose(symbol,InpRegimeTF,1);
   if(mid<=0.0 || c<=0.0) return(true);
   if(signal>0 && c<mid) { why="BREAKOUT_BUY_BELOW_REGIME_MID close="+DoubleToString(c,5)+" mid="+DoubleToString(mid,5); return(false); }
   if(signal<0 && c>mid) { why="BREAKOUT_SELL_ABOVE_REGIME_MID close="+DoubleToString(c,5)+" mid="+DoubleToString(mid,5); return(false); }
   return(true);
}

// FX pair split into base/quote when both are known currencies.
bool FxPair(string symbol,string &a,string &b)
{
   a=""; b="";
   string s=Upper(symbol);
   if(IsCryptoSymbol(symbol) || StringLen(s)<6) return(false);
   string x=StringSubstr(s,0,3), y=StringSubstr(s,3,3);
   string known=" USD EUR GBP JPY CHF CAD AUD NZD ";
   if(StringFind(known," "+x+" ")<0 || StringFind(known," "+y+" ")<0) return(false);
   a=x; b=y;
   return(true);
}

// Max N open positions long (or short) the same currency, e.g. avoids 4 simultaneous USD longs.
bool CurrencyConcentrated(string symbol,int cmd,string &why)
{
   why="";
   if(InpMaxPerCurrencyDir<=0) return(false);
   string a,b;
   if(!FxPair(symbol,a,b)) return(false);
   string longC=(cmd==OP_BUY?a:b), shortC=(cmd==OP_BUY?b:a);
   int nl=0, ns=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      string x,y;
      if(!FxPair(OrderSymbol(),x,y)) continue;
      string pl=(t==OP_BUY?x:y), ps=(t==OP_BUY?y:x);
      if(pl==longC) nl++;
      if(ps==shortC) ns++;
   }
   if(nl>=InpMaxPerCurrencyDir) { why="CURRENCY_CONCENTRATION long="+longC+" open="+IntegerToString(nl)+" max="+IntegerToString(InpMaxPerCurrencyDir); return(true); }
   if(ns>=InpMaxPerCurrencyDir) { why="CURRENCY_CONCENTRATION short="+shortC+" open="+IntegerToString(ns)+" max="+IntegerToString(InpMaxPerCurrencyDir); return(true); }
   return(false);
}

// Same underlying asset under different broker symbols: ETHUSD / ETHUSDT / ETHUSDT.m -> "ETH".
string UnderlyingKey(string symbol)
{
   string s=Upper(symbol);
   while(StringLen(s)>0 && !((StringGetCharacter(s,0)>='A' && StringGetCharacter(s,0)<='Z') ||
                             (StringGetCharacter(s,0)>='0' && StringGetCharacter(s,0)<='9')))
      s=StringSubstr(s,1);
   int dot=StringFind(s,".");
   if(dot>0) s=StringSubstr(s,0,dot);
   if(IsCryptoSymbol(symbol) || IsStockOrCommodityToken(s))
   {
      string q[]={"USDT","USDC","BUSD","FDUSD","USD"};
      for(int i=0;i<ArraySize(q);i++)
      {
         int ql=StringLen(q[i]), n=StringLen(s);
         if(n>ql+1 && StringSubstr(s,n-ql)==q[i]) { s=StringSubstr(s,0,n-ql); break; }
      }
   }
   return(s);
}

bool UnderlyingDuplicate(string symbol,string &why)
{
   why="";
   if(!InpBlockUnderlyingDup) return(false);
   string key=UnderlyingKey(symbol);
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      if(OrderSymbol()==symbol) continue;
      if(UnderlyingKey(OrderSymbol())==key)
      {
         why="UNDERLYING_DUPLICATE underlying="+key+" openAs="+OrderSymbol();
         return(true);
      }
   }
   return(false);
}

//--- Entry and execution
int CountScoutOpensLastHour()
{
   datetime from=TimeCurrent()-3600;
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(StringFind(OrderComment(),"BBM_SC_")==0 && OrderOpenTime()>=from) n++;
   }
   int total=OrdersHistoryTotal();
   int scanned=0;
   for(int j=total-1;j>=0 && scanned<400;j--,scanned++)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      if(StringFind(OrderComment(),"BBM_SC_")==0 && OrderOpenTime()>=from) n++;
   }
   return(n);
}

bool SessionAllows(string symbol,string &why)
{
   why="";
   if(!InpSessionFilterEnabled) return(true);
   if(IsCryptoSymbol(symbol) && !InpCryptoSessionFilter) return(true);
   int h=TimeHour(TimeCurrent());
   bool ok=(InpSessionStartHour<=InpSessionEndHour ? (h>=InpSessionStartHour && h<InpSessionEndHour)
                                                    : (h>=InpSessionStartHour || h<InpSessionEndHour));
   if(!ok) why="OUTSIDE_SESSION serverHour="+IntegerToString(h)+" window="+IntegerToString(InpSessionStartHour)+"-"+IntegerToString(InpSessionEndHour);
   return(ok);
}

int CurrentLossStreak()
{
   LoadClosedCache();
   int streak=0;
   for(int j=0;j<g_cCount;j++)
   {
      if(g_cNet[j]>0.0) break;
      if(g_cNet[j]<=-InpCooldownMinLossUSD) streak++;
   }
   return(streak);
}

bool SymbolDayBlocked(string symbol,string &why)
{
   why="";
   if(InpSymbolDayLossLimit<=0) return(false);
   LoadClosedCache();
   datetime now=TimeCurrent();
   datetime dayStart=now-(now%86400);
   int losses=0;
   for(int i=0;i<g_cCount;i++)
   {
      if(g_cTime[i]<dayStart) break;                         // sorted newest first
      if(g_cSym[i]==symbol && g_cNet[i]<=-InpCooldownMinLossUSD) losses++;
   }
   if(losses>=InpSymbolDayLossLimit) { why="SYMBOL_DAY_BLOCK losses="+IntegerToString(losses)+" limit="+IntegerToString(InpSymbolDayLossLimit); return(true); }
   return(false);
}

//--- v1.0.17 daily profit bank
datetime DayStartServer() { datetime now=TimeCurrent(); return(now-(now%86400)); }
string DayKey(string prefix) { return(prefix+IntegerToString((int)DayStartServer())); }
bool DayHalted() { return(GlobalVariableCheck(DayKey("BBM_DHALT_"))); }

double DayNetUSD()
{
   LoadClosedCache();
   datetime ds=DayStartServer();
   double net=0.0;
   for(int i=0;i<g_cCount;i++)
   {
      if(g_cTime[i]<ds) break;                               // sorted newest first
      net+=g_cNet[i];
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return(net);
}

void CloseAllOurs()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      string s=OrderSymbol();
      int tk=OrderTicket();
      double px=(t==OP_BUY?MarketInfo(s,MODE_BID):MarketInfo(s,MODE_ASK));
      ResetLastError();
      if(!OrderClose(tk,OrderLots(),px,InpSlippagePoints,clrAqua))
         Print("DAILY_BANK_CLOSE_FAIL | ticket=",tk," symbol=",s," error=",GetLastError()," action=RETRY_NEXT_SECOND");
   }
}

void FlattenAndHalt(string reason,double net)
{
   string k=DayKey("BBM_DHALT_");
   bool first=!GlobalVariableCheck(k);
   CloseAllOurs();
   GlobalVariableSet(k,(CountOurPositions("",-1)>0?2.0:1.0));   // 2 = flatten still pending, retried every second
   if(first)
      Print("DAILY_BANK_HALT | reason=",reason," dayNetUSD=",DoubleToString(net,2)," targetUSD=",DoubleToString(InpDailyTargetUSD,2),
            " action=CLOSE_ALL_AND_NO_NEW_ENTRIES_TODAY");
}

void DailyBankCheck()
{
   if(!InpDailyBankEnabled) return;
   static datetime lastRun=0;
   datetime now=TimeCurrent();
   if(now==lastRun) return;                                  // at most once per second
   lastRun=now;
   string hk=DayKey("BBM_DHALT_");
   if(GlobalVariableCheck(hk))
   {
      if(GlobalVariableGet(hk)>=2.0)                         // retry a flatten that did not fully complete
      {
         CloseAllOurs();
         if(CountOurPositions("",-1)==0) GlobalVariableSet(hk,1.0);
      }
      return;
   }
   double net=DayNetUSD();
   string pk=DayKey("BBM_DPEAK_");
   double peak=(GlobalVariableCheck(pk)?GlobalVariableGet(pk):0.0);
   if(InpDailyEndBankHour>0 && TimeHour(now)>=InpDailyEndBankHour && net>=InpDailyEndBankMinUSD)
   {
      FlattenAndHalt("END_OF_DAY_BANK",net);
      return;
   }
   if(net>=InpDailyTargetUSD)
   {
      if(net>peak) { peak=net; GlobalVariableSet(pk,peak); }
      if(InpDailyHaltAtTarget) { FlattenAndHalt("DAILY_TARGET_REACHED",net); return; }
   }
   if(!InpDailyHaltAtTarget && peak>=InpDailyTargetUSD)
   {
      double lockLevel=MathMax(InpDailyLockFloorUSD,peak*(1.0-InpDailyGiveBackPct/100.0));
      if(net<=lockLevel) FlattenAndHalt("DAILY_PEAK_GIVEBACK peakUSD="+DoubleToString(peak,2)+" lockUSD="+DoubleToString(lockLevel,2),net);
   }
}

void CleanupDayGlobals()
{
   string cur=IntegerToString((int)DayStartServer());
   string pf[]={"BBM_DHALT_","BBM_DPEAK_"};
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   {
      string name=GlobalVariableName(i);
      for(int p=0;p<2;p++)
      {
         if(StringFind(name,pf[p])!=0) continue;
         if(StringSubstr(name,StringLen(pf[p]))!=cur) GlobalVariableDel(name);
         break;
      }
   }
}

bool SendScout(string symbol,int signal,string signalName,bool addOn=false,double riskCap=0.0)
{
   int cmd=(signal>0?OP_BUY:OP_SELL);
   if((cmd==OP_BUY && !InpAllowBuy)||(cmd==OP_SELL && !InpAllowSell)) return(false);
   if(!addOn && CountByKind(0)>=InpMaxOpenPositions) return(false);       // scouts only: add-ons never consume scout slots
   if(addOn && CountByKind(1)>=InpMaxAddOnsTotal)
   {
      if(ThrottledLog("ALL|ADDON_TOTAL")) Print("ADDON_SKIP | symbol=",symbol," reason=MAX_ADDONS_TOTAL max=",InpMaxAddOnsTotal);
      return(false);
   }
   if(!addOn && CountOurPositions(symbol,-1)>=InpMaxPositionsPerSymbol) return(false);
   if(addOn && CountOurPositions(symbol,-1)>=1+InpMaxAddOnsPerSymbol) return(false);

   if(IsQuarantined(symbol)) return(false);
   string gateWhy="";
   if(InpDailyBankEnabled && DayHalted())
   {
      if(ThrottledLog("ALL|DAYHALT")) Print("ENTRY_SKIP | symbol=",symbol," reason=DAILY_BANK_HALT dayNetUSD=",DoubleToString(DayNetUSD(),2));
      return(false);
   }
   if(CircuitBreakerActive(gateWhy))
   {
      if(ThrottledLog("ALL|BREAKER|"+gateWhy)) Print("ENTRY_SKIP | symbol=",symbol," reason=CIRCUIT_BREAKER detail=",gateWhy);
      return(false);
   }
   if(!addOn && CooldownActive(symbol,cmd,gateWhy))
   {
      if(ThrottledLog(symbol+"|COOLDOWN|"+IntegerToString(cmd))) Print("ENTRY_SKIP | symbol=",symbol," reason=",gateWhy);
      return(false);
   }

   if(!addOn)
   {
      if(SymbolDayBlocked(symbol,gateWhy) || SessionAllows(symbol,gateWhy)==false)
      {
         if(ThrottledLog(symbol+"|GATE16|"+StringSubstr(gateWhy,0,12))) Print("ENTRY_SKIP | symbol=",symbol," reason=",gateWhy);
         return(false);
      }
      if(InpMaxEntriesPerHour>0)
      {
         int recent=CountScoutOpensLastHour();
         if(recent>=InpMaxEntriesPerHour)
         {
            if(ThrottledLog("ALL|RATE_LIMIT")) Print("ENTRY_SKIP | symbol=",symbol," reason=ENTRY_RATE_LIMIT opensLastHour=",recent," max=",InpMaxEntriesPerHour);
            return(false);
         }
      }
   }

   if(!addOn && (UnderlyingDuplicate(symbol,gateWhy) || CurrencyConcentrated(symbol,cmd,gateWhy)))
   {
      if(ThrottledLog(symbol+"|CONC|"+IntegerToString(cmd))) Print("ENTRY_SKIP | symbol=",symbol," reason=",gateWhy);
      return(false);
   }

   string quoteWhy="";
   if(!QuoteReady(symbol,quoteWhy)) { if(ThrottledLog(symbol+"|QNR")) Print("ENTRY_SKIP | symbol=",symbol," reason=QUOTE_NOT_READY detail=",quoteWhy); return(false); }
   double point=MarketInfo(symbol,MODE_POINT);
   int digits=(int)MarketInfo(symbol,MODE_DIGITS);
   double atr=iATR(symbol,InpSignalTF,InpATRPeriod,1);
   double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
   double entryPrice=(cmd==OP_BUY?ask:bid);
   double slDist=0.0,tpDist=0.0;
   if(point<=0.0 || atr<=0.0 || !AdaptiveDistances(symbol,signal,entryPrice,atr,slDist,tpDist))
   { if(ThrottledLog(symbol+"|ADAPT")) Print("ENTRY_SKIP | symbol=",symbol," reason=ADAPTIVE_ATR_BB_DISTANCE_UNAVAILABLE"); return(false); }
   if(addOn) { slDist*=InpAddOnSLScale; tpDist*=InpAddOnTPScale; }     // add-on gets its own adaptive SL/TP, freshly computed now
   double stopLevel=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
   if(slDist<=stopLevel+point || tpDist<=stopLevel+point)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=BROKER_STOP_LEVEL slDist=",DoubleToString(slDist,digits),
            " required=",DoubleToString(stopLevel+point,digits));
      return(false);
   }

   bid=MarketInfo(symbol,MODE_BID); ask=MarketInfo(symbol,MODE_ASK);
   double spread=ask-bid;
   if(spread>InpMaxSpreadPoints*point || spread>slDist*InpMaxSpreadPctOfSL/100.0)
   {
      if(ThrottledLog(symbol+"|SPREAD_GATE")) Print("ENTRY_SKIP | symbol=",symbol," reason=SPREAD_GATE spreadPts=",DoubleToString(spread/point,1));
      return(false);
   }

   double riskBudget=EntryRiskBudget();
   if(addOn) riskBudget=MathMin(riskBudget,riskCap);
   if(!addOn && InpStreakRiskScale<1.0 && InpStreakScaleAfter>0 && CurrentLossStreak()>=InpStreakScaleAfter)
   {
      riskBudget*=InpStreakRiskScale;
      if(ThrottledLog(symbol+"|STREAKSCALE")) Print("RISK_SCALED | symbol=",symbol," reason=LOSS_STREAK scale=",DoubleToString(InpStreakRiskScale,2)," riskUSD=",DoubleToString(riskBudget,2));
   }
   double lots=CalcLots(symbol,slDist,riskBudget);
   if(lots<=0.0)
   {
      if(ThrottledLog(symbol+"|MIN_LOT")) Print("ENTRY_SKIP | symbol=",symbol," reason=MIN_LOT_EXCEEDS_RISK_BUDGET riskUSD=",DoubleToString(riskBudget,2));
      return(false);
   }
   double value=PriceValuePerUnit(symbol);
   double newRisk=lots*slDist*value;
   if(InpCostFilterEnabled && value>0.0 && newRisk>0.0)
   {
      double rate=((IsCryptoSymbol(symbol)||HasStableQuote(Upper(symbol)))?InpCommissionStablePerLotUSD:InpCommissionPerLotUSD);
      double costUSD=lots*rate+spread*lots*value;
      if(costUSD>newRisk*InpMaxCostPctOfRisk/100.0)
      {
         if(ThrottledLog(symbol+"|COST_GATE"))
            Print("ENTRY_SKIP | symbol=",symbol," reason=COST_GATE costUSD=",DoubleToString(costUSD,2),
                  " riskUSD=",DoubleToString(newRisk,2)," costPctOfRisk=",DoubleToString(100.0*costUSD/newRisk,1),
                  " maxPct=",DoubleToString(InpMaxCostPctOfRisk,1));
         return(false);
      }
   }
   double aggregateCap=AggregateRiskCapUSD();
   if(value<=0.0 || OpenRiskMoney()+newRisk>aggregateCap)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=AGGREGATE_RISK_CAP newRisk=",DoubleToString(newRisk,2),
            " openRisk=",DoubleToString(OpenRiskMoney(),2)," cap=",DoubleToString(aggregateCap,2));
      return(false);
   }

   int type=cmd;
   double price=(cmd==OP_BUY?ask:bid);
   double sl=(cmd==OP_BUY?price-slDist:price+slDist);
   double tp=(cmd==OP_BUY?price+tpDist:price-tpDist);
   price=NormalizeDouble(price,digits); sl=NormalizeDouble(sl,digits); tp=NormalizeDouble(tp,digits);
   ResetLastError();
   double freeBefore=AccountFreeMargin();
   double freeAfter=AccountFreeMarginCheck(symbol,cmd,lots);
   double marginRequired=freeBefore-freeAfter;
   if(freeAfter<=0.0 || marginRequired<=0.0 || marginRequired>freeBefore*InpMaxMarginUsePctFree/100.0)
   {
      Print("ENTRY_SKIP | symbol=",symbol," reason=MARGIN_GUARD lots=",DoubleToString(lots,3),
            " marginRequired=",DoubleToString(marginRequired,2)," freeMargin=",DoubleToString(freeBefore,2),
            " maxUsePct=",DoubleToString(InpMaxMarginUsePctFree,1));
      return(false);
   }
   int ticket=OrderSend(symbol,type,lots,price,InpSlippagePoints,sl,tp,
                        (addOn?"BBM_AD_":"BBM_SC_")+signalName,InpMagic,0,(cmd==OP_BUY?clrDodgerBlue:clrTomato));
   if(ticket>0)
   {
      GlobalVariableSet("BBM_INITR_"+IntegerToString(ticket),slDist);
      Print((addOn?"ADDON_OPEN":"SCOUT_OPEN")," | ticket=",ticket," symbol=",symbol," signal=",signalName,
            " lots=",DoubleToString(lots,3)," riskUSD=",DoubleToString(newRisk,2),
            " strategicCapitalUSD=",DoubleToString(StrategyCapitalUSD(),2),
            " adaptiveTP_R=",DoubleToString(tpDist/slDist,2)," marginRequired=",DoubleToString(marginRequired,2),
            " sl=",DoubleToString(sl,digits)," tp=",DoubleToString(tp,digits),
            " strategy=BOLLINGER_ONLY newsMode=SHADOW fundedByLockedProfit=",(addOn?"true":"false"));
      return(true);
   }
   int err=GetLastError();
   Print("ORDER_SEND_FAIL | symbol=",symbol," signal=",signalName," error=",err);
   if(err==133 || err==132)
   {
      QuarantineSymbol(symbol,InpQuarantineMinutes);
      Print("SYMBOL_QUARANTINED | symbol=",symbol," error=",err," minutes=",InpQuarantineMinutes);
   }
   return(false);
}

datetime g_lastGlobalCleanup=0;

bool TicketIsOpen(int ticket)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderTicket()==ticket) return(true);
   }
   return(false);
}

// Remove BBM_INITR_/BBM_MOD_ globals whose ticket is no longer open (runs at most hourly).
void CleanupGlobals()
{
   if(TimeCurrent()-g_lastGlobalCleanup<3600) return;
   g_lastGlobalCleanup=TimeCurrent();
   CleanupDayGlobals();
   string prefixes[]={"BBM_INITR_","BBM_MOD_","BBM_PEAK_"};
   for(int i=GlobalVariablesTotal()-1;i>=0;i--)
   {
      string name=GlobalVariableName(i);
      for(int p=0;p<3;p++)
      {
         if(StringFind(name,prefixes[p])!=0) continue;
         int ticket=(int)StrToInteger(StringSubstr(name,StringLen(prefixes[p])));
         if(ticket>0 && !TicketIsOpen(ticket)) GlobalVariableDel(name);
         break;
      }
   }
}

void ManageOpenPositions()
{
   NewsGuardLoad();
   DailyBankCheck();
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      string symbol=OrderSymbol();
      string quoteWhy="";
      if(!QuoteReady(symbol,quoteWhy)) { if(InpLogScannerDiagnostics && ThrottledLog("T"+IntegerToString(OrderTicket())+"|MANAGE")) Print("MANAGE_SKIP | ticket=",OrderTicket()," symbol=",symbol," reason=STALE_OR_INVALID_QUOTE detail=",quoteWhy); continue; }

      double point=MarketInfo(symbol,MODE_POINT);
      int digits=(int)MarketInfo(symbol,MODE_DIGITS);
      double atr=iATR(symbol,InpSignalTF,InpATRPeriod,1);
      if(point<=0.0 || atr<=0.0) continue;
      double dir=(type==OP_BUY?1.0:-1.0);
      double bid=MarketInfo(symbol,MODE_BID), ask=MarketInfo(symbol,MODE_ASK);
      double market=(type==OP_BUY?bid:ask);
      // v1.0.14 net-loss guard. trueNet = what closing now would really cost/earn:
      //   trueNet = profit + swap + posted commission - still-unposted round-trip commission - other close costs
      //   costs   = round-trip commission + other close costs + current spread cost
      // Close when trueNet <= -(costs + buffer): i.e. price has moved against us by more than spread + buffer.
      // (The previous build compared trueNet to -buffer, which already contains the costs, so it closed trades at entry.)
      if(InpNetLossBufferUSD>0.0 && TimeCurrent()-OrderOpenTime()>=InpLossGuardGraceSec)
      {
         double gLots=OrderLots();
         double gValue=PriceValuePerUnit(symbol);
         double gPosted=MathAbs(OrderCommission());
         double gRate=((IsCryptoSymbol(symbol)||HasStableQuote(Upper(symbol)))?InpCommissionStablePerLotUSD:InpCommissionPerLotUSD);
         double gRoundTrip=MathMax(gPosted,gRate*gLots);
         double gRemaining=gRoundTrip-gPosted;
         double gOther=MathMax(0.0,InpOtherCloseCostsPerLotUSD)*gLots;
         double gSpread=(gValue>0.0?(ask-bid)*gLots*gValue:0.0);
         double gTrueNet=OrderProfit()+OrderSwap()+OrderCommission()-gRemaining-gOther;
         double gCosts=gRoundTrip+gOther+gSpread;
         double gInit=(GlobalVariableCheck("BBM_INITR_"+IntegerToString(OrderTicket()))?GlobalVariableGet("BBM_INITR_"+IntegerToString(OrderTicket())):MathAbs(OrderOpenPrice()-OrderStopLoss()));
         double gRiskUSD=(gValue>0.0?gInit*gLots*gValue:0.0);
         double gBuffer=MathMin(InpLossGuardMaxBufferUSD,MathMax(InpNetLossBufferUSD,InpLossGuardRiskFrac*gRiskUSD));
         double gLimit=MathMax(gCosts+gBuffer,InpLossGuardFloorUSD);
         if(gTrueNet<=-gLimit)
         {
            RefreshRates();
            double gClosePrice=(type==OP_BUY?MarketInfo(symbol,MODE_BID):MarketInfo(symbol,MODE_ASK));
            int gTicket=OrderTicket();
            ResetLastError();
            if(OrderClose(gTicket,gLots,gClosePrice,InpSlippagePoints,clrRed))
               Print("NET_LOSS_GUARD_CLOSE | ticket=",gTicket," symbol=",symbol," type=",(type==OP_BUY?"BUY":"SELL"),
                     " trueNetUSD=",DoubleToString(gTrueNet,2)," limitUSD=",DoubleToString(-gLimit,2),
                     " costsUSD=",DoubleToString(gCosts,2)," (commission=",DoubleToString(gRoundTrip,2),
                     " spread=",DoubleToString(gSpread,2)," other=",DoubleToString(gOther,2),")",
                     " bufferUSD=",DoubleToString(gBuffer,2)," riskUSD=",DoubleToString(gRiskUSD,2)," floorUSD=",DoubleToString(InpLossGuardFloorUSD,2)," lots=",DoubleToString(gLots,2));
            else if(ThrottledLog("T"+IntegerToString(gTicket)+"|GUARDFAIL"))
               Print("NET_LOSS_GUARD_CLOSE_FAIL | ticket=",gTicket," symbol=",symbol," trueNetUSD=",DoubleToString(gTrueNet,2),
                     " error=",GetLastError()," action=RETRY_NEXT_TICK_OR_TIMER");
            continue;   // never run BE/trailing on a position that just hit the loss guard
         }
      }
      string riskKey="BBM_INITR_"+IntegerToString(OrderTicket());
      double initialRisk=(GlobalVariableCheck(riskKey)?GlobalVariableGet(riskKey):MathAbs(OrderOpenPrice()-OrderStopLoss()));
      if(initialRisk<=0.0) continue;
      double favorable=dir*(market-OrderOpenPrice());
      double r=favorable/initialRisk;
      double candidate=OrderStopLoss();
      bool improve=false;
      if(InpBreakEvenEnabled && r>=InpBreakEvenAtR)
      {
         double lockDist=InpBreakEvenLockR*initialRisk;
         if(InpBELockCoversCosts)
         {
            double mpp=PriceValuePerUnit(symbol)*OrderLots();
            if(mpp>0.0)
            {
               double costs=(MathAbs(OrderCommission())+MathMax(0.0,-OrderSwap()))/mpp;
               if(type==OP_SELL) costs+=(ask-bid);        // a sell stop is hit on the ask
               lockDist=MathMax(lockDist,costs);
            }
            lockDist=MathMin(lockDist,0.5*initialRisk);   // never lock more than half the initial risk
         }
         double be=OrderOpenPrice()+dir*lockDist;
         if(type==OP_BUY && (candidate<=0.0 || be>candidate+point)) { candidate=be; improve=true; }
         if(type==OP_SELL && (candidate<=0.0 || be<candidate-point)) { candidate=be; improve=true; }
      }
      if(InpTrailingEnabled && r>=InpTrailStartR)
      {
         double trail=market-dir*(atr*InpTrailDistanceATR);
         if(type==OP_BUY && trail>candidate+point) { candidate=trail; improve=true; }
         if(type==OP_SELL && (candidate<=0.0 || trail<candidate-point)) { candidate=trail; improve=true; }
      }

      // v1.0.14 peak-lock ratchet (applies to scouts and add-ons): lock a growing share of the best excursion reached.
      if(InpPeakLockEnabled)
      {
         string pk="BBM_PEAK_"+IntegerToString(OrderTicket());
         double peak=(GlobalVariableCheck(pk)?GlobalVariableGet(pk):0.0);
         if(favorable>peak) { peak=favorable; GlobalVariableSet(pk,peak); }
         double peakR=peak/initialRisk;
         if(peakR>=InpPeakLockStartR)
         {
            double frac=MathMin(InpPeakLockMaxFrac,InpPeakLockMinFrac+InpPeakLockSlope*(peakR-InpPeakLockStartR));
            double lockSL=OrderOpenPrice()+dir*(peak*frac);
            if(type==OP_BUY && (candidate<=0.0 || lockSL>candidate+point)) { candidate=lockSL; improve=true; }
            if(type==OP_SELL && (candidate<=0.0 || lockSL<candidate-point)) { candidate=lockSL; improve=true; }
         }
      }

      // Event-window protection: secure a fraction of existing net profit with SL only.
      // It never widens an SL and never changes or vetoes a SCOUT entry.
      double eventMinutes=0.0; string eventWhy="";
      double liveNet=OrderProfit()+OrderSwap()+OrderCommission();
      if(liveNet>=InpNewsProtectMinNetUSD && InpNewsProtectKeepPct>0.0 &&
         InpNewsProtectKeepPct<100.0 && NewsEventNear(symbol,eventMinutes,eventWhy))
      {
         double moneyPerPrice=PriceValuePerUnit(symbol)*OrderLots();
         double closeCost=MathAbs(OrderCommission())+MathMax(0.0,-OrderSwap());
         if(moneyPerPrice>0.0)
         {
            double targetNet=liveNet*InpNewsProtectKeepPct/100.0;
            double requiredGross=targetNet-OrderSwap()-OrderCommission()+closeCost;
            double lockMove=requiredGross/moneyPerPrice;
            double newsSL=OrderOpenPrice()+dir*lockMove;
            double minDistNews=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
            bool valid=(type==OP_BUY ? (newsSL>OrderOpenPrice() && newsSL<bid-minDistNews)
                                    : (newsSL<OrderOpenPrice() && newsSL>ask+minDistNews));
            bool tighter=(type==OP_BUY ? (candidate<=0.0 || newsSL>candidate+point)
                                       : (candidate<=0.0 || newsSL<candidate-point));
            if(valid && tighter)
            {
               candidate=newsSL; improve=true;
               Print("NEWS_PRE_PROTECT_STOP_ARMED | ticket=",OrderTicket()," symbol=",symbol,
                     " netNow=",DoubleToString(liveNet,2)," protectedNetPct=",DoubleToString(InpNewsProtectKeepPct,1),
                     " minutesToEvent=",DoubleToString(eventMinutes,1)," event=",eventWhy,
                     " action=PROTECTIVE_SL_ONLY_NO_WIDENING");
            }
         }
      }
      if(!improve) continue;
      // Never widen the original or already-tightened stop.
      if(type==OP_BUY && OrderStopLoss()>0.0 && candidate<=OrderStopLoss()+point) continue;
      if(type==OP_SELL && OrderStopLoss()>0.0 && candidate>=OrderStopLoss()-point) continue;
      double minDist=MathMax(MarketInfo(symbol,MODE_STOPLEVEL),MarketInfo(symbol,MODE_FREEZELEVEL))*point;
      if(type==OP_BUY && candidate>=bid-minDist) continue;
      if(type==OP_SELL && candidate<=ask+minDist) continue;
      if(InpMinTrailStepATR>0.0 && atr>0.0 && OrderStopLoss()>0.0)
      {
         bool firstBE=(dir*(OrderStopLoss()-OrderOpenPrice())<0.0 && dir*(candidate-OrderOpenPrice())>=0.0);
         if(!firstBE && dir*(candidate-OrderStopLoss())<InpMinTrailStepATR*atr) continue;
      }
      string throttleKey="BBM_MOD_"+IntegerToString(OrderTicket());
      datetime last=0;
      if(GlobalVariableCheck(throttleKey)) last=(datetime)GlobalVariableGet(throttleKey);
      if(TimeCurrent()-last<InpModifyThrottleSec) continue;
      ResetLastError();
      if(OrderModify(OrderTicket(),OrderOpenPrice(),NormalizeDouble(candidate,digits),OrderTakeProfit(),0,clrNONE))
      {
         GlobalVariableSet(throttleKey,(double)TimeCurrent());
         Print("PROTECTIVE_SL_UPDATE | ticket=",OrderTicket()," symbol=",symbol,
               " currentR=",DoubleToString(r,2)," sl=",DoubleToString(candidate,digits),
               " invariant=SL_NEVER_WIDENED");
      }
      else
      {
         int e=GetLastError();
         if(e!=1) Print("SL_MODIFY_FAIL | ticket=",OrderTicket()," symbol=",symbol," error=",e);
      }
   }
}

//--- Funded add-on. Uses only profit already locked by the scout's SL; aggregate risk cap remains absolute.
bool TryFundedAddOn(string symbol,int signal,string signalName)
{
   if(!InpAddOnEnabled) return(false);
   int cmd=(signal>0?OP_BUY:OP_SELL);
   double dir=(cmd==OP_BUY?1.0:-1.0);
   double v=PriceValuePerUnit(symbol);
   if(v<=0.0) return(false);
   double market=(cmd==OP_BUY?MarketInfo(symbol,MODE_BID):MarketInfo(symbol,MODE_ASK));
   int scouts=0, addons=0;
   double locked=0.0, addOnOpenRisk=0.0, scoutMaxR=0.0;
   bool rUnknown=false;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=symbol) continue;
      int t=OrderType();
      if(t!=OP_BUY && t!=OP_SELL) continue;
      if(t!=cmd) return(false);                 // never hedge against an existing position
      double sl=OrderStopLoss();
      if(sl<=0.0) return(false);                // unprotected position: fail closed
      double signedDist=dir*(sl-OrderOpenPrice());   // >0 = SL beyond entry (profit locked)
      if(IsAddOnOrder())
      {
         addons++;
         if(signedDist<0.0) addOnOpenRisk+=-signedDist*OrderLots()*v;
      }
      else
      {
         scouts++;
         if(signedDist>0.0)
            locked+=signedDist*OrderLots()*v+OrderCommission()+OrderSwap();
         string rk="BBM_INITR_"+IntegerToString(OrderTicket());
         if(GlobalVariableCheck(rk) && GlobalVariableGet(rk)>0.0)
            scoutMaxR=MathMax(scoutMaxR,dir*(market-OrderOpenPrice())/GlobalVariableGet(rk));
         else rUnknown=true;
      }
   }
   if(scouts<1 || addons>=InpMaxAddOnsPerSymbol) return(false);

   // --- Add-on safety evaluation (every check must pass; each failure is logged, throttled) ---
   if(locked<InpAddOnMinLockedUSD)
   {
      if(ThrottledLog(symbol+"|ADDON_LOCK")) Print("ADDON_SKIP | symbol=",symbol," reason=NO_LOCKED_PROFIT locked=",DoubleToString(locked,2));
      return(false);
   }
   if(!rUnknown && scoutMaxR<InpAddOnMinScoutR)
   {
      if(ThrottledLog(symbol+"|ADDON_R")) Print("ADDON_SKIP | symbol=",symbol," reason=SCOUT_R_TOO_LOW scoutR=",DoubleToString(scoutMaxR,2)," min=",DoubleToString(InpAddOnMinScoutR,2));
      return(false);
   }
   if(InpAddOnNewsVeto && InpNewsGuardEnabled)
   {
      double mins=0.0; string nw="";
      NewsGuardLoad();
      if(NewsEventNear(symbol,mins,nw))
      {
         if(ThrottledLog(symbol+"|ADDON_NEWS")) Print("ADDON_SKIP | symbol=",symbol," reason=NEWS_EVENT_WINDOW event=",nw," minutesToEvent=",DoubleToString(mins,1));
         return(false);
      }
   }
   double fundedRisk=locked*MathMin(100.0,MathMax(0.0,InpAddOnFundPct))/100.0-addOnOpenRisk;
   if(fundedRisk<=0.0)
   {
      if(ThrottledLog(symbol+"|ADDON_FUND")) Print("ADDON_SKIP | symbol=",symbol," reason=FUNDING_EXHAUSTED locked=",DoubleToString(locked,2));
      return(false);
   }
   Print("ADDON_FUNDED | symbol=",symbol," signal=",signalName," lockedUSD=",DoubleToString(locked,2),
         " scoutR=",(rUnknown?"unknown":DoubleToString(scoutMaxR,2)),
         " addOnRiskBudgetUSD=",DoubleToString(MathMin(fundedRisk,EntryRiskBudget()),2));
   // SendScout applies the remaining safety gates: quote, circuit breaker, adaptive SL/TP, spread, cost, aggregate risk, margin.
   bool ok=SendScout(symbol,signal,signalName,true,fundedRisk);
   if(!ok && ThrottledLog(symbol+"|ADDON_NOTOPEN"))
      Print("ADDON_NOT_OPENED | symbol=",symbol," signal=",signalName," see the ENTRY_SKIP/ORDER_SEND_FAIL line just above for the reason");
   return(ok);
}

//+------------------------------------------------------------------+
// SCAN_SKIP logging: the same reason for the same symbol is logged at most every InpSkipLogThrottleMin minutes.
void LogScanSkip(int index,string symbol,string why,string extra)
{
   if(!InpLogScannerDiagnostics) return;
   string base=why;
   int sp=StringFind(why," ");
   if(sp>0) base=StringSubstr(why,0,sp);
   datetime now=TimeCurrent();
   if(g_skipReason[index]==base && now-g_skipLogTime[index]<MathMax(1,InpSkipLogThrottleMin)*60) return;
   g_skipReason[index]=base;
   g_skipLogTime[index]=now;
   Print("SCAN_SKIP | symbol=",symbol," reason=",why,extra);
}

void ScanOne(int index)
{
   string symbol=g_symbols[index], why="";
   if(g_deadUntil[index]>TimeCurrent()) return;   // quarantined dead symbol: skipped until recheck time
   if(IsQuarantined(symbol)) return;               // v1.0.7: order error 133/132 quarantine
   if(!QuoteReady(symbol,why))
   {
      bool dead=(g_lastQuoteAge>=MathMax(3600,InpDeadQuoteAgeSec));
      if(dead) g_deadUntil[index]=TimeCurrent()+MathMax(60,InpDeadRecheckSec);
      LogScanSkip(index,symbol,why,
         " cryptoExpected24x7="+(IsCryptoSymbol(symbol)&&InpCryptoExpected24x7?"true":"false")+
         (dead?" quarantined=true":""));
      return;
   }
   g_deadUntil[index]=0;
   if(iBars(symbol,InpSignalTF)<MathMax(InpMinBars,InpBBPeriod+5))
   {
      LogScanSkip(index,symbol,"INSUFFICIENT_HISTORY bars="+IntegerToString(iBars(symbol,InpSignalTF)),"");
      return;
   }
   datetime bar=0;
   if(!IsNewSignalBar(index,symbol,bar)) return;
   int age=(int)(TimeCurrent()-bar);
   if(age<0 || age>InpEntryWindowSeconds)
   {
      LogScanSkip(index,symbol,"ENTRY_WINDOW_EXPIRED barAgeSec="+IntegerToString(age),"");
      return;
   }
   string name="",detail="";
   int signal=BollingerSignal(symbol,name,detail);
   if(signal==99)
   {
      Print("SIGNAL_ABSTAIN | symbol=",symbol," reason=",detail," strategy=BOLLINGER_ONLY");
      return;
   }
   if(signal==0)
   {
      if(detail!="") Print("SIGNAL_UNAVAILABLE | symbol=",symbol," reason=",detail);
      return;
   }
   NewsShadowLog(symbol); // Observational only: SCOUT entries remain eligible.
   string regimeWhy="";
   if(!RegimeAllows(symbol,signal,regimeWhy))
   {
      if(ThrottledLog(symbol+"|REGIME")) Print("SIGNAL_SKIP | symbol=",symbol," signal=",name," reason=REGIME_FILTER detail=",regimeWhy);
      return;
   }
   if(CountOurPositions(symbol,-1)>0)
   {
      if(TryFundedAddOn(symbol,signal,name)) return;
      if(ThrottledLog(symbol+"|POSLIMIT")) Print("SIGNAL_SKIP | symbol=",symbol," signal=",name," reason=SYMBOL_POSITION_LIMIT");
      return;
   }
   SendScout(symbol,signal,name);
}

void OnTimer()
{
   if(g_lastUniverseRefresh<=0 || TimeCurrent()-g_lastUniverseRefresh>=MathMax(60,InpUniverseRefreshSeconds))
      BuildUniverse();
   ManageOpenPositions();
   CleanupGlobals();
   if(g_symbolCount<=0 || TimeCurrent()-g_lastScan<MathMax(1,InpScanIntervalSeconds)) return;
   g_lastScan=TimeCurrent();
   for(int i=0;i<g_symbolCount;i++) ScanOne(i);
   if(InpHealthLogMinutes>0 && TimeCurrent()-g_lastHealthLog>=InpHealthLogMinutes*60)
   {
      g_lastHealthLog=TimeCurrent();
      int dead=0;
      for(int d=0;d<g_symbolCount;d++) if(g_deadUntil[d]>TimeCurrent()) dead++;
      Print("SCANNER_HEALTH | symbols=",g_symbolCount," quarantinedDead=",dead,
            " openPositions=",CountOurPositions("",-1)," scouts=",CountByKind(0)," addOns=",CountByKind(1)," openRiskUSD=",DoubleToString(OpenRiskMoney(),2));
   }
}

int OnInit()
{
   if(InpBBPeriod<2 || InpBBDeviation<=0.0 || InpRiskPercent<=0.0 ||
      InpMaxAggregateRiskPct<=0.0 || InpMaxOpenPositions<1 || InpStrategicCapitalUSD<=0.0 ||
      InpMaxMarginUsePctFree<=0.0 || InpMaxMarginUsePctFree>100.0 || InpUniverseRefreshSeconds<60 || InpMaxSymbols<0 || InpMaxQuoteAgeSec<1 || InpCryptoMaxQuoteAgeSec<InpMaxQuoteAgeSec || InpEntryWindowSeconds<1 ||
      InpMinAdaptiveTP_R<1.0 || InpMaxAdaptiveTP_R<InpMinAdaptiveTP_R || InpSLStructureBufferATR<0.0 ||
      InpMaxCostPctOfRisk<=0.0 || InpCooldownMinutes<0 || InpMaxConsecLosses<0 || InpMaxDailyLossUSD<0.0 || InpMaxEntriesPerHour<0 || InpSessionStartHour<0 || InpSessionStartHour>23 || InpSessionEndHour<0 || InpSessionEndHour>24 || InpStreakRiskScale<=0.0 || InpStreakRiskScale>1.0 || InpSymbolDayLossLimit<0 || InpMinTrailStepATR<0.0 || InpNetLossBufferUSD<0.0 || InpLossGuardRiskFrac<0.0 || InpLossGuardMaxBufferUSD<InpNetLossBufferUSD || InpLossGuardFloorUSD<0.0 || InpLossGuardGraceSec<0 || InpOtherCloseCostsPerLotUSD<0.0 ||
      InpPeakLockStartR<=0.0 || InpPeakLockMinFrac<0.0 || InpPeakLockMaxFrac>1.0 || InpPeakLockMaxFrac<InpPeakLockMinFrac || InpPeakLockSlope<0.0 ||
      InpTPWidthHighATR<=InpTPWidthLowATR || InpMaxPerCurrencyDir<0 ||
      InpSoftDailyLossUSD<0.0 || InpSoftLossPauseMin<0 ||
      (InpSoftDailyLossUSD>0.0 && InpMaxDailyLossUSD>0.0 && InpSoftDailyLossUSD>InpMaxDailyLossUSD) ||
      InpMaxAddOnsTotal<0 || InpAddOnMinScoutR<0.0 || InpAddOnSLScale<0.5 || InpAddOnSLScale>2.0 ||
      InpAddOnTPScale<0.5 || InpAddOnTPScale>3.0 ||
      InpDailyTargetUSD<=0.0 || InpDailyGiveBackPct<0.0 || InpDailyGiveBackPct>=100.0 || InpDailyLockFloorUSD<0.0 ||
      InpDailyEndBankHour<0 || InpDailyEndBankHour>23 || InpDailyEndBankMinUSD<0.0)
   {
      Print("INIT_FAILED | reason=INVALID_INPUT_CONFIGURATION");
      return(INIT_PARAMETERS_INCORRECT);
   }
   if(AccountCurrency()!="USD")
   {
      Print("INIT_FAILED | reason=ACCOUNT_CURRENCY_MUST_BE_USD_FOR_FIXED_USD_RISK currency=",AccountCurrency());
      return(INIT_FAILED);
   }
   if(!InpNewsGuardShadowOnly)
   {
      Print("INIT_FAILED | reason=NEWS_GUARD_MUST_REMAIN_SHADOW_ONLY_IN_V1_0_6");
      return(INIT_PARAMETERS_INCORRECT);
   }
   BuildUniverse();
   if(g_symbolCount<=0)
   {
      Print("INIT_FAILED | reason=EMPTY_SYMBOL_UNIVERSE");
      return(INIT_FAILED);
   }
   EventSetTimer(1);
   Print("EA_READY | name=",EA_NAME," version=",EA_VER,
         " symbols=",g_symbolCount,
         " signalIndicators=BOLLINGER_BANDS_ONLY",
         " strategicCapitalUSD=",DoubleToString(StrategyCapitalUSD(),2),
         " riskPerTradeUSD=",DoubleToString(EntryRiskBudget(),2),
         " aggregateRiskCapUSD=",DoubleToString(AggregateRiskCapUSD(),2),
         " netLossGuard=costs+max(",DoubleToString(InpNetLossBufferUSD,2),",",DoubleToString(InpLossGuardRiskFrac,2),"*risk)<=",DoubleToString(InpLossGuardMaxBufferUSD,2)," floorUSD=",DoubleToString(InpLossGuardFloorUSD,2)," graceSec=",InpLossGuardGraceSec,
         " peakLock=",(InpPeakLockEnabled?"ON":"OFF")," start=",DoubleToString(InpPeakLockStartR,2),"R frac=",DoubleToString(InpPeakLockMinFrac,2),"-",DoubleToString(InpPeakLockMaxFrac,2),
         " adaptiveSL=ATR_PLUS_SIGNAL_STRUCTURE adaptiveTP=BB_WIDTH_VS_ATR",
         " marginGuardMaxFreePct=",DoubleToString(InpMaxMarginUsePctFree,1),
         " pyramiding=FUNDED_ADDONS_ONLY",
         " modes=REBOUND+BREAKOUT conflictPolicy=ABSTAIN",
         " newsGuard=SHADOW_ONLY scoutsNotBlocked=true",
         " fundedAddOns=",(InpAddOnEnabled?"ENABLED":"DISABLED")," addOnFundPct=",DoubleToString(InpAddOnFundPct,0)," maxAddOnsPerSymbol=",InpMaxAddOnsPerSymbol,
         " universeRefreshSec=",MathMax(60,InpUniverseRefreshSeconds),
         " maxSymbols=",(InpMaxSymbols<=0?"ALL":IntegerToString(InpMaxSymbols)),
         " universeSource=",(StringLen(InpSymbolsCSV)>0?"EXPLICIT_CSV":(InpScanMarketWatch?"MARKET_WATCH":"ALL_BROKER_SYMBOLS")),
         " crypto24x7=EXPECTED_ONLY_FRESH_QUOTE_AND_BROKER_PERMISSION_REQUIRED",
         " cryptoDiscoveryPriority=FIRST",
         " universeDone=true");
   Print("EA_READY_LOSSCONTROL | name=",EA_NAME," version=",EA_VER,
         " lossControl=cooldown",(InpCooldownEnabled?IntegerToString(InpCooldownMinutes)+"min":"OFF"),
         " maxConsecLosses=",InpMaxConsecLosses," dailySoftUSD=",DoubleToString(InpSoftDailyLossUSD,2)," softPauseMin=",InpSoftLossPauseMin," dailyHardCapUSD=",DoubleToString(InpMaxDailyLossUSD,2),
         " regimeFilter=",(InpRegimeFilterEnabled?"ON":"OFF")," costGatePct=",(InpCostFilterEnabled?DoubleToString(InpMaxCostPctOfRisk,1):"OFF"),
         " quarantineMin=",InpQuarantineMinutes,
         " addOnMaxTotal=",InpMaxAddOnsTotal," addOnMinScoutR=",DoubleToString(InpAddOnMinScoutR,2),
         " addOnSLx=",DoubleToString(InpAddOnSLScale,2)," addOnTPx=",DoubleToString(InpAddOnTPScale,2),
         " addOnNewsVeto=",(InpAddOnNewsVeto?"ON":"OFF"),
         " tpWidthATR=",DoubleToString(InpTPWidthLowATR,1),"-",DoubleToString(InpTPWidthHighATR,1),
         " maxPerCurrencyDir=",InpMaxPerCurrencyDir," underlyingDupBlock=",(InpBlockUnderlyingDup?"ON":"OFF"));
   Print("EA_READY_V16 | maxEntriesPerHour=",InpMaxEntriesPerHour," sessionFilter=",(InpSessionFilterEnabled?"ON":"OFF")," window=",InpSessionStartHour,"-",InpSessionEndHour,
         " cryptoSession=",(InpCryptoSessionFilter?"ON":"OFF")," shortsNeedBearishRegime=",(InpShortsNeedBearishRegime?"ON":"OFF"),
         " streakScaleAfter=",InpStreakScaleAfter," streakRiskScale=",DoubleToString(InpStreakRiskScale,2)," symbolDayLossLimit=",InpSymbolDayLossLimit,
         " minTrailStepATR=",DoubleToString(InpMinTrailStepATR,2)," lossBufferUSD=",DoubleToString(InpNetLossBufferUSD,2)," lossRiskFrac=",DoubleToString(InpLossGuardRiskFrac,2),
         " peakLockStartR=",DoubleToString(InpPeakLockStartR,2));
   Print("EA_READY_V18 | quoteAgeFXSec=",InpMaxQuoteAgeSec," quoteAgeCryptoSec=",InpCryptoMaxQuoteAgeSec," entryWindowSec=",InpEntryWindowSeconds,
         " dailyBank=",(InpDailyBankEnabled?"ON":"OFF")," targetUSD=",DoubleToString(InpDailyTargetUSD,2)," haltAtTarget=",(InpDailyHaltAtTarget?"true":"false"),
         " giveBackPct=",DoubleToString(InpDailyGiveBackPct,0)," lockFloorUSD=",DoubleToString(InpDailyLockFloorUSD,2),
         " endBankHour=",InpDailyEndBankHour," endBankMinUSD=",DoubleToString(InpDailyEndBankMinUSD,2),
         " softDailyLossUSD=",DoubleToString(InpSoftDailyLossUSD,2)," hardDailyLossUSD=",DoubleToString(InpMaxDailyLossUSD,2));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   Print("EA_STOP | name=",EA_NAME," reason=",reason);
}

void OnTick()
{
   ManageOpenPositions();
}
//+------------------------------------------------------------------+