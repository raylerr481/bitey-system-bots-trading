//+------------------------------------------------------------------+
//| Bitey_Scalper_MultiAsset_v1_4_2_Temporary133Cooldown.mq4           |
//| Scalping / day trading, multi-asset (max 5), bidirectional,       |
//| adaptive SL/TP. Account type (demo/real) NEVER gates orders.      |
//| Not performance-validated: test on demo/tester before live use.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.42"
#property description "Ensemble scalper v1.4.2: temporary broker-133 cooldown with permission recheck, session statistics and bounded ranking"

#define EA_VERSION          "1.4.2"
#define MAX_SYMBOLS         128
#define HARD_MAX_POSITIONS  5

//--- universe and timeframes
input string           InpSymbolsCSV            = "";      // Blank = symbols in Market Watch (aliases deduplicated)
input ENUM_TIMEFRAMES  InpSignalTF              = PERIOD_M5;
input ENUM_TIMEFRAMES  InpHTF                   = PERIOD_M15; // Higher-timeframe bias (trend regime only)
input bool             InpUseHTFFilter          = true;
input int              InpMagic                 = 21102026;

//--- risk
input double           InpReferenceCapitalUSD   = 500.0;
input double           InpRiskPctPerTrade       = 0.5;     // 5 positions x 0.5% = 2.5% aggregate
input double           InpMaxAggregateRiskPct   = 2.5;
input double           InpMaxCurrencyRiskPct    = 1.5;     // Maximum stop-risk attributed to either FX currency
input double           InpDailyLossPct          = 3.0;     // Blocks NEW entries; open trades stay managed
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
input double           InpRewardRisk            = 1.5;

//--- execution filters
input double           InpMaxSpreadPctOfStop    = 12.0;    // Diagnostic warning threshold
input double           InpHardMaxSpreadPctOfStop = 35.0;    // Hard execution-quality cap; 0 = disabled
input double           InpMinEntryScore          = 0.0;     // Reject weak/negative-ranked signals below this score
input int              InpMaxSpreadPoints       = 0;       // Optional absolute cap, 0 = off
input int              InpMaxQuoteAgeSec        = 120;
input int              InpSlippagePoints        = 20;
input int              InpBroker133CooldownMinutes = 60; // 0 = block until EA restart
input int              InpBroker133RecheckMinutes  = 60; // Permission-only recheck interval after cooldown
input int              InpMinBars               = 250;
input bool             InpUseSessionFilter      = true;    // Server hours; crypto is exempt
input int              InpSessionStartHour      = 7;
input int              InpSessionEndHour        = 21;
input int              InpCooldownBars          = 6;       // Bars to wait on a symbol after a losing trade
input int              InpMaxHoldBars           = 48;      // Time exit (0 = off)

//--- adaptive SL/TP
input bool             InpEnableAdaptiveExits   = true;
input double           InpBreakEvenTriggerATR   = 1.0;
input double           InpBreakEvenLockATR      = 0.15;
input double           InpTrailStartATR         = 1.5;
input double           InpTrailDistanceATR      = 1.2;
input double           InpTrailStepATR          = 0.10;    // Minimum SL improvement per modification
input double           InpTPExpandTriggerATR    = 1.0;
input double           InpTPExpandBufferATR     = 1.0;
input double           InpTPExpandADXMin        = 22.0;
input double           InpTPMaxDistanceATR      = 5.0;
input double           InpSmallProfitCloseUSD   = 0.10;    // Close each position once estimated net after close costs reaches this amount (account currency)
input double           InpNetTargetR            = 0.0;     // Optional close at +N R net (0 = off; let adaptive TP run)
input double           InpNetLockStartUSD        = 1.00;    // Account-currency floating net profit required to activate
input double           InpNetLockMinUSD          = 0.25;    // Minimum net amount to protect after activation
input double           InpNetLockGivebackPct     = 35.0;    // Lock (100-this)% of peak floating net profit
input double           InpNetLockStepUSD         = 0.25;    // Persist peak only after this improvement
input double           InpEstimatedCloseCommissionPerLot = 0.0; // Configure broker close commission per 1.0 lot, account currency
input int              InpNetLockSlippagePoints  = 3;       // Adverse stop-fill slippage reserve

input bool             InpEnableTrading         = true;    // false = log candidates only
input bool             InpLogRejects            = false;
input bool             InpShowScanDashboard     = true;    // Show scan counts and last indicator snapshot on chart

string   g_symbols[MAX_SYMBOLS];
string   g_keys[MAX_SYMBOLS];
datetime g_lastBar[MAX_SYMBOLS];
int      g_symbolCount = 0;
uint     g_lastCycleTick = 0;
datetime g_lastHeartbeat = 0;
uint     g_lastHeartbeatTick = 0;
int      g_cycleNewBars = 0;
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
   g_sessionStartTime=TimeCurrent();
   for(int i=0;i<g_symbolCount;i++)
   {
      g_sessionBlocked[i]=false;
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
      SymbolSelect(g_symbols[i],true);
      g_lastQuoteStamp[i]=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      g_lastQuoteChangeTick[i]=GetTickCount();
   }
   EventSetTimer(1);
   if(AccountCurrency()!="USD") Print("RISK_WARNING | reference capital is USD but account currency is ",AccountCurrency(),"; verify conversion before trading");
   if(InpEstimatedCloseCommissionPerLot<=0.0) Print("NET_LOCK_WARNING | set InpEstimatedCloseCommissionPerLot if broker charges closing commission; exact net lock cannot be guaranteed otherwise");
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

int SessionSymbolIndex(string sym)
{
   string key=AssetKey(sym);
   for(int i=0;i<g_symbolCount;i++)
      if(g_keys[i]==key) return(i);
   return(-1);
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
      g_sessionBlockUntilTime[idx]=0;
      Print("SESSION_SYMBOL_UNBLOCK | symbol=",sym,
            " reason=COOLDOWN_EXPIRED_AND_PERMISSIONS_READY",
            " permissionProbeOnly=true no_test_order=true");
      return(false);
   }

   int recheckMinutes=MathMax(1,InpBroker133RecheckMinutes);
   g_sessionNextPermissionCheckTick[idx]=nowTick+(uint)(recheckMinutes*60000);
   Print("SESSION_SYMBOL_BLOCK_RETAINED | symbol=",sym,
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
      if(g_processedCloseCount>=2048) break;
      g_processedCloseTickets[g_processedCloseCount++]=ticket;
      int idx=SessionSymbolIndex(OrderSymbol());
      if(idx>=0)
      {
         double net=OrderProfit()+OrderSwap()+OrderCommission();
         g_sessionClosed[idx]++;
         g_sessionNet[idx]+=net;
         Print("SESSION_CLOSED_TRADE | symbol=",OrderSymbol()," ticket=",ticket,
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
   SyncClosedTradeStats();

   int maxPos=MaxPositions();
   int nc=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      string sym=g_symbols[i];
      datetime bt=iTime(sym,InpSignalTF,0);
      if(bt<=0 || bt==g_lastBar[i]) continue;
      g_lastBar[i]=bt;                      // one evaluation per closed bar per symbol
      g_cycleNewBars++;
      g_lastScanSymbol=sym;

      // Candidate capacity is independent of the live-position limit.
      // Collect signals across the whole universe; execution below stops only
      // after the configured number of positions have actually been accepted.
      if(nc>=MAX_SYMBOLS)
      {
         Reject(sym,"CANDIDATE_BUFFER_FULL");
         g_cycleCapacityRejects++;
         continue;
      }
      int cmd; double score; string why;
      if(!Prefilter(sym,why)) { Reject(sym,why); g_cyclePrefilterRejects++; continue; }
      g_cyclePrefilterOK++;
      g_cycleIndicatorRuns++;
      if(!Analyze(sym,cmd,score,why)) { Reject(sym,why); g_cycleSignalRejects++; continue; }
      if(cmd==OP_BUY && !InpAllowBuy)  { Reject(sym,"BUY_DISABLED");  g_cycleSignalRejects++; continue; }
      if(cmd==OP_SELL && !InpAllowSell) { Reject(sym,"SELL_DISABLED"); g_cycleSignalRejects++; continue; }
      if(score<InpMinEntryScore) { Reject(sym,"ENTRY_SCORE_BELOW_MINIMUM"); g_cycleSignalRejects++; continue; }
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

      double dailyLimit=InpReferenceCapitalUSD*InpDailyLossPct/100.0;
      double dayNet=TodayNet();
      if(dayNet<=-dailyLimit)
      {
         Print("DAILY_LOSS_BLOCK | dayNet=",DoubleToString(dayNet,2)," limit=-",DoubleToString(dailyLimit,2)," | no new entries");
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
            }
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
      Print("HEARTBEAT | v",EA_VERSION," open=",CountOpenPositions(),"/",maxPos,
            " dayNet=",DoubleToString(TodayNet(),2)," assetsInUniverse=",g_symbolCount,
            " newBarsScanned=",g_cycleNewBars," prefilterOK=",g_cyclePrefilterOK,
            " indicatorsEvaluated=",g_cycleIndicatorRuns," candidates=",g_cycleSignalCandidates,
            " buy=",g_cycleBuySignals," sell=",g_cycleSellSignals,
            " prefilterRejected=",g_cyclePrefilterRejects," signalRejected=",g_cycleSignalRejects," capacitySkipped=",g_cycleCapacityRejects);
      int quoteFresh=0,quoteStale=0,quoteMissing=0,quoteOldestAge=0;
      CountQuoteStates(quoteFresh,quoteStale,quoteMissing,quoteOldestAge);
      string feedStatus="NO_FRESH_QUOTES";
      if(quoteFresh==g_symbolCount && quoteStale==0 && quoteMissing==0)
         feedStatus="ALL_QUOTES_FRESH";
      else if(quoteFresh>0)
         feedStatus="PARTIAL_QUOTES_FRESH";
      else if(quoteMissing==g_symbolCount)
         feedStatus="NO_QUOTES";
      LogSessionSymbolStats();
      Print("MARKET_DATA_DIAGNOSTICS | freshQuotes=",quoteFresh," staleQuotes=",quoteStale,
            " missingQuotes=",quoteMissing," oldestObservedAgeSec=",quoteOldestAge,
            " feedStatus=",feedStatus,
            " universe=",g_symbolCount,
            " note=QUOTE_FRESHNESS_DOES_NOT_GUARANTEE_SYMBOL_TRADE_PERMISSION");
      // Reset interval counters after each 5-minute heartbeat.
      g_cycleNewBars=0; g_cyclePrefilterOK=0; g_cycleIndicatorRuns=0; g_cycleSignalCandidates=0;
      g_cycleBuySignals=0; g_cycleSellSignals=0; g_cyclePrefilterRejects=0; g_cycleSignalRejects=0; g_cycleCapacityRejects=0;
   }
}

void UpdateScanDashboard(int candidates)
{
   if(!InpShowScanDashboard) { Comment(""); return; }
   string panel="BITEY SCALPER v"+EA_VERSION+" | SCAN DASHBOARD\n";
   panel+="Activos en universo: "+IntegerToString(g_symbolCount)+" / "+IntegerToString(MAX_SYMBOLS)+"\n";
   panel+="Barras nuevas escaneadas: "+IntegerToString(g_cycleNewBars)+" | Prefiltro OK: "+IntegerToString(g_cyclePrefilterOK)+"\n";
   panel+="Indicadores evaluados: "+IntegerToString(g_cycleIndicatorRuns)+" | Candidatos: "+IntegerToString(candidates)+" (BUY "+IntegerToString(g_cycleBuySignals)+" / SELL "+IntegerToString(g_cycleSellSignals)+")\n";
   panel+="Descartes prefiltro: "+IntegerToString(g_cyclePrefilterRejects)+" | Sin señal: "+IntegerToString(g_cycleSignalRejects)+" | Saltos por capacidad: "+IntegerToString(g_cycleCapacityRejects)+"\n";
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
// Quote age uses the local monotonic tick counter because server time can stop on idle markets.
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
      g_lastQuoteChangeTick[idx]=GetTickCount();
      return(0);
   }
   uint elapsed=GetTickCount()-g_lastQuoteChangeTick[idx];
   return((int)(elapsed/1000));
}

bool QuoteFresh(string sym)
{
   int age=QuoteAgeSeconds(sym);
   return(age>=0 && age<=InpMaxQuoteAgeSec);
}

void CountQuoteStates(int &fresh,int &stale,int &missing,int &oldestAge)
{
   fresh=0; stale=0; missing=0; oldestAge=0;
   for(int i=0;i<g_symbolCount;i++)
   {
      datetime qt=(datetime)MarketInfo(g_symbols[i],MODE_TIME);
      if(qt<=0) { missing++; continue; }
      int age=QuoteAgeSeconds(g_symbols[i]);
      if(age<=InpMaxQuoteAgeSec) fresh++; else stale++;
      if(age>oldestAge && age<2147483647) oldestAge=age;
   }
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
   if(!TradePermissionsReady(sym,"PREFILTER")) { why="TRADE_PERMISSION_BLOCKED"; return(false); }
   if(MarketInfo(sym,MODE_TRADEALLOWED)==0) { why="SYMBOL_TRADING_DISABLED"; return(false); }
   if(iBars(sym,InpSignalTF)<InpMinBars) { why="INSUFFICIENT_HISTORY"; return(false); }
   int quoteAge=QuoteAgeSeconds(sym);
   if(quoteAge>InpMaxQuoteAgeSec)
   {
      why=(quoteAge>=2147483647?"QUOTE_MISSING":"STALE_QUOTE ageSec="+IntegerToString(quoteAge));
      return(false);
   }
   if(!SessionOK(sym)) { why="OUTSIDE_SESSION"; return(false); }
   if(HasPositionForKey(AssetKey(sym))) { why="POSITION_ALREADY_OPEN"; return(false); }
   if(InCooldown(sym)) { why="LOSS_COOLDOWN"; return(false); }
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
   if(adx<InpMinADX) { why="DEAD_MARKET_ADX"; return(false); }

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
         double hc=iClose(sym,InpHTF,1), he=iMA(sym,InpHTF,50,0,MODE_EMA,PRICE_CLOSE,1);
         if(hc<=0 || he<=0) { why="HTF_DATA_UNAVAILABLE"; return(false); }
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
//| Order entry: stops, spread-vs-stop, risk budget, lots             |
//+------------------------------------------------------------------+
bool OpenTrade(string sym,int cmd,double score)
{
   g_lastExecutionRejectCategory="";
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
   if(bid<=0 || ask<bid || point<=0 || atr<=0) { g_lastExecutionRejectCategory="OTHER"; Reject(sym,"ENTRY_DATA_INVALID"); return(false); }
   if(!QuoteFresh(sym)) { g_lastExecutionRejectCategory="OTHER"; Reject(sym,"STALE_QUOTE_AT_ENTRY"); return(false); }

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
   if(InpHardMaxSpreadPctOfStop>0.0 && spreadPctOfStop>InpHardMaxSpreadPctOfStop)
   {
      Print("EXECUTION_QUALITY_REJECT | symbol=",sym," spreadPctOfStop=",DoubleToString(spreadPctOfStop,1),
            " hardMax=",DoubleToString(InpHardMaxSpreadPctOfStop,1)," reason=SPREAD_TOO_LARGE");
      g_lastExecutionRejectCategory="SPREAD";
      return(false);
   }

   double entry=(cmd==OP_BUY?ask:bid);
   double sl=NormalizeDouble(cmd==OP_BUY?entry-stopDist:entry+stopDist,digits);
   double tp=NormalizeDouble(cmd==OP_BUY?entry+targetDist:entry-targetDist,digits);
   stopDist=MathAbs(entry-sl);
   bool ok=false;
   if(cmd==OP_BUY) ok=(sl>0 && tp>0 && sl<bid-brokerMin*0.5 && tp>bid+brokerMin*0.5);
   else            ok=(sl>ask+brokerMin*0.5 && tp>0 && tp<ask-brokerMin*0.5);
   if(!ok) { g_lastExecutionRejectCategory="STOP_PREFLIGHT"; Print("STOP_PREFLIGHT_REJECT | symbol=",sym," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits)); return(false); }

   double maxAgg=InpReferenceCapitalUSD*InpMaxAggregateRiskPct/100.0;
   double openRisk=CurrentOpenRisk();
   double remaining=maxAgg-openRisk;
   double perTrade=InpReferenceCapitalUSD*InpRiskPctPerTrade/100.0;
   if(remaining<=0.01) { g_lastExecutionRejectCategory="RISK"; Print("RISK_REJECT | symbol=",sym," reason=AGGREGATE_RISK_CAP open=",DoubleToString(openRisk,2)," cap=",DoubleToString(maxAgg,2)); return(false); }
   double budget=MathMin(perTrade,remaining);
   double riskDistance=stopDist+MathMax(0,InpSlippagePoints)*point;
   double lots=LotsForRisk(sym,riskDistance,budget);
   if(lots<=0) { g_lastExecutionRejectCategory="RISK"; Print("RISK_REJECT | symbol=",sym," reason=MIN_LOT_EXCEEDS_BUDGET budget=",DoubleToString(budget,2)," riskDistance=",DoubleToString(riskDistance,digits)); return(false); }
   double risk=EstimateRisk(sym,lots,riskDistance);
   if(!CurrencyRiskAllowed(sym,lots,riskDistance,risk)) { g_lastExecutionRejectCategory="RISK"; return(false); }

   if(!InpEnableTrading)
   {
      Print("DRY_RUN_CANDIDATE | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL")," score=",DoubleToString(score,1),
            " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
            " spread=",DoubleToString(spreadPrice,digits)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      g_lastExecutionRejectCategory="DRY_RUN";
      return(false);
   }
   if(!TradePermissionsReady(sym,"PRE_ORDER")) { g_lastExecutionRejectCategory="TRADE_PERMISSION"; return(false); }

   ResetLastError();
   int ticket=OrderSend(sym,cmd,lots,entry,InpSlippagePoints,sl,tp,"Bitey Ens v"+EA_VERSION,InpMagic,0,clrNONE);
   if(ticket<0)
   {
      int err=GetLastError();
      g_lastExecutionErrorCode=err;
      Print("ORDER_REJECTED | symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
            " error=",err," errorName=",TradeErrorDescription(err),
            " lots=",DoubleToString(lots,2)," SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
      g_lastExecutionRejectCategory="BROKER_ERROR";
      if(err==133)
      {
         int blockedIdx=SessionSymbolIndex(sym);
         if(blockedIdx>=0)
         {
            g_sessionBlocked[blockedIdx]=true;
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
   Print("ORDER_ACCEPTED | ticket=",ticket," symbol=",sym," side=",(cmd==OP_BUY?"BUY":"SELL"),
         " lots=",DoubleToString(lots,2)," risk=",DoubleToString(risk,2)," riskDistance=",DoubleToString(riskDistance,digits),
         " spread=",DoubleToString(spreadPrice,digits)," score=",DoubleToString(score,1),
         " SL=",DoubleToString(sl,digits)," TP=",DoubleToString(tp,digits));
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
   if(ok) { string pk=NetPeakKey(ticket); if(GlobalVariableCheck(pk)) GlobalVariableDel(pk); }
   return(ok);
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
      double point=MarketInfo(sym,MODE_POINT);
      double bid=MarketInfo(sym,MODE_BID), ask=MarketInfo(sym,MODE_ASK);
      if(point<=0 || bid<=0 || ask<=0) continue;
      int digits=(int)MarketInfo(sym,MODE_DIGITS);
      double entry=OrderOpenPrice(), oldSL=OrderStopLoss(), oldTP=OrderTakeProfit(), lots=OrderLots();
      double net=OrderProfit()+OrderSwap()+OrderCommission();
      double atr=iATR(sym,InpSignalTF,InpATRPeriod,1);

      // Small-net-profit exit: closes independently of trend strength; all other entry/risk/SLTP logic stays intact.
      // Estimate net after current swap/commission, configured closing commission and adverse slippage reserve.
      double closeCommissionEstimate=MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots;
      double closeSlippageReserve=0.0;
      if(InpNetLockSlippagePoints>0)
         closeSlippageReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
      double estimatedNetAfterCloseCosts=net-closeCommissionEstimate-closeSlippageReserve;
      if(InpSmallProfitCloseUSD>0.0 && closeSlippageReserve<1.0e11 && estimatedNetAfterCloseCosts>=InpSmallProfitCloseUSD)
      {
         Print("SMALL_NET_PROFIT_TARGET | ticket=",ticket," symbol=",sym,
               " estimatedNetAfterCloseCosts=",DoubleToString(estimatedNetAfterCloseCosts,2),
               " target=",DoubleToString(InpSmallProfitCloseUSD,2),
               " trend-independent close");
         CloseTicket(ticket,"SMALL_NET_PROFIT_TARGET");
         continue;
      }

      if(InpMaxHoldBars>0)
      {
         int barsOpen=iBarShift(sym,InpSignalTF,OrderOpenTime(),false);
         if(barsOpen>=InpMaxHoldBars) { CloseTicket(ticket,"TIME_EXIT"); continue; }
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
      // ATR trailing
      if(InpTrailStartATR>0 && InpTrailDistanceATR>0 && favorable>=atr*InpTrailStartATR)
      {
         double tr=(type==OP_BUY?bid-atr*InpTrailDistanceATR:ask+atr*InpTrailDistanceATR);
         if(type==OP_BUY  && tr>newSL+atr*InpTrailStepATR && tr<bid-minDist) newSL=tr;
         if(type==OP_SELL && (newSL<=0 || tr<newSL-atr*InpTrailStepATR) && tr>ask+minDist) newSL=tr;
      }
      // Cost-aware net-profit lock: never loosens an existing protective stop.
      double netLockSL=0.0;
      if(NetProfitLockStop(ticket,sym,type,entry,lots,net,point,digits,minDist,price,netLockSL))
      {
         if(type==OP_BUY  && (newSL<=0 || netLockSL>newSL)) newSL=netLockSL;
         if(type==OP_SELL && (newSL<=0 || netLockSL<newSL)) newSL=netLockSL;
      }

      newSL=(newSL>0?NormalizeDouble(newSL,digits):0);
      if(type==OP_BUY)  slUp=(newSL>0 && (oldSL<=0 || newSL>oldSL+point*0.5));
      else              slUp=(newSL>0 && (oldSL<=0 || newSL<oldSL-point*0.5));

      // Adaptive TP: extend only in a strong trend when price nears the target
      double adx=iADX(sym,InpSignalTF,14,PRICE_CLOSE,MODE_MAIN,1);
      if(oldTP>0 && favorable>=atr*InpTPExpandTriggerATR && adx>=InpTPExpandADXMin)
      {
         double remainingToTP=(type==OP_BUY?oldTP-bid:ask-oldTP);
         if(remainingToTP<=atr*InpTPExpandBufferATR)
         {
            double curDist=MathAbs(oldTP-entry);
            double want=MathMin(atr*InpTPMaxDistanceATR,MathMax(curDist,favorable+atr*InpTPExpandBufferATR));
            double prop=NormalizeDouble(type==OP_BUY?entry+want:entry-want,digits);
            if(type==OP_BUY  && prop>oldTP+point && prop>ask+minDist) { newTP=prop; tpUp=true; }
            if(type==OP_SELL && prop<oldTP-point && prop<bid-minDist) { newTP=prop; tpUp=true; }
         }
      }

      if(!slUp && !tpUp) continue;
      double fSL=(slUp?newSL:oldSL), fTP=(tpUp?newTP:oldTP);
      ResetLastError();
      if(OrderModify(ticket,entry,fSL,fTP,0,clrNONE))
         Print("ADAPTIVE_MODIFY | ticket=",ticket," symbol=",sym,
               " SL ",DoubleToString(oldSL,digits),"->",DoubleToString(fSL,digits),
               " TP ",DoubleToString(oldTP,digits),"->",DoubleToString(fTP,digits));
      else
         Print("ADAPTIVE_MODIFY_FAILED | ticket=",ticket," symbol=",sym," error=",GetLastError());
   }
}


//+------------------------------------------------------------------+
//| Persistent peak-profit tracking and cost-aware net-profit lock    |
//+------------------------------------------------------------------+
string NetPeakKey(int ticket)
{
   return("BiteyNP_"+IntegerToString(AccountNumber())+"_"+IntegerToString(ticket));
}

bool NetProfitLockStop(int ticket,string sym,int type,double entry,double lots,double net,
                       double point,int digits,double minDist,double marketPrice,double &stopOut)
{
   stopOut=0.0;
   if(InpNetLockStartUSD<=0.0 || InpNetLockGivebackPct<0.0 || InpNetLockGivebackPct>=100.0) return(false);
   string key=NetPeakKey(ticket);
   double peak=(GlobalVariableCheck(key)?GlobalVariableGet(key):0.0);
   if(net>peak)
   {
      if(net-peak>=MathMax(0.01,InpNetLockStepUSD) || peak<=0.0) GlobalVariableSet(key,net);
      peak=MathMax(peak,net);
   }
   if(peak<InpNetLockStartUSD) return(false);
   double lockNet=MathMax(InpNetLockMinUSD,peak*(1.0-InpNetLockGivebackPct/100.0));
   if(lockNet>=net) lockNet=MathMax(0.0,net-MathMax(0.05,InpNetLockMinUSD*0.10));
   if(lockNet<=0.0) return(false);
   double tv=MarketInfo(sym,MODE_TICKVALUE), ts=MarketInfo(sym,MODE_TICKSIZE);
   if(tv<=0.0 || ts<=0.0 || lots<=0.0 || point<=0.0) return(false);
   double moneyPerPrice=(tv/ts)*lots;
   if(moneyPerPrice<=0.0) return(false);
   // Floating OrderProfit is marked at Bid for BUY / Ask for SELL: spread is included.
   // Reserve estimated closing commission and adverse stop-fill slippage.
   double closeCommission=MathMax(0.0,InpEstimatedCloseCommissionPerLot)*lots;
   double slipReserve=0.0;
   if(InpNetLockSlippagePoints>0) slipReserve=EstimateRisk(sym,lots,InpNetLockSlippagePoints*point);
   if(slipReserve>=1.0e11) return(false);
   double requiredGross=lockNet-OrderSwap()-OrderCommission()+closeCommission+slipReserve;
   double move=requiredGross/moneyPerPrice;
   double candidate=NormalizeDouble(type==OP_BUY?entry+move:entry-move,digits);
   if(type==OP_BUY)
   {
      if(candidate<=entry || candidate>=marketPrice-minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate<=OrderStopLoss()+point*0.5) return(false);
   }
   else
   {
      if(candidate>=entry || candidate<=marketPrice+minDist) return(false);
      if(OrderStopLoss()>0.0 && candidate>=OrderStopLoss()-point*0.5) return(false);
   }
   stopOut=candidate;
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

bool InCooldown(string sym)
{
   if(InpCooldownBars<=0) return(false);
   datetime latest=0; double latestNet=0.0;
   int seen=0;
   for(int i=OrdersHistoryTotal()-1;i>=0 && seen<80;i--)
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
   if(latest<=0 || latestNet>=0.0) return(false);
   return((TimeCurrent()-latest)<InpCooldownBars*PeriodSeconds(InpSignalTF));
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