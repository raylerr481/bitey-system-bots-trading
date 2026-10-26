//+------------------------------------------------------------------+
//| Bitey_Ensemble_Scalper_MultiAsset_v1_8_0_0_ThirtyEvaluatorsExperimental.mq4      |
//| EXPERIMENTAL 30-evaluator multi-asset scalper (max 5), BUY/SELL.   |
//| Preserves adaptive SL/TP and existing risk controls.               |
//| v1.7.2 = v1.7.1 + gross FX currency cap + diversification ranking:   |
//|  - InpMaxCcyGross: max positions touching one FX currency in ANY     |
//|    direction (v1.7.1 only capped the NET, so 2 long + 2 short JPY    |
//|    crosses looked "flat" while all four rode the same yen factor).   |
//|  - Candidates are ranked by score MINUS a penalty for piling onto    |
//|    exposure that is already open (InpDiversifyPenalty), re-ranked    |
//|    after every entry: the bot prefers the best UNCORRELATED trade.   |
//|    This changes which trades are picked, not the signals themselves. |
//| v1.7.1 = YOUR v1.6.1 (all kept) + MASTER1011 ideas + Agresivo brakes |
//|  - Envelope reversion family (ATR-scaled, from MASTER1011): range-   |
//|    regime confirmation/veto. Inert while InpAllowRangeRegime=false.  |
//|  - Mean-reversion exit for range trades, judged on NET profit.       |
//|    Inert while InpAllowRangeRegime=false.                            |
//|  - Monthly drawdown brake, optional monthly target, optional flatten |
//|    (EA_Agresivo_Mensual), restart-safe (built from history).         |
//|  - Hard equity floor safety stop (MASTER1011 CashAccount), OFF by    |
//|    default so account type/size never gates trading.                 |
//|  - Correlation guard: crypto cluster cap + FX currency exposure cap. |
//|  - Fix: InpDailyLossPct=0 now disables the daily brake (before it    |
//|    blocked entries whenever the day P&L was <= 0).                   |
//| Kept intact from v1.6.1: net profit lock in R, auto *USDT 24/7,      |
//|  MaxCostR 0.20, IsCrypto USD/USDT fix, CSV duplicate guard,          |
//|  adaptive SL/TP, BUY+SELL, multi-asset (max 5).                      |
//| v1.6.1: auto-add every tradable *USDT symbol (24/7 incl. weekends), CSV duplicate-row guard.
//| v1.6.0: profit lock sized in R (not flat USD), MaxCostR 0.20, range regime OFF by default (hypotheses to A/B test).
//| v1.5.4: IsCrypto needs a USD/USDT quote in the name (stock CFDs no longer misread as crypto).
//| v1.5.3: adds cost-aware net USD profit lock after +$1; v1.5.2: auto-add tradable cryptos.
//| v1.5.0: tester = chart symbol only, regime tag + toggles, equity-risk option, Friday flat, M15 default.
//| v1.4.0.3: MFE/MAE CSV per trade, throttled reject logs, no entry on the start bar, TP-expand toggle.
//| v1.4.0.2: TP step + log fixes. v1.4.0: cost-aware (commission+spread), lot caps, circuit         |
//| breakers, rollover handling, BE/trail that cover costs.           |
//| v1.8.0.0 EXPERIMENTAL: 30 evaluators, 2 assemblies, CSV audit.  |
//| Not compiled or performance-validated; test in MT4 Strategy Tester. |
//+------------------------------------------------------------------+
#property strict

#include <Bitey_Ensemble_Experimental_CSV_Audit.mqh>

// A/B exit presets to compare in the Strategy Tester (same period, every tick, real commission):
//  A) Current:      StopATR 1.5 | RR 1.8 | BE 1.5 | TrailStart 1.8 | TrailDist 1.2 | TPExpand true
//  B) No BE/trail:  InpEnableAdaptiveExits=false | RR 1.5
//  C) Fixed TP only: BE 0 | TrailStart 0 | TPExpand false | RR 1.2
//  D) Trail only:   BE 0 | TrailStart 1.5 | TrailDist 1.5 | RR 2.5
#property version   "1.800"
#property description "Experimental 30 evaluators / two assemblies / CSV audit; not performance validated"

#define EA_VERSION          "1.8.0.0-EXP"
#define MAX_SYMBOLS         256
#define HARD_MAX_POSITIONS  5

//--- universe and timeframes
input string           InpSymbolsCSV            = "";      // Blank = symbols in Market Watch (aliases deduplicated)
input bool             InpAutoAddCrypto         = true;    // v1.5.2: add every tradable crypto the broker offers (not only Market Watch)
input bool             InpAutoAddUSDT           = true;    // v1.6.1: add every tradable *USDT symbol the broker offers (weekend-capable)
input bool             InpUSDTIs24x7            = true;    // *USDT symbols skip session filter and Friday flat (spread/staleness filters still apply)
input string           InpExtraCryptoPrefixes   = "";      // Extra crypto base tickers for auto-add, e.g. "PEPE,TON,SUI"
input string           InpExtraSymbolsCSV       = "NEARUSDT,ZECUSDT"; // Always included; replaces a same-asset alias already listed (e.g. NEARUSD)
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M15; // M15: wider stops dilute spread+commission (was M5)
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_H1;   // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102027;

//--- risk (risk per trade INCLUDES round-turn commission)
input double           InpReferenceCapitalUSD   = 500.0;
input bool             InpUseEquityRisk         = false;   // true = size risk on min(balance,equity) instead of the reference capital
input double           InpRiskPctPerTrade       = 0.5;     // 5 positions x 0.5% = 2.5% aggregate
input double           InpMaxAggregateRiskPct   = 2.5;
input double           InpDailyLossPct          = 3.0;     // Blocks NEW entries; open trades stay managed
input int              InpMaxOpenPositions      = 5;       // Clamped to 1..5, one position per asset
input double           InpMaxLotsFX             = 0.30;    // Hard lot cap, forex pairs
input double           InpMaxLotsOther          = 0.10;    // Hard lot cap, metals/crypto/stocks/indices

//--- costs (round-turn commission per 1.00 lot, account currency)
input double           InpCommissionPerLotFX    = 10.0;    // Tradewill statement: 0.01 lot = 0.10
input double           InpCommissionPerLotOther = 15.0;    // Tradewill statement: 0.01 lot = 0.15
input double           InpMaxCostR              = 0.20;    // Skip if (spread+commission) > this fraction of the stop (R)

//--- direction
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- signal
input int              InpFamilyMinVotes        = 3;       // Of 5 evaluators needed for a family to speak
input int              InpAssemblyMinFamilies   = 3;       // Trend assembly: minimum agreeing families (out of 4)
input int              InpAssemblyMinModelVotes = 3;       // Minimum directional models inside a family (out of 5)
input double           InpTrendADX              = 20.0;
input bool             InpAllowTrendRegime      = true;    // A/B: disable to test range-only
input bool             InpAllowRangeRegime      = false;    // A/B: disable to test trend-only    // ADX >= this: trend regime, otherwise range regime
input double           InpMinADX                = 10.0;    // Dead-market filter
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.5;
input double           InpRewardRisk            = 1.8;     // Raised from 1.5: winners must pay for the losers

//--- execution filters
input double           InpMaxSpreadPctOfStop    = 10.0;    // Spread must be <= this % of the stop distance
input int              InpMaxSpreadPoints       = 0;       // Optional absolute cap, 0 = off
input int              InpMaxQuoteAgeSec        = 120;
input int              InpSlippagePoints        = 20;
input int              InpMinBars               = 250;
input bool             InpUseSessionFilter      = true;    // Server hours; crypto is exempt
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 6;       // Bars to wait on a symbol after a LOSING trade
input int              InpReentryBars           = 3;       // Bars to wait on a symbol after a winning/flat trade
input int              InpMaxHoldBars           = 48;      // Time exit (0 = off)

//--- rollover (swap/spread widening)
input bool             InpBlockRollover         = true;    // No new entries inside the window
input bool             InpFlatBeforeRollover    = true;
input int              InpFridayFlatHour        = 22;      // Server hour on Friday: no entries and flat (non-crypto). 0 = off    // Close open trades when the window starts (avoids swap)
input int              InpRolloverStartMin      = 1410;    // Server minute of day (1410 = 23:30)
input int              InpRolloverEndMin        = 15;      // Server minute of day (15 = 00:15)

//--- circuit breakers
input int              InpMaxConsecLosses       = 4;       // Pause all new entries after N losing closes in a row (0 = off)
input int              InpLossStreakPauseMin    = 60;
input int              InpExpectancyWindow      = 20;      // Last N closed trades per symbol
input int              InpExpectancyMinTrades   = 12;      // Need at least this many before judging a symbol
input int              InpExpectancyBanHours    = 24;      // Ban a symbol this long after its last close if net expectancy < 0

//--- v1.7.1 portfolio brakes (EA_Agresivo_Mensual + MASTER1011 safety stop). Percentages are of the risk capital.
input double           InpMonthDDPct            = 8.0;     // Blocks NEW entries when this month's net P&L <= -X% (0 = off)
input double           InpMonthTargetPct        = 0.0;     // Optional: blocks NEW entries once this month's net P&L >= +X% (0 = off)
input bool             InpCloseAllOnMonthHalt   = false;   // true = also flatten every position when the monthly drawdown brake trips
input double           InpEquityFloorUSD        = 0.0;     // Hard stop: flatten and halt if min(balance,equity) < this (0 = off; never tied to demo/real)

//--- v1.7.1 correlation guard (5 positions must not be one bet in disguise)
input bool             InpUseCorrelationGuard   = true;
input int              InpMaxCryptoPositions    = 2;       // Max simultaneous crypto positions (0 = no cap)
input int              InpMaxCcyExposure        = 2;       // Max net same-direction positions on one FX currency (0 = no cap)
input int              InpMaxCcyGross           = 3;       // v1.7.2: max positions touching one FX currency in ANY direction (0 = no cap)
input double           InpDiversifyPenalty      = 4.0;     // v1.7.2: score penalty per unit of same-direction overlap with open positions (0 = rank by raw score)

//--- v1.7.1 envelope reversion family (from MASTER1011). Only used in the RANGE regime: needs InpAllowRangeRegime=true
input bool             InpUseEnvelopeFamily     = true;    // Range regime: envelope agreeing = score bonus, envelope opposing = veto
input bool             InpEnvelopeCanTrigger    = false;   // true = envelope alone may open a range trade (default: confirmation/veto only)
input bool             InpEnvelopeRequireConfirm= false;   // true = range trades need the envelope to agree
input double           InpEnvelopeATRScale      = 1.0;     // Multiplies the 8 band widths (0.6..1.3 ATR)

//--- v1.7.1 mean-reversion exit for range-regime trades (net-profit based, never below cost). Needs InpAllowRangeRegime=true
input bool             InpUseMeanExit           = true;
input int              InpExitMAPeriod          = 20;      // SMA used as the mean
input double           InpExitBandATR           = 1.0;     // Opposite band = mean +/- this many ATR
input double           InpMeanExitMinR          = 0.5;     // At the mean, close only if net profit >= this fraction of R

//--- adaptive SL/TP
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.0;     // Start protecting sooner; broker stop/freeze levels still apply
input double           InpBreakEvenLockATR      = 0.15;    // Plus commission is added automatically
input double           InpTrailStartATR         = 1.2;
input double           InpTrailDistanceATR      = 0.9;
input double           InpTrailStepATR          = 0.08;    // Minimum SL improvement per modification
input double           InpTrailTightenPerATR     = 0.15;    // Tighten trail as unrealized gain grows
input double           InpTrailMinDistanceATR    = 0.45;    // Minimum ATR distance for adaptive trail
input double           InpTPExpandTriggerATR    = 1.5;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandStepATR       = 0.25;    // Minimum TP extension per modification (fewer broker requests)
input bool             InpEnableTPExpand        = true;    // false = fixed TP (A/B tests)
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 5.0;
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)
input bool             InpEnableNetProfitLock    = true;    // Cost-aware USD profit lock after net trigger
input double           InpProfitLockTriggerR    = 0.50;    // Begin cost-aware profit protection earlier
input double           InpProfitLockTargetR     = 0.10;    // Net profit (in R) targeted by the SL after estimated costs
input double           InpProfitLockStepR       = 0.05;    // Smaller steps to ratchet the net lock upward
input bool             InpEnableConfirmedReversalExit = true; // Exit profitable trades on a closed-bar EMA reversal
input int              InpReversalFastMAPeriod   = 9;
input int              InpReversalSlowMAPeriod   = 21;
input double           InpReversalExitMinR       = 0.0;     // 0 = exit once net P/L is non-negative; no fill guarantee

input bool             InpEnableTrading         = true;    // false = log candidates only
input bool             InpLogRejects            = false;
input bool             InpLogTradesCSV          = true;    // Per-trade audit CSV -> terminal MQL4\Files\Bitey_Ens_TradeAudit_<magic>.csv
input bool             InpLogAssetSummaryCSV    = true;    // Net summary CSV in this terminal MQL4\\Files folder
input int              InpRejectLogMinutes      = 60;      // Throttle SPREAD/COST reject logs per symbol (0 = log all)

string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
datetime g_lastDailyBlockLog = 0;
datetime g_lastCsvScan = 0;
datetime g_lastNetSummaryScan = 0;
bool     g_haltAll = false;    // v1.7.1: equity floor tripped, flatten and stop for this session
int      g_tmpRegime = 0;      // 1 = trend, 2 = range (set by Analyze)
int      g_tmpValidModels = 0;
int      g_tmpBuyVotes = 0;
int      g_tmpSellVotes = 0;
int      g_candReg[MAX_SYMBOLS];
datetime g_lastRejectLog[MAX_SYMBOLS];

string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];
bool     g_candUsed[MAX_SYMBOLS];
int      g_candBuyVotes[MAX_SYMBOLS];
int      g_candSellVotes[MAX_SYMBOLS];

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   AddExtraSymbols();
   AddAllCrypto();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   for(int i=0;i<g_symbolCount;i++)
   {
      g_lastBar[i]=0;
      SymbolSelect(g_symbols[i],true);
   }
   EventSetTimer(1);
   Print("BITEY_ENSEMBLE_INIT | version=",EA_VERSION," | symbols=",g_symbolCount,
         " | maxPositions=",MaxPositions()," | tf=",(int)InpSignalTF,
         " | accountMode=NOT_A_GATE | trading=",(InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason) { EventKillTimer(); }
void OnTick()  { RunCycle(); }
void OnTimer() { RunCycle(); }

int MaxPositions()
{
   return(MathMin(HARD_MAX_POSITIONS,MathMax(1,InpMaxOpenPositions)));
}

//+------------------------------------------------------------------+
//| Asset key: strips prefix/suffix so broker aliases collapse        |
//+------------------------------------------------------------------+
string AssetKey(string s)
{
   StringToUpper(s);
   if(StringLen(s)>0 && StringGetChar(s,0)=='#') s=StringSubstr(s,1);
   string k="";
   for(int i=0;i<StringLen(s) && StringLen(k)<6;i++)
   {
      int ch=StringGetChar(s,i);
      bool alnum=((ch>='0' && ch<='9') || (ch>='A' && ch<='Z'));
      if(!alnum) break;
      k+=CharToString((uchar)ch);
   }
   return(k);
}

bool IsUSDTSymbol(string sym)
{
   string nm=sym;
   StringToUpper(nm);
   return(StringFind(nm,"USDT")>=1);
}

bool IsCrypto(string sym)
{
   string k=AssetKey(sym);
   string nm=sym;
   StringToUpper(nm);
   if(InpUSDTIs24x7 && StringFind(nm,"USDT")>=1) return(true);
   if(StringFind(nm,"USD")<2) return(false);   // crypto CFDs here are quoted vs USD/USDT; avoids stock tickers like LIN, UNI, COMP
   string p[60]={"BTC","XBT","ETH","SOL","XRP","LTC","BCH","DOG","ADA","DOT","LIN","AVA","BNB","NEA",
                 "ZEC","TRX","ATO","FIL","ALG","DAS","IOT","ETC","UNI","AXS","HYP",
                 "SHI","MATIC","POL","XLM","XMR","EOS","NEO","AAVE","APT","ARB","SUI","INJ","TON","ICP",
                 "HBAR","VET","SAND","MANA","CRV","GRT","XTZ","COMP","MKR","SNX","RUNE","FTM","EGLD","KAS","OP","PEPE","BONK","WLD","SEI","TIA","JUP"};
   for(int i=0;i<60;i++)
      if(StringFind(k,p[i])==0) return(true);
   string ex=InpExtraCryptoPrefixes;
   StringToUpper(ex);
   while(StringLen(ex)>0)
   {
      int q=StringFind(ex,",");
      string t;
      if(q<0) { t=ex; ex=""; } else { t=StringSubstr(ex,0,q); ex=StringSubstr(ex,q+1); }
      StringTrimLeft(t); StringTrimRight(t);
      if(StringLen(t)>0 && StringFind(k,t)==0) return(true);
   }
   return(false);
}

bool IsCcy(string c)
{
   string l[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   for(int i=0;i<8;i++)
      if(c==l[i]) return(true);
   return(false);
}

bool IsForex(string sym)
{
   string k=AssetKey(sym);
   if(StringLen(k)!=6) return(false);
   return(IsCcy(StringSubstr(k,0,3)) && IsCcy(StringSubstr(k,3,3)));
}

double CommissionPerLot(string sym)
{
   return(IsForex(sym)?InpCommissionPerLotFX:InpCommissionPerLotOther);
}

double LotCap(string sym)
{
   return(IsForex(sym)?InpMaxLotsFX:InpMaxLotsOther);
}

void ParseSymbols()
{
   g_symbolCount=0;
   if(IsTesting()) { AddSymbol(Symbol()); return; }   // Strategy Tester models the chart symbol only
   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   if(StringLen(csv)==0)
   {
      int total=SymbolsTotal(true);
      for(int i=0;i<total && g_symbolCount<MAX_SYMBOLS;i++)
         AddSymbol(SymbolName(i,true));
      return;
   }
   while(StringLen(csv)>0 && g_symbolCount<MAX_SYMBOLS)
   {
      int p=StringFind(csv,",");
      string s;
      if(p<0) { s=csv; csv=""; }
      else { s=StringSubstr(csv,0,p); csv=StringSubstr(csv,p+1); }
      StringTrimLeft(s); StringTrimRight(s);
      AddSymbol(s);
   }
}

void AddSymbol(string s)
{
   if(StringLen(s)<=0) return;
   string k=AssetKey(s);
   if(StringLen(k)<3) return;
   for(int i=0;i<g_symbolCount;i++)
      if(g_keys[i]==k) return;            // alias of an asset already listed
   g_symbols[g_symbolCount]=s;
   g_keys[g_symbolCount]=k;
   g_symbolCount++;
}

//+------------------------------------------------------------------+
//| Main cycle: manage exits, collect candidates, open the best ones  |
//+------------------------------------------------------------------+
void RunCycle()
{
   if(!IsTesting())
   {
      uint nowTick=GetTickCount();
      if(g_lastCycleTick!=0 && (nowTick-g_lastCycleTick)<900) return;
      g_lastCycleTick=nowTick;
   }

   ManageExits();
   LogClosedTrades();
   WriteAssetNetSummary(); // Read-only audit; does not alter orders or signals
   CheckHaltActions();                     // v1.7.1: equity floor / monthly flatten (no-ops by default)

   int maxPos=MaxPositions();
   bool lossBlock=LossStreakBlock();       // circuit breaker: pauses NEW entries only
   int limit=(lossBlock?0:g_symbolCount);
   int nc=0;
   for(int i=0;i<limit;i++)
   {
      string sym=g_symbols[i];
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      bool firstSight=(g_lastBar[i]==0);
      g_lastBar[i]=bt;                      // one evaluation per closed bar per symbol
      if(firstSight) continue;              // never trade on the bar where the EA started

      if(CountOpenPositions()+nc>=maxPos) { Reject(sym,"MAX_POSITIONS"); continue; }
      int cmd; double score; string why;
      if(!Prefilter(sym,why))
      {
         BiteyCsvLogAssetAssembly(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,
            sym,InpSignalTF,0.0,0.0,0.0,0,0,0,false,"PREFILTER_REJECT_"+why);
         Reject(sym,why); continue;
      }
      if(!Analyze(sym,cmd,score,why))
      {
         BiteyCsvLogAssetAssembly(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,
            sym,InpSignalTF,score,0.0,0.0,g_tmpValidModels,g_tmpBuyVotes,g_tmpSellVotes,false,"SIGNAL_REJECT_"+why);
         Reject(sym,why); continue;
      }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); continue; }
      BiteyCsvLogAssetAssembly(sym+"_"+IntegerToString((int)iTime(sym,InpSignalTF,1)),EA_VERSION,sym,InpSignalTF,
         score,0.0,0.0,g_tmpValidModels,g_tmpBuyVotes,g_tmpSellVotes,false,"ELIGIBLE_CANDIDATE_POOL");
      g_candSym[nc]=sym; g_candCmd[nc]=cmd; g_candScore[nc]=score; g_candReg[nc]=g_tmpRegime;
      g_candBuyVotes[nc]=g_tmpBuyVotes; g_candSellVotes[nc]=g_tmpSellVotes; nc++;
   }

   if(nc>0)
   {
      // sort candidates by score, best first
      for(int a=0;a<nc-1;a++)
         for(int b=a+1;b<nc;b++)
            if(g_candScore[b]>g_candScore[a])
            {
               string ts=g_candSym[a]; g_candSym[a]=g_candSym[b]; g_candSym[b]=ts;
               int tc=g_candCmd[a];    g_candCmd[a]=g_candCmd[b];  g_candCmd[b]=tc;
               double td=g_candScore[a]; g_candScore[a]=g_candScore[b]; g_candScore[b]=td;
               int tg=g_candReg[a];     g_candReg[a]=g_candReg[b];     g_candReg[b]=tg;
               int tb=g_candBuyVotes[a]; g_candBuyVotes[a]=g_candBuyVotes[b]; g_candBuyVotes[b]=tb;
               int tsell=g_candSellVotes[a]; g_candSellVotes[a]=g_candSellVotes[b]; g_candSellVotes[b]=tsell;
            }

      string blockWhy=EntryBlockReason();   // equity floor, daily loss, monthly drawdown, monthly target
      if(blockWhy!="")
      {
         if(g_lastDailyBlockLog==0 || TimeCurrent()-g_lastDailyBlockLog>=300)
         {
            g_lastDailyBlockLog=TimeCurrent();
            Print("ENTRY_BLOCK | reason=",blockWhy," dayNet=",DoubleToString(TodayNet(),2),
                  " monthNet=",DoubleToString(MonthNet(),2)," | no new entries; open trades stay managed");
         }
      }
      else
      {
         // v1.7.2: pick the best candidate by (score - overlap penalty), re-ranked after every entry,
         // so the 5 slots go to the best UNCORRELATED trades instead of the 5 highest raw scores.
         for(int c0=0;c0<nc;c0++) g_candUsed[c0]=false;
         for(int pick=0;pick<nc;pick++)
         {
            if(CountOpenPositions()>=maxPos) break;
            int best=-1; double bestAdj=-1.0e100, bestOv=0.0;
            for(int c=0;c<nc;c++)
            {
               if(g_candUsed[c]) continue;
               double ov=DiversifyOverlap(g_candSym[c],g_candCmd[c]);
               double adj=g_candScore[c]-InpDiversifyPenalty*ov;
               if(adj>bestAdj) { bestAdj=adj; best=c; bestOv=ov; }
            }
            if(best<0) break;
            g_candUsed[best]=true;
            string corrWhy="";
            if(!CorrelationOK(g_candSym[best],g_candCmd[best],corrWhy))
            {
               Reject(g_candSym[best],corrWhy);
               if(RejectLogDue(g_candSym[best])) Print("CORRELATION_BLOCK | symbol=",g_candSym[best]," reason=",corrWhy);
               continue;
            }
            if(bestOv>0.0)
               Print("DIVERSIFY_RANK | symbol=",g_candSym[best]," rawScore=",DoubleToString(g_candScore[best],1),
                     " overlap=",DoubleToString(bestOv,1)," adjScore=",DoubleToString(bestAdj,1));
            BiteyCsvLogAssetAssembly(g_candSym[best]+"_"+IntegerToString((int)iTime(g_candSym[best],InpSignalTF,1)),EA_VERSION,
               g_candSym[best],InpSignalTF,g_candScore[best],0.0,0.0,30,g_candBuyVotes[best],g_candSellVotes[best],true,"ASSEMBLY1_SELECTED_FOR_EXECUTION");
            OpenTrade(g_candSym[best],g_candCmd[best],g_candScore[best],g_candReg[best]);
         }
      }
   }

   datetime now=TimeCurrent();
   if(g_lastHeartbeat==0 || now-g_lastHeartbeat>=300)
   {
      g_lastHeartbeat=now;
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(TodayNet(),2)," monthNet=",DoubleToString(MonthNet(),2)," symbols=",g_symbolCount,
            " lossStreakPause=",(lossBlock?"ON":"off")," equityHalt=",(g_haltAll?"ON":"off"));
   }
}

void Reject(string sym,string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}

//+------------------------------------------------------------------+
//| Cheap checks that do not need indicators                          |
//+------------------------------------------------------------------+
bool QuoteFresh(string sym)
{
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
   if(qt<=0) return(false);
   int age=(int)(TimeCurrent()-qt);
   return(age>=-5 && age<=InpMaxQuoteAgeSec);
}

bool SessionOK(string sym)
{
   if(!InpUseSessionFilter || IsCrypto(sym)) return(true);
   int h=TimeHour(TimeCurrent());
   if(InpSessionStartHour<InpSessionEndHour) return(h>=InpSessionStartHour && h<InpSessionEndHour);
   return(h>=InpSessionStartHour || h<InpSessionEndHour);
}

bool InRolloverWindow()
{
   datetime t=TimeCurrent();
   int m=TimeHour(t)*60+TimeMinute(t);
   if(InpRolloverStartMin>InpRolloverEndMin) return(m>=InpRolloverStartMin || m<InpRolloverEndMin);
   return(m>=InpRolloverStartMin && m<InpRolloverEndMin);
}

bool Prefilter(string sym,string &why)
{
   why="";
   if(!IsTradeAllowed()) { why="TERMINAL_TRADING_NOT_ALLOWED"; return(false); }
   if(InpBlockRollover && InRolloverWindow()) { why="ROLLOVER_WINDOW"; return(false); }
   if(FridayCutoff(sym)) { why="FRIDAY_CUTOFF"; return(false); }
   if(MarketInfo(sym,MODE_TRADEALLOWED)==0) { why="SYMBOL_TRADING_DISABLED"; return(false); }
   if(iBars(sym,InpSignalTF)<InpMinBars) { why="INSUFFICIENT_HISTORY"; return(false); }
   if(!QuoteFresh(sym)) { why="STALE_QUOTE"; return(false); }
   if(!SessionOK(sym)) { why="OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetKey(sym))) { why="POSITION_ALREADY_OPEN"; return(false); }
   if(InCooldown(sym)) { why="COOLDOWN"; return(false); }
   if(SymbolExpectancyBad(sym)) { why="NEGATIVE_EXPECTANCY_BAN"; return(false); }
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   if(bid<=0 || ask<bid || point<=0) { why="INVALID_QUOTE"; return(false); }
   if(InpMaxSpreadPoints>0 && (ask-bid)/point>InpMaxSpreadPoints) { why="SPREAD_POINTS_CAP"; return(false); }
   return(true);
}

//+------------------------------------------------------------------+
//| Signal: 4 families x 8 variants, regime aware                     |
//|  trend regime (ADX>=InpTrendADX): trend+momentum+breakout, 2 of 3 |
//|  range regime: Bollinger re-entry + RSI extreme, no opposing mom. |
//+------------------------------------------------------------------+
void Vote(bool buy,bool sell,int &b,int &s)
{
   if(buy && !sell) b++;
   else if(sell && !buy) s++;
}

int FamilyDir(int b,int s)
{
   if(b>=InpFamilyMinVotes && b>2*s) return(1);
   if(s>=InpFamilyMinVotes && s>2*b) return(-1);
   return(0);
}

bool Analyze(string sym,int &cmd,double &score,string &why)
{
   cmd=-1; score=0.0; why="";
   g_tmpValidModels=0; g_tmpBuyVotes=0; g_tmpSellVotes=0;
   int tf=InpSignalTF;
   double c1=iClose(sym,tf,1), c2=iClose(sym,tf,2);
   double atr=iATR(sym,tf,InpATRPeriod,1);
   double adx=iADX(sym,tf,14,PRICE_CLOSE,MODE_MAIN,1);
   double rsi14=iRSI(sym,tf,14,PRICE_CLOSE,1);
   if(c1<=0 || c2<=0 || atr<=0 || adx<0 || rsi14<0) { why="INDICATOR_DATA_INVALID"; return(false); }
   if(adx<InpMinADX) { why="DEAD_MARKET_ADX"; return(false); }

   // 30 evaluators = 6 strategy families x 5 variants. Family-level aggregation
   // reduces duplicate/correlated votes before the assemblies decide.
   int modelDir[30]; double modelScore[30];
   string modelName[30]; string modelFamily[30];
   ArrayInitialize(modelDir,0); ArrayInitialize(modelScore,0.0);
   int fastEMA[5]={5,8,13,21,34}, slowEMA[5]={21,34,50,89,144};
   int macdFast[5]={5,8,10,12,15}, macdSlow[5]={13,17,21,26,30}, macdSig[5]={3,5,7,9,10};
   int donLen[5]={5,8,12,18,24}, rsiLen[5]={7,9,14,21,28};
   int bbLen[5]={10,14,20,24,30}, stochLen[5]={5,7,9,14,21};

   for(int k=0;k<5;k++)
   {
      int ix=k;
      double f=iMA(sym,tf,fastEMA[k],0,MODE_EMA,PRICE_CLOSE,1);
      double sl=iMA(sym,tf,slowEMA[k],0,MODE_EMA,PRICE_CLOSE,1);
      double fp=iMA(sym,tf,fastEMA[k],0,MODE_EMA,PRICE_CLOSE,2);
      if(f>0 && sl>0 && fp>0)
      { if(f>sl && c1>f && f>=fp) modelDir[ix]=1; else if(f<sl && c1<f && f<=fp) modelDir[ix]=-1; }
      modelScore[ix]=modelDir[ix]; modelName[ix]="EMA_"+IntegerToString(k+1); modelFamily[ix]="EMA_TREND";

      ix=5+k;
      double mm=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_MAIN,1);
      double ms=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_SIGNAL,1);
      double mprev=iMACD(sym,tf,macdFast[k],macdSlow[k],macdSig[k],PRICE_CLOSE,MODE_MAIN,2);
      if(mm>ms && mm>mprev) modelDir[ix]=1; else if(mm<ms && mm<mprev) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="MACD_"+IntegerToString(k+1); modelFamily[ix]="MACD_TREND";

      ix=10+k;
      int hi=iHighest(sym,tf,MODE_HIGH,donLen[k],2), lo=iLowest(sym,tf,MODE_LOW,donLen[k],2);
      double hh=(hi>=0?iHigh(sym,tf,hi):0.0), ll=(lo>=0?iLow(sym,tf,lo):0.0);
      if(hh>0 && c1>hh && c1>c2) modelDir[ix]=1; else if(ll>0 && c1<ll && c1<c2) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="DONCHIAN_"+IntegerToString(k+1); modelFamily[ix]="BREAKOUT";

      ix=15+k;
      double rv=iRSI(sym,tf,rsiLen[k],PRICE_CLOSE,1), rp=iRSI(sym,tf,rsiLen[k],PRICE_CLOSE,2);
      if(rv>52 && rv>rp && rv<75) modelDir[ix]=1; else if(rv<48 && rv<rp && rv>25) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="RSI_MOMENTUM_"+IntegerToString(k+1); modelFamily[ix]="RSI_MOMENTUM";

      ix=20+k;
      double up=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_UPPER,1);
      double lw=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_LOWER,1);
      double up2=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_UPPER,2);
      double lw2=iBands(sym,tf,bbLen[k],2.0,0,PRICE_CLOSE,MODE_LOWER,2);
      if(c2<lw2 && c1>lw && c1>c2) modelDir[ix]=1; else if(c2>up2 && c1<up && c1<c2) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="BOLLINGER_REENTRY_"+IntegerToString(k+1); modelFamily[ix]="MEAN_REVERSION";

      ix=25+k;
      double sm1=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_MAIN,1);
      double ss1=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_SIGNAL,1);
      double sm2=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_MAIN,2);
      double ss2=iStochastic(sym,tf,stochLen[k],3,3,MODE_SMA,0,MODE_SIGNAL,2);
      if(sm2<=ss2 && sm1>ss1 && sm1<35) modelDir[ix]=1; else if(sm2>=ss2 && sm1<ss1 && sm1>65) modelDir[ix]=-1;
      modelScore[ix]=modelDir[ix]; modelName[ix]="STOCHASTIC_"+IntegerToString(k+1); modelFamily[ix]="MEAN_REVERSION";
   }

   string decisionId=sym+"_"+IntegerToString((int)iTime(sym,tf,1));
   g_tmpValidModels=30; g_tmpBuyVotes=0; g_tmpSellVotes=0;
   for(int countModel=0;countModel<30;countModel++)
   {
      if(modelDir[countModel]>0) g_tmpBuyVotes++;
      else if(modelDir[countModel]<0) g_tmpSellVotes++;
   }
   for(int v=0;v<30;v++)
      BiteyCsvLogEvaluatorVote(decisionId,EA_VERSION,sym,tf,modelName[v],modelFamily[v],
         (modelDir[v]>0?"BUY":(modelDir[v]<0?"SELL":"ABSTAIN")),modelScore[v],1.0,
         MathAbs(modelScore[v]),(modelDir[v]!=0),(modelDir[v]==0?"NO_SIGNAL":"CLOSED_BAR_SIGNAL"));

   int famBuy[6],famSell[6],famDir[6];
   ArrayInitialize(famBuy,0); ArrayInitialize(famSell,0); ArrayInitialize(famDir,0);
   for(int m=0;m<30;m++) { int fam=m/5; if(modelDir[m]>0) famBuy[fam]++; else if(modelDir[m]<0) famSell[fam]++; }
   for(int fidx=0;fidx<6;fidx++)
   {
      if(famBuy[fidx]>=InpAssemblyMinModelVotes && famBuy[fidx]>famSell[fidx]) famDir[fidx]=1;
      else if(famSell[fidx]>=InpAssemblyMinModelVotes && famSell[fidx]>famBuy[fidx]) famDir[fidx]=-1;
   }

   int dir=0, agree=0, opposing=0, modelVotes=0;
   int upTrend=0, downTrend=0;
   for(int t=0;t<4;t++) { if(famDir[t]>0) upTrend++; else if(famDir[t]<0) downTrend++; }
   if(adx>=InpTrendADX)
   {
      if(!InpAllowTrendRegime) { why="TREND_REGIME_DISABLED"; return(false); }
      g_tmpRegime=1;
      if(upTrend>=InpAssemblyMinFamilies && downTrend<=1) dir=1;
      else if(downTrend>=InpAssemblyMinFamilies && upTrend<=1) dir=-1;
      else
      {
         why="ASSEMBLY2_ABSTAIN_TREND_NO_CONSENSUS";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,upTrend+downTrend,0,0,0,0,false,why);
         return(false);
      }
      agree=(dir>0?upTrend:downTrend); opposing=(dir>0?downTrend:upTrend);
   }
   else
   {
      if(!InpAllowRangeRegime) { why="RANGE_REGIME_DISABLED"; return(false); }
      g_tmpRegime=2;
      if(famDir[4]!=0 && famDir[4]==famDir[5] &&
         ((famDir[4]>0 && rsi14<=45.0) || (famDir[4]<0 && rsi14>=55.0))) dir=famDir[4];
      if(dir==0)
      {
         why="ASSEMBLY2_ABSTAIN_RANGE_NO_CONSENSUS";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,
            (famDir[4]!=0 ? 1 : 0)+(famDir[5]!=0 ? 1 : 0),0,0,0,0,false,why);
         return(false);
      }
      agree=2; opposing=0;
   }

   if(InpUseHTFFilter)
   {
      double hc=iClose(sym,InpHTF,1), he=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
      if(hc<=0 || he<=0) { why="HTF_DATA_UNAVAILABLE"; return(false); }
      if((dir>0 && hc<=he) || (dir<0 && hc>=he))
      {
         why="HTF_BIAS_AGAINST";
         BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,"ABSTAIN",0,0,agree,opposing,0,0,0,false,why);
         return(false);
      }
   }
   double stopRef=atr*InpStopATR, costR=EntryCostR(sym,stopRef);
   score=10.0*agree+MathMin(adx,40.0)/4.0-30.0*MathMin(costR,2.0)-2.0*opposing;
   cmd=(dir>0?OP_BUY:OP_SELL);
   modelVotes=(dir>0?famBuy[0]+famBuy[1]+famBuy[2]+famBuy[3]:famSell[0]+famSell[1]+famSell[2]+famSell[3]);
   BiteyCsvLogTradeAssembly(decisionId,EA_VERSION,sym,tf,(dir>0?"BUY":"SELL"),score,
      MathMin(1.0,(double)agree/4.0),modelVotes,
      (dir>0?famSell[0]+famSell[1]+famSell[2]+famSell[3]:famBuy[0]+famBuy[1]+famBuy[2]+famBuy[3]),
      0,0,0,true,"ASSEMBLY2_CONSENSUS");
   return(true);
}

//+------------------------------------------------------------------+
//| Cost of entering + exiting one lot, as a fraction of the stop (R) |
//+------------------------------------------------------------------+
double EntryCostR(string sym,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   if(tv<=0 || ts<=0 || stopDist<=0 || bid<=0 || ask<bid) return(99.0);
   double stopPerLot=(stopDist/ts)*tv;
   double costPerLot=((ask-bid)/ts)*tv+CommissionPerLot(sym);
   if(stopPerLot<=0) return(99.0);
   return(costPerLot/stopPerLot);
}

//+------------------------------------------------------------------+
//| Order entry: stops, cost filter, risk budget, lots                |
//+------------------------------------------------------------------+
bool OpenTrade(string sym,int cmd,double score,int regime)
{
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { Reject(sym,"ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { Reject(sym,"STALE_QUOTE_AT_ENTRY"); return(false); }

   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=MathMax(atr*InpStopATR,spreadPrice+brokerMin);
   double targetDist=MathMax(stopDist*InpRewardRisk,spreadPrice+brokerMin);
   if(spreadPrice>stopDist*InpMaxSpreadPctOfStop/100.0)
   {
      if(RejectLogDue(sym)) Print("SPREAD_VS_STOP_REJECT | symbol=",sym," spread=",DoubleToString(spreadPrice,digits),
            " stop=",DoubleToString(stopDist,digits)," maxPct=",DoubleToString(InpMaxSpreadPctOfStop,1));
      return(false);
   }

   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)); return(false); }

   // Cost filter: spread + round-turn commission must be a small fraction of the stop
   double costR=EntryCostR(sym,stopDist);
   if(costR>InpMaxCostR)
   {
      if(RejectLogDue(sym)) Print("COST_REJECT | symbol=",sym," costR=",DoubleToString(costR,3)," max=",DoubleToString(InpMaxCostR,3));
      return(false);
   }

   double maxAgg=RiskCapital()*InpMaxAggregateRiskPct/100.0;
   double openRisk=CurrentOpenRisk();
   double remaining=maxAgg-openRisk;
   double perTrade=RiskCapital()*InpRiskPctPerTrade/100.0;
   if(remaining<=0.01) { Print("RISK_REJECT | symbol=",sym," reason=AGGREGATE_RISK_CAP open=",DoubleToString(openRisk,2)," cap=",DoubleToString(maxAgg,2)); return(false); }
   double budget=MathMin(perTrade,remaining);
   double lots=LotsForRisk(sym,stopDist,budget);
   if(lots<=0) { Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET_OR_CAP budget=",DoubleToString(budget,2)); return(false); }
   double risk=EstimateRisk(sym,lots,stopDist);

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
            " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   if(IsTradeContextBusy()) { Reject(sym,"TRADE_CONTEXT_BUSY"); return(false); }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"BE"+EA_VERSION+(regime==1?" T":" R"),InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      Print("ORDER_REJECTED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," error=",err,
            " lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      return(false);
   }
   Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," costR=",DoubleToString(costR,3),
         " score=",DoubleToString(score,1)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
   TrackOpen(ticket,stopDist);
   datetime decisionBar=iTime(sym,InpSignalTF,1);
   GlobalVariableSet(GvKey("DID",ticket),(double)decisionBar);
   string decisionId=sym+"_"+IntegerToString((int)decisionBar);
   BiteyCsvLogTradeOpened(decisionId,EA_VERSION,ticket,sym,(cmd==OP_BUY?"BUY":"SELL"),
      lots,entry,sl,tp,InpReferenceCapitalUSD,risk,(IsTesting()?"TESTER":"TERMINAL"),"ORDER_ACCEPTED");
   return(true);
}

//+------------------------------------------------------------------+
//| Position management: adaptive SL/TP, time exit, optional R close |
//+------------------------------------------------------------------+
bool CloseTicket(int ticket,string reason)
{
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES) || OrderCloseTime()>0) return(false);
   string sym=OrderSymbol();
   int type=OrderType();
   double lots=OrderLots();
   double px=(type==OP_BUY?MarketInfo(sym,MODE_BID):MarketInfo(sym,MODE_ASK));
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   if(px<=0) return(false);
   double net=OrderProfit()+OrderSwap()+OrderCommission();
   ResetLastError();
   bool ok=OrderClose(ticket,lots,NormalizeDouble(px,digits),InpSlippagePoints,clrNONE);
   Print("CLOSE | reason=",reason," ticket=",ticket," symbol=",sym," net=",DoubleToString(net,2)," ok=",(ok?"true":"false"),
         " error=",(ok?0:GetLastError()));
   return(ok);
}

void ManageExits()
{
   bool rollover=(InpFlatBeforeRollover && InRolloverWindow());
   for(int pos=OrdersTotal()-1;pos>=0;pos--)
   {
      if(!OrderSelect(pos,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      int ticket=OrderTicket();
      string sym=OrderSymbol();
      double point=MarketInfo(sym,MODE_POINT);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double entry=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit(), lots=OrderLots();
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      bool rangeTrade=(StringFind(OrderComment()," R")>=0);   // order comment is tagged " R" (range) or " T" (trend) at entry

      UpdateExcursion(ticket,type,entry,oldSL,bid,ask);
      if(rollover) { CloseTicket(ticket,"ROLLOVER_FLAT"); continue; }   // avoid overnight swap
      if(FridayCutoff(sym)) { CloseTicket(ticket,"FRIDAY_FLAT"); continue; }   // avoid overnight swap
      if(InpMaxHoldBars>0)
      {
         int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
         if(barsOpen>=InpMaxHoldBars) { CloseTicket(ticket,"TIME_EXIT"); continue; }
      }
      if(atr<=0) continue;

      // Confirmed reversal exit: use CLOSED candles only (shifts 1 and 2), and only
      // close when current net P/L meets the configured floor. Broker-side SL/TP remains
      // the protection if the EA is offline or a close request fails.
      if(InpEnableConfirmedReversalExit && InpReversalFastMAPeriod>0 &&
         InpReversalSlowMAPeriod>InpReversalFastMAPeriod)
      {
         double fast1=iMA(sym,InpSignalTF,InpReversalFastMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
         double fast2=iMA(sym,InpSignalTF,InpReversalFastMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
         double slow1=iMA(sym,InpSignalTF,InpReversalSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,1);
         double slow2=iMA(sym,InpSignalTF,InpReversalSlowMAPeriod,0,MODE_EMA,PRICE_CLOSE,2);
         double reversalRisk=EstimateRisk(sym,lots,atr*InpStopATR);
         double reversalFloor=(reversalRisk<1.0e11 ? MathMax(0.0,InpReversalExitMinR*reversalRisk) : 0.0);
         bool bearishCross=(fast2>=slow2 && fast1<slow1);
         bool bullishCross=(fast2<=slow2 && fast1>slow1);
         if(((type==OP_BUY && bearishCross) || (type==OP_SELL && bullishCross)) && net>=reversalFloor)
         {
            if(CloseTicket(ticket,"PROFITABLE_CONFIRMED_REVERSAL")) continue;
            // If rejected, continue managing the broker-side SL/TP below.
         }
      }

      if(InpNetTargetR>0.0)
      {
         double refRisk=EstimateRisk(sym,lots,atr*InpStopATR);   // reference R, independent of SL trailing
         if(refRisk<1.0e11 && net>=InpNetTargetR*refRisk) { CloseTicket(ticket,"NET_TARGET_R"); continue; }
      }
      // v1.7.1 (from MASTER1011): range trades exit on reversion to the mean, judged on NET profit.
      // At the mean the trade is closed only if net profit covers InpMeanExitMinR of R (never a sub-cost scalp);
      // at the opposite band it is closed while in profit. SL/TP stay on the server as the adaptive backstop.
      if(InpUseMeanExit && rangeTrade)
      {
         double mid=iMA(sym,InpSignalTF,InpExitMAPeriod,0,MODE_SMA,PRICE_CLOSE,0);
         if(mid>0.0)
         {
            double bandW=InpExitBandATR*atr;
            bool atMean=(type==OP_BUY ? bid>=mid : ask<=mid);
            bool atFar =(type==OP_BUY ? bid>=mid+bandW : ask<=mid-bandW);
            double refR=EstimateRisk(sym,lots,atr*InpStopATR);
            if(atFar && net>0.0) { CloseTicket(ticket,"OPPOSITE_BAND"); continue; }
            if(atMean && refR<1.0e11 && net>=InpMeanExitMinR*refR) { CloseTicket(ticket,"MEAN_TARGET"); continue; }
         }
      }
      if(!InpEnableAdaptiveExits) continue;

      double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL)+2.0)*point;
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-entry:entry-price);
      double newSL=oldSL, newTP=oldTP;
      bool slUp=false, tpUp=false;

      // Price distance that equals the round-turn commission, so "break-even" really breaks even
      double tvv=MarketInfo(sym,MODE_TICKVALUE), tss=MarketInfo(sym,MODE_TICKSIZE);
      double commPrice=(tvv>0 && tss>0 ? CommissionPerLot(sym)*tss/tvv : 0.0);

      // Break-even + commission + small lock (SL only ever moves toward profit)
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double lockDist=atr*InpBreakEvenLockATR+commPrice;
         double be=(type==OP_BUY?entry+lockDist:entry-lockDist);
         if(type==OP_BUY  && (newSL<=0 || be>newSL) && be<bid-minDist) newSL=be;
         if(type==OP_SELL && (newSL<=0 || be<newSL) && be>ask+minDist) newSL=be;
      }
      // ATR trailing
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double trailDistanceATR=MathMax(InpTrailMinDistanceATR,
                                         InpTrailDistanceATR-MathMax(0.0,favorable/atr-InpTrailStartATR)*InpTrailTightenPerATR);
          double tr=(type==OP_BUY?bid-atr*trailDistanceATR:ask+atr*trailDistanceATR);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) newSL=tr;
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) newSL=tr;
      }
      // Net USD profit lock: do not apply a USD threshold to a non-USD account.
      // Convert the protected net amount to price distance using this symbol's tick value/size.
      double lockR0=(GlobalVariableCheck(GvKey("R0",ticket))?GlobalVariableGet(GvKey("R0",ticket)):0.0);
      double lockRef=EstimateRisk(sym,lots,(lockR0>0.0?lockR0:atr*InpStopATR));   // initial risk in money
      double lockTrigUSD=InpProfitLockTriggerR*lockRef;
      double lockTargetUSD=InpProfitLockTargetR*lockRef;
      double lockStepUSD=InpProfitLockStepR*lockRef;
      if(InpEnableNetProfitLock && lockRef<1.0e11 && InpProfitLockTriggerR>0.0 && InpProfitLockTargetR>0.0 &&
         lockTargetUSD<lockTrigUSD && net>=lockTrigUSD)
      {
         double lockTickValue=MarketInfo(sym,MODE_TICKVALUE);
         double lockTickSize=MarketInfo(sym,MODE_TICKSIZE);
         double lockMoneyPerPrice=(lockTickValue>0.0 && lockTickSize>0.0 ? lots*lockTickValue/lockTickSize : 0.0);
         if(lockMoneyPerPrice>0.0 && lots>0.0)
         {
            // Use the greater of posted commission and configured round-turn commission to avoid
            // double-counting commission already booked while still reserving the expected full cost.
            double postedCommission=MathAbs(OrderCommission());
            double configuredRoundTurn=CommissionPerLot(sym)*lots;
            double commissionEstimate=MathMax(postedCommission,configuredRoundTurn);
            // Expected net at stop ~= price P/L + swap - commission estimate.
            double requiredPricePnl=lockTargetUSD-OrderSwap()+commissionEstimate;
            double lockMove=MathMax(0.0,requiredPricePnl/lockMoneyPerPrice);
            double lockSL=NormalizeDouble(type==OP_BUY?entry+lockMove:entry-lockMove,digits);
            bool improves=(type==OP_BUY ? (newSL<=0.0 || lockSL>newSL+point*0.5)
                                        : (newSL<=0.0 || lockSL<newSL-point*0.5));
            bool brokerValid=(type==OP_BUY ? lockSL<bid-minDist : lockSL>ask+minDist);
            double currentLockNet=-1.0e100;
            if(oldSL>0.0)
            {
               double oldMove=(type==OP_BUY?oldSL-entry:entry-oldSL);
               currentLockNet=oldMove*lockMoneyPerPrice+OrderSwap()-commissionEstimate;
            }
            double candidateLockNet=lockMove*lockMoneyPerPrice+OrderSwap()-commissionEstimate;
            bool stepReached=(oldSL<=0.0 ||
                              currentLockNet<lockTargetUSD-lockStepUSD ||
                              candidateLockNet>=currentLockNet+lockStepUSD);
            if(improves && brokerValid && stepReached)
            {
               newSL=lockSL;
               Print("NET_PROFIT_LOCK | ticket=",ticket," symbol=",sym,
                     " netUSD=",DoubleToString(net,2),
                     " targetNetUSD=",DoubleToString(lockTargetUSD,2),
                     " commissionEstimate=",DoubleToString(commissionEstimate,2),
                     " swap=",DoubleToString(OrderSwap(),2),
                     " SLcandidate=",DoubleToString(lockSL,digits));
            }
         }
      }
      

      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Adaptive TP: extend only in a strong trend when price nears the target
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(InpEnableTPExpand && oldTP>0 && favorable>=atr*InpTPExpandTriggerATR && adx>=InpTPExpandADXMin)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double want=MathMin(atr*InpTPMaxDistanceATR,MathMax(curDist,favorable+atr*InpTPExpandBufferATR));
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+atr*InpTPExpandStepATR && prop>ask+minDist) { newTP=prop; tpUp=true; }
            if(type==OP_SELL && prop<oldTP-atr*InpTPExpandStepATR && prop<bid-minDist) { newTP=prop; tpUp=true; }
         }
      }

      if(!slUp && !tpUp) continue;
      double fSL=(slUp?newSL:oldSL), fTP=(tpUp?newTP:oldTP);
      ResetLastError();
      if(OrderModify(ticket,entry,fSL,fTP,0,clrNONE))
      {
         string exitDecisionId="ticket_"+IntegerToString(ticket);
         if(GlobalVariableCheck(GvKey("DID",ticket)))
            exitDecisionId=sym+"_"+IntegerToString((int)GlobalVariableGet(GvKey("DID",ticket)));
         BiteyCsvLogAdaptiveExit(exitDecisionId,EA_VERSION,ticket,sym,oldSL,fSL,oldTP,fTP,
            OrderProfit()+OrderCommission()+OrderSwap(),"ADAPTIVE_SLTP_UPDATE");
         Print("ADAPTIVE_MODIFY | ticket=",ticket," symbol=",sym,
               " SL ",DoubleToString(oldSL,digits),"->",DoubleToString(fSL,digits),
               " TP ",DoubleToString(oldTP,digits),"->",DoubleToString(fTP,digits));
      }
      else
         Print("ADAPTIVE_MODIFY_FAILED | ticket=",ticket," symbol=",sym," error=",GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Portfolio helpers                                                 |
//+------------------------------------------------------------------+
bool HasPositionForKey(string key)
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(AssetKey(OrderSymbol())==key) return(true);
   }
   return(false);
}

int CountOpenPositions()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()==InpMagic && (OrderType()==OP_BUY || OrderType()==OP_SELL)) n++;
   }
   return(n);
}

// Adverse entry-to-stop risk only (incl. commission); a stop at/after break-even counts as zero risk.
double CurrentOpenRisk()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return(RiskCapital());      // unknown risk fails closed
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(d>0) total+=EstimateRisk(OrderSymbol(),OrderLots(),d);
   }
   return(total);
}

double TodayNet()
{
   return(PeriodNet(StrToTime(TimeToString(TimeCurrent(),TIME_DATE))));
}

// v1.7.1: net P&L of this EA (closed + floating) since the first day of the current server month.
// Built from history, so it survives EA restarts (same design as TodayNet).
double MonthNet()
{
   datetime t=TimeCurrent();
   return(PeriodNet(StrToTime(StringFormat("%04d.%02d.01",TimeYear(t),TimeMonth(t)))));
}

double PeriodNet(datetime ds)
{
   double net=0.0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      if(OrderCloseTime()>=ds) net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      net+=OrderProfit()+OrderSwap()+OrderCommission();
   }
   return(net);
}

// Per-symbol pause: longer after a loss (InpCooldownBars), shorter after a win (InpReentryBars)
bool InCooldown(string sym)
{
   datetime latest=0; double latestNet=0.0;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<120;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=sym || OrderType()>OP_SELL) continue;
      if(OrderCloseTime()>latest)
      {
         latest=OrderCloseTime();
         latestNet=OrderProfit()+OrderSwap()+OrderCommission();
      }
   }
   if(latest<=0) return(false);
   int bars=(latestNet<0.0?InpCooldownBars:InpReentryBars);
   if(bars<=0) return(false);
   return((TimeCurrent()-latest)<bars*PeriodSeconds(InpSignalTF));
}

// Circuit breaker: N losing closes in a row (any symbol) -> pause new entries
bool LossStreakBlock()
{
   if(InpMaxConsecLosses<=0) return(false);
   datetime ct[40]; double nt[40]; bool used[40];
   ArrayInitialize(ct,0);
   ArrayInitialize(nt,0.0);
   ArrayInitialize(used,false);
   int cnt=0, seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<300 && cnt<40;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      ct[cnt]=OrderCloseTime();
      nt[cnt]=OrderProfit()+OrderSwap()+OrderCommission();
      used[cnt]=false;
      cnt++;
   }
   if(cnt<InpMaxConsecLosses) return(false);

   int streak=0;
   datetime newest=0;
   for(int k=0;k<cnt;k++)
   {
      int best=-1;
      for(int j=0;j<cnt;j++)
         if(!used[j] && (best<0 || ct[j]>ct[best])) best=j;
      if(best<0) break;
      used[best]=true;
      if(nt[best]<0.0)
      {
         streak++;
         if(newest==0) newest=ct[best];
      }
      else break;
   }
   if(streak<InpMaxConsecLosses) return(false);
   return((TimeCurrent()-newest)<InpLossStreakPauseMin*60);
}

// Per-symbol filter: net expectancy of the last N closed trades < 0 -> ban for InpExpectancyBanHours after the last close
bool SymbolExpectancyBad(string sym)
{
   if(InpExpectancyWindow<=0 || InpExpectancyMinTrades<=0) return(false);
   int cnt=0, seen=0;
   double sum=0.0;
   datetime last=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<500 && cnt<InpExpectancyWindow;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderSymbol()!=sym || OrderType()>OP_SELL) continue;
      cnt++;
      sum+=OrderProfit()+OrderSwap()+OrderCommission();
      if(OrderCloseTime()>last) last=OrderCloseTime();
   }
   if(cnt<InpExpectancyMinTrades || sum>=0.0) return(false);
   return((TimeCurrent()-last)<InpExpectancyBanHours*3600);
}

//+------------------------------------------------------------------+
//| Sizing (risk includes round-turn commission; lot caps by class)   |
//+------------------------------------------------------------------+
double EstimateRisk(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0 || ts<=0 || lots<=0 || stopDist<=0) return(1.0e12);
   return(((stopDist/ts)*tv+CommissionPerLot(sym))*lots);
}

int LotDigits(double step)
{
   if(step>=1.0) return(0);
   if(step>=0.1) return(1);
   if(step>=0.01) return(2);
   return(3);
}

double LotsForRisk(string sym,double stopDist,double riskMoney)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   double minLot=MarketInfo(sym,MODE_MINLOT), maxLot=MarketInfo(sym,MODE_MAXLOT), step=MarketInfo(sym,MODE_LOTSTEP);
   if(riskMoney<=0 || tv<=0 || ts<=0 || stopDist<=0 || minLot<=0 || maxLot<minLot || step<=0) return(0.0);
   double lossPerLot=(stopDist/ts)*tv+CommissionPerLot(sym);
   if(lossPerLot<=0) return(0.0);
   double lots=MathFloor(riskMoney/lossPerLot/step+1e-9)*step;
   lots=MathMin(lots,maxLot);
   lots=MathMin(lots,LotCap(sym));
   lots=MathFloor(lots/step+1e-9)*step;
   lots=NormalizeDouble(lots,LotDigits(step));
   if(lots<minLot) return(0.0);
   if(EstimateRisk(sym,lots,stopDist)>riskMoney+0.02) return(0.0);
   return(lots);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Throttled reject logging (one line per symbol per N minutes)      |
//+------------------------------------------------------------------+
int SymIndex(string sym)
{
   for(int i=0;i<g_symbolCount;i++)
      if(g_symbols[i]==sym) return(i);
   return(-1);
}

bool RejectLogDue(string sym)
{
   if(InpRejectLogMinutes<=0) return(true);
   int i=SymIndex(sym);
   if(i<0) return(true);
   datetime now=TimeCurrent();
   if(g_lastRejectLog[i]!=0 && now-g_lastRejectLog[i]<InpRejectLogMinutes*60) return(false);
   g_lastRejectLog[i]=now;
   return(true);
}

//+------------------------------------------------------------------+
//| MFE/MAE tracking (terminal global variables survive restarts)     |
//+------------------------------------------------------------------+
string GvKey(string tag,int ticket)
{
   return("BE"+IntegerToString(InpMagic)+"_"+tag+"_"+IntegerToString(ticket));
}

void TrackOpen(int ticket,double r0)
{
   GlobalVariableSet(GvKey("R0",ticket),r0);
   GlobalVariableSet(GvKey("MFE",ticket),0.0);
   GlobalVariableSet(GvKey("MAE",ticket),0.0);
}

void UpdateExcursion(int ticket,int type,double entry,double sl,double bid,double ask)
{
   string kr=GvKey("R0",ticket);
   if(!GlobalVariableCheck(kr))
   {
      // position not opened by this version: best available estimate of the initial risk
      double r0=(sl>0?MathAbs(entry-sl):0.0);
      GlobalVariableSet(kr,r0);
      GlobalVariableSet(GvKey("MFE",ticket),0.0);
      GlobalVariableSet(GvKey("MAE",ticket),0.0);
   }
   double px=(type==OP_BUY?bid:ask);
   double move=(type==OP_BUY?px-entry:entry-px);
   string kf=GvKey("MFE",ticket), ka=GvKey("MAE",ticket);
   double mfe=GlobalVariableGet(kf), mae=GlobalVariableGet(ka);
   if(move>mfe)  GlobalVariableSet(kf,move);
   if(-move>mae) GlobalVariableSet(ka,-move);
}

// Writes one CSV row for the order currently selected in history
bool WriteTradeRow(int ticket)
{
   string sym=OrderSymbol();
   int type=OrderType();
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double r0=GlobalVariableGet(GvKey("R0",ticket));
   double mfe=GlobalVariableGet(GvKey("MFE",ticket));
   double mae=GlobalVariableGet(GvKey("MAE",ticket));
   double mfeR=(r0>0?mfe/r0:0.0), maeR=(r0>0?mae/r0:0.0);
   double gross=OrderProfit(), comm=OrderCommission(), swp=OrderSwap();
   int durMin=(int)((OrderCloseTime()-OrderOpenTime())/60);

   string fn="Bitey_Ens_TradeAudit_"+IntegerToString(InpMagic)+".csv";
   int h=FileOpen(fn,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE) { Print("CSV_OPEN_FAILED | file=",fn," error=",GetLastError()); return(false); }
   if(FileSize(h)==0)
      FileWrite(h,"ticket","symbol","side","open_time","close_time","duration_min","lots","open_price","close_price",
                "initial_risk_price","mfe_price","mae_price","mfe_R","mae_R","gross","commission","swap","net","comment");
   FileSeek(h,0,SEEK_END);
   FileWrite(h,ticket,sym,(type==OP_BUY?"BUY":"SELL"),
             TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
             durMin,DoubleToString(OrderLots(),2),DoubleToString(OrderOpenPrice(),digits),DoubleToString(OrderClosePrice(),digits),
             DoubleToString(r0,digits),DoubleToString(mfe,digits),DoubleToString(mae,digits),
             DoubleToString(mfeR,2),DoubleToString(maeR,2),
             DoubleToString(gross,2),DoubleToString(comm,2),DoubleToString(swp,2),DoubleToString(gross+comm+swp,2),
             OrderComment());
   FileClose(h);
   string closedDecisionId="ticket_"+IntegerToString(ticket);
   if(GlobalVariableCheck(GvKey("DID",ticket)))
      closedDecisionId=sym+"_"+IntegerToString((int)GlobalVariableGet(GvKey("DID",ticket)));
   BiteyCsvLogTradeClosed(closedDecisionId,EA_VERSION,ticket,sym,
      (type==OP_BUY?"BUY":"SELL"),OrderLots(),OrderOpenTime(),OrderCloseTime(),
      OrderOpenPrice(),OrderClosePrice(),gross,comm,swp,0.0,OrderComment());
   return(true);
}

// Scans recent history every ~20 s and logs closed trades that were tracked and not yet written
void LogClosedTrades()
{
   if(!InpLogTradesCSV) return;
   datetime now=TimeCurrent();
   if(g_lastCsvScan!=0 && now-g_lastCsvScan<20) return;
   g_lastCsvScan=now;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<60;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      seen++;
      if(OrderMagicNumber()!=InpMagic || OrderType()>OP_SELL) continue;
      int ticket=OrderTicket();
      if(!GlobalVariableCheck(GvKey("R0",ticket))) continue;    // not tracked (closed before this version)
      string kd=GvKey("LOG",ticket);
      if(GlobalVariableCheck(kd)) continue;
      GlobalVariableSet(kd,1.0);                       // claim first so a second copy does not write the same row
      if(!WriteTradeRow(ticket)) GlobalVariableDel(kd);
   }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Net-profit audit by asset                                        |
//| Writes to this terminal's MQL4\\Files folder (NOT Common\\Files). |
//| MT4 Account History should be set to "All History".               |
//+------------------------------------------------------------------+
void WriteAssetNetSummary()
{
   if(!InpLogAssetSummaryCSV) return;
   datetime now=TimeCurrent();
   if(g_lastNetSummaryScan!=0 && now-g_lastNetSummaryScan<60) return;
   g_lastNetSummaryScan=now;

   string symbols[512];
   int counts[512], wins[512], losses[512];
   double gross[512], commissions[512], swaps[512], nets[512];
   ArrayInitialize(counts,0); ArrayInitialize(wins,0); ArrayInitialize(losses,0);
   ArrayInitialize(gross,0.0); ArrayInitialize(commissions,0.0);
   ArrayInitialize(swaps,0.0); ArrayInitialize(nets,0.0);
   int symbolCount=0, included=0, skipped=0;
   double totalGross=0.0, totalCommission=0.0, totalSwap=0.0, totalNet=0.0;
   int totalWins=0, totalLosses=0;

   int historyTotal=OrdersHistoryTotal();
   for(int p=historyTotal-1; p>=0; p--)
   {
      if(!OrderSelect(p,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if((type!=OP_BUY && type!=OP_SELL) || OrderCloseTime()<=0) continue;

      string sym=OrderSymbol();
      int idx=-1;
      for(int k=0;k<symbolCount;k++)
      {
         if(symbols[k]==sym) { idx=k; break; }
      }
      if(idx<0)
      {
         if(symbolCount>=512) { skipped++; continue; }
         idx=symbolCount++;
         symbols[idx]=sym;
      }

      double g=OrderProfit();
      double c=OrderCommission();
      double s=OrderSwap();
      double n=g+c+s;
      counts[idx]++;
      gross[idx]+=g;
      commissions[idx]+=c;
      swaps[idx]+=s;
      nets[idx]+=n;
      if(n>0.000001) wins[idx]++;
      else if(n< -0.000001) losses[idx]++;
      included++;
      totalGross+=g;
      totalCommission+=c;
      totalSwap+=s;
      totalNet+=n;
      if(n>0.000001) totalWins++;
      else if(n< -0.000001) totalLosses++;
   }

   string fn="Bitey_Ens_NetByAsset_"+IntegerToString(InpMagic)+".csv";
   ResetLastError();
   // Deliberately omit FILE_COMMON so the file is created in this terminal's MQL4\\Files.
   int h=FileOpen(fn,FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,';');
   if(h==INVALID_HANDLE)
   {
      int err=GetLastError();
      Print("NET_SUMMARY_OPEN_FAILED | file=",fn," error=",err,
            " | expected_folder=MQL4\\Files");
      return;
   }
   FileWrite(h,"updated_server_time",TimeToString(now,TIME_DATE|TIME_SECONDS));
   FileWrite(h,"magic",InpMagic,"history_orders_visible_to_MT4",historyTotal,
             "matched_closed_trades",included,"skipped_symbol_limit",skipped);
   FileWrite(h,"symbol","closed_trades","wins_net","losses_net","gross_profit","commission","swap","net_profit");
   for(int j=0;j<symbolCount;j++)
   {
      FileWrite(h,symbols[j],counts[j],wins[j],losses[j],
                DoubleToString(gross[j],2),DoubleToString(commissions[j],2),
                DoubleToString(swaps[j],2),DoubleToString(nets[j],2));
   }
   FileWrite(h,"TOTAL",included,totalWins,totalLosses,DoubleToString(totalGross,2),
             DoubleToString(totalCommission,2),DoubleToString(totalSwap,2),DoubleToString(totalNet,2));
   FileClose(h);
   Print("NET_SUMMARY_UPDATED | file=",fn," folder=MQL4\\Files",
         " | history=",historyTotal," matched=",included," assets=",symbolCount,
         " | gross=",DoubleToString(totalGross,2),
         " commission=",DoubleToString(totalCommission,2),
         " swap=",DoubleToString(totalSwap,2),
         " net=",DoubleToString(totalNet,2),
         " | set Account History to All History for full available totals");
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v1.5.0 helpers                                                    |
//+------------------------------------------------------------------+
double RiskCapital()
{
   if(!InpUseEquityRisk) return(InpReferenceCapitalUSD);
   double c=MathMin(AccountBalance(),AccountEquity());
   return(c>1.0?c:InpReferenceCapitalUSD);
}

bool FridayCutoff(string sym)
{
   if(InpFridayFlatHour<=0 || IsCrypto(sym)) return(false);
   datetime t=TimeCurrent();
   return(TimeDayOfWeek(t)==5 && TimeHour(t)>=InpFridayFlatHour);
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| v1.5.1: extra symbols that must always be in the universe         |
//+------------------------------------------------------------------+
string ResolveSymbol(string want)
{
   string w=want;
   StringToUpper(w);
   int total=SymbolsTotal(false);               // every symbol the broker offers
   for(int i=0;i<total;i++)
   {
      string n=SymbolName(i,false);
      string u=n;
      StringToUpper(u);
      if(u==w) return(n);
   }
   return("");
}

void AddExtraSymbols()
{
   if(IsTesting()) return;                      // Tester models the chart symbol only
   string csv=InpExtraSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);
   while(StringLen(csv)>0 && g_symbolCount<MAX_SYMBOLS)
   {
      int p=StringFind(csv,",");
      string s;
      if(p<0) { s=csv; csv=""; }
      else { s=StringSubstr(csv,0,p); csv=StringSubstr(csv,p+1); }
      StringTrimLeft(s); StringTrimRight(s);
      if(StringLen(s)<=0) continue;

      string real=ResolveSymbol(s);
      if(real=="") { Print("EXTRA_SYMBOL_NOT_FOUND | requested=",s," | not offered by this broker"); continue; }
      if(!SymbolSelect(real,true)) { Print("EXTRA_SYMBOL_SELECT_FAILED | symbol=",real," error=",GetLastError()); continue; }

      string k=AssetKey(real);
      bool replaced=false;
      for(int i=0;i<g_symbolCount;i++)
         if(g_keys[i]==k)
         {
            Print("EXTRA_SYMBOL | requested=",s," | replaces alias ",g_symbols[i]," with ",real);
            g_symbols[i]=real;
            replaced=true;
            break;
         }
      if(!replaced)
      {
         AddSymbol(real);
         Print("EXTRA_SYMBOL | requested=",s," | added as ",real);
      }
   }
}

//+------------------------------------------------------------------+
//| v1.5.2: add every tradable crypto the broker offers               |
//+------------------------------------------------------------------+
void AddAllCrypto()
{
   if(!InpAutoAddCrypto || IsTesting()) return;
   int total=SymbolsTotal(false);
   int added=0, skipped=0;
   string list="";
   for(int i=0;i<total && g_symbolCount<MAX_SYMBOLS;i++)
   {
      string n=SymbolName(i,false);
      if(!(IsCrypto(n) || (InpAutoAddUSDT && IsUSDTSymbol(n)))) continue;
      string k=AssetKey(n);
      bool dup=false;
      for(int j=0;j<g_symbolCount;j++)
         if(g_keys[j]==k) { dup=true; break; }
      if(dup) continue;
      if(MarketInfo(n,MODE_TRADEALLOWED)<=0) { skipped++; continue; }
      if(!SymbolSelect(n,true)) { skipped++; continue; }
      AddSymbol(n);
      added++;
      list+=n+" ";
   }
   Print("AUTO_CRYPTO | added=",added," skippedNotTradable=",skipped," | ",list);
}

//+------------------------------------------------------------------+
//| v1.7.1 helpers                                                    |
//+------------------------------------------------------------------+

// Envelope reversion family (idea from MASTER1011), 8 variants: SMA period + band half-width in ATR.
// Buy vote : the last closed bar's low reached the lower band and the bar closed up (bounce).
// Sell vote: the last closed bar's high reached the upper band and the bar closed down.
void EnvelopeVotes(string sym,int tf,double atr,double c1,double c2,int &eb,int &es)
{
   eb=0; es=0;
   double l1=iLow(sym,tf,1), h1=iHigh(sym,tf,1);
   if(l1<=0.0 || h1<=0.0 || atr<=0.0) return;
   int    ep[8]={3,4,5,6,8,10,12,15};
   double ek[8]={0.6,0.7,0.8,0.9,1.0,1.1,1.2,1.3};
   for(int ev=0;ev<8;ev++)
   {
      double ma=iMA(sym,tf,ep[ev],0,MODE_SMA,PRICE_CLOSE,1);
      if(ma<=0.0) continue;
      double w=ek[ev]*InpEnvelopeATRScale*atr;
      Vote(l1<=ma-w && c1>c2, h1>=ma+w && c1<c2, eb, es);
   }
}

// Closes every position of this EA. Returns how many are still open (retried on the next cycle).
int CloseAllPositions(string reason)
{
   int left=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;
      if(!CloseTicket(OrderTicket(),reason)) left++;
   }
   return(left);
}

// Hard equity floor (MASTER1011 "CashAccount") and optional monthly flatten (EA_Agresivo_Mensual).
// Both are OFF by default: InpEquityFloorUSD=0 and InpCloseAllOnMonthHalt=false.
void CheckHaltActions()
{
   if(!g_haltAll && InpEquityFloorUSD>0.0 && MathMin(AccountBalance(),AccountEquity())<InpEquityFloorUSD)
   {
      g_haltAll=true;
      Print("EQUITY_FLOOR_HALT | min(balance,equity)=",DoubleToString(MathMin(AccountBalance(),AccountEquity()),2),
            " floor=",DoubleToString(InpEquityFloorUSD,2)," | flattening and halting new entries");
   }
   if(g_haltAll)
   {
      CloseAllPositions("EQUITY_FLOOR");
      return;
   }
   if(InpCloseAllOnMonthHalt && InpMonthDDPct>0.0 && CountOpenPositions()>0 &&
      MonthNet()<=-RiskCapital()*InpMonthDDPct/100.0)
      CloseAllPositions("MONTH_DD_FLAT");
}

// "" = entries allowed, otherwise the reason new entries are blocked (open trades stay managed)
string EntryBlockReason()
{
   if(g_haltAll) return("EQUITY_FLOOR_HALT");
   double cap=RiskCapital();
   if(InpDailyLossPct>0.0 && TodayNet()<=-cap*InpDailyLossPct/100.0) return("DAILY_LOSS_BLOCK");
   if(InpMonthDDPct>0.0 || InpMonthTargetPct>0.0)
   {
      double mn=MonthNet();
      if(InpMonthDDPct>0.0 && mn<=-cap*InpMonthDDPct/100.0) return("MONTH_DD_BLOCK");
      if(InpMonthTargetPct>0.0 && mn>=cap*InpMonthTargetPct/100.0) return("MONTH_TARGET_REACHED");
   }
   return("");
}

// Adds the signed currency exposure of one FX position: BUY = long base / short quote, SELL = the reverse
void AddCcyExposure(string sym,int type,int &net[])
{
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   int sgn=(type==OP_BUY?1:-1);
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base)  net[ci]+=sgn;
      if(cc[ci]==quote) net[ci]-=sgn;
   }
}

// Correlation guard: crypto positions move together, and FX pairs sharing a currency are one bet.
//  - at most InpMaxCryptoPositions crypto positions open at once
//  - at most InpMaxCcyExposure net same-direction positions on any single FX currency
bool CorrelationOK(string sym,int cmd,string &why)
{
   why="";
   if(!InpUseCorrelationGuard) return(true);

   if(IsCrypto(sym))
   {
      if(InpMaxCryptoPositions<=0) return(true);
      int cryptoOpen=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(IsCrypto(OrderSymbol())) cryptoOpen++;
      }
      if(cryptoOpen>=InpMaxCryptoPositions) { why="CRYPTO_CLUSTER_CAP open="+IntegerToString(cryptoOpen); return(false); }
      return(true);
   }

   if(!IsForex(sym)) return(true);
   if(InpMaxCcyExposure<=0 && InpMaxCcyGross<=0) return(true);
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   int expo[8], gross[8];
   ArrayInitialize(expo,0);
   ArrayInitialize(gross,0);
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(!IsForex(OrderSymbol())) continue;
      AddCcyExposure(OrderSymbol(),OrderType(),expo);
      AddCcyGross(OrderSymbol(),gross);
   }
   AddCcyExposure(sym,cmd,expo);
   AddCcyGross(sym,gross);
   for(int k2=0;k2<8;k2++)
   {
      if(InpMaxCcyExposure>0 && MathAbs(expo[k2])>InpMaxCcyExposure)
      {
         why="FX_CURRENCY_EXPOSURE_CAP "+cc[k2]+" net="+IntegerToString(expo[k2]);
         return(false);
      }
      if(InpMaxCcyGross>0 && gross[k2]>InpMaxCcyGross)
      {
         why="FX_CURRENCY_GROSS_CAP "+cc[k2]+" gross="+IntegerToString(gross[k2]);
         return(false);
      }
   }
   return(true);
}

// v1.7.2: every FX position counts once on each of its two currencies, whatever its direction
void AddCcyGross(string sym,int &gross[])
{
   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base)  gross[ci]++;
      if(cc[ci]==quote) gross[ci]++;
   }
}

// v1.7.2: how much a candidate would pile onto what is already open (0 = fully diversifying).
//  FX    : for each of its two currency legs, the open net exposure already pointing the same way.
//  Crypto: open crypto positions in the same direction.
//  Other : 0 (metals, indices, stocks are not ranked against each other).
double DiversifyOverlap(string sym,int cmd)
{
   if(InpDiversifyPenalty<=0.0) return(0.0);
   if(IsCrypto(sym))
   {
      int same=0;
      for(int i=OrdersTotal()-1;i>=0;i--)
      {
         if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
         if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
         if(IsCrypto(OrderSymbol()) && OrderType()==cmd) same++;
      }
      return((double)same);
   }
   if(!IsForex(sym)) return(0.0);

   string cc[8]={"USD","EUR","GBP","JPY","AUD","NZD","CAD","CHF"};
   int expo[8];
   ArrayInitialize(expo,0);
   for(int j=OrdersTotal()-1;j>=0;j--)
   {
      if(!OrderSelect(j,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(!IsForex(OrderSymbol())) continue;
      AddCcyExposure(OrderSymbol(),OrderType(),expo);
   }
   string k=AssetKey(sym);
   string base=StringSubstr(k,0,3), quote=StringSubstr(k,3,3);
   int sgn=(cmd==OP_BUY?1:-1);
   double ov=0.0;
   for(int ci=0;ci<8;ci++)
   {
      if(cc[ci]==base  && expo[ci]*sgn>0)    ov+=expo[ci]*sgn;
      if(cc[ci]==quote && expo[ci]*(-sgn)>0) ov+=expo[ci]*(-sgn);
   }
   return(ov);
}
//+------------------------------------------------------------------+