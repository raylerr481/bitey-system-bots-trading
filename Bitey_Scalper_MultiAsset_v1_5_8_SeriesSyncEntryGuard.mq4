//+------------------------------------------------------------------+
//| Bitey_Scalper_MultiAsset_v1_5_8_SeriesSyncEntryGuard.mq4 |
//| Adaptive loss manager retained; net-profit protection triggers at 50% giveback from peak. |
//| Existing signals and adaptive SL/TP are retained; no SL widening or martingale. |
//| Loss response scales new-entry risk; open positions retain existing SL/TP management. |
//+------------------------------------------------------------------+
#property strict
#property version   "1.580"
#property description "Bitey v1.5.8: synchronized-series entry guard with progressive analytical selectivity"

#define EA_VERSION          "1.5.8"
#define MAX_SYMBOLS         256
#define HARD_MAX_POSITIONS  5

//--- universe and timeframes
input string           InpSymbolsCSV            = "";      // Blank = Market Watch; broker-listed USDT symbols are always added
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M15;
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_H1;  // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102026;

//--- risk
input double           InpReferenceCapitalUSD   = 500.0;
input double           InpRiskPctPerTrade       = 0.5;     // 5 positions x 0.5% = 2.5% aggregate
input double           InpMaxAggregateRiskPct   = 2.5;
input double           InpMaxCurrencyRiskPct    = 1.5;     // Maximum stop-risk attributed to either FX currency
input double           InpDailyLossPct          = 2.0;     // Daily net loss threshold as % of reference capital
input bool             InpEnableDailyEntryProtection = true; // Enables progressive selectivity; never hard-locks entries by daily loss alone
input double           InpSelectivityLevel1LossPct = 1.0; // Net daily loss %: Level 1
input double           InpSelectivityLevel3LossPct = 3.0; // Net daily loss %: Level 3
input double           InpSelectivityScoreStep = 5.0; // Added minimum score per selectivity level
input double           InpSelectivityRiskFactorL1 = 0.75;
input double           InpSelectivityRiskFactorL2 = 0.50;
input double           InpSelectivityRiskFactorL3 = 0.25;
input double           InpSelectivitySpreadFactor = 0.90; // Tighten hard spread ceiling per level
input double           InpSelectivityADXStep = 2.0; // Additional ADX requirement per level
input int              InpSelectivityRecoveryStableCycles = 1200; // ~20 minutes at the one-second cycle; stable cycles required before lowering a level
input int              InpMaxOpenPositions      = 5;       // Clamped to 1..5, one position per asset

//--- direction
input bool             InpAllowBuy              = true;
input bool             InpAllowSell             = true;

//--- signal
input int              InpFamilyMinVotes        = 3;       // Variants (of 8) needed for a family to speak
input double           InpTrendADX              = 20.0;    // ADX >= this: trend regime, otherwise range regime
input double           InpMinADX                = 10.0;    // Dead-market filter
input int              InpATRPeriod             = 14;
input double           InpStopATR               = 1.5;
input double           InpRewardRisk            = 2.0;

//--- execution filters
input double           InpMaxSpreadPctOfStop    = 12.0;    // Diagnostic warning threshold
input double           InpHardMaxSpreadPctOfStop = 10.0;    // Hard execution-quality cap; 0 = disabled
input double           InpMinEntryScore          = 15.0;    // Minimum entry score
input bool             InpEnableDailyAdaptiveQuality = false; // Experimental; false until validated in Strategy Tester
input int              InpDailyAdaptiveSampleSize = 10;      // Most recent closed EA trades for the current server day
input int              InpDailyAdaptiveMinLosses  = 6;       // Require more losses than wins (default 6/10)
input double           InpDailyAdaptiveExtraScore = 8.0;     // Additional score required while daily strict mode is active
input double           InpDailyAdaptiveHoldFactor = 0.75;    // Reduce max hold bars only when losers lasted longer
input double           InpDailyAdaptiveDurationRatio = 1.20; // Loser average duration must exceed winner duration by 20%
input int              InpDailyAdaptiveMinHoldBars = 12;      // Floor for the reduced time limit
input int              InpMaxSpreadPoints       = 0;       // Optional absolute cap, 0 = off
input int              InpMaxQuoteAgeSec        = 120;
input int              InpStaleQuoteRetryInitialSec = 5; // First stale-data recheck delay
input int              InpStaleQuoteRetryMaxSec  = 60; // Exponential backoff ceiling
input int              InpSlippagePoints        = 20;
input int              InpBroker133CooldownMinutes = 60; // 0 = block until EA restart
input int              InpBroker133RecheckMinutes  = 60; // Permission-only recheck interval after cooldown
input int              InpMinBars               = 250;
input bool             InpUseSessionFilter      = true;    // Server-hour window; recognized crypto prefixes are exempt
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 6;       // Closed signal bars after a net loss, same asset and direction only
input int              InpMaxHoldBars           = 0;       // Generic time exit disabled; winners remain managed by profit exits
input bool             InpEnableRollingLossPolicy = true;
input int              InpLossPolicySampleSize    = 10; // Rolling window of the latest N closed trades
input double           InpLossDurationMaxCostMultiple = 1.0; // Timed loss exit only within estimated transaction-cost budget
input int              InpLossNegativeMinutes     = 30;
input int              InpLossAssetPauseMinutes   = 30; // Legacy CSV compatibility only; no asset entry pause is applied
input double           InpLossPolicyExtraScore    = 5.0;
input double           InpLossPolicyExtraADX      = 2.0;
input double           InpLossPolicySpreadFactor  = 0.90;
input int              InpLossPolicySuspendStreak = 5; // Maximum loss-response level; no suspension
input double           InpLossRiskLevel1Factor    = 0.75;
input double           InpLossRiskLevel2Factor    = 0.50;
input double           InpLossRiskLevel3Factor    = 0.25;
input int              InpLossRecoveryWinCount    = 7; // Positive batch wins required for full risk recovery
input bool             InpEnableOpenExposureGuard = true; // Scale new-entry risk when floating portfolio/currency-cluster losses grow
input double           InpOpenExposureLevel1Pct   = 0.50; // Floating loss threshold as % of reference capital
input double           InpOpenExposureLevel2Pct   = 1.00;
input double           InpOpenExposureLevel3Pct   = 1.50; // Highest defensive level; never suspends the trading day

//--- adaptive SL/TP
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.25;
input double           InpBreakEvenLockATR      = 0.05;
input double           InpTrailStartATR         = 1.2;
input double           InpTrailDistanceATR      = 0.9;
input bool             InpEnableConfirmedRetracementExit = true; // Close after a meaningful, closed-bar-confirmed pullback
input double           InpRetracementMinPeakATR   = 0.8; // Minimum favorable excursion before retracement exit can trigger
input double           InpRetracementPullbackATR  = 0.45; // Pullback from best price required for exit
input double           InpRetracementExitMinR      = 0.80; // Require at least +0.80R net before retracement exit
input double           InpTrailStepATR          = 0.0;     // 0 = trail at broker-point granularity; never loosen SL
input int              InpAdaptiveSLModifyMinIntervalSeconds = 5;   // Minimum time between non-emergency SL modifications per ticket
input double           InpAdaptiveSLModifyMinStepATR = 0.0; // 0 = no ATR-sized defer; broker point remains the minimum
input double           InpAdaptiveSLEmergencyStepATR = 0.50; // Bypass time interval for a large protective SL improvement
input double           InpTPExpandTriggerATR    = 1.0;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 4.0;     // Maximum TP distance from entry in ATR; 0 = unlimited
input double           InpSmallProfitCloseUSD   = 0.10;    // Minimum small-profit close
input double           InpSmallProfitCloseR      = 0.80;    // Dynamic small-profit close floor in R
input double           InpSmallLossCloseUSD     = 0.0;     // Legacy optional fixed loss exit; disabled by default
input bool             InpEnableProgressiveLossExit = true; // Exit only when closed-bar progression confirms adverse movement
input double           InpProgressiveLossBaseRiskPct = 60.0; // Initial allowance as % of original ticket stop risk
input int              InpSmallLossMinHoldSeconds = 60;      // If explicitly enabled, never use this exit during the first 60 seconds
input int              InpProgressionLookbackBars = 3;     // Closed-bar EMA slope lookback for directional progression
input double           InpProgressionADXMin     = 18.0;    // Minimum ADX for directional progression confirmation
input double           InpProfitLockTriggerR     = 0.85;  // Activate profit lock after peak net reaches +0.85R
input double           InpTrendRunnerTriggerNetUSD = 0.20;  // Fallback trigger if original risk data is unavailable
input double           InpWeakTrendTrailATR     = 0.60;    // Tighten trailing distance when progression turns against the trade
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)
input double           InpNetLockMinUSD          = 0.10;    // Minimum net amount protected after runner activation
input double           InpNetLockGivebackPct     = 40.0;    // Close after 40% giveback from qualifying peak net profit
input double           InpNetLockStepUSD         = 0.05;    // Persist peak after each small improvement
input double           InpEstimatedCloseCommissionPerLot = 0.0; // Optional estimated close commission per 1.0 lot
input bool             InpIncludeEstimatedCloseCommission = false; // Default false: spread/booked costs only; enable if close commission applies
input int              InpDiagnosticThrottleSeconds = 60; // Per-symbol/per-event diagnostic interval
input int              InpPauseAfterConsecutiveLosses = 3; // Escalate analytical selectivity after N consecutive net losses; no hard lock
input int              InpNetLockSlippagePoints  = 3;       // Adverse stop-fill slippage reserve

#define DIAGNOSTIC_ONLY_BUILD false
input bool             InpEnableTrading         = true;    // order sending only after all signal, broker and risk checks pass
input bool             InpLogRejects            = false;
input bool             InpEnableDetailedExecutionDiagnostics = true; // Log broker contract, quote, sizing and permission context for rejected entries
input bool             InpLogBarScanDiagnostics  = true;    // Log per-symbol bar-scan state changes
input bool             InpShowScanDashboard     = true;    // Show scan counts and last indicator snapshot on chart

string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
datetime g_pendingBar[MAX_SYMBOLS];
int      g_barRetryCount[MAX_SYMBOLS];
bool     g_barBaselineSet[MAX_SYMBOLS];
string   g_lastBarDiagState[MAX_SYMBOLS];
string   g_sessionBlockReason[MAX_SYMBOLS];
int      g_sessionBlockError[MAX_SYMBOLS];
string   g_lastMarketDataDiagState[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
uint     g_lastHeartbeatTick = 0;
uint     g_lastDailyLossWarningTick = 0;
int      g_cycleNewBars = 0;
int      g_cycleBarRetries = 0;
int      g_cycleNoNewBar = 0;
int      g_cycleHistoryUnavailable = 0;
int      g_cycleInsufficientHistory = 0;
int      g_cyclePrefilterOK = 0;
int      g_cycleIndicatorRuns = 0;
int      g_cycleSignalCandidates = 0;
int      g_cycleBuySignals = 0;
int      g_cycleSellSignals = 0;
int      g_cyclePrefilterRejects = 0;
int      g_cycleSignalRejects = 0;
int      g_cycleCapacityRejects = 0;
datetime g_lastPermissionDiagnostic = 0;
datetime g_lastQuoteStamp[MAX_SYMBOLS];
uint     g_lastQuoteChangeTick[MAX_SYMBOLS];
int      g_quoteBaseAgeSec[MAX_SYMBOLS]; // Server-time age at last observed quote timestamp
bool     g_quoteStale[MAX_SYMBOLS];
uint     g_quoteNextCheckTick[MAX_SYMBOLS];
int      g_quoteRetryDelaySec[MAX_SYMBOLS];
string   g_lastScanSymbol = "-";
string   g_lastIndicatorSummary = "Waiting for first indicator evaluation";
string   g_lastExecutionRejectCategory = "";
datetime g_sessionStartTime = 0;
bool     g_sessionBlocked[MAX_SYMBOLS];
uint     g_sessionBlockUntilTick[MAX_SYMBOLS];
uint     g_sessionNextPermissionCheckTick[MAX_SYMBOLS];
datetime g_sessionBlockUntilTime[MAX_SYMBOLS];
int      g_sessionCandidates[MAX_SYMBOLS];
int      g_sessionAttempts[MAX_SYMBOLS];
int      g_sessionAccepted[MAX_SYMBOLS];
int      g_sessionRejected[MAX_SYMBOLS];
int      g_sessionClosed[MAX_SYMBOLS];
double   g_sessionNet[MAX_SYMBOLS];
int      g_processedCloseTickets[2048];
int      g_processedCloseCount = 0;
int      g_eaCloseReasonTickets[2048];
string   g_eaCloseReasonText[2048];
int      g_eaCloseReasonCount = 0;
int      g_globalLossSampleCount = 0;
datetime g_lossPolicyDayStart = 0;
datetime g_globalLossBlockLogDay = 0;
int      g_dailyLossCsvHandle = INVALID_HANDLE;
string   g_dailyLossCsvName = "";
int      g_globalLossWins = 0;
int      g_globalLossLosses = 0;
int      g_globalLossStreak = 0;
double   g_globalLossNet = 0.0;
bool     g_globalLossAdverse = false;

// Append-only research audit CSV; daily adaptive decisions are independently logged.
int      g_auditCsvHandle = INVALID_HANDLE;
string   g_auditCsvName = "";
string   g_execDiagKeys[2048];
uint     g_execDiagLastTick[2048];
int      g_execDiagSuppressed[2048];
int      g_execDiagKeyCount = 0;
bool     g_dailyEntryLocked = false;
datetime g_dailyEntryLockDay = 0;
string   g_dailyEntryLockReason = "";
int      g_analyticalSelectivityLevel = 0;
int      g_pendingSelectivityLevel = 0;
int      g_selectivityStableCycles = 0;
double   g_lastSelectivityDayNet = 0.0;

string   g_candSym[MAX_SYMBOLS];
int      g_candCmd[MAX_SYMBOLS];
double   g_candScore[MAX_SYMBOLS];
double   g_candSpreadPct[MAX_SYMBOLS];
double   g_candPriority[MAX_SYMBOLS];
int      g_lastExecutionErrorCode = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   ParseSymbols();
   if(g_symbolCount<=0) { Print("INIT_ERROR | no symbols found"); return(INIT_FAILED); }
   OpenAuditCSV();
   g_lossPolicyDayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   OpenDailyLossSummaryCSV();
   CheckDailyLossDay();
   g_sessionStartTime=TimeCurrent();
   for(int i=0;i<g_symbolCount;i++)
   {
      g_sessionBlocked[i]=false;
      g_sessionBlockReason[i]="";
      g_sessionBlockError[i]=0;
      g_sessionBlockUntilTick[i]=0;
      g_sessionNextPermissionCheckTick[i]=0;
      g_sessionBlockUntilTime[i]=0;
      g_sessionCandidates[i]=0;
      g_sessionAttempts[i]=0;
      g_sessionAccepted[i]=0;
      g_sessionRejected[i]=0;
      g_sessionClosed[i]=0;
      g_sessionNet[i]=0.0;
      g_lastBar[i]=0;
      g_pendingBar[i]=0;
      g_barRetryCount[i]=0;
      g_barBaselineSet[i]=false;
      g_lastBarDiagState[i]="";
      g_lastMarketDataDiagState[i]="";
      g_quoteStale[i]=false;
      g_quoteNextCheckTick[i]=0;
      g_quoteRetryDelaySec[i]=0;
      bool symbolSelected=SymbolSelect(g_symbols[i],true);
      Print("SYMBOL_SELECT_DIAGNOSTIC | symbol=",g_symbols[i],
            " selected=",(symbolSelected?"true":"false"),
            " tradeAllowed=",(MarketInfo(g_symbols[i],MODE_TRADEALLOWED)>0?"true":"false"));
      // Capture the already-existing current bar as the startup baseline.
      // It must not be counted as a newly formed bar on the first RunCycle.
      datetime startupBar=iTime(g_symbols[i],InpSignalTF,0);
      if(startupBar>0)
      {
         g_lastBar[i]=startupBar;
         g_pendingBar[i]=0;
         g_barRetryCount[i]=0;
         g_barBaselineSet[i]=true;
         g_lastBarDiagState[i]="INITIAL_BASELINE";
         if(InpLogBarScanDiagnostics)
         {
            datetime startupTick=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
            int startupBarAge=(int)MathMax(0,TimeCurrent()-startupBar);
            int startupQuoteAge=(startupTick>0?(int)MathMax(0,TimeCurrent()-startupTick):-1);
            Print("BAR_SCAN_SYMBOL | symbol=",g_symbols[i],
                  " tf=",(int)InpSignalTF,
                  " state=INITIAL_BASELINE bars=",iBars(g_symbols[i],InpSignalTF),
                  " minBars=",InpMinBars,
                  " currentBarTime=",(long)startupBar,
                  " barAgeSec=",startupBarAge,
                  " quoteAgeSec=",startupQuoteAge,
                  " note=EXISTING_BAR_NOT_COUNTED_AS_NEW");
         }
      }
      g_lastQuoteStamp[i]=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      datetime initServerTime=TimeCurrent();
      if(g_lastQuoteStamp[i]>0 && initServerTime>=g_lastQuoteStamp[i])
      {
         long initialAge=(long)initServerTime-(long)g_lastQuoteStamp[i];
         g_quoteBaseAgeSec[i]=(initialAge>=2147483647?2147483647:(int)initialAge);
         g_lastQuoteChangeTick[i]=GetTickCount();
      }
      else
      {
         g_quoteBaseAgeSec[i]=2147483647;
         g_lastQuoteChangeTick[i]=0;
      }
      // Recent cached quotes are age-checked at startup and then aged monotonically.
   }
   LogPotentialAliasGroups();
   EventSetTimer(1);
   if(AccountCurrency()!="USD") Print("RISK_WARNING | reference capital is USD but account currency is ",AccountCurrency(),"; verify conversion before trading");
   if(InpIncludeEstimatedCloseCommission && InpEstimatedCloseCommissionPerLot<=0.0) Print("NET_LOCK_WARNING | close commission inclusion is enabled but estimate is zero; configure the actual amount");
   else Print("NET_COST_POLICY | closeCommissionEstimateIncluded=",(InpIncludeEstimatedCloseCommission?"true":"false")," bookedCommission=INCLUDED spread=REFLECTED_IN_EXECUTABLE_BID_ASK");
   Print("QUOTE_STALE_RECOVERY | maxAgeSec=",InpMaxQuoteAgeSec,
         " retryInitialSec=",MathMax(1,InpStaleQuoteRetryInitialSec),
         " retryMaxSec=",MathMax(MathMax(1,InpStaleQuoteRetryInitialSec),InpStaleQuoteRetryMaxSec),
         " action=SKIP_STALE_SYMBOL_ONLY_AUTO_RECOVER_ON_FRESH_TICK");
   Print("TP_DISTANCE_CAP | maxATR=",DoubleToString(InpTPMaxDistanceATR,2)," scope=ADAPTIVE_EXTENSION_ONLY");
   Print("ADAPTIVE_SL_TP_PRESERVED | SL=NO_WIDENING TP=EXISTING_ADAPTIVE_EXPANSION_AND_CAP BREAK_EVEN=ON TRAILING=ON NET_GIVEBACK=40_AFTER_0_85R");
   Print("PROGRESSIVE_SELECTIVITY_CONFIG | levels=0,1,2,3 scoreFloor=15,20,25,30 dailyLossPct=1,2,3 consecutiveLossEscalation=2,3,4 action=NO_HARD_DAILY_ENTRY_LOCK");
   Print("ADAPTIVE_LOSS_MANAGER | enabled=",(InpEnableRollingLossPolicy?"true":"false"),
      " sample=ROLLING_LAST_N_CLOSED_TRADES global=ALL_ASSETS assetAndSide=INDEPENDENT",
      " riskFactors=",DoubleToString(InpLossRiskLevel1Factor,2),"/",DoubleToString(InpLossRiskLevel2Factor,2),"/",DoubleToString(InpLossRiskLevel3Factor,2),
      " recoveryWins=",InpLossRecoveryWinCount," globalSuspension=OFF assetSuspension=OFF");
   Print("DAILY_LOSS_REPORT | timeBasis=MT4_SERVER_DAY file=",g_dailyLossCsvName,
      " rows=GLOBAL_AND_ASSET net=GROSS_PLUS_SWAP_PLUS_COMMISSION");
   Print("BITEY_ENSEMBLE_INIT | version=",EA_VERSION," | universe=MARKET_WATCH_PLUS_ALL_BROKER_USDT_ADDITIVE | quoteFreshness=SERVER_ANCHORED_MONOTONIC maxQuoteAgeSec=",InpMaxQuoteAgeSec," | tradeAudit=PER_TICKET_GROSS_COMMISSION_SWAP_NET | symbols=",g_symbolCount,
         " | maxPositions=",MaxPositions()," | tf=",(int)InpSignalTF,
         " | profitRunner=NET_+",DoubleToString(InpTrendRunnerTriggerNetUSD,2)," lockFloor=+",DoubleToString(InpNetLockMinUSD,2)," | accountMode=NOT_A_GATE | diagnosticOnly=",(DIAGNOSTIC_ONLY_BUILD?"ON":"OFF"),
          " | trading=",(InpEnableTrading?"ON":"OFF"));
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   if(g_auditCsvHandle!=INVALID_HANDLE)
   {
      FileFlush(g_auditCsvHandle); FileClose(g_auditCsvHandle); g_auditCsvHandle=INVALID_HANDLE;
      Print("AUDIT_CSV_CLOSED | file=",g_auditCsvName);
   }
   if(g_dailyLossCsvHandle!=INVALID_HANDLE)
   {
      FileFlush(g_dailyLossCsvHandle); FileClose(g_dailyLossCsvHandle); g_dailyLossCsvHandle=INVALID_HANDLE;
      Print("DAILY_LOSS_CSV_CLOSED | file=",g_dailyLossCsvName);
   }
}
void OnTick()  { RunCycle(); }
void OnTimer() { RunCycle(); }

int MaxPositions()
{
   return(MathMin(HARD_MAX_POSITIONS,MathMax(1,InpMaxOpenPositions)));
}

int SessionSymbolIndex(string sym)
{
   string key=AssetIdentityKey(sym);
   for(int i=0;i<g_symbolCount;i++)
      if(g_keys[i]==key) return(i);
   return(-1);
}

void BlockSessionSymbol(string sym,string reason,int brokerError)
{
   int idx=SessionSymbolIndex(sym);
   if(idx<0) return;
   bool newlyBlocked=!g_sessionBlocked[idx];
   g_sessionBlocked[idx]=true;
   g_sessionBlockReason[idx]=reason;
   g_sessionBlockError[idx]=brokerError;
   uint nowTick=GetTickCount();
   int cooldownMinutes=MathMax(0,InpBroker133CooldownMinutes);
   g_sessionBlockUntilTick[idx]=nowTick+(uint)(cooldownMinutes*60000);
   g_sessionNextPermissionCheckTick[idx]=g_sessionBlockUntilTick[idx];
   g_sessionBlockUntilTime[idx]=(cooldownMinutes>0?TimeCurrent()+cooldownMinutes*60:0);
   if(newlyBlocked || brokerError>0)
      Print("BROKER_SYMBOL_DISABLED | symbol=",sym," assetKey=",g_keys[idx],
            " reason=",reason," error=",brokerError,
            " errorName=",(brokerError>0?TradeErrorDescription(brokerError):"MODE_TRADEALLOWED_FALSE"),
            " cooldownMinutes=",cooldownMinutes,
            " retryPolicy=NO_ORDER_RETRY_PERMISSION_ONLY_RECHECK");
}

bool SessionSymbolBlocked(string sym)
{
   int idx=SessionSymbolIndex(sym);
   if(idx<0 || !g_sessionBlocked[idx]) return(false);

   // Zero keeps the symbol blocked until EA reinitialization.
   // GetTickCount measures elapsed time independently of server quote time.
   if(InpBroker133CooldownMinutes<=0) return(true);

   uint nowTick=GetTickCount();
   if((int)(nowTick-g_sessionBlockUntilTick[idx])<0) return(true);
   if((int)(nowTick-g_sessionNextPermissionCheckTick[idx])<0) return(true);

   // Permission-only probe: never send a test order to "check" broker access.
   bool symbolAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);
   bool permissionsReady=TradePermissionsReady(sym,"BROKER_133_COOLDOWN_EXPIRED");
   if(symbolAllowed && permissionsReady)
   {
      g_sessionBlocked[idx]=false;
      g_sessionBlockUntilTick[idx]=0;
      g_sessionNextPermissionCheckTick[idx]=0;
      string previousBlockReason=g_sessionBlockReason[idx];
      int previousBlockError=g_sessionBlockError[idx];
      g_sessionBlockUntilTime[idx]=0;
      g_sessionBlockReason[idx]="";
      g_sessionBlockError[idx]=0;
      Print("SESSION_SYMBOL_UNBLOCK | symbol=",sym,
            " previousReason=",previousBlockReason,
            " previousError=",previousBlockError,
            " reason=COOLDOWN_EXPIRED_AND_PERMISSIONS_READY",
            " permissionProbeOnly=true no_test_order=true");
      return(false);
   }

   int recheckMinutes=MathMax(1,InpBroker133RecheckMinutes);
   g_sessionNextPermissionCheckTick[idx]=nowTick+(uint)(recheckMinutes*60000);
   Print("SESSION_SYMBOL_BLOCK_RETAINED | symbol=",sym,
         " blockedReason=",g_sessionBlockReason[idx],
         " brokerError=",g_sessionBlockError[idx],
         " reason=PERMISSIONS_NOT_READY_AFTER_COOLDOWN",
         " symbolTradeAllowed=",(symbolAllowed?"true":"false"),
         " nextCheckMinutes=",recheckMinutes,
         " no_order_sent=true");
   return(true);
}

// Session-only, bounded adjustment. It is inactive until five closed trades
// exist for the symbol and only uses account-currency net results on USD accounts.
double SessionPerformanceAdjustment(string sym)
{
   if(AccountCurrency()!="USD") return(0.0);
   int idx=SessionSymbolIndex(sym);
   if(idx<0 || g_sessionClosed[idx]<5) return(0.0);
   double avg=g_sessionNet[idx]/g_sessionClosed[idx];
   return(MathMax(-2.0,MathMin(2.0,avg*2.0)));
}


//+------------------------------------------------------------------+
//| Research audit CSV: trade lifecycle snapshots and final outcomes |
//+------------------------------------------------------------------+
string AuditPeakKey(int ticket)   { return("BiteyAuditPeak_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket)); }
string EntrySpreadKey(int ticket)  { return("BiteyEntrySpread_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket)); }
string AuditTroughKey(int ticket) { return("BiteyAuditTrough_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket)); }
string AuditLastKey(int ticket)   { return("BiteyAuditLast_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket)); }

void OpenAuditCSV()
{
   string stamp=TimeToString(TimeLocal(),TIME_DATE|TIME_MINUTES);
   StringReplace(stamp,".","-"); StringReplace(stamp,":","-"); StringReplace(stamp," ","_");
   g_auditCsvName="Bitey_v1_5_7_ProgressiveSelectivity_Audit_"+stamp+".csv";
   ResetLastError();
   g_auditCsvHandle=FileOpen(g_auditCsvName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(g_auditCsvHandle==INVALID_HANDLE)
   {
      Print("AUDIT_CSV_ERROR | action=OPEN file=",g_auditCsvName," error=",GetLastError(),
            " expectedFolder=MQL4\\Files or Tester\\Files");
      return;
   }
   bool fresh=(FileSize(g_auditCsvHandle)==0);
   FileSeek(g_auditCsvHandle,0,SEEK_END);
   if(fresh)
      FileWrite(g_auditCsvHandle,"timestamp_server","event","ticket","symbol","side","lots",
         "open_time_server","age_seconds","bars_open","open_price","mark_price","stop_loss","take_profit",
         "floating_gross","commission_booked","swap_booked","floating_net",
         "max_favorable_net_seen","max_adverse_net_seen","realized_gross","realized_commission",
         "realized_swap","realized_net","close_price","close_reason_classification","extra");
   FileFlush(g_auditCsvHandle);
   Print("AUDIT_CSV_OPEN | file=",g_auditCsvName," folder=",(IsTesting()?"Tester\\Files":"MQL4\\Files"),
         " append=true intervalSeconds=60 strategyChanges=DAILY_ADAPTIVE_QUALITY_OPTIONAL losses=TRADE_LOSS cooldown=ACTIVE_6_CLOSED_M15_BARS");
}

void AuditLifecycleSnapshot(int ticket,string eventName,string extra)
{
   if(g_auditCsvHandle==INVALID_HANDLE) return;
   if(!OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES) || OrderCloseTime()>0) return;
   int type=OrderType();
   if(type!=OP_BUY && type!=OP_SELL) return;
   string sym=OrderSymbol();
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double mark=(type==OP_BUY?bid:ask);
   if(mark<=0.0) return;
   double gross=OrderProfit(), commission=OrderCommission(), swap=OrderSwap();
   double net=gross+commission+swap;
   string peakKey=AuditPeakKey(ticket), troughKey=AuditTroughKey(ticket), lastKey=AuditLastKey(ticket);
   double peak=(GlobalVariableCheck(peakKey)?GlobalVariableGet(peakKey):net);
   double trough=(GlobalVariableCheck(troughKey)?GlobalVariableGet(troughKey):net);
   peak=MathMax(peak,net); trough=MathMin(trough,net);
   GlobalVariableSet(peakKey,peak); GlobalVariableSet(troughKey,trough);
   datetime now=TimeCurrent();
   double last=(GlobalVariableCheck(lastKey)?GlobalVariableGet(lastKey):0.0);
   if(eventName=="SNAPSHOT" && last>0.0 && (now-(datetime)last)<60) return;
   GlobalVariableSet(lastKey,(double)now);
   int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   FileWrite(g_auditCsvHandle,TimeToString(now,TIME_DATE|TIME_SECONDS),eventName,ticket,sym,
      (type==OP_BUY?"BUY":"SELL"),OrderLots(),
      TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
      (long)MathMax(0,now-OrderOpenTime()),barsOpen,OrderOpenPrice(),mark,
      OrderStopLoss(),OrderTakeProfit(),gross,commission,swap,net,peak,trough,
      0.0,0.0,0.0,0.0,0.0,"OPEN",extra);
   FileFlush(g_auditCsvHandle);
}

void AuditClosedTrade(int ticket,string sym,string side,double lots,datetime opened,datetime closed,
                      double openPrice,double closePrice,double sl,double tp,double gross,
                      double commission,double swap,double net,string classification)
{
   if(g_auditCsvHandle==INVALID_HANDLE) return;
   string pk=AuditPeakKey(ticket), tk=AuditTroughKey(ticket);
   double peak=(GlobalVariableCheck(pk)?GlobalVariableGet(pk):0.0);
   double trough=(GlobalVariableCheck(tk)?GlobalVariableGet(tk):0.0);
   string closeEvent=(net<0.0?"TRADE_LOSS":"TRADE_CLOSED");
   FileWrite(g_auditCsvHandle,TimeToString(closed,TIME_DATE|TIME_SECONDS),closeEvent,
      ticket,sym,side,lots,TimeToString(opened,TIME_DATE|TIME_SECONDS),
      (long)MathMax(0,closed-opened),0,openPrice,closePrice,sl,tp,
      0.0,0.0,0.0,0.0,peak,trough,gross,commission,swap,net,closePrice,classification,
      (net<0.0?"history_source=MT4;analysis=LOSS_RECORDED;cooldown=ACTIVE_6_CLOSED_M15_BARS":"history_source=MT4;cooldown=ACTIVE_6_CLOSED_M15_BARS")+";entrySpreadPrice="+DoubleToString((GlobalVariableCheck(EntrySpreadKey(ticket))?GlobalVariableGet(EntrySpreadKey(ticket)):0.0),8)+";net=gross+commission+swap;spread_in_execution_prices");
   FileFlush(g_auditCsvHandle);
   double mfeCapturePct=(peak>0.0?100.0*net/peak:0.0);
   double adverseToMfe=(peak>0.0?MathAbs(MathMin(0.0,trough))/peak:0.0);
   Print("MFE_MAE_PROFILE | ticket=",ticket," symbol=",sym," side=",side,
      " realizedNet=",DoubleToString(net,2)," mfeNet=",DoubleToString(peak,2),
      " maeNet=",DoubleToString(trough,2),
      " realizedCapturePctOfMFE=",DoubleToString(mfeCapturePct,1),
      " adverseToMFERatio=",DoubleToString(adverseToMfe,2),
      " interpretation=DIAGNOSTIC_ONLY_NO_SL_TP_CHANGE");
   if(net<0.0) Print("TRADE_LOSS_RECORDED | ticket=",ticket," symbol=",sym," side=",side,
      " net=",DoubleToString(net,2)," classification=",classification," csv=",g_auditCsvName);
   if(GlobalVariableCheck(pk)) GlobalVariableDel(pk);
   if(GlobalVariableCheck(tk)) GlobalVariableDel(tk);
   string lk=AuditLastKey(ticket); if(GlobalVariableCheck(lk)) GlobalVariableDel(lk);
   string sk=EntrySpreadKey(ticket); if(GlobalVariableCheck(sk)) GlobalVariableDel(sk);
}

//+------------------------------------------------------------------+
//| Record EA-originated market closes for later history attribution  |
//+------------------------------------------------------------------+
void RecordEAClosedReason(int ticket,string reason)
{
   if(ticket<=0 || g_eaCloseReasonCount>=2048) return;
   for(int i=0;i<g_eaCloseReasonCount;i++)
      if(g_eaCloseReasonTickets[i]==ticket) return;
   g_eaCloseReasonTickets[g_eaCloseReasonCount]=ticket;
   g_eaCloseReasonText[g_eaCloseReasonCount]=reason;
   g_eaCloseReasonCount++;
}

string ClassifyHistoricalClose(int ticket,double closePrice,double sl,double tp,string sym)
{
   for(int i=0;i<g_eaCloseReasonCount;i++)
      if(g_eaCloseReasonTickets[i]==ticket)
         return("EA_MARKET_CLOSE_CONFIRMED:"+g_eaCloseReasonText[i]);
   double point=MarketInfo(sym,MODE_POINT);
   double tickSize=MarketInfo(sym,MODE_TICKSIZE);
   double tolerance=MathMax(point*3.0,tickSize*1.5);
   bool nearSL=(sl>0.0 && MathAbs(closePrice-sl)<=tolerance);
   bool nearTP=(tp>0.0 && MathAbs(closePrice-tp)<=tolerance);
   if(nearSL && nearTP) return("SLTP_MATCH_AMBIGUOUS");
   if(nearSL) return("SL_HIT_PROBABLE_NOT_PROVEN");
   if(nearTP) return("TP_HIT_PROBABLE_NOT_PROVEN");
   return("BROKER_MANUAL_OR_OTHER_UNKNOWN");
}

//+------------------------------------------------------------------+
void SyncClosedTradeStats()
{
   int total=OrdersHistoryTotal();
   for(int i=total-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderCloseTime()<g_sessionStartTime) continue;
      int ticket=OrderTicket();
      bool seen=false;
      for(int j=0;j<g_processedCloseCount;j++)
         if(g_processedCloseTickets[j]==ticket) { seen=true; break; }
      if(seen) continue;
      if(g_processedCloseCount>=2048)
      {
         Print("TRADE_AUDIT_CAPACITY_WARNING | ticket=",ticket," capacity=2048 action=stop_session_audit");
         break;
      }
      g_processedCloseTickets[g_processedCloseCount++]=ticket;

      // MT4 history is the source of truth for realized gross P/L and booked costs.
      // EA close records are definitive; SL/TP price matches remain probable only.
      string closeClassification=ClassifyHistoricalClose(ticket,OrderClosePrice(),OrderStopLoss(),OrderTakeProfit(),OrderSymbol());
      long serverLocalOffset=(long)TimeLocal()-(long)TimeCurrent();
      double gross=OrderProfit();
      double swap=OrderSwap();
      double commission=OrderCommission();
      double net=gross+swap+commission;
      string side=(OrderType()==OP_BUY?"BUY":"SELL");
      double entrySpreadPrice=(GlobalVariableCheck(EntrySpreadKey(ticket))?GlobalVariableGet(EntrySpreadKey(ticket)):0.0);
      double spreadCostEstimate=(entrySpreadPrice>0.0?EstimateRisk(OrderSymbol(),OrderLots(),entrySpreadPrice):0.0);
      if(spreadCostEstimate>=1.0e11) spreadCostEstimate=0.0;
      AuditClosedTrade(ticket,OrderSymbol(),side,OrderLots(),OrderOpenTime(),OrderCloseTime(),OrderOpenPrice(),OrderClosePrice(),OrderStopLoss(),OrderTakeProfit(),gross,commission,swap,net,closeClassification);
      string resultLabel=(net>0.0?"EXITOSA":(net<0.0?"FRACASADA":"EMPATE"));
      Print("TRADE_RESULT_COMMENT | ticket=",ticket," symbol=",OrderSymbol()," side=",side,
         " result=",resultLabel," net=",DoubleToString(net,2),
         " gross=",DoubleToString(gross,2)," commission=",DoubleToString(commission,2),
         " swap=",DoubleToString(swap,2)," entrySpreadCostEstimate=",DoubleToString(spreadCostEstimate,2),
         " exitReason=",closeClassification,
         " note=spread_reflected_in_execution_prices;taxes_only_if_broker_books_them_in_commission_or_swap");
      Print("TRADE_CLOSE_AUDIT | scope=EA_SESSION_ONLY ticket=",ticket,
            " symbol=",OrderSymbol()," side=",side,
            " lots=",DoubleToString(OrderLots(),3),
            " openTimeServer=",TimeToString(OrderOpenTime(),TIME_DATE|TIME_SECONDS),
            " closeTimeServer=",TimeToString(OrderCloseTime(),TIME_DATE|TIME_SECONDS),
            " closeTimeLocalEstimate=",TimeToString(OrderCloseTime()+serverLocalOffset,TIME_DATE|TIME_SECONDS),
            " closeClassification=",closeClassification,
            " auditTimeServer=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            " auditTimeLocal=",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
            " auditTimeGMT=",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
            " serverLocalOffsetSec=",serverLocalOffset,
            " openPrice=",DoubleToString(OrderOpenPrice(),(int)MarketInfo(OrderSymbol(),MODE_DIGITS)),
            " closePrice=",DoubleToString(OrderClosePrice(),(int)MarketInfo(OrderSymbol(),MODE_DIGITS)),
            " gross=",DoubleToString(gross,2),
            " commission=",DoubleToString(commission,2),
            " swap=",DoubleToString(swap,2),
            " net=",DoubleToString(net,2),
            " magic=",OrderMagicNumber());

      int idx=SessionSymbolIndex(OrderSymbol());
      if(idx>=0)
      {
         g_sessionClosed[idx]++;
         g_sessionNet[idx]+=net;
         Print("SESSION_TRADE_STAT | symbol=",OrderSymbol()," ticket=",ticket,
               " gross=",DoubleToString(gross,2),
               " commission=",DoubleToString(commission,2),
               " swap=",DoubleToString(swap,2),
               " net=",DoubleToString(net,2),
               " symbolClosed=",g_sessionClosed[idx],
               " symbolSessionNet=",DoubleToString(g_sessionNet[idx],2));
      }
   }
}

void LogSessionSymbolStats()
{
   for(int i=0;i<g_symbolCount;i++)
   {
      if(g_sessionCandidates[i]+g_sessionAttempts[i]+g_sessionClosed[i]==0 && !g_sessionBlocked[i]) continue;
      Print("SESSION_SYMBOL_STATS | symbol=",g_symbols[i],
            " candidates=",g_sessionCandidates[i],
            " attempts=",g_sessionAttempts[i],
            " accepted=",g_sessionAccepted[i],
            " rejected=",g_sessionRejected[i],
            " closed=",g_sessionClosed[i],
            " net=",DoubleToString(g_sessionNet[i],2),
            " broker133Blocked=",(g_sessionBlocked[i]?"true":"false"),
            " sample=EA_SESSION_ONLY");
   }
}
//+------------------------------------------------------------------+
//| Asset key: strips prefix/suffix so broker aliases collapse        |
//+------------------------------------------------------------------+
string AssetIdentityKey(string s)
{
   StringTrimLeft(s); StringTrimRight(s);
   StringToUpper(s);
   if(StringLen(s)>0 && StringGetChar(s,0)=='#') s=StringSubstr(s,1);
   string key="";
   for(int i=0;i<StringLen(s);i++)
   {
      int ch=StringGetChar(s,i);
      bool alnum=((ch>='0' && ch<='9') || (ch>='A' && ch<='Z'));
      if(!alnum) break; // Strip broker suffixes such as .p; retain the full base contract.
      key+=CharToString((uchar)ch);
   }
   return(key);
}

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

bool IsCrypto(string sym)
{
   string k=AssetKey(sym);
   // Exact six-character AssetKey values avoid exempting unrelated symbols
   // that happen to share the first three letters with a crypto ticker.
   if(k=="ICPUSD" || k=="IOTAUS" || k=="ASTERU" || k=="TRUMPU" ||
      k=="DASHUS" || k=="GRTUSD" || k=="ARUSD" || k=="ARUSDT")
      return(true);

   // Preserve the original prefix list for the previously supported assets.
   string p[24]={"BTC","XBT","ETH","SOL","XRP","LTC","BCH","DOG","ADA","DOT","LIN","AVA","BNB","NEA","ZEC","LRC","UNI","TRX","ETC","FIL","ATOM","LINK","SHIB","TON"};
   for(int i=0;i<24;i++)
      if(StringFind(k,p[i])==0) return(true);
   return(false);
}

void ParseSymbols()
{
   g_symbolCount=0;
   string csv=InpSymbolsCSV;
   StringTrimLeft(csv); StringTrimRight(csv);

   // Preserve the existing configured universe. If no CSV is supplied,
   // start with every symbol already present in Market Watch.
   if(StringLen(csv)==0)
   {
      int selectedTotal=SymbolsTotal(true);
      for(int i=0;i<selectedTotal && g_symbolCount<MAX_SYMBOLS;i++)
         AddSymbol(SymbolName(i,true));
   }
   else
   {
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

   // Add every broker-catalog symbol containing USDT, without removing
   // or replacing any non-USDT symbol already in the configured universe.
   int brokerTotal=SymbolsTotal(false);
   int usdtAdded=0;
   for(int j=0;j<brokerTotal && g_symbolCount<MAX_SYMBOLS;j++)
   {
      string brokerSymbol=SymbolName(j,false);
      string upperSymbol=brokerSymbol;
      StringToUpper(upperSymbol);
      if(StringFind(upperSymbol,"USDT")<0) continue;
      int before=g_symbolCount;
      AddSymbol(brokerSymbol);
      if(g_symbolCount>before) usdtAdded++;
   }
   Print("SYMBOL_UNIVERSE_ADDITIVE | marketWatchOrConfigured+brokerUSDT=true brokerCatalog=",brokerTotal,
         " usdtAdded=",usdtAdded," total=",g_symbolCount,
         " capacity=",MAX_SYMBOLS," note=NO_NON_USDT_SYMBOLS_REMOVED");
}

void AddSymbol(string s)
{
   if(StringLen(s)<=0 || g_symbolCount>=MAX_SYMBOLS) return;
   string k=AssetIdentityKey(s);
   if(StringLen(k)<3) return;
   // Suffix aliases share one identity; exact broker symbols remain available for execution.
   string identity=s;
   StringToUpper(identity);
   for(int i=0;i<g_symbolCount;i++)
   {
      string existing=g_symbols[i];
      StringToUpper(existing);
      if(existing==identity) return;
   }
   g_symbols[g_symbolCount]=s;
   g_keys[g_symbolCount]=k;
   g_symbolCount++;
}

//+------------------------------------------------------------------+
//| Report possible aliases without removing or merging instruments  |
//+------------------------------------------------------------------+
void LogPotentialAliasGroups()
{
   int groups=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      bool first=true;
      for(int p=0;p<i;p++)
         if(g_keys[p]==g_keys[i]) { first=false; break; }
      if(!first) continue;

      int members=0;
      string peers="";
      for(int j=i;j<g_symbolCount;j++)
      {
         if(g_keys[j]!=g_keys[i]) continue;
         members++;
         if(StringLen(peers)>0) peers+=";";
         peers+=g_symbols[j];
      }
      if(members>1)
      {
         groups++;
         Print("POTENTIAL_ASSET_ALIAS_GROUP | assetKey=",g_keys[i],
               " count=",members," symbols=",peers,
               " action=REPORT_ONLY_NO_SYMBOL_REMOVED_OR_MERGED");
      }
   }
   Print("POTENTIAL_ALIAS_SUMMARY | groups=",groups,
         " symbols=",g_symbolCount,
         " identity=SUFFIX_NORMALIZED_BASE_CONTRACT_KEY");
}

//+------------------------------------------------------------------+
//| Per-symbol scan diagnostics: emit only when a symbol changes state|
//+------------------------------------------------------------------+
void LogBarScanSymbolState(int index,string sym,string state,int bars,datetime barTime)
{
   if(!InpLogBarScanDiagnostics) return;
   if(index<0 || index>=MAX_SYMBOLS) return;
   if(g_lastBarDiagState[index]==state) return;
   g_lastBarDiagState[index]=state;
   datetime tickTime=(datetime)MarketInfo(sym,MODE_TIME);
   int barAge=(barTime>0?(int)MathMax(0,TimeCurrent()-barTime):-1);
   int quoteAge=(tickTime>0?(int)MathMax(0,TimeCurrent()-tickTime):-1);
   Print("BAR_SCAN_SYMBOL | symbol=",sym,
         " tf=",(int)InpSignalTF,
         " state=",state,
         " bars=",bars,
         " minBars=",InpMinBars,
         " currentBarTime=",(long)barTime,
         " barAgeSec=",barAge,
         " quoteAgeSec=",quoteAge);
}


int ScanSymbolIndex(string sym)
{
   for(int i=0;i<g_symbolCount;i++)
      if(g_symbols[i]==sym) return(i);
   return(-1);
}

void FinalizeScanBar(int index,datetime barTime,string reason)
{
   if(index<0 || index>=g_symbolCount || barTime<=0) return;
   g_lastBar[index]=barTime;
   g_pendingBar[index]=0;
   g_barRetryCount[index]=0;
   if(InpLogBarScanDiagnostics)
      Print("BAR_SCAN_FINALIZED | symbol=",g_symbols[index],
            " barTime=",(long)barTime,
            " reason=",reason,
            " action=NO_MORE_RETRY_THIS_BAR");
}

bool IsTransientPrefilterReject(string why)
{
   if(StringFind(why,"STALE_QUOTE")==0) return(true);
   if(StringFind(why,"QUOTE_TIMESTAMP")==0) return(true);
   if(why=="TRADE_PERMISSION_BLOCKED") return(true);
   if(why=="INVALID_QUOTE" || why=="INSUFFICIENT_HISTORY" || why=="HISTORY_DATA_NOT_READY") return(true);
   return(false);
}

bool IsTransientSignalReject(string why)
{
   return(why=="INDICATOR_DATA_INVALID" ||
          why=="EMA_UNAVAILABLE" ||
          why=="HTF_DATA_UNAVAILABLE" ||
          why=="HISTORY_DATA_NOT_READY");
}

bool IsTransientExecutionReject()
{
   if(g_lastExecutionRejectCategory=="TRANSIENT_DATA" ||
      g_lastExecutionRejectCategory=="TRADE_PERMISSION") return(true);
   if(g_lastExecutionRejectCategory!="BROKER_ERROR") return(false);
   int e=g_lastExecutionErrorCode;
   // Error 128 (trade timeout) is excluded because broker outcome may be ambiguous.
   return(e==129 || e==135 || e==136 || e==137 ||
          e==138 || e==146 || e==4109);
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

   CheckDailyLossDay();
   UpdateGlobalLossPolicy();
   ManageExits();
   SyncClosedTradeStats();
   UpdateDailyEntryProtection();

   bool dailyStrict=false, dailyShortenHold=false;
   datetime dailyAdaptiveStart=0;
   int dailySample=0, dailyWins=0, dailyLosses=0;
   double dailyNet=0.0, avgWinSeconds=0.0, avgLossSeconds=0.0;
   GetDailyAdaptiveState(dailyStrict,dailyShortenHold,dailyAdaptiveStart,
                         dailySample,dailyWins,dailyLosses,dailyNet,
                         avgWinSeconds,avgLossSeconds);
   // Loss performance never suspends the full trading day; it scales new-entry risk.
   int maxPos=MaxPositions();
   int nc=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      string sym=g_symbols[i];
      // Isolate stale feeds before touching bar retry state.
      // This prevents RETRY_PENDING/RETRY_READY churn while quotes are frozen.
      if(!SymbolQuoteFresh(i,sym))
      {
         int staleBars=iBars(sym,InpSignalTF);
         datetime staleBar=iTime(sym,InpSignalTF,0);
         LogBarScanSymbolState(i,sym,"STALE_QUOTE_WAIT",staleBars,staleBar);
         continue;
      }
      int bars=iBars(sym,InpSignalTF);
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0)
      {
         g_cycleHistoryUnavailable++;
         LogBarScanSymbolState(i,sym,"HISTORY_UNAVAILABLE",bars,bt);
         continue;
      }
      // If history was unavailable during OnInit, establish a baseline now.
      // Do not treat the first subsequently loaded historical bar as a new bar.
      if(!g_barBaselineSet[i])
      {
         g_lastBar[i]=bt;
         g_barBaselineSet[i]=true;
         LogBarScanSymbolState(i,sym,"INITIAL_BASELINE",bars,bt);
         continue;
      }
      if(bt==g_lastBar[i])
      {
         g_cycleNoNewBar++;
         LogBarScanSymbolState(i,sym,"NO_NEW_BAR",bars,bt);
         continue;
      }

      bool retrying=(g_pendingBar[i]==bt);
      if(!retrying)
      {
         if(g_pendingBar[i]>0 && InpLogBarScanDiagnostics)
            Print("BAR_RETRY_EXPIRED | symbol=",sym,
                  " previousPendingBar=",(long)g_pendingBar[i],
                  " newerBar=",(long)bt,
                  " reason=NEW_BAR_SUPERSEDED");
         g_pendingBar[i]=bt;
         g_barRetryCount[i]=0;
         g_cycleNewBars++;
         LogBarScanSymbolState(i,sym,"NEW_BAR_PENDING",bars,bt);
      }
      else
      {
         if(g_barRetryCount[i]<2147483647) g_barRetryCount[i]++;
         g_cycleBarRetries++;
         LogBarScanSymbolState(i,sym,"RETRY_PENDING",bars,bt);
      }
      g_lastScanSymbol=sym;

      if(bars<InpMinBars)
      {
         g_cycleInsufficientHistory++;
         LogBarScanSymbolState(i,sym,"NEW_BAR_INSUFFICIENT_HISTORY",bars,bt);
         continue;
      }

      // Fail closed for NEW entries when signal history is not demonstrably ready.
      // ManageExits() has already run and remains independent of this per-symbol guard.
      string seriesGuardReason="";
      if(!EntrySeriesReady(sym,seriesGuardReason))
      {
         LogBarScanSymbolState(i,sym,"ENTRY_SERIES_"+seriesGuardReason,bars,bt);
         continue; // Keep this bar pending so the symbol is retried after synchronization.
      }
      LogBarScanSymbolState(i,sym,(retrying?"RETRY_READY":"NEW_BAR_READY"),bars,bt);

      // Candidate capacity is independent of the live-position limit.
      // Collect signals across the whole universe; execution below stops only
      // after the configured number of positions have actually been accepted.
      if(nc>=MAX_SYMBOLS)
      {
         Reject(sym,"CANDIDATE_BUFFER_FULL");
         g_cycleCapacityRejects++;
         FinalizeScanBar(i,bt,"CANDIDATE_BUFFER_FULL");
         continue;
      }
      int cmd; double score; string why;
      if(!Prefilter(sym,why))
      {
         Reject(sym,why); g_cyclePrefilterRejects++;
         if(!IsTransientPrefilterReject(why))
            FinalizeScanBar(i,bt,"PREFILTER_"+why);
         else if(g_barRetryCount[i]==0 && InpLogBarScanDiagnostics)
            Print("BAR_RETRY_WAIT | symbol=",sym," reason=",why," stage=PREFILTER");
         continue;
      }
      g_cyclePrefilterOK++;
      g_cycleIndicatorRuns++;
      if(!Analyze(sym,cmd,score,why))
      {
         Reject(sym,why); g_cycleSignalRejects++;
         if(!IsTransientSignalReject(why))
            FinalizeScanBar(i,bt,"SIGNAL_"+why);
         else if(g_barRetryCount[i]==0 && InpLogBarScanDiagnostics)
            Print("BAR_RETRY_WAIT | symbol=",sym," reason=",why," stage=SIGNAL_DATA");
         continue;
      }
      // Analyze first, then apply cooldown to the same normalized asset and side.
      if(DirectionalLossCooldownActive(sym,cmd))
      {
         Reject(sym,"DIRECTIONAL_LOSS_COOLDOWN");
         g_cycleSignalRejects++;
         FinalizeScanBar(i,bt,"DIRECTIONAL_LOSS_COOLDOWN");
         continue;
      }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  g_cycleSignalRejects++; FinalizeScanBar(i,bt,"BUY_DISABLED"); continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); g_cycleSignalRejects++; FinalizeScanBar(i,bt,"SELL_DISABLED"); continue; }
      int assetSample=0,assetWins=0,assetLosses=0,assetStreak=0;
      double assetNet=0.0; bool assetAdverse=false;
      GetRecentLossPolicy(sym,assetSample,assetWins,assetLosses,assetNet,assetStreak,assetAdverse);
      int directionSample=0,directionWins=0,directionLosses=0,directionStreak=0;
      double directionNet=0.0; bool directionAdverse=false;
      GetRecentLossPolicy(sym,directionSample,directionWins,directionLosses,directionNet,directionStreak,directionAdverse,cmd);
      int globalLevel=LossPolicyLevel(g_globalLossAdverse,g_globalLossStreak);
      int assetLevel=LossPolicyLevel(assetAdverse,assetStreak);
      int directionLevel=LossPolicyLevel(directionAdverse,directionStreak);
      double requiredScore=InpMinEntryScore + MathMax(0.0,InpSelectivityScoreStep)*g_analyticalSelectivityLevel;
      if(InpEnableDailyAdaptiveQuality && dailyStrict)
         requiredScore+=MathMax(0.0,InpDailyAdaptiveExtraScore);
      if(InpEnableRollingLossPolicy)
         requiredScore+=MathMax(0.0,InpLossPolicyExtraScore)*(globalLevel+assetLevel+directionLevel);
      if(g_analyticalSelectivityLevel>=2 && !SelectivityHTFAligned(sym,cmd,g_analyticalSelectivityLevel))
      {
         string rejectReason="PROGRESSIVE_SELECTIVITY_HTF_CONFIRMATION";
         LogRejectedSelectivityCandidate(sym,cmd,score,requiredScore,g_analyticalSelectivityLevel,rejectReason);
         Reject(sym,rejectReason); g_cycleSignalRejects++; FinalizeScanBar(i,bt,rejectReason); continue;
      }
      if(score<requiredScore)
      {
         string rejectReason=(g_analyticalSelectivityLevel>0?"PROGRESSIVE_SELECTIVITY_SCORE":"ENTRY_SCORE_BELOW_MINIMUM");
         LogRejectedSelectivityCandidate(sym,cmd,score,requiredScore,g_analyticalSelectivityLevel,rejectReason);
         Reject(sym,rejectReason); g_cycleSignalRejects++;
         FinalizeScanBar(i,bt,rejectReason);
         continue;
      }
      double qBid=MarketInfo(sym,MODE_BID),qAsk=MarketInfo(sym,MODE_ASK);
      double qPoint=MarketInfo(sym,MODE_POINT);
      double qAtr=iATR(sym,InpSignalTF,InpATRPeriod,1);
      double qSpreadPct=1000.0;
      if(qBid>0.0 && qAsk>=qBid && qPoint>0.0 && qAtr>0.0)
      {
         double qSpread=qAsk-qBid;
         double qBrokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*qPoint;
         double qStop=MathMax(qAtr*InpStopATR,qSpread+qBrokerMin);
         if(qStop>0.0) qSpreadPct=100.0*qSpread/qStop;
      }
      // Quality affects ordering only. Hard spread, risk and permission checks remain in OpenTrade().
      double qPenalty=MathMin(10.0,MathMax(0.0,qSpreadPct-InpMaxSpreadPctOfStop)*0.20);
      double qSessionAdjustment=SessionPerformanceAdjustment(sym);
      double qPriority=score-qPenalty+qSessionAdjustment;
      g_candSym[nc]=sym; g_candCmd[nc]=cmd; g_candScore[nc]=score;
      g_candSpreadPct[nc]=qSpreadPct; g_candPriority[nc]=qPriority; nc++;
      int sessionIdx=SessionSymbolIndex(sym);
      if(sessionIdx>=0) g_sessionCandidates[sessionIdx]++;
      g_cycleSignalCandidates++;
      if(cmd==OP_BUY) g_cycleBuySignals++; else g_cycleSellSignals++;
   }

   // Daily P/L warning only. It never blocks or limits new entries or trade count.
   double dailyLimit=InpReferenceCapitalUSD*InpDailyLossPct/100.0;
   double dayNet=TodayNet();
   bool dailyLossExceeded=(dayNet<=-dailyLimit);
   uint dailyWarningNowTick=GetTickCount();
   if(dailyLossExceeded &&
      (g_lastDailyLossWarningTick==0 || dailyWarningNowTick-g_lastDailyLossWarningTick>=60000))
   {
      g_lastDailyLossWarningTick=dailyWarningNowTick;
      Print("DAILY_LOSS_WARNING | dayNet=",DoubleToString(dayNet,2),
            " limit=-",DoubleToString(dailyLimit,2),
            " candidates=",nc,
            " selectivityLevel=",g_analyticalSelectivityLevel,
            " riskFactor=",DoubleToString(SelectivityRiskMultiplier(g_analyticalSelectivityLevel),2),
            " action=",(InpEnableDailyEntryProtection?
               "PROGRESSIVE_SELECTIVITY_ESCALATION_NO_HARD_ENTRY_LOCK":"WARNING_ONLY_NO_ENTRY_LOCK"));
   }

   if(nc>0)
   {
      // sort candidates by score, best first
      for(int a=0;a<nc-1;a++)
         for(int b=a+1;b<nc;b++)
            if(g_candPriority[b]>g_candPriority[a])
            {
               string ts=g_candSym[a]; g_candSym[a]=g_candSym[b]; g_candSym[b]=ts;
               int tc=g_candCmd[a];    g_candCmd[a]=g_candCmd[b];  g_candCmd[b]=tc;
               double td=g_candScore[a]; g_candScore[a]=g_candScore[b]; g_candScore[b]=td;
               td=g_candSpreadPct[a]; g_candSpreadPct[a]=g_candSpreadPct[b]; g_candSpreadPct[b]=td;
               td=g_candPriority[a]; g_candPriority[a]=g_candPriority[b]; g_candPriority[b]=td;
            }

      if(DIAGNOSTIC_ONLY_BUILD)
      {
         for(int dryC=0;dryC<nc;dryC++)
         {
            int dryIdx=ScanSymbolIndex(g_candSym[dryC]);
            if(dryIdx>=0) FinalizeScanBar(dryIdx,g_pendingBar[dryIdx],"DIAGNOSTIC_ONLY");
         }
         Print("DIAGNOSTIC_ONLY_BLOCK | candidates=",nc,
               " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
               " action=NO_ORDER_SEND exits_for_existing_positions=MANAGED");
      }
      else
      {
         int attempted=0,accepted=0,executionRejected=0;
         int candidateBuy=0,candidateSell=0,attemptedBuy=0,attemptedSell=0;
         int rejectSpread=0,rejectRisk=0,rejectPermission=0,rejectBroker=0;
         int rejectStops=0,rejectOther=0,dryRunCount=0;
         int brokerErr133=0,brokerErr4109=0,brokerErr146=0,brokerErrOther=0;
         for(int c=0;c<nc;c++)
         {
            if(g_candCmd[c]==OP_BUY) candidateBuy++; else if(g_candCmd[c]==OP_SELL) candidateSell++;
            // The hard cap applies to accepted/open trades, never to candidates.
            string candidateAssetKey=AssetIdentityKey(g_candSym[c]);
             if(HasPositionForKey(candidateAssetKey))
             {
                Print("ASSET_ALIAS_COLLISION | symbol=",g_candSym[c],
                      " assetKey=",candidateAssetKey,
                      " side=",(g_candCmd[c]==OP_BUY?"BUY":"SELL"),
                      " reason=POSITION_ALREADY_OPEN_ON_ALIAS action=SKIP");
                int aliasIdx=ScanSymbolIndex(g_candSym[c]);
                if(aliasIdx>=0) FinalizeScanBar(aliasIdx,g_pendingBar[aliasIdx],"ASSET_ALIAS_COLLISION");
                continue;
             }
             if(CountOpenPositions()>=maxPos) break;
            attempted++;
            if(g_candCmd[c]==OP_BUY) attemptedBuy++; else if(g_candCmd[c]==OP_SELL) attemptedSell++;
            double qPenalty=g_candScore[c]-g_candPriority[c];
            Print("EXECUTION_PRIORITY | symbol=",g_candSym[c],
                  " side=",(g_candCmd[c]==OP_BUY?"BUY":"SELL"),
                  " signalScore=",DoubleToString(g_candScore[c],1),
                  " spreadPctOfStop=",DoubleToString(g_candSpreadPct[c],1),
                  " qualityPenalty=",DoubleToString(qPenalty,1),
                  " sessionNetAdjustment=",DoubleToString(SessionPerformanceAdjustment(g_candSym[c]),1),
                  " priorityScore=",DoubleToString(g_candPriority[c],1),
                  " rank=",attempted,"/",nc);
            int statIdx=SessionSymbolIndex(g_candSym[c]);
            if(statIdx>=0) g_sessionAttempts[statIdx]++;
            if(OpenTrade(g_candSym[c],g_candCmd[c],g_candScore[c]))
            {
               accepted++;
               if(statIdx>=0) g_sessionAccepted[statIdx]++;
               int acceptedScanIdx=ScanSymbolIndex(g_candSym[c]);
               if(acceptedScanIdx>=0) FinalizeScanBar(acceptedScanIdx,g_pendingBar[acceptedScanIdx],"ORDER_ACCEPTED");
            }
            else
            {
               executionRejected++;
               if(statIdx>=0) g_sessionRejected[statIdx]++;
               if(g_lastExecutionRejectCategory=="SPREAD") rejectSpread++;
               else if(g_lastExecutionRejectCategory=="RISK") rejectRisk++;
               else if(g_lastExecutionRejectCategory=="TRADE_PERMISSION") rejectPermission++;
               else if(g_lastExecutionRejectCategory=="BROKER_ERROR")
               {
                  rejectBroker++;
                  if(g_lastExecutionErrorCode==133) brokerErr133++;
                  else if(g_lastExecutionErrorCode==4109) brokerErr4109++;
                  else if(g_lastExecutionErrorCode==146) brokerErr146++;
                  else brokerErrOther++;
               }
               else if(g_lastExecutionRejectCategory=="STOP_PREFLIGHT") rejectStops++;
               else if(g_lastExecutionRejectCategory=="DRY_RUN") dryRunCount++;
               else rejectOther++;

               int rejectedScanIdx=ScanSymbolIndex(g_candSym[c]);
               if(rejectedScanIdx>=0)
               {
                  if(!IsTransientExecutionReject())
                     FinalizeScanBar(rejectedScanIdx,g_pendingBar[rejectedScanIdx],"EXECUTION_"+g_lastExecutionRejectCategory);
                  else if(g_barRetryCount[rejectedScanIdx]==0 && InpLogBarScanDiagnostics)
                     Print("BAR_RETRY_WAIT | symbol=",g_candSym[c],
                           " category=",g_lastExecutionRejectCategory,
                           " error=",g_lastExecutionErrorCode,
                           " stage=ORDER_EXECUTION");
               }
            }
         }
         for(int pendingC=attempted;pendingC<nc;pendingC++)
         {
            int pendingIdx=ScanSymbolIndex(g_candSym[pendingC]);
            if(pendingIdx>=0) FinalizeScanBar(pendingIdx,g_pendingBar[pendingIdx],"PORTFOLIO_CAPACITY_REACHED");
         }
         int capacityNotAttempted=MathMax(0,nc-attempted);
         Print("CANDIDATE_EXECUTION_SUMMARY | collected=",nc,
               " candidateBuy=",candidateBuy," candidateSell=",candidateSell,
               " attempted=",attempted," attemptedBuy=",attemptedBuy," attemptedSell=",attemptedSell,
               " accepted=",accepted," executionRejected=",executionRejected,
               " rejectSpread=",rejectSpread," rejectRisk=",rejectRisk,
               " rejectTradePermission=",rejectPermission," rejectBrokerError=",rejectBroker,
               " brokerErr133=",brokerErr133," brokerErr4109=",brokerErr4109,
               " brokerErr146=",brokerErr146," brokerErrOther=",brokerErrOther,
               " rejectStopPreflight=",rejectStops," rejectOther=",rejectOther," dryRun=",dryRunCount,
               " capacityNotAttempted=",capacityNotAttempted,
               " ranking=SIGNAL_MINUS_SPREAD_PLUS_SESSION_NET_ADJUSTMENT",
               " openAfter=",CountOpenPositions(),"/",maxPos,
               " remainingCandidates=",capacityNotAttempted);
      }
   }

   UpdateScanDashboard(nc);

   datetime now=TimeCurrent();
   uint nowTick=GetTickCount();
   if(g_lastHeartbeatTick==0 || nowTick-g_lastHeartbeatTick>=300000)
   {
      g_lastHeartbeatTick=nowTick;
      g_lastHeartbeat=now;
      long serverLocalOffset=(long)TimeLocal()-(long)TimeCurrent();
      Print("SCAN_CYCLE_SUMMARY | windowSec=300 assets=",g_symbolCount,
            " newBarsScanned=",g_cycleNewBars,
            " barRetries=",g_cycleBarRetries,
            " indicatorsEvaluated=",g_cycleIndicatorRuns,
            " candidates=",g_cycleSignalCandidates,            " prefilterRejected=",g_cyclePrefilterRejects,
            " signalRejected=",g_cycleSignalRejects,
            " historyUnavailable=",g_cycleHistoryUnavailable,
            " insufficientHistory=",g_cycleInsufficientHistory,
            " prefilterOK=",g_cyclePrefilterOK,
            " noNewBar=",g_cycleNoNewBar,
            " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
            " dailyLossExceeded=",(dailyLossExceeded?"true":"false"),
             " dailyPolicy=WARNING_ONLY",
            " dayNet=",DoubleToString(dayNet,2),
            " dailyLossLimit=-",DoubleToString(dailyLimit,2));
      Print("CLOCK_DIAGNOSTIC | serverTime=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            " localTime=",TimeToString(TimeLocal(),TIME_DATE|TIME_SECONDS),
            " gmtTime=",TimeToString(TimeGMT(),TIME_DATE|TIME_SECONDS),
            " serverLocalOffsetSec=",serverLocalOffset,
            " note=LOCAL_ESTIMATE_USES_CURRENT_OFFSET_NOT_HISTORICAL_DST");
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(dayNet,2),
            " dailyLossLimit=-",DoubleToString(dailyLimit,2),
            " diagnosticOnly=",(DIAGNOSTIC_ONLY_BUILD?"true":"false"),
            " assetsInUniverse=",g_symbolCount,
            " newBarsScanned=",g_cycleNewBars,
            " barRetries=",g_cycleBarRetries,
            " noNewBar=",g_cycleNoNewBar,
            " historyUnavailable=",g_cycleHistoryUnavailable,
            " insufficientHistory=",g_cycleInsufficientHistory,
            " prefilterOK=",g_cyclePrefilterOK,
            " indicatorsEvaluated=",g_cycleIndicatorRuns," candidates=",g_cycleSignalCandidates,
            " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
            " prefilterRejected=",g_cyclePrefilterRejects," signalRejected=",g_cycleSignalRejects," capacitySkipped=",g_cycleCapacityRejects);
      for(int md=0;md<g_symbolCount;md++) LogMarketDataState(md,g_symbols[md]);
      int quoteFresh=0,quoteStale=0,quoteMissing=0,quoteNeverRefreshed=0,quoteOldestAge=0;
      CountQuoteStates(quoteFresh,quoteStale,quoteMissing,quoteNeverRefreshed,quoteOldestAge);
      string feedStatus="NO_FRESH_QUOTES";
      if(quoteFresh==g_symbolCount && quoteStale==0 && quoteMissing==0)
         feedStatus="ALL_QUOTES_FRESH";
      else if(quoteFresh>0)
         feedStatus="PARTIAL_QUOTES_FRESH";
      else if(quoteMissing==g_symbolCount)
         feedStatus="NO_QUOTES";
      LogSessionSymbolStats();
      Print("MARKET_DATA_DIAGNOSTICS | freshQuotes=",quoteFresh," staleQuotes=",quoteStale,
            " missingQuotes=",quoteMissing," neverRefreshedAfterInit=",quoteNeverRefreshed," oldestObservedAgeSec=",quoteOldestAge,
            " feedStatus=",feedStatus,
            " universe=",g_symbolCount,
            " note=QUOTE_FRESHNESS_DOES_NOT_GUARANTEE_SYMBOL_TRADE_PERMISSION");
      // Reset interval counters after each 5-minute heartbeat.
      g_cycleNewBars=0; g_cycleBarRetries=0; g_cycleNoNewBar=0; g_cycleHistoryUnavailable=0; g_cycleInsufficientHistory=0;
      g_cyclePrefilterOK=0; g_cycleIndicatorRuns=0; g_cycleSignalCandidates=0;
      g_cycleBuySignals=0; g_cycleSellSignals=0; g_cyclePrefilterRejects=0; g_cycleSignalRejects=0; g_cycleCapacityRejects=0;
   }
}

void UpdateScanDashboard(int candidates)
{
   if(!InpShowScanDashboard) { Comment(""); return; }
   string panel="BITEY SCALPER v"+EA_VERSION+" | SCAN DASHBOARD\n";
   panel+="Activos en universo: "+IntegerToString(g_symbolCount)+" / "+IntegerToString(MAX_SYMBOLS)+"\n";
   panel+="Barras nuevas: "+IntegerToString(g_cycleNewBars)+" | Reintentos: "+IntegerToString(g_cycleBarRetries)+" | Prefiltro OK: "+IntegerToString(g_cyclePrefilterOK)+"\n";
   panel+="Indicadores evaluados: "+IntegerToString(g_cycleIndicatorRuns)+" | Candidatos: "+IntegerToString(candidates)+" (BUY "+IntegerToString(g_cycleBuySignals)+" / SELL "+IntegerToString(g_cycleSellSignals)+")\n";
   panel+="Descartes prefiltro: "+IntegerToString(g_cyclePrefilterRejects)+" | Sin señal: "+IntegerToString(g_cycleSignalRejects)+" | Saltos por capacidad: "+IntegerToString(g_cycleCapacityRejects)+"\n";
   panel+="Modo diagnóstico: "+(DIAGNOSTIC_ONLY_BUILD?"ON - NO NEW ORDERS":"OFF")+"\n";
   panel+="Posiciones: "+IntegerToString(CountOpenPositions())+"/"+IntegerToString(MaxPositions())+" | P/L día+flotante: "+DoubleToString(TodayNet(),2)+"\n";
   panel+="Último activo: "+g_lastScanSymbol+"\n";
   panel+="INDICADORES: "+g_lastIndicatorSummary;
   Comment(panel);
}

void Reject(string sym,string reason)
{
   if(InpLogRejects) Print("SYMBOL_REJECT | symbol=",sym," | reason=",reason);
}

//+------------------------------------------------------------------+
//| Cheap checks that do not need indicators                          |
//+------------------------------------------------------------------+
// Quote age is anchored to server time, then advanced with a monotonic clock.
// Recent cached quotes can be used briefly, but never remain fresh indefinitely.
int QuoteAgeSeconds(string sym)
{
   int idx=-1;
   for(int i=0;i<g_symbolCount;i++) if(g_symbols[i]==sym) { idx=i; break; }
   if(idx<0) return(2147483647);
   datetime qt=(datetime)MarketInfo(sym,MODE_TIME);
   if(qt<=0) return(2147483647);
   if(qt!=g_lastQuoteStamp[idx])
   {
      g_lastQuoteStamp[idx]=qt;
      g_quoteBaseAgeSec[idx]=0;
      g_lastQuoteChangeTick[idx]=GetTickCount();
      return(0);
   }
   if(g_lastQuoteChangeTick[idx]==0 || g_quoteBaseAgeSec[idx]>=2147483647)
      return(2147483647);
   uint elapsed=(GetTickCount()-g_lastQuoteChangeTick[idx])/1000;
   if((long)g_quoteBaseAgeSec[idx]+(long)elapsed>=2147483647) return(2147483647);
   return(g_quoteBaseAgeSec[idx]+(int)elapsed);
}


 
// Per-symbol stale-feed isolation with exponential polling backoff.
// Stale quotes never finalize/advance the bar scanner; the symbol is
// reconsidered automatically when MODE_TIME advances and the quote is fresh.
bool SymbolQuoteFresh(int index,string sym)
{
   if(index<0 || index>=g_symbolCount) return(false);
   uint nowTick=GetTickCount();
   if(g_quoteStale[index] && g_quoteNextCheckTick[index]!=0 &&
      (int)(nowTick-g_quoteNextCheckTick[index])<0)
      return(false);

   int age=QuoteAgeSeconds(sym);
   if(age>=0 && age<=InpMaxQuoteAgeSec)
   {
      if(g_quoteStale[index])
         Print("QUOTE_FRESHNESS_GATE | symbol=",sym,
               " state=RECOVERED quoteAgeSec=",age,
               " action=RESUME_SYMBOL_SCAN_AND_EXIT_MANAGEMENT");
      g_quoteStale[index]=false;
      g_quoteNextCheckTick[index]=0;
      g_quoteRetryDelaySec[index]=0;
      return(true);
   }

   int maxDelay=MathMax(1,MathMax(InpStaleQuoteRetryInitialSec,InpStaleQuoteRetryMaxSec));
   int initialDelay=MathMax(1,InpStaleQuoteRetryInitialSec);
   if(!g_quoteStale[index])
   {
      g_quoteStale[index]=true;
      g_quoteRetryDelaySec[index]=initialDelay;
      Print("QUOTE_FRESHNESS_GATE | symbol=",sym,
            " state=STALE quoteAgeSec=",(age>=2147483647?-1:age),
            " maxAgeSec=",InpMaxQuoteAgeSec,
            " action=SKIP_ENTRY_AND_EA_EXIT_MODIFICATIONS_BROKER_SL_TP_REMAIN_ACTIVE");
   }
   else
      g_quoteRetryDelaySec[index]=MathMin(maxDelay,MathMax(initialDelay,g_quoteRetryDelaySec[index]*2));

   g_quoteNextCheckTick[index]=nowTick+(uint)(g_quoteRetryDelaySec[index]*1000);
   return(false);
}

bool QuoteFresh(string sym)
{
   int age=QuoteAgeSeconds(sym);
   return(age>=0 && age<=InpMaxQuoteAgeSec);
}

void CountQuoteStates(int &fresh,int &stale,int &missing,int &neverRefreshed,int &oldestAge)
{
   fresh=0; stale=0; missing=0; neverRefreshed=0; oldestAge=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      datetime qt=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      if(qt<=0) { missing++; continue; }
      int age=QuoteAgeSeconds(g_symbols[i]);
      if(age<=InpMaxQuoteAgeSec) fresh++; else stale++;
      if(age>=2147483647) { neverRefreshed++; oldestAge=2147483647; }
      else if(oldestAge<2147483647 && age>oldestAge) oldestAge=age;
   }
}

//+------------------------------------------------------------------+
//| v1.5.8 per-symbol entry-series readiness guard                    |
//+------------------------------------------------------------------+
bool EntrySeriesReady(string sym,string &reason)
{
   reason="";
   long signalSyncValue=0;
   ResetLastError();
   bool signalSyncKnown=SeriesInfoInteger(sym,InpSignalTF,SERIES_SYNCHRONIZED,signalSyncValue);
   int signalError=GetLastError();
   if(!signalSyncKnown)
   {
      reason="SYNC_UNKNOWN";
      Print("ENTRY_SERIES_GUARD | symbol=",sym,
         " timeframe=",(int)InpSignalTF,
         " state=SYNC_UNKNOWN queryError=",signalError,
         " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
      return(false);
   }
   if(signalSyncValue==0)
   {
      reason="SERIES_NOT_SYNCHRONIZED";
      Print("ENTRY_SERIES_GUARD | symbol=",sym,
         " timeframe=",(int)InpSignalTF,
         " state=SERIES_NOT_SYNCHRONIZED",
         " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
      return(false);
   }

   int signalBars=iBars(sym,InpSignalTF);
   datetime signalCurrent=iTime(sym,InpSignalTF,0);
   datetime signalClosed=iTime(sym,InpSignalTF,1);
   if(signalBars<InpMinBars || signalCurrent<=0 || signalClosed<=0)
   {
      reason="HISTORY_INSUFFICIENT";
      Print("ENTRY_SERIES_GUARD | symbol=",sym,
         " timeframe=",(int)InpSignalTF,
         " state=HISTORY_INSUFFICIENT bars=",signalBars,
         " minBars=",InpMinBars,
         " currentBarTime=",(long)signalCurrent,
         " previousClosedBarTime=",(long)signalClosed,
         " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
      return(false);
   }

   int quoteAge=QuoteAgeSeconds(sym);
   int signalPeriodSec=PeriodSeconds(InpSignalTF);
   int signalBarAge=(int)MathMax(0,TimeCurrent()-signalCurrent);
   if(quoteAge<=InpMaxQuoteAgeSec && signalPeriodSec>0 &&
      signalBarAge>(2*signalPeriodSec))
   {
      reason="STALE_BAR";
      Print("ENTRY_SERIES_GUARD | symbol=",sym,
         " timeframe=",(int)InpSignalTF,
         " state=STALE_BAR barAgeSec=",signalBarAge,
         " maxExpectedAgeSec=",2*signalPeriodSec,
         " quoteAgeSec=",quoteAge,
         " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
      return(false);
   }

   // H1 is mandatory whenever the normal HTF filter or elevated selectivity consumes it.
   bool requireHigher=(InpUseHTFFilter || g_analyticalSelectivityLevel>=2);
   if(requireHigher)
   {
      long higherSyncValue=0;
      ResetLastError();
      bool higherSyncKnown=SeriesInfoInteger(sym,InpHTF,SERIES_SYNCHRONIZED,higherSyncValue);
      int higherError=GetLastError();
      if(!higherSyncKnown)
      {
         reason="SYNC_UNKNOWN";
         Print("ENTRY_SERIES_GUARD | symbol=",sym,
            " timeframe=",(int)InpHTF,
            " state=SYNC_UNKNOWN queryError=",higherError,
            " scope=HIGHER_TIMEFRAME action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
         return(false);
      }
      if(higherSyncValue==0)
      {
         reason="SERIES_NOT_SYNCHRONIZED";
         Print("ENTRY_SERIES_GUARD | symbol=",sym,
            " timeframe=",(int)InpHTF,
            " state=SERIES_NOT_SYNCHRONIZED scope=HIGHER_TIMEFRAME",
            " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
         return(false);
      }
      int higherBars=iBars(sym,InpHTF);
      datetime higherCurrent=iTime(sym,InpHTF,0);
      datetime higherClosed=iTime(sym,InpHTF,1);
      int requiredHigherBars=(g_analyticalSelectivityLevel>=3?202:52);
      if(higherBars<requiredHigherBars || higherCurrent<=0 || higherClosed<=0)
      {
         reason="HISTORY_INSUFFICIENT";
         Print("ENTRY_SERIES_GUARD | symbol=",sym,
            " timeframe=",(int)InpHTF,
            " state=HISTORY_INSUFFICIENT scope=HIGHER_TIMEFRAME",
            " bars=",higherBars," requiredBars=",requiredHigherBars,
            " currentBarTime=",(long)higherCurrent,
            " previousClosedBarTime=",(long)higherClosed,
            " action=SKIP_NEW_ENTRY_RETRY_PENDING_BAR");
         return(false);
      }
   }
   return(true);
}

//+------------------------------------------------------------------+
//| v1.4.5.2 diagnostics only: separate quote freshness from history    |
//| and never infer a closed session from an old tick.                |
//+------------------------------------------------------------------+
void LogMarketDataState(int index,string sym)
{
   if(index<0 || index>=g_symbolCount) return;

   datetime tickTime=(datetime)MarketInfo(sym,MODE_TIME);
   int quoteAge=QuoteAgeSeconds(sym);
   string quoteState="NO_SERVER_TICK";
   if(tickTime>0)
   {
      if(quoteAge>=2147483647) quoteState="NO_POST_INIT_TICK_CHANGE";
      else if(quoteAge<=InpMaxQuoteAgeSec) quoteState="FRESH";
      else quoteState="STALE";
   }

   int barsSignal=iBars(sym,InpSignalTF);
   datetime barSignal=iTime(sym,InpSignalTF,0);
   datetime prevSignal=iTime(sym,InpSignalTF,1);
   int barsHigher=iBars(sym,InpHTF);
   datetime barHigher=iTime(sym,InpHTF,0);
   datetime prevHigher=iTime(sym,InpHTF,1);

   string historyState="HISTORY_UNAVAILABLE";
   if(barsSignal>=InpMinBars && barSignal>0) historyState="HISTORY_READY";
   else if(barsSignal>0) historyState="HISTORY_INSUFFICIENT";

   long syncSignalValue=0, syncHigherValue=0, selectedValue=0;
   bool syncSignalKnown=SeriesInfoInteger(sym,InpSignalTF,SERIES_SYNCHRONIZED,syncSignalValue);
   bool syncHigherKnown=SeriesInfoInteger(sym,InpHTF,SERIES_SYNCHRONIZED,syncHigherValue);
   bool selectedKnown=SymbolInfoInteger(sym,SYMBOL_SELECT,selectedValue);
   bool signalSynchronized=(syncSignalKnown && syncSignalValue!=0);
   bool higherSynchronized=(syncHigherKnown && syncHigherValue!=0);
   bool symbolSelected=(selectedKnown && selectedValue!=0);
   bool tradeAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);

   double bid=MarketInfo(sym,MODE_BID);
   double ask=MarketInfo(sym,MODE_ASK);
   bool quotePricesValid=(bid>0.0 && ask>=bid);

   string sessionState=(IsCrypto(sym)?"SESSION_NOT_APPLICABLE":"SESSION_UNCONFIRMED");
   int dot=StringFind(sym,".");
   string suffix=(dot>=0?StringSubstr(sym,dot):"NONE");
   string combined=quoteState+"|"+historyState+
      "|M5="+IntegerToString(barsSignal)+":"+IntegerToString((int)barSignal)+
      "|M15="+IntegerToString(barsHigher)+":"+IntegerToString((int)barHigher)+
      "|SYNC="+(signalSynchronized?"1":"0")+":"+(higherSynchronized?"1":"0")+
      "|SELECT="+(symbolSelected?"1":"0")+
      "|TRADE="+(tradeAllowed?"1":"0")+
      "|PRICE="+(quotePricesValid?"1":"0")+
      "|TICK="+IntegerToString((int)tickTime);
   if(g_lastMarketDataDiagState[index]==combined) return;
   g_lastMarketDataDiagState[index]=combined;

   int signalBarAge=(barSignal>0?(int)MathMax(0,TimeCurrent()-barSignal):-1);
   int higherBarAge=(barHigher>0?(int)MathMax(0,TimeCurrent()-barHigher):-1);
   int quoteAgeForLog=(quoteAge>=2147483647?-1:quoteAge);

   Print("MARKET_DATA_SYMBOL | symbol=",sym,
         " quoteState=",quoteState,
         " quoteAgeSec=",quoteAgeForLog,
         " quoteAgeMeaning=",(quoteAge>=2147483647?"SERVER_TIME_UNAVAILABLE_OR_INVALID":"SERVER_ANCHORED_MONOTONIC_SECONDS"),
         " tickTime=",(long)tickTime,
         " historyState=",historyState,
         " signalTF=",(int)InpSignalTF,
         " signalBars=",barsSignal,
         " signalBarTime=",(long)barSignal,
         " signalPrevClosedBarTime=",(long)prevSignal,
         " signalBarAgeSec=",signalBarAge,
         " higherTF=",(int)InpHTF,
         " higherBars=",barsHigher,
         " higherBarTime=",(long)barHigher,
         " higherPrevClosedBarTime=",(long)prevHigher,
         " higherBarAgeSec=",higherBarAge,
         " signalSeriesSyncKnown=",(syncSignalKnown?"true":"false"),
         " signalSeriesSynchronized=",(signalSynchronized?"true":"false"),
         " higherSeriesSyncKnown=",(syncHigherKnown?"true":"false"),
         " higherSeriesSynchronized=",(higherSynchronized?"true":"false"),
         " symbolSelectKnown=",(selectedKnown?"true":"false"),
         " symbolSelected=",(symbolSelected?"true":"false"),
         " symbolTradeAllowed=",(tradeAllowed?"true":"false"),
         " bid=",DoubleToString(bid,(int)MarketInfo(sym,MODE_DIGITS)),
         " ask=",DoubleToString(ask,(int)MarketInfo(sym,MODE_DIGITS)),
         " quotePricesValid=",(quotePricesValid?"true":"false"),
         " contractSuffix=",suffix,
         " existingCryptoPrefixHeuristic=",(IsCrypto(sym)?"true":"false"),
         " sessionState=",sessionState,
         " maxQuoteAgeSec=",InpMaxQuoteAgeSec,
         " brokerSessionSchedule=NOT_CONFIRMED",
         " note=QUOTE_FRESHNESS_DOES_NOT_PROVE_NEW_BAR_OR_TRADE_PERMISSION");
}

bool SessionOK(string sym)
{
   if(!InpUseSessionFilter || IsCrypto(sym)) return(true);
   int h=TimeHour(TimeCurrent());
   if(InpSessionStartHour<InpSessionEndHour) return(h>=InpSessionStartHour && h<InpSessionEndHour);
   return(h>=InpSessionStartHour || h<InpSessionEndHour);
}

bool TradePermissionsReady(string sym,string stage)
{
   bool terminalAllowed=IsTradeAllowed();
   bool expertEnabled=IsExpertEnabled();
   // Use the supported MQL4 terminal/account-level permission check.
   bool symbolAllowed=(MarketInfo(sym,MODE_TRADEALLOWED)>0);
   bool contextBusy=IsTradeContextBusy();
   bool ready=(terminalAllowed && expertEnabled && symbolAllowed && !contextBusy);
   datetime now=TimeCurrent();
   bool logNow=(g_lastPermissionDiagnostic==0 || now-g_lastPermissionDiagnostic>=60);
   if(logNow)
   {
      string reason="TERMINAL_TRADING_NOT_ALLOWED";
      if(contextBusy) reason="TRADE_CONTEXT_BUSY";
      else if(!expertEnabled) reason="EXPERT_TRADING_DISABLED";
      else if(!symbolAllowed) reason="SYMBOL_TRADING_DISABLED";
      Print("TRADE_PERMISSION_DIAGNOSTICS | stage=",stage," symbol=",sym,
            " terminalIsTradeAllowed=",(terminalAllowed?"true":"false"),
            " expertEnabled=",(expertEnabled?"true":"false"),
            " terminalAccountPermission=",(terminalAllowed?"true":"false"),
            " symbolTradeAllowed=",(symbolAllowed?"true":"false"),
            " tradeContextBusy=",(contextBusy?"true":"false"),
            " result=",(ready?"READY":"BLOCKED"));
      if(!ready)
         Print("TRADE_PERMISSION_BLOCK | stage=",stage," symbol=",sym," reason=",reason);
      g_lastPermissionDiagnostic=now;
   }
   return(ready);
}

string TradeErrorDescription(int err)
{
   switch(err)
   {
      case 7:   return("NOT_ENOUGH_RIGHTS");
      case 128: return("TRADE_TIMEOUT");
      case 129: return("INVALID_PRICE");
      case 130: return("INVALID_STOPS");
      case 131: return("INVALID_TRADE_VOLUME");
      case 132: return("MARKET_CLOSED");
      case 133: return("TRADE_DISABLED");
      case 134: return("NOT_ENOUGH_MONEY");
      case 135: return("PRICE_CHANGED");
      case 136: return("OFF_QUOTES");
      case 137: return("BROKER_BUSY");
      case 138: return("REQUOTE");
      case 146: return("TRADE_CONTEXT_BUSY");
      case 148: return("TOO_MANY_ORDERS");
      case 4109:return("EXPERT_TRADING_NOT_ALLOWED");
   }
   return("UNCLASSIFIED_TRADE_ERROR");
}

bool Prefilter(string sym,string &why)
{
   why="";
   if(SessionSymbolBlocked(sym)) { why="SESSION_BLOCKED_AFTER_BROKER_133"; return(false); }
   // Strict freshness gate runs before permission/indicator work.
   // Cached quotes are accepted only while server-anchored monotonic age stays within the limit.
   int quoteAge=QuoteAgeSeconds(sym);
   if(quoteAge>InpMaxQuoteAgeSec)
   {
      why=(quoteAge>=2147483647?"QUOTE_TIMESTAMP_UNAVAILABLE_OR_INVALID":"STALE_QUOTE ageSec="+IntegerToString(quoteAge));
      return(false);
   }
   if(MarketInfo(sym,MODE_TRADEALLOWED)<=0)
   {
      BlockSessionSymbol(sym,"SYMBOL_TRADEALLOWED_FALSE",0);
      why="SYMBOL_TRADING_DISABLED";
      return(false);
   }
   if(!TradePermissionsReady(sym,"PREFILTER")) { why="TRADE_PERMISSION_BLOCKED"; return(false); }
   int signalBars=iBars(sym,InpSignalTF);
   if(signalBars<InpMinBars) { why="INSUFFICIENT_HISTORY"; return(false); }
   datetime signalClosed=iTime(sym,InpSignalTF,1);
   datetime signalPrior=iTime(sym,InpSignalTF,2);
   if(signalClosed<=0 || signalPrior<=0 ||
      iClose(sym,InpSignalTF,1)<=0.0 || iClose(sym,InpSignalTF,2)<=0.0)
   { why="HISTORY_DATA_NOT_READY"; return(false); }
   if(!SessionOK(sym)) { why="OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetIdentityKey(sym))) { why="POSITION_ALREADY_OPEN"; return(false); }
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
   int tf=InpSignalTF;
   double c1=iClose(sym,tf,1), c2=iClose(sym,tf,2);
   double atr=iATR(sym,tf,InpATRPeriod,1);
   double adx=iADX(sym,tf,14,PRICE_CLOSE,MODE_MAIN,1);
   double rsi14=iRSI(sym,tf,14,PRICE_CLOSE,1);
   if(c1<=0 || c2<=0 || atr<=0 || adx<0 || rsi14<0) { why="INDICATOR_DATA_INVALID"; return(false); }
   int assetSample=0,assetWins=0,assetLosses=0,assetStreak=0;
   double assetNet=0.0; bool assetAdverse=false;
   if(InpEnableRollingLossPolicy)
      GetRecentLossPolicy(sym,assetSample,assetWins,assetLosses,assetNet,assetStreak,assetAdverse);
   int strictLevels=(InpEnableRollingLossPolicy?
      LossPolicyLevel(g_globalLossAdverse,g_globalLossStreak)+LossPolicyLevel(assetAdverse,assetStreak):0);
   double requiredADX=InpMinADX+MathMax(0.0,InpLossPolicyExtraADX)*strictLevels+MathMax(0.0,InpSelectivityADXStep)*g_analyticalSelectivityLevel;
   if(adx<requiredADX) { why=(strictLevels>0?"ROLLING_LOSS_ADX_FILTER":"DEAD_MARKET_ADX"); return(false); }

   // Family 0: EMA stack alignment (8 variants)
   int tb=0,tsl=0;
   int per[9]={5,8,10,13,21,34,50,89,144};
   double ema[9];
   ArrayInitialize(ema,0.0);
   for(int e=0;e<9;e++)
   {
      ema[e]=iMA(sym,tf,per[e],0,MODE_EMA,PRICE_CLOSE,1);
      if(ema[e]<=0) { why="EMA_UNAVAILABLE"; return(false); }
   }
   for(int e2=0;e2<8;e2++)
      Vote(ema[e2]>ema[e2+1] && c1>ema[e2], ema[e2]<ema[e2+1] && c1<ema[e2], tb, tsl);

   // Family 1: RSI momentum (8 variants)
   int mb=0,ms=0;
   int rp[8]={5,7,9,11,14,18,21,28};
   for(int r=0;r<8;r++)
   {
      double rv=iRSI(sym,tf,rp[r],PRICE_CLOSE,1);
      double rprev=iRSI(sym,tf,rp[r],PRICE_CLOSE,2);
      Vote(rv>52 && rv>rprev && rv<75, rv<48 && rv<rprev && rv>25, mb, ms);
   }

   // Family 2: Donchian breakout (8 variants)
   int bb=0,bs=0;
   int lb[8]={5,7,9,12,15,18,22,30};
   for(int d=0;d<8;d++)
   {
      int hi=iHighest(sym,tf,MODE_HIGH,lb[d],2);
      int lo=iLowest(sym,tf,MODE_LOW,lb[d],2);
      double hh=(hi>=0?iHigh(sym,tf,hi):0.0);
      double ll=(lo>=0?iLow(sym,tf,lo):0.0);
      Vote(hh>0 && c1>hh && c1>c2, ll>0 && c1<ll && c1<c2, bb, bs);
   }

   // Family 3: Bollinger re-entry / mean reversion (8 variants)
   int rb=0,rs=0;
   int bp[8]={8,10,12,14,18,20,24,30};
   for(int m=0;m<8;m++)
   {
      double up=iBands(sym,tf,bp[m],2.0,0,PRICE_CLOSE,MODE_UPPER,1);
      double lw=iBands(sym,tf,bp[m],2.0,0,PRICE_CLOSE,MODE_LOWER,1);
      Vote(c2<lw && c1>lw && c1>c2, c2>up && c1<up && c1<c2, rb, rs);
   }

   int dT=FamilyDir(tb,tsl), dM=FamilyDir(mb,ms), dB=FamilyDir(bb,bs), dR=FamilyDir(rb,rs);
   double ema50=ema[6], ema144=ema[8];
   double bb20Upper=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_UPPER,1);
   double bb20Lower=iBands(sym,tf,20,2.0,0,PRICE_CLOSE,MODE_LOWER,1);
   int dc20High=iHighest(sym,tf,MODE_HIGH,20,2);
   int dc20Low=iLowest(sym,tf,MODE_LOW,20,2);
   double donchianHigh=(dc20High>=0?iHigh(sym,tf,dc20High):0.0);
   double donchianLow=(dc20Low>=0?iLow(sym,tf,dc20Low):0.0);
   string regime=(adx>=InpTrendADX?"TREND":"RANGE");
   string htf="OFF";
   if(InpUseHTFFilter)
   {
      double htfClose=iClose(sym,InpHTF,1), htfEma=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
      htf=(htfClose>0 && htfEma>0?(htfClose>htfEma?"BULL":"BEAR"):"NO_DATA");
   }
   g_lastIndicatorSummary=StringFormat("%s TF=%d | ADX14=%.1f %s | ATR%d=%.5f | RSI14=%.1f | EMA50/144=%.5f/%.5f | votes T%d/%d M%d/%d D%d/%d BB%d/%d | BB20[%.5f..%.5f] | Donchian20[%.5f..%.5f] | HTF=%s",
      sym,tf,adx,regime,InpATRPeriod,atr,rsi14,ema50,ema144,tb,tsl,mb,ms,bb,bs,rb,rs,bb20Lower,bb20Upper,donchianLow,donchianHigh,htf);
   int dir=0, agree=0, win=0;

   if(adx>=InpTrendADX)
   {
      int upF=0, dnF=0;
      if(dT>0) upF++; else if(dT<0) dnF++;
      if(dM>0) upF++; else if(dM<0) dnF++;
      if(dB>0) upF++; else if(dB<0) dnF++;
      if(upF>=2 && dnF==0 && dT>0) { dir=1;  agree=upF; win=tb+mb+bb; }
      else if(dnF>=2 && upF==0 && dT<0) { dir=-1; agree=dnF; win=tsl+ms+bs; }
      else { why="TREND_REGIME_NO_FAMILY_CONSENSUS"; return(false); }

      if(InpUseHTFFilter)
      {
         int htfBars=iBars(sym,InpHTF);
         datetime htfClosed=iTime(sym,InpHTF,1);
         datetime signalClosed=iTime(sym,tf,1);
         double hc=iClose(sym,InpHTF,1);
         double he=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
         // SeriesInfoInteger may report "unknown" on some MT4 feeds. Validate
         // actual closed-bar timestamps and indicator values instead of treating
         // an unavailable synchronization flag as proof of bad data.
         if(htfBars<52 || htfClosed<=0 || signalClosed<=0 ||
            htfClosed>signalClosed || hc<=0.0 || he<=0.0)
         { why="HTF_DATA_UNAVAILABLE"; return(false); }
         if((dir>0 && hc<=he) || (dir<0 && hc>=he)) { why="HTF_BIAS_AGAINST"; return(false); }
      }
   }
   else
   {
      if(dR>0 && rsi14<=40.0 && dM>=0) { dir=1;  agree=1; win=rb; }
      else if(dR<0 && rsi14>=60.0 && dM<=0) { dir=-1; agree=1; win=rs; }
      else { why="RANGE_REGIME_NO_REVERSION_SETUP"; return(false); }
   }

   // Spread cost is part of the ranking: tighter spread -> better score
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double stopRef=atr*InpStopATR;
   double spreadRatio=(stopRef>0?(ask-bid)/stopRef:1.0);
   score=10.0*agree+win+MathMin(adx,40.0)/4.0-30.0*spreadRatio;
   cmd=(dir>0?OP_BUY:OP_SELL);
   return(true);
}

//+------------------------------------------------------------------+
//| Detailed execution diagnostics (observability only; no trade logic)|
//+------------------------------------------------------------------+
void LogExecutionDiagnostic(string eventName,string sym,int cmd,double lots,
   double entry,double sl,double tp,int errorCode,double budget=0.0,
   double riskDistance=0.0,double appliedFactor=0.0,double lossPerLot=0.0)
{
   if(!InpEnableDetailedExecutionDiagnostics) return;
   string diagnosticKey=sym+"|"+eventName;
   int diagnosticIndex=-1;
   for(int dk=0;dk<g_execDiagKeyCount;dk++) if(g_execDiagKeys[dk]==diagnosticKey){diagnosticIndex=dk;break;}
   if(diagnosticIndex<0 && g_execDiagKeyCount<2048)
   {
      diagnosticIndex=g_execDiagKeyCount++;
      g_execDiagKeys[diagnosticIndex]=diagnosticKey;
      g_execDiagLastTick[diagnosticIndex]=0;
      g_execDiagSuppressed[diagnosticIndex]=0;
   }
   uint diagnosticNow=GetTickCount();
   int throttleMs=MathMax(1,InpDiagnosticThrottleSeconds)*1000;
   if(diagnosticIndex>=0 && g_execDiagLastTick[diagnosticIndex]!=0 &&
      (uint)(diagnosticNow-g_execDiagLastTick[diagnosticIndex])<(uint)throttleMs)
   {
      g_execDiagSuppressed[diagnosticIndex]++;
      return;
   }
   int suppressed=(diagnosticIndex>=0?g_execDiagSuppressed[diagnosticIndex]:0);
   if(diagnosticIndex>=0){g_execDiagLastTick[diagnosticIndex]=diagnosticNow;g_execDiagSuppressed[diagnosticIndex]=0;}
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
   double point=MarketInfo(sym,MODE_POINT);
   double spreadPts=(point>0.0?(ask-bid)/point:0.0);
   Print("EXECUTION_DIAGNOSTIC | event=",eventName,
      " symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
      " errorCode=",errorCode," errorName=",(errorCode>0?TradeErrorDescription(errorCode):"NONE"),
      " tradeAllowed=",(MarketInfo(sym,MODE_TRADEALLOWED)>0?"true":"false"),
      " terminalAllowed=",(IsTradeAllowed()?"true":"false"),
      " expertEnabled=",(IsExpertEnabled()?"true":"false"),
      " contextBusy=",(IsTradeContextBusy()?"true":"false"),
      " bid=",DoubleToString(bid,digits)," ask=",DoubleToString(ask,digits),
      " spreadPoints=",DoubleToString(spreadPts,1),
      " quoteAgeSec=",QuoteAgeSeconds(sym),
      " point=",DoubleToString(point,digits)," digits=",digits,
      " lots=",DoubleToString(lots,LotDigits(MathMax(0.0000001,MarketInfo(sym,MODE_LOTSTEP)))),
      " minLot=",DoubleToString(MarketInfo(sym,MODE_MINLOT),3),
      " lotStep=",DoubleToString(MarketInfo(sym,MODE_LOTSTEP),3),
      " maxLot=",DoubleToString(MarketInfo(sym,MODE_MAXLOT),3),
      " stopLevelPoints=",DoubleToString(MarketInfo(sym,MODE_STOPLEVEL),0),
      " freezeLevelPoints=",DoubleToString(MarketInfo(sym,MODE_FREEZELEVEL),0),
      " tickValue=",DoubleToString(MarketInfo(sym,MODE_TICKVALUE),6),
      " tickSize=",DoubleToString(MarketInfo(sym,MODE_TICKSIZE),digits),
      " marginRequired=",DoubleToString(MarketInfo(sym,MODE_MARGINREQUIRED),2),
      " freeMargin=",DoubleToString(AccountFreeMargin(),2),
      " entry=",DoubleToString(entry,digits),
      " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits),
      " timestampServer=",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS));
   Print("EXECUTION_DIAGNOSTIC_RISK | event=",eventName,
      " symbol=",sym," budget=",DoubleToString(budget,2),
      " riskDistance=",DoubleToString(riskDistance,digits),
      " appliedRiskFactor=",DoubleToString(appliedFactor,3),
      " lossPerLot=",DoubleToString(lossPerLot,4),
      " minLotLoss=",DoubleToString(lossPerLot*MarketInfo(sym,MODE_MINLOT),2),
      " suppressedSinceLastLog=",suppressed);
}

//+------------------------------------------------------------------+
//| Order entry: stops, spread-vs-stop, risk budget, lots             |
//+------------------------------------------------------------------+
// Daily loss never suspends entries; loss policy scales new-entry risk only. Open positions remain under the existing exit manager.
bool OpenTrade(string sym,int cmd,double score)
{
   g_lastExecutionRejectCategory="";
   if(DIAGNOSTIC_ONLY_BUILD)
   {
      g_lastExecutionRejectCategory="DRY_RUN";
      Print("DIAGNOSTIC_ONLY_HARD_BLOCK | symbol=",sym,
            " action=ORDER_SEND_FORBIDDEN");
      return(false);
   }
   if(SessionSymbolBlocked(sym))
   {
      g_lastExecutionRejectCategory="TRADE_PERMISSION";
      Print("SESSION_SYMBOL_BLOCK | symbol=",sym," reason=PREVIOUS_BROKER_133 no_retry=true");
      return(false);
   }
   g_lastExecutionErrorCode=0;
   double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK), point=MarketInfo(sym,MODE_POINT);
   int digits=(int)MarketInfo(sym,MODE_DIGITS);
   double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { g_lastExecutionRejectCategory="TRANSIENT_DATA"; Reject(sym,"ENTRY_DATA_INVALID"); LogExecutionDiagnostic("PREFLIGHT_DATA_INVALID",sym,cmd,0.0,0.0,0.0,0.0,0); return(false); }
   if(!QuoteFresh(sym)) { g_lastExecutionRejectCategory="TRANSIENT_DATA"; Reject(sym,"STALE_QUOTE_AT_ENTRY"); LogExecutionDiagnostic("PREFLIGHT_STALE_QUOTE",sym,cmd,0.0,0.0,0.0,0.0,0); return(false); }

   double spreadPrice=ask-bid;
   double brokerMin=(MathMax(MarketInfo(sym,MODE_STOPLEVEL),MarketInfo(sym,MODE_FREEZELEVEL))+2.0)*point;
   double stopDist=MathMax(atr*InpStopATR,spreadPrice+brokerMin);
   double targetDist=MathMax(stopDist*InpRewardRisk,spreadPrice+brokerMin);
   // The warning threshold is informational; the hard cap rejects excessive spread.
   // Entry-to-SL already uses executable Ask (BUY) or Bid (SELL) entry price.
   // Adding spread again would double-count it; reserve only adverse slippage here.
   double spreadPctOfStop=(stopDist>0.0?100.0*spreadPrice/stopDist:0.0);
   if(InpMaxSpreadPctOfStop>0.0 && spreadPctOfStop>InpMaxSpreadPctOfStop)
      Print("HIGH_SPREAD_WARNING | symbol=",sym," spread=",DoubleToString(spreadPrice,digits),
            " stop=",DoubleToString(stopDist,digits)," spreadPctOfStop=",DoubleToString(spreadPctOfStop,1),
            " diagnosticThreshold=",DoubleToString(InpMaxSpreadPctOfStop,1),
            " action=CHECK_HARD_CAP");
   int assetSample=0,assetWins=0,assetLosses=0,assetStreak=0;
   double assetNet=0.0; bool assetAdverse=false;
   if(InpEnableRollingLossPolicy)
      GetRecentLossPolicy(sym,assetSample,assetWins,assetLosses,assetNet,assetStreak,assetAdverse);
   int directionSample=0,directionWins=0,directionLosses=0,directionStreak=0;
   double directionNet=0.0; bool directionAdverse=false;
   if(InpEnableRollingLossPolicy)
      GetRecentLossPolicy(sym,directionSample,directionWins,directionLosses,directionNet,directionStreak,directionAdverse,cmd);
   int spreadLevels=(InpEnableRollingLossPolicy?
      LossPolicyLevel(g_globalLossAdverse,g_globalLossStreak)+LossPolicyLevel(assetAdverse,assetStreak)+LossPolicyLevel(directionAdverse,directionStreak):0);
   double effectiveHardSpread=InpHardMaxSpreadPctOfStop;
   if(effectiveHardSpread>0.0 && g_analyticalSelectivityLevel>0)
      effectiveHardSpread*=MathPow(MathMax(0.50,MathMin(1.0,InpSelectivitySpreadFactor)),g_analyticalSelectivityLevel);
   if(effectiveHardSpread>0.0 && spreadLevels>0)
      effectiveHardSpread*=MathPow(MathMax(0.50,MathMin(1.0,InpLossPolicySpreadFactor)),spreadLevels);
   if(effectiveHardSpread>0.0 && spreadPctOfStop>effectiveHardSpread)
   {
      Print("EXECUTION_QUALITY_REJECT | symbol=",sym," spreadPctOfStop=",DoubleToString(spreadPctOfStop,1),
            " hardMax=",DoubleToString(effectiveHardSpread,1)," baseHardMax=",DoubleToString(InpHardMaxSpreadPctOfStop,1),
            " rollingLevels=",spreadLevels," selectivityLevel=",g_analyticalSelectivityLevel," reason=SPREAD_TOO_LARGE");
      g_lastExecutionRejectCategory="SPREAD";
      LogExecutionDiagnostic("PREFLIGHT_SPREAD_REJECT",sym,cmd,0.0,0.0,0.0,0.0,0);
      return(false);
   }

   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { g_lastExecutionRejectCategory="STOP_PREFLIGHT"; Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)," brokerMinDistance=",DoubleToString(brokerMin,digits)," stopLevelPoints=",MarketInfo(sym,MODE_STOPLEVEL)," freezeLevelPoints=",MarketInfo(sym,MODE_FREEZELEVEL)); LogExecutionDiagnostic("PREFLIGHT_INVALID_STOPS",sym,cmd,0.0,entry,sl,tp,0); return(false); }

   double maxAgg=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double openRisk=CurrentOpenRisk();
   double remaining=maxAgg-openRisk;
   double perTrade=InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0;
   double globalRiskFactor=AdaptiveLossRiskMultiplier(g_globalLossSampleCount,g_globalLossWins,g_globalLossLosses,g_globalLossNet,g_globalLossStreak,g_globalLossAdverse);
   double assetRiskFactor=AdaptiveLossRiskMultiplier(assetSample,assetWins,assetLosses,assetNet,assetStreak,assetAdverse);
   double directionRiskFactor=AdaptiveLossRiskMultiplier(directionSample,directionWins,directionLosses,directionNet,directionStreak,directionAdverse);
   double closedTradeRiskFactor=MathMin(globalRiskFactor,MathMin(assetRiskFactor,directionRiskFactor));
   double openExposureFactor=OpenExposureRiskMultiplier(sym,cmd);
   double adaptiveRiskFactor=MathMin(closedTradeRiskFactor,openExposureFactor);
   double selectivityRiskFactor=SelectivityRiskMultiplier(g_analyticalSelectivityLevel);
   adaptiveRiskFactor=MathMin(adaptiveRiskFactor,selectivityRiskFactor);
   double adjustedPerTrade=perTrade*adaptiveRiskFactor;
   if(remaining<=0.01) { g_lastExecutionRejectCategory="RISK"; Print("RISK_REJECT | symbol=",sym," reason=AGGREGATE_RISK_CAP open=",DoubleToString(openRisk,2)," cap=",DoubleToString(maxAgg,2)); LogExecutionDiagnostic("PREFLIGHT_AGGREGATE_RISK_CAP",sym,cmd,0.0,entry,sl,tp,0); return(false); }
   double budget=MathMin(adjustedPerTrade,remaining);
   Print("ADAPTIVE_LOSS_RISK | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
      " globalFactor=",DoubleToString(globalRiskFactor,2)," assetFactor=",DoubleToString(assetRiskFactor,2),
      " directionFactor=",DoubleToString(directionRiskFactor,2),
      " openExposureFactor=",DoubleToString(openExposureFactor,2),
      " analyticalSelectivityLevel=",g_analyticalSelectivityLevel,
      " selectivityRiskFactor=",DoubleToString(selectivityRiskFactor,2),
      " appliedFactor=",DoubleToString(adaptiveRiskFactor,2),
      " baseRiskUSD=",DoubleToString(perTrade,2)," adjustedRiskUSD=",DoubleToString(adjustedPerTrade,2),
      " action=REDUCE_NEW_ENTRY_SIZE_ONLY_NO_ENTRY_SUSPENSION");
   double riskDistance=stopDist+MathMax(0,InpSlippagePoints)*point;
   double lots=LotsForRisk(sym,riskDistance,budget);
   if(lots<=0)
    {
       g_lastExecutionRejectCategory="RISK";
       Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET budget=",DoubleToString(budget,2)," riskDistance=",DoubleToString(riskDistance,digits));
       double minLotLossPerLot=((riskDistance>0.0 && MarketInfo(sym,MODE_TICKSIZE)>0.0)?
          (riskDistance/MarketInfo(sym,MODE_TICKSIZE))*MarketInfo(sym,MODE_TICKVALUE):0.0);
       LogExecutionDiagnostic("PREFLIGHT_MIN_LOT_EXCEEDS_BUDGET",sym,cmd,0.0,entry,sl,tp,0,
          budget,riskDistance,adaptiveRiskFactor,minLotLossPerLot);
       return(false);
    }
   double risk=EstimateRisk(sym,lots,riskDistance);
   if(!CurrencyRiskAllowed(sym,lots,riskDistance,risk)) { g_lastExecutionRejectCategory="RISK"; LogExecutionDiagnostic("PREFLIGHT_CURRENCY_RISK_LIMIT",sym,cmd,lots,entry,sl,tp,0); return(false); }

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
            " spread=",DoubleToString(spreadPrice,digits)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      g_lastExecutionRejectCategory="DRY_RUN";
      return(false);
   }
   if(!TradePermissionsReady(sym,"PRE_ORDER")) { g_lastExecutionRejectCategory="TRADE_PERMISSION"; LogExecutionDiagnostic("PREFLIGHT_TRADE_PERMISSION",sym,cmd,lots,entry,sl,tp,0); return(false); }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"Bitey Ens v"+EA_VERSION,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      g_lastExecutionErrorCode=err;
      Print("ORDER_SEND_FAILED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
            " error=",err," errorName=",TradeErrorDescription(err),
            " lots=",DoubleToString(lots,2)," entry=",DoubleToString(entry,digits),
            " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      LogExecutionDiagnostic("ORDER_SEND_FAILED",sym,cmd,lots,entry,sl,tp,err);
      g_lastExecutionRejectCategory="BROKER_ERROR";
      if(err==133)
      {
         int blockedIdx=SessionSymbolIndex(sym);
         if(blockedIdx>=0)
         {
            g_sessionBlocked[blockedIdx]=true;
          g_sessionBlockReason[blockedIdx]="ORDER_SEND_TRADE_DISABLED";
          g_sessionBlockError[blockedIdx]=err;
            uint nowTick=GetTickCount();
            int cooldownMinutes=MathMax(0,InpBroker133CooldownMinutes);
            g_sessionBlockUntilTick[blockedIdx]=nowTick+(uint)(cooldownMinutes*60000);
            g_sessionNextPermissionCheckTick[blockedIdx]=g_sessionBlockUntilTick[blockedIdx];
            g_sessionBlockUntilTime[blockedIdx]=(cooldownMinutes>0?TimeCurrent()+cooldownMinutes*60:0);
         }
         Print("SESSION_SYMBOL_BLOCK | symbol=",sym,
               " reason=TRADE_DISABLED_133 no_retry=true cooldownMinutes=",MathMax(0,InpBroker133CooldownMinutes),
               " scope=",(InpBroker133CooldownMinutes>0?"TEMPORARY_PERMISSION_RECHECK":"UNTIL_EA_RESTART"),
               " unlockRequiresPermissionCheck=true");
      }
      if(err==133 || err==4109 || err==146)
         TradePermissionsReady(sym,"ORDER_SEND_FAILURE");
      return(false);
   }
   GlobalVariableSet(InitialRiskKey(ticket),risk); // Persist original monetary stop risk at entry.
   GlobalVariableSet(EntrySpreadKey(ticket),spreadPrice); // Preserve entry spread for post-trade cost audit.
    Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
         " spread=",DoubleToString(spreadPrice,digits)," score=",DoubleToString(score,1),
         " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
   return(true);
}

//+------------------------------------------------------------------+
//| Directional progression: closed-bar EMA alignment and slope      |
//| Returns +1 favorable, -1 adverse, 0 neutral / not confirmed.     |
//+------------------------------------------------------------------+
int DirectionalProgression(string sym,int orderType,double atr)
{
   if(atr<=0.0) return(0);
   int lookback=MathMax(1,InpProgressionLookbackBars);
   double fastNow=iMA(sym,InpSignalTF,8,0,MODE_EMA,PRICE_CLOSE,1);
   double fastPast=iMA(sym,InpSignalTF,8,0,MODE_EMA,PRICE_CLOSE,lookback+1);
   double slowNow=iMA(sym,InpSignalTF,21,0,MODE_EMA,PRICE_CLOSE,1);
   double closeNow=iClose(sym,InpSignalTF,1);
   double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
   if(fastNow<=0.0 || fastPast<=0.0 || slowNow<=0.0 || closeNow<=0.0 || adx<InpProgressionADXMin)
      return(0);
   double slopeMin=atr*0.02;
   if(orderType==OP_BUY)
   {
      if(fastNow>slowNow && fastNow-fastPast>=slopeMin && closeNow>fastNow) return(1);
      if(fastNow<slowNow && fastNow-fastPast<=-slopeMin && closeNow<fastNow) return(-1);
   }
   else if(orderType==OP_SELL)
   {
      if(fastNow<slowNow && fastPast-fastNow>=slopeMin && closeNow<fastNow) return(1);
      if(fastNow>slowNow && fastPast-fastNow<=-slopeMin && closeNow>fastNow) return(-1);
   }
   return(0);
}

// Convert the R-based profit-lock threshold to account currency using the
// original monetary stop risk saved when the order was opened.
double ProfitLockTriggerMoney(int ticket)
{
   string riskKey=InitialRiskKey(ticket);
   if(InpProfitLockTriggerR>0.0 && GlobalVariableCheck(riskKey))
   {
      double initialRisk=GlobalVariableGet(riskKey);
      if(initialRisk>0.0) return(initialRisk*InpProfitLockTriggerR);
   }
   return(MathMax(0.0,InpTrendRunnerTriggerNetUSD));
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
   if(ok)
   {
      RecordEAClosedReason(ticket,reason);
      string pk=NetPeakKey(ticket); if(GlobalVariableCheck(pk)) GlobalVariableDel(pk);
      string rk=RunnerActiveKey(ticket); if(GlobalVariableCheck(rk)) GlobalVariableDel(rk);
      string ik=InitialRiskKey(ticket); if(GlobalVariableCheck(ik)) GlobalVariableDel(ik);
      string xk=RetracementPeakKey(ticket); if(GlobalVariableCheck(xk)) GlobalVariableDel(xk);
      string lossTimer=LossDurationStartKey(ticket); if(GlobalVariableCheck(lossTimer)) GlobalVariableDel(lossTimer);
   }
   return(ok);
}

// Confirm retracement only after a completed candle breaks the prior candle structure.
bool ConfirmedRetracementBreak(string sym,int orderType)
{
   if(iBars(sym,InpSignalTF)<3) return(false);
   double o1=iOpen(sym,InpSignalTF,1), c1=iClose(sym,InpSignalTF,1);
   double h2=iHigh(sym,InpSignalTF,2), l2=iLow(sym,InpSignalTF,2);
   if(o1<=0.0 || c1<=0.0 || h2<=0.0 || l2<=0.0) return(false);
   if(orderType==OP_BUY)  return(c1<o1 && c1<l2);
   if(orderType==OP_SELL) return(c1>o1 && c1>h2);
   return(false);
}

// Existing broker SL must already secure a positive net result after booked costs,
// estimated closing commission and the configured adverse stop-fill reserve.
bool StopProtectsNetCosts(int ticket,string sym,int orderType,double entry,double lots,double stopPrice)
{
   if(stopPrice<=0.0 || lots<=0.0 || !OrderSelect(ticket,SELECT_BY_TICKET,MODE_TRADES)) return(false);
   if(InpIncludeEstimatedCloseCommission && InpEstimatedCloseCommissionPerLot<=0.0) return(false);
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0.0 || ts<=0.0) return(false);
   double favorableMove=(orderType==OP_BUY?stopPrice-entry:entry-stopPrice);
   if(favorableMove<=0.0) return(false);
   double grossAtStop=(favorableMove/ts)*tv*lots;
   double closeCommission=(InpIncludeEstimatedCloseCommission?MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots:0.0);
   double slipReserve=0.0;
   if(InpNetLockSlippagePoints>0)
      slipReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*MarketInfo(sym,MODE_POINT));
   if(slipReserve>=1.0e11) return(false);
   double projectedNet=grossAtStop+OrderCommission()+OrderSwap()-closeCommission-slipReserve;
   return(projectedNet>=MathMax(0.05,InpNetLockMinUSD));
}

void ManageExits()
{
   for(int pos=OrdersTotal()-1;pos>=0;pos--)
   {
      if(!OrderSelect(pos,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic) continue;
      int type=OrderType();
      if(type!=OP_BUY && type!=OP_SELL) continue;

      int ticket=OrderTicket();
      string sym=OrderSymbol();
      int quoteIndex=ScanSymbolIndex(sym);
      // Never calculate or send EA-managed exits from a frozen quote.
      // Broker-resident SL/TP remain active while this symbol awaits fresh data.
      if(!SymbolQuoteFresh(quoteIndex,sym)) continue;
      double point=MarketInfo(sym,MODE_POINT);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double entry=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit(), lots=OrderLots();
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      AuditLifecycleSnapshot(ticket,"SNAPSHOT","source=ManageExits");
       double netPeak=UpdateNetPeak(ticket,net);
       double givebackTriggerNet=netPeak*(1.0-InpNetLockGivebackPct/100.0);
       double givebackActivationNet=ProfitLockTriggerMoney(ticket); // Existing +0.85R activation floor
       if(InpNetLockGivebackPct>0.0 && InpNetLockGivebackPct<100.0 &&
          givebackActivationNet>0.0 && netPeak>=MathMax(MathMax(0.0,InpNetLockMinUSD),givebackActivationNet) && net<=givebackTriggerNet)
       {
          double actualGiveback=(netPeak>0.0?(netPeak-net)/netPeak*100.0:0.0);
          Print("NET_GIVEBACK_40_TRIGGERED | ticket=",ticket," symbol=",sym,
                " side=",(type==OP_BUY?"BUY":"SELL"),
                " peakNet=",DoubleToString(netPeak,2)," currentNet=",DoubleToString(net,2),
                " givebackNet=",DoubleToString(netPeak-net,2)," givebackPct=",DoubleToString(actualGiveback,2),
                " thresholdPct=",DoubleToString(InpNetLockGivebackPct,2),
                " activationFloorNet=",DoubleToString(givebackActivationNet,2),
                " action=CLOSE_TICKET_IF_BROKER_SL_NOT_ALREADY_FILLED");
          CloseTicket(ticket,"NET_GIVEBACK_40_AFTER_0_85R");
          continue;
       }
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);

      // Evaluate directional progression before any small-profit decision.
      // The signal uses closed candles only; an uncertain/weak signal is neutral.
      int progression=(atr>0.0?DirectionalProgression(sym,type,atr):0);

      // Require a confirmed retracement to have bankable net profit of at least the
      // configured R threshold. Costs and adverse execution reserve are deducted.
      double retracementInitialRisk=(GlobalVariableCheck(InitialRiskKey(ticket))?GlobalVariableGet(InitialRiskKey(ticket)):0.0);
      double retracementCloseCommission=(InpIncludeEstimatedCloseCommission?MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots:0.0);
      double retracementSlipReserve=(InpNetLockSlippagePoints>0?EstimateRisk(sym,lots,InpNetLockSlippagePoints*point):0.0);
      double retracementNetAfterCosts=net-retracementCloseCommission-retracementSlipReserve;
      bool retracementCommissionValid=(!InpIncludeEstimatedCloseCommission || InpEstimatedCloseCommissionPerLot>0.0);
       bool retracementProfitQualified=(retracementCommissionValid && retracementInitialRisk>0.0 && retracementSlipReserve<1.0e11 &&
         retracementNetAfterCosts>=retracementInitialRisk*MathMax(0.0,InpRetracementExitMinR));

      // Track the best executable-side price per ticket. This is research state,
      // not an entry gate; it survives terminal restarts through MT4 GlobalVariables.
      if(atr>0.0 && InpEnableConfirmedRetracementExit)
      {
         string peakKey=RetracementPeakKey(ticket);
         double peakPrice=(GlobalVariableCheck(peakKey)?GlobalVariableGet(peakKey):entry);
         double livePrice=(type==OP_BUY?bid:ask);
         if(type==OP_BUY) peakPrice=MathMax(peakPrice,livePrice);
         else             peakPrice=(peakPrice<=0.0?livePrice:MathMin(peakPrice,livePrice));
         GlobalVariableSet(peakKey,peakPrice);
         double peakFavorable=(type==OP_BUY?peakPrice-entry:entry-peakPrice);
         double pullback=(type==OP_BUY?peakPrice-bid:ask-peakPrice);
         bool structureBroken=ConfirmedRetracementBreak(sym,type);
         if(peakFavorable>=atr*InpRetracementMinPeakATR &&
            pullback>=atr*InpRetracementPullbackATR && structureBroken && retracementProfitQualified)
         {
            Print("CONFIRMED_RETRACEMENT_EXIT | ticket=",ticket," symbol=",sym,
                  " side=",(type==OP_BUY?"BUY":"SELL"),
                  " peakFavorableATR=",DoubleToString(peakFavorable/atr,2),
                  " pullbackATR=",DoubleToString(pullback/atr,2),
                  " progression=",progression,
                  " netAfterCloseCosts=",DoubleToString(retracementNetAfterCosts,2),
                  " initialRisk=",DoubleToString(retracementInitialRisk,2),
                  " minimumExitR=",DoubleToString(InpRetracementExitMinR,2),
                  " action=CLOSE_TICKET_AND_RECORD_CSV initialSL=UNCHANGED");
            CloseTicket(ticket,"CONFIRMED_FAVORABLE_RETRACEMENT_EXIT");
            continue;
         }
      }

      // Conservative estimated net after booked costs, estimated closing commission
      // and adverse execution reserve. All thresholds are in account currency.
      double closeCommissionEstimate=(InpIncludeEstimatedCloseCommission?MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots:0.0);
      double closeSlippageReserve=0.0;
      if(InpNetLockSlippagePoints>0)
         closeSlippageReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
      double estimatedNetAfterCloseCosts=net-closeCommissionEstimate-closeSlippageReserve;
      bool costEstimateValid=(closeSlippageReserve<1.0e11 &&
          (!InpIncludeEstimatedCloseCommission || InpEstimatedCloseCommissionPerLot>0.0));

      // Mode A: +0.10 is the fallback close only while a trend runner has NOT
      // been activated. If closed-bar progression is favorable, let the trade
      // reach +0.20 net before activating the runner.
      string runnerKey=RunnerActiveKey(ticket);
      bool runnerActive=(GlobalVariableCheck(runnerKey) && GlobalVariableGet(runnerKey)>0.5);
      double runnerTriggerMoney=ProfitLockTriggerMoney(ticket);
      if(!runnerActive && costEstimateValid && progression>0 && runnerTriggerMoney>0.0 &&
         estimatedNetAfterCloseCosts>=runnerTriggerMoney)
      {
         GlobalVariableSet(runnerKey,1.0);
         runnerActive=true;
         Print("PROFIT_RUNNER_ACTIVATED | ticket=",ticket," symbol=",sym,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " trigger=+",DoubleToString(runnerTriggerMoney,2),
               " progression=",progression,
               " action=LET_WINNER_RUN_AND_LOCK_NET");
      }

      // Without a confirmed runner, bank at least the small net target once
      // progression is neutral/adverse. An active runner is never closed here:
      // its progressive broker-side SL manages the giveback.
      double smallProfitInitialRisk=(GlobalVariableCheck(InitialRiskKey(ticket))?GlobalVariableGet(InitialRiskKey(ticket)):0.0);
      double smallProfitTarget=MathMax(MathMax(0.0,InpSmallProfitCloseUSD),smallProfitInitialRisk*MathMax(0.0,InpSmallProfitCloseR));
      if(!runnerActive && costEstimateValid && smallProfitTarget>0.0 &&
         estimatedNetAfterCloseCosts>=smallProfitTarget && progression<=0)
      {
         Print("NET_RANGE_PROFIT_CLOSE | ticket=",ticket," symbol=",sym,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " target=+",DoubleToString(smallProfitTarget,2),
               " targetR=",DoubleToString(InpSmallProfitCloseR,2),
               " progression=",progression,
               " action=CLOSE");
         CloseTicket(ticket,"NET_RANGE_PROFIT_MAX_0_10_OR_0_8R");
         continue;
      }

      // Only continuously negative positions are timed. Winners keep existing profit exits.
      if(InpEnableRollingLossPolicy && costEstimateValid)
      {
         string timerKey=LossDurationStartKey(ticket);
         if(estimatedNetAfterCloseCosts<0.0)
         {
            double negativeSince=(GlobalVariableCheck(timerKey)?GlobalVariableGet(timerKey):0.0);
            if(negativeSince<=0.0){negativeSince=(double)TimeCurrent();GlobalVariableSet(timerKey,negativeSince);}
            int sample=0,wins=0,losses=0,streak=0;
            double recentNet=0.0; bool adverse=false;
            GetRecentLossPolicy(sym,sample,wins,losses,recentNet,streak,adverse);
            int level=LossPolicyLevel(adverse,streak);
            int allowedMinutes=LossDurationLimitMinutes(streak);
            int negativeSeconds=(int)MathMax(0,TimeCurrent()-(datetime)negativeSince);
            if(negativeSeconds>=allowedMinutes*60)
            {
               double entrySpreadPrice=(GlobalVariableCheck(EntrySpreadKey(ticket))?GlobalVariableGet(EntrySpreadKey(ticket)):0.0);
               double spreadCostEstimate=(entrySpreadPrice>0.0?EstimateRisk(sym,lots,entrySpreadPrice):0.0);
               if(spreadCostEstimate>=1.0e11) spreadCostEstimate=0.0;
               double bookedCostBudget=MathAbs(OrderCommission())+MathAbs(OrderSwap())+
                  closeCommissionEstimate+spreadCostEstimate+closeSlippageReserve;
               double permittedLoss=bookedCostBudget*MathMax(0.0,InpLossDurationMaxCostMultiple);
               double estimatedLoss=MathAbs(MathMin(0.0,estimatedNetAfterCloseCosts));
               if(estimatedLoss<=permittedLoss+0.000001)
               {
                  Print("ROLLING_LOSS_DURATION_EXIT | ticket=",ticket," symbol=",sym,
                     " negativeSeconds=",negativeSeconds," allowedMinutes=",allowedMinutes,
                     " estimatedLoss=",DoubleToString(estimatedLoss,2),
                     " estimatedTransactionCostBudget=",DoubleToString(bookedCostBudget,2),
                     " spreadCostEstimate=",DoubleToString(spreadCostEstimate,2),
                     " sample=",sample," wins=",wins," losses=",losses,
                     " recentNet=",DoubleToString(recentNet,2)," streak=",streak,
                     " policyLevel=",level," action=CLOSE_WITHIN_COST_BUDGET_AND_CONTINUE_ADAPTIVE_RISK");
                  CloseTicket(ticket,"ROLLING_LOSS_DURATION_WITHIN_COST_BUDGET_"+IntegerToString(allowedMinutes)+"M");
                  continue;
               }
               Print("ROLLING_LOSS_DURATION_DEFERRED | ticket=",ticket," symbol=",sym,
                  " negativeSeconds=",negativeSeconds," allowedMinutes=",allowedMinutes,
                  " estimatedLoss=",DoubleToString(estimatedLoss,2),
                  " transactionCostBudget=",DoubleToString(bookedCostBudget,2),
                  " action=KEEP_OPEN_INITIAL_SL_REMAINS_ACTIVE reason=LOSS_EXCEEDS_COST_BUDGET");
            }
         }
         else if(GlobalVariableCheck(timerKey)) GlobalVariableDel(timerKey);
      }

      if(atr<=0) continue;

      if(InpNetTargetR>0.0)
      {
         double initialDist=(oldSL>0.0?MathAbs(entry-oldSL):atr*InpStopATR);
         double refRisk=EstimateRisk(sym,lots,initialDist); // current protective-stop distance proxy
         if(refRisk<1.0e11 && net>=InpNetTargetR*refRisk) { CloseTicket(ticket,"NET_TARGET_R"); continue; }
      }
      if(!InpEnableAdaptiveExits) continue;

      double minDist=(MarketInfo(sym,MODE_STOPLEVEL)+MarketInfo(sym,MODE_FREEZELEVEL)+2.0)*point;
      double price=(type==OP_BUY?bid:ask);
      double favorable=(type==OP_BUY?price-entry:entry-price);
      double newSL=oldSL, newTP=oldTP;
      bool slUp=false, tpUp=false;

      // Break-even + small lock (SL only ever moves toward profit)
      if(InpBreakEvenTriggerATR>0 && favorable>=atr*InpBreakEvenTriggerATR)
      {
         double be=(type==OP_BUY?entry+atr*InpBreakEvenLockATR:entry-atr*InpBreakEvenLockATR);
         if(type==OP_BUY  && (newSL<=0 || be>newSL) && be<bid-minDist) newSL=be;
         if(type==OP_SELL && (newSL<=0 || be<newSL) && be>ask+minDist) newSL=be;
      }
      // ATR trailing. If closed-bar progression turns adverse, tighten (never widen) the trail.
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double trailDistance=InpTrailDistanceATR;
         if(progression<0 && InpWeakTrendTrailATR>0.0)
            trailDistance=MathMin(trailDistance,InpWeakTrendTrailATR);
         double tr=(type==OP_BUY?bid-atr*trailDistance:ask+atr*trailDistance);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) newSL=tr;
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) newSL=tr;
      }
      // Cost-aware net-profit lock: peak and current P/L are net of booked commission and swap;
      // the stop target also reserves estimated closing commission and adverse fill slippage.
      double netLockSL=0.0;
      if(NetProfitLockStop(ticket,sym,type,entry,lots,net,point,digits,minDist,price,netLockSL))
      {
         if(type==OP_BUY  && (newSL<=0 || netLockSL>newSL)) newSL=netLockSL;
         if(type==OP_SELL && (newSL<=0 || netLockSL<newSL)) newSL=netLockSL;
      }

      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Experimental guard for ALL adaptive SL paths (break-even, trail and net lock).
      // First protective SL is allowed immediately. Existing SL is never loosened.
      // A >=0.50 ATR improvement bypasses the time interval as an emergency protection.
      if(slUp && oldSL>0.0 && atr>0.0)
      {
         double slAdvance=(type==OP_BUY?newSL-oldSL:oldSL-newSL);
         double minAdvance=MathMax(point,atr*MathMax(0.0,InpAdaptiveSLModifyMinStepATR));
         if(slAdvance+point*0.5<minAdvance)
         {
            Print("ADAPTIVE_SL_DEFERRED | ticket=",ticket," symbol=",sym,
                  " reason=BELOW_MIN_STEP advance=",DoubleToString(slAdvance,digits),
                  " required=",DoubleToString(minAdvance,digits),
                  " stepATR=",DoubleToString(InpAdaptiveSLModifyMinStepATR,2));
            slUp=false;
         }
         else
         {
            string slModifyKey="BiteySLMod_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket);
            double lastSLModify=(GlobalVariableCheck(slModifyKey)?GlobalVariableGet(slModifyKey):0.0);
            int minInterval=MathMax(0,InpAdaptiveSLModifyMinIntervalSeconds);
            bool emergencyAdvance=(InpAdaptiveSLEmergencyStepATR>0.0 &&
                                   slAdvance>=atr*InpAdaptiveSLEmergencyStepATR);
            if(!emergencyAdvance && minInterval>0 && lastSLModify>0.0 &&
               (TimeCurrent()-(datetime)lastSLModify)<minInterval)
            {
               Print("ADAPTIVE_SL_DEFERRED | ticket=",ticket," symbol=",sym,
                     " reason=MIN_INTERVAL advance=",DoubleToString(slAdvance,digits),
                     " elapsedSec=",(int)(TimeCurrent()-(datetime)lastSLModify),
                     " requiredSec=",minInterval,
                     " emergencyBypassATR=",DoubleToString(InpAdaptiveSLEmergencyStepATR,2));
               slUp=false;
            }
         }
      }

      // Unbounded adaptive TP runner: while confirmed progression, ADX and the
      // already-installed net-positive SL remain valid, extend the target repeatedly.
      // 0 distance cap means no EA-side ATR ceiling; broker stop/freeze rules still apply.
      // A stop being proposed in this same OrderModify is not considered protection.
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      bool existingStopProtectsNet=StopProtectsNetCosts(ticket,sym,type,entry,lots,oldSL);
      if(oldTP>0 && progression>0 && favorable>=atr*InpTPExpandTriggerATR &&
         adx>=InpTPExpandADXMin && existingStopProtectsNet)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double desiredDist=MathMax(curDist,favorable+atr*InpTPExpandBufferATR);
            double maxDist=(InpTPMaxDistanceATR>0.0?atr*InpTPMaxDistanceATR:0.0);
            double want=(maxDist>0.0?MathMin(maxDist,desiredDist):desiredDist);
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+point && prop>ask+minDist) { newTP=prop; tpUp=true; }
            if(type==OP_SELL && prop<oldTP-point && prop<bid-minDist) { newTP=prop; tpUp=true; }
         }
      }

      if(!slUp && !tpUp) continue;
      double fSL=(slUp?newSL:oldSL), fTP=(tpUp?newTP:oldTP);
      ResetLastError();
      if(OrderModify(ticket,entry,fSL,fTP,0,clrNONE))
      {
         if(slUp)
         {
            string slModifyKey="BiteySLMod_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket);
            GlobalVariableSet(slModifyKey,(double)TimeCurrent());
         }
         AuditLifecycleSnapshot(ticket,"ADAPTIVE_MODIFY",
            StringFormat("oldSL=%.10f;newSL=%.10f;oldTP=%.10f;newTP=%.10f;slChanged=%s;tpChanged=%s",
               oldSL,fSL,oldTP,fTP,(slUp?"true":"false"),(tpUp?"true":"false")));
         Print("ADAPTIVE_MODIFY | ticket=",ticket," symbol=",sym,
               " SL ",DoubleToString(oldSL,digits),"->",DoubleToString(fSL,digits),
               " TP ",DoubleToString(oldTP,digits),"->",DoubleToString(fTP,digits));
      }
      else
         Print("ADAPTIVE_MODIFY_FAILED | ticket=",ticket," symbol=",sym," error=",GetLastError());
   }
}


//+------------------------------------------------------------------+
//| Persistent peak net-profit tracking and 50% giveback protection    |
//+------------------------------------------------------------------+
string NetPeakKey(int ticket)
{
   return("BiteyNP_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

string RetracementPeakKey(int ticket)
{
   return("BiteyRetracePeak_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

string RunnerActiveKey(int ticket)
{
   return("BiteyRunner_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

string InitialRiskKey(int ticket)
{
   return("BiteyInitialRisk_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

// Update the per-ticket maximum floating net result on every management pass.
// Net is OrderProfit + booked commission + swap; GlobalVariables survive MT4 restarts.
double UpdateNetPeak(int ticket,double net)
{
   string key=NetPeakKey(ticket);
   double peak=(GlobalVariableCheck(key)?GlobalVariableGet(key):net);
   if(net>peak){peak=net;GlobalVariableSet(key,peak);GlobalVariablesFlush();}
   return(peak);
}

// Arm a broker-side stop before the retracement reaches the configured giveback.
// If closing commission is unknown, do not guess: ManageExits closes at the actual threshold.
bool NetProfitLockStop(int ticket,string sym,int type,double entry,double lots,double net,
                       double point,int digits,double minDist,double marketPrice,double &stopOut)
{
   stopOut=0.0;
   if(InpNetLockGivebackPct<=0.0 || InpNetLockGivebackPct>=100.0) return(false);
   double peak=UpdateNetPeak(ticket,net);
   if(peak<MathMax(MathMax(0.0,InpNetLockMinUSD),ProfitLockTriggerMoney(ticket))) return(false);
   double lockNet=peak*(1.0-InpNetLockGivebackPct/100.0);
   if(lockNet<=0.0) return(false);
   if(InpIncludeEstimatedCloseCommission && InpEstimatedCloseCommissionPerLot<=0.0) return(false);
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0.0 || ts<=0.0 || lots<=0.0 || point<=0.0) return(false);
   double moneyPerPrice=(tv/ts)*lots;
   if(moneyPerPrice<=0.0) return(false);
   double closeCommission=(InpIncludeEstimatedCloseCommission?MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots:0.0);
   double slipReserve=0.0;
   if(InpNetLockSlippagePoints>0) slipReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
   if(slipReserve>=1.0e11) return(false);
   double requiredGross=lockNet-OrderSwap()-OrderCommission()+closeCommission+slipReserve;
   double move=requiredGross/moneyPerPrice;
   double candidate=NormalizeDouble(type==OP_BUY?entry+move:entry-move,digits);
   if(type==OP_BUY){
      if(candidate<=entry || candidate>=marketPrice-minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate<=OrderStopLoss()+point*0.5) return(false);
   } else {
      if(candidate>=entry || candidate<=marketPrice+minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate>=OrderStopLoss()-point*0.5) return(false);
   }
   stopOut=candidate;
   Print("NET_GIVEBACK_STOP_ARMED | ticket=",ticket," symbol=",sym,
         " peakNet=",DoubleToString(peak,2)," protectedNetTarget=",DoubleToString(lockNet,2),
         " givebackPct=",DoubleToString(InpNetLockGivebackPct,1),
         " action=PROTECTIVE_SL_ONLY_NO_WIDENING");
   return(true);
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
      if(AssetIdentityKey(OrderSymbol())==key) return(true);
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

// Adverse entry-to-stop risk only; a stop at/after break-even counts as zero risk.
bool CurrencyRiskAllowed(string sym,double lots,double stopDist,double candidateRisk)
{
   if(InpMaxCurrencyRiskPct<=0.0 || IsCrypto(sym)) return(true);
   string key=AssetKey(sym);
   if(StringLen(key)<6) return(true); // Unknown/non-FX contract: retain aggregate-risk control
   string base=StringSubstr(key,0,3), quote=StringSubstr(key,3,3);
   double cap=InpReferenceCapitalUSD*InpMaxCurrencyRiskPct/100.0;
   double baseRisk=candidateRisk, quoteRisk=candidateRisk;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(IsCrypto(OrderSymbol())) continue;
      string k=AssetKey(OrderSymbol());
      if(StringLen(k)<6) continue;
      string b=StringSubstr(k,0,3), q=StringSubstr(k,3,3);
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(OrderStopLoss()<=0.0) return(false); // fail closed when an existing stop-risk is unknown
      double existing=0.0;
      if(d>0.0)
      {
         double op=MarketInfo(OrderSymbol(),MODE_POINT);
         double conservativeDist=d+MathMax(0,InpSlippagePoints)*MathMax(0.0,op);
         existing=EstimateRisk(OrderSymbol(),OrderLots(),conservativeDist);
      }
      if(b==base || q==base) baseRisk+=existing;
      if(b==quote || q==quote) quoteRisk+=existing;
   }
   if(baseRisk>cap+0.02 || quoteRisk>cap+0.02)
   {
      Print("CURRENCY_RISK_REJECT | symbol=",sym," base=",base," risk=",DoubleToString(baseRisk,2),
            " quote=",quote," risk2=",DoubleToString(quoteRisk,2)," cap=",DoubleToString(cap,2));
      return(false);
   }
   return(true);
}

// Floating exposure guard: defensive sizing only. It never closes positions or blocks a full session.
double OpenExposureRiskMultiplier(string candidateSymbol,int candidateType)
{
   if(!InpEnableOpenExposureGuard) return(1.0);
   double totalFloating=0.0, sameSideFloating=0.0, overlapFloating=0.0;
   int sameSideCount=0, overlapCount=0;
   bool candidateCrypto=IsCrypto(candidateSymbol);
   string candidateKey=AssetKey(candidateSymbol);
   string candidateBase="",candidateQuote="";
   if(!candidateCrypto && StringLen(candidateKey)>=6)
   {
      candidateBase=StringSubstr(candidateKey,0,3);
      candidateQuote=StringSubstr(candidateKey,3,3);
   }
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      int type=OrderType();
      if(OrderMagicNumber()!=InpMagic || (type!=OP_BUY && type!=OP_SELL)) continue;
      double floating=OrderProfit()+OrderSwap()+OrderCommission();
      totalFloating+=floating;
      if(type!=candidateType) continue;
      sameSideFloating+=floating;
      sameSideCount++;
      bool overlaps=false;
      if(candidateCrypto) overlaps=IsCrypto(OrderSymbol());
      else if(!IsCrypto(OrderSymbol()) && StringLen(candidateBase)==3)
      {
         string openKey=AssetKey(OrderSymbol());
         if(StringLen(openKey)>=6)
         {
            string openBase=StringSubstr(openKey,0,3);
            string openQuote=StringSubstr(openKey,3,3);
            overlaps=(openBase==candidateBase || openBase==candidateQuote ||
                      openQuote==candidateBase || openQuote==candidateQuote);
         }
      }
      if(overlaps) { overlapFloating+=floating; overlapCount++; }
   }
   double capital=MathMax(1.0,InpReferenceCapitalUSD);
   double level1=capital*MathMax(0.0,InpOpenExposureLevel1Pct)/100.0;
   double level2=capital*MathMax(InpOpenExposureLevel1Pct,InpOpenExposureLevel2Pct)/100.0;
   double level3=capital*MathMax(InpOpenExposureLevel2Pct,InpOpenExposureLevel3Pct)/100.0;
   double factor=1.0;
   if(totalFloating<=-level3 && level3>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel3Factor)));
   else if(totalFloating<=-level2 && level2>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel2Factor)));
   else if(totalFloating<=-level1 && level1>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel1Factor)));
   if(sameSideCount>0)
   {
      if(sameSideFloating<=-level3 && level3>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel3Factor)));
      else if(sameSideFloating<=-level2 && level2>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel2Factor)));
      else if(sameSideFloating<=-level1 && level1>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel1Factor)));
   }
   if(overlapCount>0)
   {
      if(overlapFloating<=-level3 && level3>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel3Factor)));
      else if(overlapFloating<=-level2 && level2>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel2Factor)));
      else if(overlapFloating<=-level1 && level1>0.0) factor=MathMin(factor,MathMax(0.10,MathMin(1.0,InpLossRiskLevel1Factor)));
   }
   Print("OPEN_EXPOSURE_EVALUATION | candidate=",candidateSymbol,
      " side=",(candidateType==OP_BUY?"BUY":"SELL"),
      " portfolioFloatingNet=",DoubleToString(totalFloating,2),
      " sameSideCount=",sameSideCount," sameSideFloatingNet=",DoubleToString(sameSideFloating,2),
      " overlapClusterCount=",overlapCount," overlapClusterFloatingNet=",DoubleToString(overlapFloating,2),
      " thresholdsUSD=",DoubleToString(level1,2),"/",DoubleToString(level2,2),"/",DoubleToString(level3,2),
      " appliedFactor=",DoubleToString(factor,2),
      " action=REDUCE_NEW_ENTRY_RISK_ONLY_NO_POSITION_CLOSE_NO_SESSION_BLOCK");
   return(factor);
}

double CurrentOpenRisk()
{
   double total=0.0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_TRADES)) continue;
      if(OrderMagicNumber()!=InpMagic || (OrderType()!=OP_BUY && OrderType()!=OP_SELL)) continue;
      if(OrderStopLoss()<=0) return(InpReferenceCapitalUSD);      // unknown risk fails closed
      double d=(OrderType()==OP_BUY?OrderOpenPrice()-OrderStopLoss():OrderStopLoss()-OrderOpenPrice());
      if(d>0)
      {
         double pt=MarketInfo(OrderSymbol(),MODE_POINT);
         double conservativeDist=d+MathMax(0,InpSlippagePoints)*MathMax(0.0,pt);
         total+=EstimateRisk(OrderSymbol(),OrderLots(),conservativeDist);
      }
   }
   return(total);
}

// Rebuild daily adaptive state from MT4 history; decisions use current server-day closes.
void GetDailyAdaptiveState(bool &strictMode,bool &shortenHold,datetime &activationTime,
                           int &sampleCount,int &wins,int &losses,double &netTotal,
                           double &avgWinSeconds,double &avgLossSeconds)
{
   strictMode=false; shortenHold=false; activationTime=0;
   sampleCount=0; wins=0; losses=0; netTotal=0.0;
   avgWinSeconds=0.0; avgLossSeconds=0.0;
   if(!InpEnableDailyAdaptiveQuality) return;
   int wanted=MathMax(1,MathMin(50,InpDailyAdaptiveSampleSize));
   datetime dayStart=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   datetime closeTimes[50]; double tradeNets[50]; double durations[50];
   // Explicitly initialize every slot so the compiler and runtime both know
   // that shifted/read elements always contain deterministic values.
   ArrayInitialize(closeTimes,0);
   ArrayInitialize(tradeNets,0.0);
   ArrayInitialize(durations,0.0);
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int type=OrderType();
      if(OrderMagicNumber()!=InpMagic || (type!=OP_BUY && type!=OP_SELL)) continue;
      datetime closed=OrderCloseTime();
      if(closed<dayStart || closed<=0) continue;
      int insertAt=-1;
      for(int j=0;j<sampleCount;j++)
         if(closed>closeTimes[j]) { insertAt=j; break; }
      if(insertAt<0 && sampleCount<wanted) insertAt=sampleCount;
      if(insertAt<0) continue;
      int newCount=MathMin(wanted,sampleCount+1);
      for(int k=newCount-1;k>insertAt;k--)
      {
         closeTimes[k]=closeTimes[k-1]; tradeNets[k]=tradeNets[k-1]; durations[k]=durations[k-1];
      }
      closeTimes[insertAt]=closed;
      tradeNets[insertAt]=OrderProfit()+OrderSwap()+OrderCommission();
      durations[insertAt]=(double)MathMax(0,closed-OrderOpenTime());
      sampleCount=newCount;
   }
   if(sampleCount<wanted) return;
   activationTime=closeTimes[0];
   double winDurationTotal=0.0, lossDurationTotal=0.0;
   int winDurationCount=0, lossDurationCount=0;
   for(int n=0;n<sampleCount;n++)
   {
      netTotal+=tradeNets[n];
      if(tradeNets[n]>0.0) { wins++; winDurationTotal+=durations[n]; winDurationCount++; }
      else if(tradeNets[n]<0.0) { losses++; lossDurationTotal+=durations[n]; lossDurationCount++; }
   }
   if(winDurationCount>0) avgWinSeconds=winDurationTotal/winDurationCount;
   if(lossDurationCount>0) avgLossSeconds=lossDurationTotal/lossDurationCount;
   int requiredLosses=MathMax(1,MathMin(wanted,InpDailyAdaptiveMinLosses));
   strictMode=(losses>wins && losses>=requiredLosses && netTotal<0.0);
   if(strictMode && winDurationCount>0 && lossDurationCount>0 &&
      avgLossSeconds>avgWinSeconds*MathMax(1.0,InpDailyAdaptiveDurationRatio))
      shortenHold=true;
   static datetime lastLoggedDay=0, lastLoggedActivationTime=0;
   static bool lastLoggedStrict=false, lastLoggedShorten=false;
   if(dayStart!=lastLoggedDay || activationTime!=lastLoggedActivationTime ||
      strictMode!=lastLoggedStrict || shortenHold!=lastLoggedShorten)
   {
      int reducedBars=InpMaxHoldBars;
      if(shortenHold && InpMaxHoldBars>0)
      {
         int raw=(int)MathFloor(InpMaxHoldBars*MathMax(0.10,MathMin(1.0,InpDailyAdaptiveHoldFactor)));
         int floorBars=MathMax(1,MathMin(InpMaxHoldBars,InpDailyAdaptiveMinHoldBars));
         reducedBars=MathMax(floorBars,MathMin(InpMaxHoldBars,raw));
      }
      string adaptiveExtra="sample="+IntegerToString(sampleCount)+
         ";wins="+IntegerToString(wins)+";losses="+IntegerToString(losses)+
         ";net="+DoubleToString(netTotal,2)+
         ";avgWinDurationSec="+DoubleToString(avgWinSeconds,0)+
         ";avgLossDurationSec="+DoubleToString(avgLossSeconds,0)+
         ";strictEntryMode="+(strictMode?"ON":"OFF")+
         ";shortenHold="+(shortenHold?"ON":"OFF")+
         ";baseMaxHoldBars="+IntegerToString(InpMaxHoldBars)+
         ";reducedMaxHoldBars="+IntegerToString(reducedBars)+
         ";activationAfter="+TimeToString(activationTime,TIME_DATE|TIME_SECONDS);
      Print("DAILY_ADAPTIVE_EVALUATION | enabled=true ",adaptiveExtra,
            " policy=DAILY_ONLY_NO_SL_WIDENING_NO_RISK_INCREASE");
      if(g_auditCsvHandle!=INVALID_HANDLE)
      {
         FileSeek(g_auditCsvHandle,0,SEEK_END);
         FileWrite(g_auditCsvHandle,TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),
            "DAILY_ADAPTIVE_EVALUATION",0,"ALL","ALL",0.0,
            TimeToString(activationTime,TIME_DATE|TIME_SECONDS),0,0,
            0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,0.0,
            0.0,0.0,0.0,netTotal,0.0,"DAILY_MODE_STATE",adaptiveExtra);
         FileFlush(g_auditCsvHandle);
      }
      lastLoggedDay=dayStart; lastLoggedActivationTime=activationTime;
      lastLoggedStrict=strictMode; lastLoggedShorten=shortenHold;
   }
}

string DailyEntryLockKey(datetime dayStart)
{
   return("BiteyDailyEntryLock_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+"_"+IntegerToString((int)dayStart));
}
int ConsecutiveNetLossesToday(datetime dayStart)
{
   datetime times[64]; double nets[64]; int count=0;
   ArrayInitialize(times,0);
   ArrayInitialize(nets,0.0);
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int type=OrderType();
      if(OrderMagicNumber()!=InpMagic || (type!=OP_BUY && type!=OP_SELL)) continue;
      datetime closed=OrderCloseTime();
      if(closed<dayStart || closed>=dayStart+86400) continue;
      double tradeNet=OrderProfit()+OrderSwap()+OrderCommission();
      int insertAt=count;
      while(insertAt>0 && times[insertAt-1]<closed) insertAt--;
      if(insertAt>=64) continue;
      int limit=MathMin(count,63);
      for(int j=limit;j>insertAt;j--){times[j]=times[j-1];nets[j]=nets[j-1];}
      times[insertAt]=closed;nets[insertAt]=tradeNet;
      if(count<64) count++;
   }
   int streak=0;
   for(int k=0;k<count;k++){if(nets[k]<0.0)streak++;else break;}
   return(streak);
}
void UpdateDailyEntryProtection()
{
   static uint lastSelectivityLogTick=0;
   datetime today=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
   if(g_dailyEntryLockDay!=today)
   {
      g_dailyEntryLockDay=today;
      g_dailyEntryLocked=false;
      g_dailyEntryLockReason="";
      g_selectivityStableCycles=0;
   }
   double dayNet=TodayNet(); // Closed net plus current floating net for this EA magic.
   int streak=ConsecutiveNetLossesToday(today);
   double capital=MathMax(1.0,InpReferenceCapitalUSD);
   double lossPct=(dayNet<0.0?100.0*MathAbs(dayNet)/capital:0.0);
   int targetLevel=0;
   if(InpEnableDailyEntryProtection)
   {
      if(lossPct>=MathMax(0.0,InpSelectivityLevel3LossPct) ||
         (InpPauseAfterConsecutiveLosses>0 && streak>=InpPauseAfterConsecutiveLosses+1)) targetLevel=3;
      else if(lossPct>=MathMax(0.0,InpDailyLossPct) ||
         (InpPauseAfterConsecutiveLosses>0 && streak>=InpPauseAfterConsecutiveLosses)) targetLevel=2;
      else if(lossPct>=MathMax(0.0,InpSelectivityLevel1LossPct) || (InpPauseAfterConsecutiveLosses>0 && streak>=2)) targetLevel=1;
   }

   if(targetLevel>g_analyticalSelectivityLevel)
   {
      g_analyticalSelectivityLevel=targetLevel;
      g_selectivityStableCycles=0;
      Print("PROGRESSIVE_SELECTIVITY_ESCALATED | level=",g_analyticalSelectivityLevel,
         " dayNet=",DoubleToString(dayNet,2)," lossPct=",DoubleToString(lossPct,2),
         " consecutiveLosses=",streak,
         " action=RAISE_SCORE_CONFIRMATION_ADX_SPREAD_AND_REDUCE_NEW_ENTRY_RISK_NO_ENTRY_LOCK");
   }
   else if(targetLevel<g_analyticalSelectivityLevel)
   {
      g_selectivityStableCycles++;
      int stableRequired=MathMax(1,InpSelectivityRecoveryStableCycles);
      if(g_selectivityStableCycles>=stableRequired)
      {
         g_analyticalSelectivityLevel=MathMax(targetLevel,g_analyticalSelectivityLevel-1);
         g_selectivityStableCycles=0;
         Print("PROGRESSIVE_SELECTIVITY_RECOVERY | level=",g_analyticalSelectivityLevel,
            " targetLevel=",targetLevel," stableCycles=",stableRequired,
            " action=LOWER_ONE_LEVEL_ONLY_AFTER_STABILITY");
      }
   }
   else g_selectivityStableCycles=0;

   g_dailyEntryLocked=false; // Retained only for compatibility; v1.5.7 never hard-locks entries by daily loss.
   g_dailyEntryLockReason="PROGRESSIVE_ANALYTICAL_SELECTIVITY";
   g_lastSelectivityDayNet=dayNet;
   uint selectivityNow=GetTickCount();
   if(lastSelectivityLogTick==0 || (selectivityNow-lastSelectivityLogTick)>=60000)
   {
      lastSelectivityLogTick=selectivityNow;
      Print("PROGRESSIVE_SELECTIVITY_STATE | level=",g_analyticalSelectivityLevel,
         " targetLevel=",targetLevel," dayNet=",DoubleToString(dayNet,2),
         " lossPct=",DoubleToString(lossPct,2)," consecutiveLosses=",streak,
         " scoreFloor=",DoubleToString(InpMinEntryScore+InpSelectivityScoreStep*g_analyticalSelectivityLevel,1),
         " riskFactor=",DoubleToString(SelectivityRiskMultiplier(g_analyticalSelectivityLevel),2),
         " action=CONTINUE_QUALIFIED_ENTRIES_AND_MANAGE_OPEN_POSITIONS");
   }
}

double SelectivityRiskMultiplier(int level)
{
   if(level>=3) return(MathMax(0.10,MathMin(1.0,InpSelectivityRiskFactorL3)));
   if(level==2) return(MathMax(0.10,MathMin(1.0,InpSelectivityRiskFactorL2)));
   if(level==1) return(MathMax(0.10,MathMin(1.0,InpSelectivityRiskFactorL1)));
   return(1.0);
}

bool SelectivityHTFAligned(string sym,int cmd,int level)
{
   int tf=InpHTF;
   int minBars=(level>=3?202:52);
   if(iBars(sym,tf)<minBars) return(false);
   double c=iClose(sym,tf,1);
   double ema50=iMA(sym,tf,50,0,MODE_EMA,PRICE_CLOSE,1);
   if(c<=0.0 || ema50<=0.0) return(false);
   if(cmd==OP_BUY && c<=ema50) return(false);
   if(cmd==OP_SELL && c>=ema50) return(false);
   if(level>=3)
   {
      double ema100=iMA(sym,tf,100,0,MODE_EMA,PRICE_CLOSE,1);
      double ema200=iMA(sym,tf,200,0,MODE_EMA,PRICE_CLOSE,1);
      if(ema100<=0.0 || ema200<=0.0) return(false);
      if(cmd==OP_BUY && !(ema50>ema100 && ema100>ema200)) return(false);
      if(cmd==OP_SELL && !(ema50<ema100 && ema100<ema200)) return(false);
   }
   return(true);
}

void LogRejectedSelectivityCandidate(string sym,int cmd,double score,double requiredScore,int level,string reason)
{
   Print("SELECTIVITY_REJECTED_CANDIDATE | symbol=",sym,
      " side=",(cmd==OP_BUY?"BUY":"SELL"),
      " score=",DoubleToString(score,1)," requiredScore=",DoubleToString(requiredScore,1),
      " level=",level," reason=",reason,
      " outcome=NOT_A_TRADE_FORWARD_OUTCOME_NOT_YET_OBSERVED");
}

double TodayNet()
{
   double net=0.0;
   datetime ds=StrToTime(TimeToString(TimeCurrent(),TIME_DATE));
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



datetime ServerDayStart(datetime when)
{
   return(StrToTime(TimeToString(when,TIME_DATE)));
}
void OpenDailyLossSummaryCSV()
{
   g_dailyLossCsvName="Bitey_Daily_Loss_Summary_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic)+".csv";
   ResetLastError();
   g_dailyLossCsvHandle=FileOpen(g_dailyLossCsvName,FILE_READ|FILE_WRITE|FILE_CSV|FILE_SHARE_READ|FILE_SHARE_WRITE,',');
   if(g_dailyLossCsvHandle==INVALID_HANDLE)
   {
      Print("DAILY_LOSS_CSV_ERROR | action=OPEN file=",g_dailyLossCsvName," error=",GetLastError());
      return;
   }
   bool fresh=(FileSize(g_dailyLossCsvHandle)==0);
   FileSeek(g_dailyLossCsvHandle,0,SEEK_END);
   if(fresh) FileWrite(g_dailyLossCsvHandle,"server_day","generated_server","scope","symbol",
      "closed_trades","wins","losses","win_rate_pct","gross_profit","gross_loss","net_profit",
      "profit_factor","rolling_window_number","window_sample","batch_wins","batch_losses","batch_net",
      "consecutive_losses","protection_level","negative_limit_minutes","asset_pause_minutes",
      "new_entries_restricted","daily_wins_more_than_losses","daily_net_positive","policy_note");
   FileFlush(g_dailyLossCsvHandle);
   Print("DAILY_LOSS_CSV_OPEN | file=",g_dailyLossCsvName," time_basis=MT4_SERVER_DAY");
}
void WriteDailyLossSummary(datetime dayStart)
{
   datetime dayEnd=dayStart+86400;
   int total=0,wins=0,losses=0; double grossWin=0.0,grossLoss=0.0,net=0.0;
   string names[MAX_SYMBOLS]; int counts[MAX_SYMBOLS],assetWins[MAX_SYMBOLS],assetLosses[MAX_SYMBOLS];
   double assetGrossWin[MAX_SYMBOLS],assetGrossLoss[MAX_SYMBOLS],assetNet[MAX_SYMBOLS];
   int assetCount=0;
   ArrayInitialize(counts,0); ArrayInitialize(assetWins,0); ArrayInitialize(assetLosses,0);
   ArrayInitialize(assetGrossWin,0.0); ArrayInitialize(assetGrossLoss,0.0); ArrayInitialize(assetNet,0.0);
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int type=OrderType();
      if(OrderMagicNumber()!=InpMagic || (type!=OP_BUY && type!=OP_SELL)) continue;
      datetime closed=OrderCloseTime();
      if(closed<dayStart || closed>=dayEnd) continue;
      double tradeNet=OrderProfit()+OrderSwap()+OrderCommission();
      total++; net+=tradeNet;
      if(tradeNet>0.0){wins++;grossWin+=tradeNet;} else if(tradeNet<0.0){losses++;grossLoss+=tradeNet;}
      string sym=OrderSymbol(),key=AssetIdentityKey(sym);
      int ix=-1;
      for(int j=0;j<assetCount;j++) if(AssetIdentityKey(names[j])==key){ix=j;break;}
      if(ix<0 && assetCount<MAX_SYMBOLS){ix=assetCount++;names[ix]=sym;}
      if(ix>=0)
      {
         counts[ix]++;assetNet[ix]+=tradeNet;
         if(tradeNet>0.0){assetWins[ix]++;assetGrossWin[ix]+=tradeNet;}
         else if(tradeNet<0.0){assetLosses[ix]++;assetGrossLoss[ix]+=tradeNet;}
      }
   }
   int gs=0,gw=0,gl=0,gstreak=0;double gn=0.0;bool ga=false;
   GetRecentLossPolicyForDay("",dayStart,gs,gw,gl,gn,gstreak,ga);
   int glevel=LossPolicyLevel(ga,gstreak);
   bool globalBlocked=false; // Reporting only: global entries are never suspended.
   if(g_dailyLossCsvHandle!=INVALID_HANDLE)
   {
      FileSeek(g_dailyLossCsvHandle,0,SEEK_END);
      FileWrite(g_dailyLossCsvHandle,TimeToString(dayStart,TIME_DATE),
         TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"GLOBAL","ALL",total,wins,losses,
         (total>0?100.0*wins/total:0.0),grossWin,grossLoss,net,
         (grossLoss<0.0?grossWin/MathAbs(grossLoss):0.0),
         total/MathMax(1,InpLossPolicySampleSize),gs,gw,gl,gn,gstreak,glevel,
         LossDurationLimitMinutes(gstreak),
         InpLossAssetPauseMinutes,(globalBlocked?"YES":"NO"),
         (wins>losses?"YES":"NO"),(net>0.0?"YES":"NO"),
         "rolling_last_n_closed_trades;server_day_scope;net=gross+swap+commission;adaptive_risk_scaling;no_global_or_asset_entry_suspension");
      for(int k=0;k<assetCount;k++)
      {
         int as=0,aw=0,al=0,astreak=0;double an=0.0;bool aa=false;
         GetRecentLossPolicyForDay(names[k],dayStart,as,aw,al,an,astreak,aa);
         int alevel=LossPolicyLevel(aa,astreak);
         bool assetBlocked=false; // Reporting only: asset risk is reduced, never hard-paused.
         FileWrite(g_dailyLossCsvHandle,TimeToString(dayStart,TIME_DATE|TIME_SECONDS),
            TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),"ASSET",names[k],
            counts[k],assetWins[k],assetLosses[k],
            (counts[k]>0?100.0*assetWins[k]/counts[k]:0.0),
            assetGrossWin[k],assetGrossLoss[k],assetNet[k],
            (assetGrossLoss[k]<0.0?assetGrossWin[k]/MathAbs(assetGrossLoss[k]):0.0),
            counts[k]/MathMax(1,InpLossPolicySampleSize),as,aw,al,an,astreak,alevel,
            LossDurationLimitMinutes(astreak),
            InpLossAssetPauseMinutes,(assetBlocked?"YES":"NO"),
            (assetWins[k]>assetLosses[k]?"YES":"NO"),(assetNet[k]>0.0?"YES":"NO"),
            "asset_and_direction_scope;rolling_last_n_closed_trades;adaptive_risk_scaling;no_asset_entry_pause");
      }
      FileFlush(g_dailyLossCsvHandle);
   }
   Print("DAILY_LOSS_SUMMARY | day=",TimeToString(dayStart,TIME_DATE),
      " trades=",total," wins=",wins," losses=",losses," net=",DoubleToString(net,2),
      " globalStrictLevel=",glevel," globalBlocked=",(globalBlocked?"true":"false"),
      " assets=",assetCount," csv=",g_dailyLossCsvName);
}
void CheckDailyLossDay()
{
   datetime today=ServerDayStart(TimeCurrent());
   string reportKey="B54DailyReportDay_"+IntegerToString(AccountNumber())+"_"+IntegerToString(InpMagic);
   if(!GlobalVariableCheck(reportKey)) GlobalVariableSet(reportKey,(double)(today-172800));
   datetime lastReported=(datetime)GlobalVariableGet(reportKey);
   while(lastReported<today-86400)
   {
      datetime dayToReport=lastReported+86400;
      WriteDailyLossSummary(dayToReport);
      lastReported=dayToReport;
      GlobalVariableSet(reportKey,(double)lastReported);
   }
   if(g_lossPolicyDayStart!=today)
   {
      Print("DAILY_LOSS_POLICY_RESET | previousDay=",TimeToString(g_lossPolicyDayStart,TIME_DATE),
         " newDay=",TimeToString(today,TIME_DATE),
         " scope=GLOBAL_AND_PER_ASSET rollingSamples=RESET negativePositionTimers=CONTINUE");
      g_lossPolicyDayStart=today;
      g_globalLossBlockLogDay=0;
   }
}

// Rolling closed-trade evaluator: refresh the latest N trades after every new close, globally or per asset/side.
string LossDurationStartKey(int ticket){return("B54LT_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));}
int LossPolicyLevel(bool adverse,int streak)
{
   if(!InpEnableRollingLossPolicy || !adverse) return(0);
   int maxLevel=MathMax(1,MathMin(5,InpLossPolicySuspendStreak));
   return(MathMax(1,MathMin(maxLevel,streak)));
}

double AdaptiveLossRiskMultiplier(int sample,int wins,int losses,double net,int streak,bool adverse)
{
   if(!InpEnableRollingLossPolicy || sample<MathMax(1,InpLossPolicySampleSize)) return(1.0);
   if(adverse || losses>wins || net<0.0)
   {
      int level=LossPolicyLevel(true,streak);
      if(level<=1) return(MathMax(0.10,MathMin(1.0,InpLossRiskLevel1Factor)));
      if(level==2) return(MathMax(0.10,MathMin(1.0,InpLossRiskLevel2Factor)));
      return(MathMax(0.10,MathMin(1.0,InpLossRiskLevel3Factor)));
   }
   int firstRecoveryWins=MathMax(1,MathMin(sample,InpLossRecoveryWinCount));
   int fullRecoveryWins=MathMax(firstRecoveryWins,sample-1);
   if(net>0.0 && wins>=fullRecoveryWins) return(1.0);
   if(net>0.0 && wins>=firstRecoveryWins) return(0.875);
   return(MathMax(0.10,MathMin(1.0,InpLossRiskLevel1Factor)));
}
int LossDurationLimitMinutes(int consecutiveLosses)
{
   // First loss keeps the initial 30-minute allowance; each repeat loss cuts 5 minutes.
   int recurrenceLevel=MathMax(0,MathMin(4,consecutiveLosses-1));
   return(MathMax(5,InpLossNegativeMinutes-5*recurrenceLevel));
}
void GetRecentLossPolicy(string filterSymbol,int &sample,int &wins,int &losses,double &net,int &lossStreak,bool &adverse,int filterType=-1)
{
   sample=0; wins=0; losses=0; net=0.0; lossStreak=0; adverse=false;
   if(!InpEnableRollingLossPolicy) return;
   GetRecentLossPolicyForDay(filterSymbol,
      StrToTime(TimeToString(TimeCurrent(),TIME_DATE)),
      sample,wins,losses,net,lossStreak,adverse,filterType);
}
void GetRecentLossPolicyForDay(string filterSymbol,datetime dayStart,
   int &sample,int &wins,int &losses,double &net,int &lossStreak,bool &adverse,int filterType=-1)
{
   sample=0; wins=0; losses=0; net=0.0; lossStreak=0; adverse=false;
   if(!InpEnableRollingLossPolicy) return;
   int wanted=MathMax(1,MathMin(10,InpLossPolicySampleSize));
   datetime dayEnd=dayStart+86400;
   string wantedKey=(StringLen(filterSymbol)>0?AssetIdentityKey(filterSymbol):"");
   int totalCount=0;
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      int type=OrderType();
      if(OrderMagicNumber()!=InpMagic || (type!=OP_BUY && type!=OP_SELL)) continue;
      if(filterType>=0 && type!=filterType) continue;
      if(StringLen(wantedKey)>0 && AssetIdentityKey(OrderSymbol())!=wantedKey) continue;
      datetime closed=OrderCloseTime();
      if(closed>=dayStart && closed<dayEnd) totalCount++;
   }
   // Use a rolling window, not fixed batches, so risk adapts after each new closed trade.
   if(totalCount<wanted) return;
   int batchStart=MathMax(0,totalCount-wanted);
   datetime allTimes[]; double allNets[];
   ArrayResize(allTimes,totalCount); ArrayResize(allNets,totalCount);
   int fill=0;
   for(int h=OrdersHistoryTotal()-1;h>=0;h--)
   {
      if(!OrderSelect(h,SELECT_BY_POS,MODE_HISTORY)) continue;
      int htype=OrderType();
      if(OrderMagicNumber()!=InpMagic || (htype!=OP_BUY && htype!=OP_SELL)) continue;
      if(filterType>=0 && htype!=filterType) continue;
      if(StringLen(wantedKey)>0 && AssetIdentityKey(OrderSymbol())!=wantedKey) continue;
      datetime hclosed=OrderCloseTime();
      if(hclosed<dayStart || hclosed>=dayEnd) continue;
      if(fill<totalCount){allTimes[fill]=hclosed;allNets[fill]=OrderProfit()+OrderSwap()+OrderCommission();fill++;}
   }
   // Sort by close time, independent of MT4 history-list ordering.
   for(int x=1;x<fill;x++)
   {
      datetime t=allTimes[x]; double v=allNets[x]; int y=x-1;
      while(y>=0 && allTimes[y]>t)
      {
         allTimes[y+1]=allTimes[y];allNets[y+1]=allNets[y];y--;
      }
      allTimes[y+1]=t;allNets[y+1]=v;
   }
   for(int n=batchStart;n<batchStart+wanted && n<fill;n++)
   {
      sample++;net+=allNets[n];
      if(allNets[n]>0.0) wins++;
      else if(allNets[n]<0.0) losses++;
   }
   for(int n=sample-1;n>=0;n--){if(allNets[batchStart+n]<0.0)lossStreak++;else break;}
   adverse=(sample==wanted && (losses>wins || net<0.0));
}
void UpdateGlobalLossPolicy()
{
   int sample=0,wins=0,losses=0,streak=0; double net=0.0; bool adverse=false;
   GetRecentLossPolicy("",sample,wins,losses,net,streak,adverse);
   bool changed=(sample!=g_globalLossSampleCount || wins!=g_globalLossWins ||
      losses!=g_globalLossLosses || streak!=g_globalLossStreak ||
      MathAbs(net-g_globalLossNet)>0.01 || adverse!=g_globalLossAdverse);
   g_globalLossSampleCount=sample; g_globalLossWins=wins; g_globalLossLosses=losses;
   g_globalLossStreak=streak; g_globalLossNet=net; g_globalLossAdverse=adverse;
   if(changed) Print("ROLLING_GLOBAL_LOSS_EVALUATION | sample=",sample," wins=",wins,
      " losses=",losses," net=",DoubleToString(net,2)," consecutiveLosses=",streak,
      " adverse=",(adverse?"true":"false")," strictLevel=",LossPolicyLevel(adverse,streak));
}
bool DirectionalLossCooldownActive(string sym,int orderType)
{
   if(InpCooldownBars<=0 || (orderType!=OP_BUY && orderType!=OP_SELL)) return(false);
   string assetKey=AssetIdentityKey(sym);
   datetime latestClose=0;
   double latestNet=0.0;
   string latestSymbol="";
   for(int i=OrdersHistoryTotal()-1;i>=0;i--)
   {
      if(!OrderSelect(i,SELECT_BY_POS,MODE_HISTORY)) continue;
      if(OrderMagicNumber()!=InpMagic || OrderType()!=orderType) continue;
      if(AssetIdentityKey(OrderSymbol())!=assetKey) continue;
      datetime closed=OrderCloseTime();
      if(closed>latestClose)
      {
         latestClose=closed;
         latestNet=OrderProfit()+OrderSwap()+OrderCommission();
         latestSymbol=OrderSymbol();
      }
   }
   if(latestClose<=0 || latestNet>=0.0) return(false);
   int closeBarShift=iBarShift(latestSymbol,InpSignalTF,latestClose,false);
   int currentBarShift=iBarShift(latestSymbol,InpSignalTF,TimeCurrent(),false);
   if(closeBarShift<0 || currentBarShift<0)
   {
      Print("COOLDOWN_BLOCK | symbol=",sym," assetKey=",assetKey,
            " side=",(orderType==OP_BUY?"BUY":"SELL"),
            " lastNet=",DoubleToString(latestNet,2),
            " lastClose=",TimeToString(latestClose,TIME_DATE|TIME_SECONDS),
            " reason=BAR_HISTORY_UNAVAILABLE action=FAIL_CLOSED");
      return(true);
   }
   int barsSinceLoss=MathMax(0,closeBarShift-currentBarShift);
   int remainingBars=MathMax(0,InpCooldownBars-barsSinceLoss);
   if(remainingBars<=0) return(false);
   Print("COOLDOWN_BLOCK | symbol=",sym," lossSymbol=",latestSymbol,
         " assetKey=",assetKey," side=",(orderType==OP_BUY?"BUY":"SELL"),
         " lastNet=",DoubleToString(latestNet,2),
         " lastClose=",TimeToString(latestClose,TIME_DATE|TIME_SECONDS),
         " barsSinceLoss=",barsSinceLoss,
         " requiredClosedBars=",InpCooldownBars,
         " remainingClosedBars=",remainingBars,
         " timeframe=",(int)InpSignalTF,
         " action=BLOCK_SAME_ASSET_SAME_DIRECTION_ONLY");
   return(true);
}

//+------------------------------------------------------------------+
//| Sizing                                                            |
//+------------------------------------------------------------------+
double EstimateRisk(string sym,double lots,double stopDist)
{
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0 || ts<=0 || lots<=0 || stopDist<=0) return(1.0e12);
   return((stopDist/ts)*tv*lots);
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
   double lossPerLot=(stopDist/ts)*tv;
   if(lossPerLot<=0) return(0.0);
   double lots=MathFloor(riskMoney/lossPerLot/step+1e-9)*step;
   lots=MathMin(lots,maxLot);
   lots=NormalizeDouble(lots,LotDigits(step));
   if(lots<minLot) return(0.0);
   if(EstimateRisk(sym,lots,stopDist)>riskMoney+0.02) return(0.0);
   return(lots);
}

//+------------------------------------------------------------------+